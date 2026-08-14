--- Castbars/MSUF_FocusKickIcon.lua
---
--- Visual widget for the focus-kick replacement cast display. The StateDriver
--- owns enable checks, event registration, and cast-state selection; this file
--- owns the draggable icon frame, copied time text, border coloring, and short
--- interrupt feedback animation.

local ExportPublic = ((select(2, ...) or _G.MSUF_NS or _G.MSUF or {}).ExportPublic) or function(name, value)
    _G[name] = value
    return value
end

local ParentFrame = UIParent
local After = C_Timer and C_Timer.After

local iconFrame
local previewFrame
local previewEnabled = false
local previewSelected = false
local refreshPreviewLayout
local initialized = false

local function EnsureOptions()
    if type(_G.MSUF_EnsureDB) == "function" then _G.MSUF_EnsureDB() end

    local db = _G.MSUF_DB
    if not db then
        db = {}
        ExportPublic("MSUF_DB", db)
    end
    db.general = db.general or {}

    local general = db.general
    if general.enableFocusKickIcon == nil then general.enableFocusKickIcon = false end
    if general.focusKickIconOffsetX == nil then general.focusKickIconOffsetX = 300 end
    if general.focusKickIconOffsetY == nil then general.focusKickIconOffsetY = 0 end
    if general.focusKickIconWidth == nil then general.focusKickIconWidth = 40 end
    if general.focusKickIconHeight == nil then general.focusKickIconHeight = 40 end
    return general
end

local function IsFocusKickEnabled()
    local general = EnsureOptions()
    local db = _G.MSUF_DB
    if db and db.focus and db.focus.enabled == false then return false end

    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar
    if type(shouldUseMSUF) == "function" and not shouldUseMSUF("focus", general) then
        return false
    end

    return general.enableFocusKickIcon == true
end

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then return math.floor(value + 0.5) end
    return math.ceil(value - 0.5)
end

local function ResolveTextSize(general)
    local configured = tonumber(general.focusKickTextSize)
    if configured then return Clamp(configured, 8, 24) end
    return ((tonumber(general.focusKickIconHeight) or 40) >= 48) and 14 or 12
end

local function FocusSourceCastbar()
    return (iconFrame and iconFrame.MSUF_sourceCastBar)
        or _G.MSUF_FocusCastBar
        or _G.MSUF_FocusCastbar
        or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar)
end

local function DetachTimeDriver()
    if not iconFrame then return end

    local runtime = _G.MSUF_CastbarRuntime
    if runtime and runtime.DisableNativeTimeText then
        runtime:DisableNativeTimeText(iconFrame)
    end
    iconFrame._msufFocusTimeDuration = nil
    iconFrame._msufFocusTimeFormat = nil

    local source = iconFrame._msufTimeFollowerSource
    if source and source._msufTimeTextFollower == iconFrame.timeText then
        source._msufTimeTextFollower = nil
        source._msufForceLuaTimeTextFollower = nil
        iconFrame._msufTimeFollowerSource = nil

        if source.MSUF_castActive == true
            and runtime and runtime.PrepareWork
            and type(_G.MSUF_RegisterCastbar) == "function"
        then
            runtime:PrepareWork(source)
            _G.MSUF_RegisterCastbar(source)
        end
    end
end

local function AttachTimeDriver(state)
    if not (iconFrame and iconFrame.timeText) then return end

    local general = EnsureOptions()
    if general.showFocusCastTime == false then
        DetachTimeDriver()
        iconFrame.timeText:SetText("")
        iconFrame.timeText:SetAlpha(0)
        return
    end

    iconFrame.timeText:SetAlpha(1)
    local format = "CURRENT"
    if type(_G.MSUF_GetCastbarTimeFormat) == "function" then
        format = _G.MSUF_GetCastbarTimeFormat("focus", general) or format
    end

    local runtime = _G.MSUF_CastbarRuntime
    local source = FocusSourceCastbar()
    local durationObj = (source and source.MSUF_durationObj) or (state and state.durationObj)
    if durationObj
        and runtime and runtime.BindNativeTimeText
    then
        if iconFrame._msufNativeTimeBound == true
            and iconFrame._msufFocusTimeDuration == durationObj
            and iconFrame._msufFocusTimeFormat == format then
            return
        end
        DetachTimeDriver()
        if runtime:BindNativeTimeText(iconFrame, durationObj, format) then
            iconFrame._msufFocusTimeDuration = durationObj
            iconFrame._msufFocusTimeFormat = format
            return
        end
    end

    -- Degraded clients reuse the source castbar's already-required manager
    -- cadence.  The follower is written only when that source text changes.
    if not (source and source.timeText) then
        DetachTimeDriver()
        iconFrame.timeText:SetText("")
        iconFrame.timeText:SetAlpha(0)
        return
    end

    if iconFrame._msufTimeFollowerSource == source
        and source._msufTimeTextFollower == iconFrame.timeText then
        return
    end

    DetachTimeDriver()

    source._msufTimeTextFollower = iconFrame.timeText
    source._msufForceLuaTimeTextFollower = true
    iconFrame._msufTimeFollowerSource = source
    if runtime and runtime.PrepareWork then runtime:PrepareWork(source) end
    if type(_G.MSUF_RegisterCastbar) == "function" then _G.MSUF_RegisterCastbar(source) end

    local text = source.timeText:GetText()
    if _G.issecretvalue and _G.issecretvalue(text) == true then
        iconFrame.timeText:SetText(text)
    else
        iconFrame.timeText:SetText(text or "")
    end
end

local function ApplyTimeTextFont()
    local general = EnsureOptions()
    local fontPath = (type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath())
        or STANDARD_TEXT_FONT
        or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags()) or "OUTLINE"
    local fontSize = ResolveTextSize(general)
    local resolveSafe = _G.MSUF_ResolveSafeFontPath
    if type(resolveSafe) == "function" then
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        fontPath = resolveSafe(fontPath, fontSize, fontFlags, g and g.fontKey)
    end

    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local applyResolved = _G.MSUF_ApplyResolvedFont
    local function ApplyOne(fs)
        if not fs then return end
        if type(applyResolved) == "function" then
            applyResolved(fs, fontPath, fontSize, fontFlags, g and g.fontKey)
            return
        end
        local ok, applied = pcall(fs.SetFont, fs, fontPath, fontSize, fontFlags)
        local ready = ok and applied ~= false
        local matches = _G.MSUF_FontApplicationMatches
        if ready and type(matches) == "function" then ready = matches(fs, fontPath, fontSize) == true end
        if not ready and type(_G.MSUF_MarkFontApplyFailed) == "function" then
            _G.MSUF_MarkFontApplyFailed()
        end
    end
    ApplyOne(iconFrame and iconFrame.timeText)
    ApplyOne(previewFrame and previewFrame.timeText)

    if type(_G.MSUF_GetConfiguredFontColor) == "function" then
        local red, green, blue = _G.MSUF_GetConfiguredFontColor()
        if red and green and blue then
            if iconFrame and iconFrame.timeText then iconFrame.timeText:SetTextColor(red, green, blue, 1) end
            if previewFrame and previewFrame.timeText then previewFrame.timeText:SetTextColor(red, green, blue, 1) end
        end
    end
end

local function SetBorderColor(red, green, blue, alpha)
    if not (iconFrame and iconFrame.edges) then return end
    alpha = alpha or 1

    for index = 1, #iconFrame.edges do
        iconFrame.edges[index]:SetVertexColor(red, green, blue, alpha)
    end
end

local function ApplyInterruptibilityColor(isNotInterruptible, apiNotInterruptibleRaw)
    if not iconFrame then return end
    if type(_G.MSUF_KickReady_Init) == "function" then _G.MSUF_KickReady_Init() end

    if iconFrame.icon and iconFrame.icon.SetDesaturated then
        iconFrame.icon:SetDesaturated(isNotInterruptible == true)
    end

    if isNotInterruptible == true then
        SetBorderColor(0.6, 0.6, 0.6, 1)
        return
    end

    local red, green, blue, alpha
    local hasColor = false
    if type(_G.MSUF_KickReady_IsReady) == "function"
        and type(_G.MSUF_KickReady_EvaluateRGBA) == "function"
    then
        red, green, blue, alpha = _G.MSUF_KickReady_EvaluateRGBA(
            _G.MSUF_KickReady_IsReady(),
            apiNotInterruptibleRaw
        )
        hasColor = true
    end

    if hasColor then
        SetBorderColor(red, green, blue, alpha)
    else
        SetBorderColor(1, 0.2, 0.2, 1)
    end
end

local function LayoutBorderEdges()
    if not (iconFrame and iconFrame.edges) then return end

    local top, bottom, left, right = iconFrame.edges[1], iconFrame.edges[2], iconFrame.edges[3], iconFrame.edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", iconFrame, "TOPLEFT")
    top:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT")
    top:SetHeight(2)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT")
    bottom:SetHeight(2)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", iconFrame, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT")
    left:SetWidth(2)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT")
    right:SetWidth(2)
end

local function ApplyIconLayout()
    if not iconFrame then return end

    local general = EnsureOptions()
    local width = Clamp(general.focusKickIconWidth, 16, 128)
    local height = Clamp(general.focusKickIconHeight, 16, 128)

    iconFrame:SetParent(ParentFrame)
    iconFrame:ClearAllPoints()
    iconFrame:SetPoint("CENTER", ParentFrame, "CENTER", general.focusKickIconOffsetX or 300, general.focusKickIconOffsetY or 0)
    iconFrame:SetSize(width, height)

    LayoutBorderEdges()
    ApplyTimeTextFont()
end

local function EnsureIconFrame()
    if iconFrame then return iconFrame end

    iconFrame = CreateFrame("Frame", "MSUF_FocusKickIcon", ParentFrame, "BackdropTemplate")
    iconFrame:SetFrameStrata("HIGH")
    iconFrame:SetFrameLevel(50)
    iconFrame:Hide()
    iconFrame:HookScript("OnHide", DetachTimeDriver)

    iconFrame.bg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconFrame.bg:SetAllPoints()
    iconFrame.bg:SetColorTexture(0, 0, 0, 0.9)

    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetPoint("TOPLEFT", 1, -1)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    iconFrame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    iconFrame.edges = {}
    for index = 1, 4 do
        local edge = iconFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        iconFrame.edges[index] = edge
    end

    iconFrame.timeText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconFrame.timeText:SetPoint("BOTTOM", iconFrame, "BOTTOM", 0, 2)
    iconFrame.timeText:SetJustifyH("CENTER")
    iconFrame.timeText:SetText("")
    iconFrame.timeText:SetAlpha(0)

    iconFrame:EnableMouse(true)
    iconFrame:SetMovable(true)
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", function(frame)
        frame:StartMoving()
    end)
    iconFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()

        local general = EnsureOptions()
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = ParentFrame:GetCenter()
        if centerX and centerY and parentX and parentY then
            general.focusKickIconOffsetX = Round(centerX - parentX)
            general.focusKickIconOffsetY = Round(centerY - parentY)
        end

        ApplyIconLayout()
        if refreshPreviewLayout then refreshPreviewLayout() end
    end)

    ApplyIconLayout()
    return iconFrame
end

local function PlayInterruptFeedback()
    if not iconFrame then return end

    SetBorderColor(1, 0.2, 0.2, 1)
    if iconFrame.bg then iconFrame.bg:SetColorTexture(0, 0, 0, 0.9) end

    if After then
        After(0.18, function()
            if not iconFrame then return end
            local source = _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbar
                or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar)
            ApplyInterruptibilityColor(
                source and source.isNotInterruptible == true,
                source and source._msufApiNotInterruptibleRaw
            )
        end)
    end

    local general = EnsureOptions()
    local shakePixels = 6
    local shakeStep = 0
    local shakeSteps = 6

    local function shake()
        if not (iconFrame and iconFrame:IsShown()) then return end

        shakeStep = shakeStep + 1
        local direction = (shakeStep % 2 == 0) and -1 or 1
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint(
            "CENTER",
            ParentFrame,
            "CENTER",
            (general.focusKickIconOffsetX or 300) + direction * shakePixels,
            general.focusKickIconOffsetY or 0
        )

        if shakeStep < shakeSteps and After then
            After(0.02, shake)
        else
            ApplyIconLayout()
        end
    end

    shake()
end

local function PrintMoveError(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1, 0.2, 0.2, 1)
    elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    else
        print(message)
    end
end

local function SetPreviewSelected(selected)
    previewSelected = selected and true or false
    if previewFrame and previewFrame._selBorder then
        previewFrame._selBorder:SetShown(previewSelected)
    end
end

local function NudgePreview(deltaX, deltaY)
    if not (previewEnabled and previewSelected) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end

    local general = EnsureOptions()
    local step = (IsControlKeyDown and IsControlKeyDown()) and 10
        or ((IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1)
    general.focusKickIconOffsetX = Clamp(Round((general.focusKickIconOffsetX or 0) + (deltaX or 0) * step), -500, 500)
    general.focusKickIconOffsetY = Clamp(Round((general.focusKickIconOffsetY or 0) + (deltaY or 0) * step), -500, 500)

    ApplyIconLayout()
    if refreshPreviewLayout then refreshPreviewLayout() end
    SetPreviewSelected(true)
    return true
end

local function EnsurePreviewFrame()
    if previewFrame then return previewFrame end

    previewFrame = CreateFrame("Frame", "MSUF_FocusKickPreviewFrame", ParentFrame, "BackdropTemplate")
    previewFrame:SetFrameStrata("HIGH")
    previewFrame:SetFrameLevel(70)
    previewFrame:SetMovable(true)
    previewFrame:EnableMouse(true)
    previewFrame:EnableKeyboard(true)
    if previewFrame.SetPropagateKeyboardInput then previewFrame:SetPropagateKeyboardInput(true) end

    previewFrame:RegisterForDrag("LeftButton")
    previewFrame.icon = previewFrame:CreateTexture(nil, "ARTWORK")
    previewFrame.icon:SetAllPoints()

    previewFrame._selBorder = previewFrame:CreateTexture(nil, "OVERLAY")
    previewFrame._selBorder:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", -3, 3)
    previewFrame._selBorder:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", 3, -3)
    previewFrame._selBorder:SetColorTexture(0.27, 0.53, 0.80, 0.45)
    previewFrame._selBorder:Hide()

    previewFrame.timeText = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewFrame.timeText:SetPoint("BOTTOM", previewFrame, "BOTTOM", 0, 2)
    previewFrame.timeText:SetJustifyH("CENTER")
    previewFrame.timeText:SetText("5.0")

    local animationGroup = previewFrame:CreateAnimationGroup()
    animationGroup:SetLooping("REPEAT")
    local animation = animationGroup:CreateAnimation("Animation")
    animation:SetDuration(0.08)
    animation:SetScript("OnUpdate", function()
        if previewFrame and previewFrame:IsShown() and previewFrame.timeText then
            local remaining = 8.0 - (((GetTime and GetTime()) or 0) % 8.0)
            previewFrame.timeText:SetText(string.format("%.1f", remaining))
        end
    end)
    previewFrame._msufFakeTimerAG = animationGroup

    previewFrame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then SetPreviewSelected(true) end
    end)
    previewFrame:SetScript("OnKeyDown", function(frame, key)
        local deltaX, deltaY = 0, 0
        if key == "LEFT" then
            deltaX = -1
        elseif key == "RIGHT" then
            deltaX = 1
        elseif key == "UP" then
            deltaY = 1
        elseif key == "DOWN" then
            deltaY = -1
        else
            if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
            return
        end

        local focus = _G.GetCurrentKeyBoardFocus and _G.GetCurrentKeyBoardFocus()
        if focus and focus.IsObjectType and focus:IsObjectType("EditBox") then return end

        if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(false) end
        if not NudgePreview(deltaX, deltaY) and frame.SetPropagateKeyboardInput then
            frame:SetPropagateKeyboardInput(true)
        end
    end)
    previewFrame:SetScript("OnHide", function(frame)
        SetPreviewSelected(false)
        if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
    end)
    previewFrame:SetScript("OnDragStart", function(frame)
        if not previewEnabled then return end
        if InCombatLockdown and InCombatLockdown() then
            PrintMoveError("In combat - cannot move Focus Interrupt Tracker preview.")
            return
        end
        SetPreviewSelected(true)
        frame:StartMoving()
    end)
    previewFrame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        if not previewEnabled then return end

        local general = EnsureOptions()
        local centerX, centerY = frame:GetCenter()
        local parentX, parentY = ParentFrame:GetCenter()
        if centerX and centerY and parentX and parentY then
            general.focusKickIconOffsetX = Clamp(Round(centerX - parentX), -500, 500)
            general.focusKickIconOffsetY = Clamp(Round(centerY - parentY), -500, 500)
            ApplyIconLayout()
            if refreshPreviewLayout then refreshPreviewLayout() end
            SetPreviewSelected(true)
        end
    end)

    previewFrame:Hide()
    ApplyTimeTextFont()
    return previewFrame
end

refreshPreviewLayout = function()
    if not previewEnabled then
        if previewFrame then previewFrame:Hide() end
        return
    end

    local general = EnsureOptions()
    local frame = EnsurePreviewFrame()
    local width = Clamp(general.focusKickIconWidth, 16, 128)
    local height = Clamp(general.focusKickIconHeight, 16, 128)

    frame:SetParent(ParentFrame)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", ParentFrame, "CENTER", general.focusKickIconOffsetX or 0, general.focusKickIconOffsetY or 0)
    frame:SetSize(width, height)

    if frame.icon then
        local texture = (iconFrame and iconFrame.icon and iconFrame.icon.GetTexture and iconFrame.icon:GetTexture())
            or "Interface\\Icons\\INV_Misc_QuestionMark"
        frame.icon:SetTexture(texture)
    end

    ApplyTimeTextFont()
    frame:Show()
end

local function SetPreviewEnabled(enabled)
    previewEnabled = enabled and true or false
    EnsurePreviewFrame()

    if not previewEnabled then
        if previewFrame._msufFakeTimerAG and previewFrame._msufFakeTimerAG.Stop then
            previewFrame._msufFakeTimerAG:Stop()
        end
        SetPreviewSelected(false)
        previewFrame:Hide()
        return
    end

    if not IsFocusKickEnabled() then
        previewEnabled = false
        if previewFrame._msufFakeTimerAG and previewFrame._msufFakeTimerAG.Stop then
            previewFrame._msufFakeTimerAG:Stop()
        end
        SetPreviewSelected(false)
        previewFrame:Hide()
        PrintMoveError("Enable Focus Interrupt Tracker first to use the on-screen preview.")
        return
    end

    if previewFrame._msufFakeTimerAG and previewFrame._msufFakeTimerAG.Play then
        previewFrame._msufFakeTimerAG:Play()
    end
    refreshPreviewLayout()
end

local function EnsureInitialized(shouldCreateFrame)
    EnsureOptions()
    initialized = true
    if shouldCreateFrame then
        EnsureIconFrame()
        ApplyIconLayout()
    end
end

local function InitFocusKickIcon()
    EnsureInitialized(IsFocusKickEnabled())
    if type(_G.MSUF_FocusKickDriver_ForceUpdate) == "function" then
        _G.MSUF_FocusKickDriver_ForceUpdate()
    end
end

local function UpdateFocusKickIconOptions()
    EnsureInitialized(IsFocusKickEnabled())
    if iconFrame then ApplyIconLayout() end
    if type(_G.MSUF_FocusKickDriver_ForceUpdate) == "function" then
        _G.MSUF_FocusKickDriver_ForceUpdate()
    end
    if refreshPreviewLayout then refreshPreviewLayout() end
end

local function IsPreviewEnabled()
    return previewEnabled
end

local function ApplyCastState(state)
    EnsureOptions()

    if not IsFocusKickEnabled() then
        if iconFrame then
            if iconFrame.timeText then
                iconFrame.timeText:SetText("")
                iconFrame.timeText:SetAlpha(0)
            end
            iconFrame:Hide()
        end
        return
    end

    EnsureIconFrame()
    if not (state and state.active == true) then
        if iconFrame.timeText then
            iconFrame.timeText:SetText("")
            iconFrame.timeText:SetAlpha(0)
        end
        iconFrame:Hide()
        return
    end

    if iconFrame.icon and state.icon then
        if type(_G.MSUF_SetIconTexture) == "function" then
            _G.MSUF_SetIconTexture(iconFrame.icon, state.icon, "")
        else
            iconFrame.icon:SetTexture(state.icon)
        end
    end

    iconFrame.MSUF_sourceCastBar = _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbar
        or ((_G.FocusCastBar and _G.FocusCastBar._msufCastbarDriver == true) and _G.FocusCastBar)
    ApplyInterruptibilityColor(state.isNotInterruptible == true, state.apiNotInterruptibleRaw)
    iconFrame:Show()
    ApplyIconLayout()
    AttachTimeDriver(state)
end

--- Cooldown-only repaint used by the shared interrupt-ready driver. The cast
--- state and layout remain owned by the focus engine subscriber; this path
--- only updates the visible border after the player's interrupt cooldown
--- starts, changes, or completes.
local function RefreshReadyColor()
    if not (iconFrame and iconFrame.IsShown and iconFrame:IsShown()) then
        return
    end

    local source = FocusSourceCastbar()
    ApplyInterruptibilityColor(
        source and source.isNotInterruptible == true,
        source and source._msufApiNotInterruptibleRaw
    )
end

local function PlayInterruptFeedbackIfEnabled()
    if not IsFocusKickEnabled() then return end
    EnsureIconFrame()
    PlayInterruptFeedback()
end

ExportPublic("MSUF_InitFocusKickIcon", InitFocusKickIcon)
ExportPublic("MSUF_UpdateFocusKickIconOptions", UpdateFocusKickIconOptions)
ExportPublic("MSUF_FocusKick_SetPreviewEnabled", SetPreviewEnabled)
ExportPublic("MSUF_FocusKick_IsPreviewEnabled", IsPreviewEnabled)
ExportPublic("MSUF_FocusKick_ApplyTimeTextFont", ApplyTimeTextFont)
ExportPublic("MSUF_FocusKick_ApplyCastState", ApplyCastState)
ExportPublic("MSUF_FocusKick_RefreshReadyColor", RefreshReadyColor)
ExportPublic("MSUF_FocusKick_PlayInterruptFeedback", PlayInterruptFeedbackIfEnabled)
