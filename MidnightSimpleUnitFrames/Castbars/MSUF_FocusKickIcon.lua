local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_FocusKickIcon.lua").Castbars
local Config = Castbars.Config
local Backend = Castbars.Backend
local Core = Castbars.Core
local FocusDriver = Castbars.FocusDriver
local FocusKick = Castbars.FocusKick
local Frames = Castbars.Frames
local KickReady = Castbars.KickReady
local Manager = Castbars.Manager
local PublicAPI = Castbars.PublicAPI
---
--- Visual widget for the focus-kick replacement cast display. The StateDriver
--- owns enable checks, event registration, and cast-state selection; this file
--- owns the draggable icon frame, copied time text, border coloring, and short
--- interrupt feedback animation.

local Publish = PublicAPI.Publish

--- Kernel (Util, Libs), State defaults and the Runtime fonts, colours and font
--- registry load before this file in every client TOC.
local FILE = "Castbars/MSUF_FocusKickIcon.lua"
local Require = MSUF.Require
local Optional = MSUF.Optional
local PixelLayoutRegion = Require("MSUF_PixelLayoutRegion", FILE)
local GetCastbarTimeFormat = Require("MSUF_GetCastbarTimeFormat", FILE)
local GetConfiguredFontColor = Require("MSUF_GetConfiguredFontColor", FILE)
local SetIconTexture = Require("MSUF_SetIconTexture", FILE)
local EnsureDB = Optional("MSUF_EnsureDB")
local ResolveSafeFontPath = Require("MSUF_ResolveSafeFontPath", FILE)
local ApplyResolvedFont = Require("MSUF_ApplyResolvedFont", FILE)

local ParentFrame = UIParent
local After = C_Timer and C_Timer.After

local iconFrame
local previewFrame
local previewEnabled = false
local previewSelected = false
local refreshPreviewLayout
local initialized = false

local function EnsureOptions()
    if type(EnsureDB) == "function" then EnsureDB() end

    local db = Config.EnsureSource()

    local general = db.general
    if general.enableFocusKickIcon == nil then general.enableFocusKickIcon = false Config.Invalidate() end
    if general.focusKickShowCastbar == nil then general.focusKickShowCastbar = false Config.Invalidate() end
    if general.focusKickIconOffsetX == nil then general.focusKickIconOffsetX = 300 Config.Invalidate() end
    if general.focusKickIconOffsetY == nil then general.focusKickIconOffsetY = 0 Config.Invalidate() end
    if general.focusKickIconWidth == nil then general.focusKickIconWidth = 40 Config.Invalidate() end
    if general.focusKickIconHeight == nil then general.focusKickIconHeight = 40 Config.Invalidate() end
    return general
end

local function IsFocusKickEnabled()
    local record = Config.Read("focus")
    return record.enabled and record.unit.enabled ~= false and record.geometry.enableFocusKickIcon == true
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
        or Frames.focus
end

local function DetachTimeDriver()
    if not iconFrame then return end

    local runtime = Castbars.Runtime
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
        then
            runtime:PrepareWork(source)
            Manager.RegisterCastbar(source)
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
    -- Kernel/MSUF_Util.lua owns the castbar time format.
    local format = GetCastbarTimeFormat("focus", general) or "CURRENT"

    local runtime = Castbars.Runtime
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
    Manager.RegisterCastbar(source)

    local text = source.timeText:GetText()
    if issecretvalue and issecretvalue(text) == true then
        iconFrame.timeText:SetText(text)
    else
        iconFrame.timeText:SetText(text or "")
    end
end

--- One time-text font apply (file scope: a cast state must not build a closure).
local function ApplyTimeTextFontTo(fs, fontPath, fontSize, fontFlags, fontKey)
    if not fs then return end
    ApplyResolvedFont(fs, fontPath, fontSize, fontFlags, fontKey)
end

local function ApplyTimeTextFont()
    local general = EnsureOptions()
    local fontPath = Core.GetFontPath() or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local fontFlags = Core.GetFontFlags() or "OUTLINE"
    local fontSize = ResolveTextSize(general)
    local g = Config.Read().general
    local fontKey = g and g.fontKey
    fontPath = ResolveSafeFontPath(fontPath, fontSize, fontFlags, fontKey)
    ApplyTimeTextFontTo(iconFrame and iconFrame.timeText, fontPath, fontSize, fontFlags, fontKey)
    ApplyTimeTextFontTo(previewFrame and previewFrame.timeText, fontPath, fontSize, fontFlags, fontKey)

    local red, green, blue = GetConfiguredFontColor()
    if red and green and blue then
        if iconFrame and iconFrame.timeText then iconFrame.timeText:SetTextColor(red, green, blue, 1) end
        if previewFrame and previewFrame.timeText then previewFrame.timeText:SetTextColor(red, green, blue, 1) end
    end
end

-- Focus Kick takes the aura icon shapes (Auras3/MSUF_Auras3_IconShape.lua).
local function IconShapes()
    local auras = MSUF.MSUF_Auras3
    return auras and auras.IconShape
end

--- The icon shape (unset: rectangular). The icon has no portrait to follow, so
--- Shape.Resolve reads Follow Portrait as rectangular.
local function FocusKickShape(general)
    local shapes = IconShapes()
    if not shapes then return "RECTANGLE" end
    return (shapes.Resolve(general.focusKickIconShape))
end

-- A shaped icon's border: the shared shape ring where the square icon draws its
-- four edges (2 px, inside the icon). The edges stay tinted while hidden, so the
-- ring takes their colour when it is drawn.
local ringStyle = { borderEnabled = true, borderThickness = 2, borderPlacement = "inner" }

local function SetEdgeColor(red, green, blue, alpha)
    if not (iconFrame and iconFrame.edges) then return end
    alpha = alpha or 1

    for index = 1, #iconFrame.edges do
        iconFrame.edges[index]:SetVertexColor(red, green, blue, alpha)
    end
end

local function SetEdgeAndRingColor(red, green, blue, alpha)
    SetEdgeColor(red, green, blue, alpha)
    if iconFrame then IconShapes().TintBorderRings(iconFrame, red, green, blue, alpha or 1) end
end

-- The ready and interrupt colours (cast states, in combat too) go through
-- this. The layout picks it: a square icon keeps the plain edge painter and
-- pays nothing for shapes; a shaped one also tints its ring.
local SetBorderColor = SetEdgeColor

--- Masks the backdrop and the spell icon of `frame` with the icon shape. The
--- live icon (`edges`) also swaps its square edges for the shape ring. A
--- never-shaped rectangular icon is left untouched.
local function ApplyFocusKickShape(frame, general, edges)
    local shapes = IconShapes()
    if not shapes then return end
    local shape = shapes.ApplyIconShape(frame, FocusKickShape(general), nil, true, frame.bg, frame.icon)
    if not (edges and frame._msufA3AuraShapeMask) then return end
    local shaped = shape ~= shapes.RECTANGLE
    for index = 1, #edges do edges[index]:SetShown(not shaped) end
    ringStyle.borderR, ringStyle.borderG, ringStyle.borderB, ringStyle.borderA = edges[1]:GetVertexColor()
    shapes.ApplyBorderRings(frame, shaped and ringStyle or nil, shape)
    SetBorderColor = shaped and SetEdgeAndRingColor or SetEdgeColor
end

local function ApplyInterruptibilityColor(isNotInterruptible, apiNotInterruptibleRaw)
    if not iconFrame then return end
    KickReady.KickReady_Init()

    if iconFrame.icon and iconFrame.icon.SetDesaturated then
        iconFrame.icon:SetDesaturated(isNotInterruptible == true)
    end

    if isNotInterruptible == true then
        SetBorderColor(0.6, 0.6, 0.6, 1)
        return
    end

    SetBorderColor(KickReady.KickReady_EvaluateRGBA(KickReady.KickReady_IsReady(), apiNotInterruptibleRaw))
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
    ApplyFocusKickShape(iconFrame, general, iconFrame.edges)
    ApplyTimeTextFont()
    -- The settings this geometry came from; a drag or the interrupt shake
    -- clears them while they move the icon themselves.
    iconFrame._msufFocusKickLayoutShape = general.focusKickIconShape
    iconFrame._msufFocusKickLayoutW = general.focusKickIconWidth
    iconFrame._msufFocusKickLayoutH = general.focusKickIconHeight
    iconFrame._msufFocusKickLayoutX = general.focusKickIconOffsetX
    iconFrame._msufFocusKickLayoutY = general.focusKickIconOffsetY
    iconFrame._msufFocusKickLayoutValid = true
end

local function InvalidateIconLayout()
    if iconFrame then iconFrame._msufFocusKickLayoutValid = nil end
end

--- True while the icon still sits where the current settings put it.
local function IconLayoutCurrent(general)
    return iconFrame._msufFocusKickLayoutValid == true
        and iconFrame._msufFocusKickLayoutShape == general.focusKickIconShape
        and iconFrame._msufFocusKickLayoutW == general.focusKickIconWidth
        and iconFrame._msufFocusKickLayoutH == general.focusKickIconHeight
        and iconFrame._msufFocusKickLayoutX == general.focusKickIconOffsetX
        and iconFrame._msufFocusKickLayoutY == general.focusKickIconOffsetY
end

local function EnsureIconFrame()
    if iconFrame then return iconFrame end

    iconFrame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_FocusKickIcon", ParentFrame, "BackdropTemplate"))
    Frames.Register("focusKick", nil, iconFrame)
    iconFrame:SetFrameStrata("HIGH")
    iconFrame:SetFrameLevel(50)
    iconFrame:Hide()
    iconFrame:HookScript("OnHide", DetachTimeDriver)

    iconFrame.bg = PixelLayoutRegion(iconFrame:CreateTexture(nil, "BACKGROUND"))
    iconFrame.bg:SetAllPoints()
    iconFrame.bg:SetColorTexture(0, 0, 0, 0.9)

    iconFrame.icon = PixelLayoutRegion(iconFrame:CreateTexture(nil, "ARTWORK"))
    iconFrame.icon:SetPoint("TOPLEFT", 1, -1)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    iconFrame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    iconFrame.edges = {}
    for index = 1, 4 do
        local edge = PixelLayoutRegion(iconFrame:CreateTexture(nil, "OVERLAY", nil, 7))
        edge:SetTexture("Interface\\Buttons\\WHITE8x8")
        iconFrame.edges[index] = edge
    end

    iconFrame.timeText = PixelLayoutRegion(iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    iconFrame.timeText:SetPoint("BOTTOM", iconFrame, "BOTTOM", 0, 2)
    iconFrame.timeText:SetJustifyH("CENTER")
    iconFrame.timeText:SetText("")
    iconFrame.timeText:SetAlpha(0)

    iconFrame:EnableMouse(true)
    iconFrame:SetMovable(true)
    iconFrame:RegisterForDrag("LeftButton")
    iconFrame:SetScript("OnDragStart", function(frame)
        InvalidateIconLayout()
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
            Config.Invalidate()
        end

        ApplyIconLayout()
        if refreshPreviewLayout then refreshPreviewLayout() end
    end)

    ApplyIconLayout()
    return iconFrame
end

local feedbackGeneration = 0
local feedbackActive = false
local function PlayInterruptFeedback()
    if not iconFrame then return end
    feedbackGeneration = feedbackGeneration + 1
    local generation = feedbackGeneration
    feedbackActive = true
    iconFrame:Show()

    SetBorderColor(1, 0.2, 0.2, 1)
    if iconFrame.bg then iconFrame.bg:SetColorTexture(0, 0, 0, 0.9) end

    if After then
        After(0.18, function()
            if not iconFrame or generation ~= feedbackGeneration then return end
            feedbackActive = false
            if not IsFocusKickEnabled() or not iconFrame._msufFocusCastActive then
                iconFrame:Hide()
                return
            end
            local source = Frames.focus
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
        if generation ~= feedbackGeneration or not (iconFrame and iconFrame:IsShown()) then return end

        shakeStep = shakeStep + 1
        local direction = (shakeStep % 2 == 0) and -1 or 1
        InvalidateIconLayout()
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

local function Translate(text)
    local translate = MSUF.Translate
    if type(translate) == "function" then return translate(text) end
    return text
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

-- Kernel/MSUF_Util.lua loads before this file in every TOC. Resolved at use
-- time (the preview keyboard paths only), so castbar harnesses without it load.
local function InCombat(event)
    return MSUF.Util.InCombat(event)
end

local function NudgePreview(deltaX, deltaY)
    if not (previewEnabled and previewSelected) then return false end
    if InCombat() then return false end

    local general = EnsureOptions()
    local step = (IsControlKeyDown and IsControlKeyDown()) and 10
        or ((IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1)
    general.focusKickIconOffsetX = Clamp(Round((general.focusKickIconOffsetX or 0) + (deltaX or 0) * step), -500, 500)
    general.focusKickIconOffsetY = Clamp(Round((general.focusKickIconOffsetY or 0) + (deltaY or 0) * step), -500, 500)

    Config.Invalidate()
    ApplyIconLayout()
    if refreshPreviewLayout then refreshPreviewLayout() end
    SetPreviewSelected(true)
    return true
end

--- The preview takes the keyboard (arrow-key nudges) only out of combat.
--- SetPropagateKeyboardInput is restricted in combat, and OnKeyDown calls it
--- for every key, so a preview left on into combat raised a blocked action per
--- key press, and a nudge just before the pull left keybinds swallowed. The
--- keyboard is released at PLAYER_REGEN_DISABLED, while the lockdown has not
--- started yet (propagation back on first), and taken again at
--- PLAYER_REGEN_ENABLED. EnableKeyboard is protected only on protected frames.
local function SetPreviewKeyboard(frame, enabled)
    if InCombatLockdown and InCombatLockdown() then return false end
    if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
    frame:EnableKeyboard(enabled)
    return true
end

local function OnPreviewCombatEvent(frame, event)
    if InCombat(event) then
        SetPreviewKeyboard(frame, false)
    else
        SetPreviewKeyboard(frame, true)
    end
end

local function EnsurePreviewFrame()
    if previewFrame then return previewFrame end

    previewFrame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_FocusKickPreviewFrame", ParentFrame, "BackdropTemplate"))
    previewFrame:SetFrameStrata("HIGH")
    previewFrame:SetFrameLevel(70)
    previewFrame:SetMovable(true)
    previewFrame:EnableMouse(true)
    -- Built in combat: the keyboard waits for PLAYER_REGEN_ENABLED.
    SetPreviewKeyboard(previewFrame, true)
    previewFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    previewFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    previewFrame:SetScript("OnEvent", OnPreviewCombatEvent)

    previewFrame:RegisterForDrag("LeftButton")
    previewFrame.icon = PixelLayoutRegion(previewFrame:CreateTexture(nil, "ARTWORK"))
    previewFrame.icon:SetAllPoints()

    previewFrame._selBorder = PixelLayoutRegion(previewFrame:CreateTexture(nil, "OVERLAY"))
    previewFrame._selBorder:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", -3, 3)
    previewFrame._selBorder:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", 3, -3)
    previewFrame._selBorder:SetColorTexture(0.27, 0.53, 0.80, 0.45)
    previewFrame._selBorder:Hide()

    previewFrame.timeText = PixelLayoutRegion(previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
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
        -- A key reaching the preview in combat (built at the combat edge) only
        -- propagates: no restricted call and no nudge.
        if InCombat() then return end
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

        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.IsObjectType and focus:IsObjectType("EditBox") then return end

        if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(false) end
        if not NudgePreview(deltaX, deltaY) and frame.SetPropagateKeyboardInput then
            frame:SetPropagateKeyboardInput(true)
        end
    end)
    previewFrame:SetScript("OnHide", function(frame)
        SetPreviewSelected(false)
        if frame.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
            frame:SetPropagateKeyboardInput(true)
        end
    end)
    previewFrame:SetScript("OnDragStart", function(frame)
        if not previewEnabled then return end
        if InCombatLockdown and InCombatLockdown() then
            PrintMoveError(Translate("In combat - cannot move Focus Interrupt Tracker preview."))
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
            Config.Invalidate()
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
    ApplyFocusKickShape(frame, general)

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
        PrintMoveError(Translate("Enable Focus Interrupt Tracker first to use the on-screen preview."))
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
    FocusDriver.FocusKickDriver_ForceUpdate()
end

local function UpdateFocusKickIconOptions()
    EnsureInitialized(IsFocusKickEnabled())
    if iconFrame then ApplyIconLayout() end
    FocusDriver.FocusKickDriver_ForceUpdate()
    if refreshPreviewLayout then refreshPreviewLayout() end
end

local function IsPreviewEnabled()
    return previewEnabled
end

local function ApplyCastState(state)
    local general = Config.Read("focus").geometry

    if not IsFocusKickEnabled() then
        feedbackGeneration = feedbackGeneration + 1
        feedbackActive = false
        if iconFrame then
            iconFrame._msufFocusCastActive = nil
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
        iconFrame._msufFocusCastActive = nil
        if iconFrame.timeText then
            iconFrame.timeText:SetText("")
            iconFrame.timeText:SetAlpha(0)
        end
        if not feedbackActive then iconFrame:Hide() end
        return
    end
    iconFrame._msufFocusCastActive = true
    feedbackGeneration = feedbackGeneration + 1
    feedbackActive = false

    if iconFrame.icon and state.icon then
        SetIconTexture(iconFrame.icon, state.icon, "")
    end

    iconFrame.MSUF_sourceCastBar = Frames.focus
    ApplyInterruptibilityColor(state.isNotInterruptible == true, state.apiNotInterruptibleRaw)
    iconFrame:Show()
    -- The option, font, drag and shake paths own the geometry; a cast state
    -- only re-lays the icon out when it no longer matches the settings (a
    -- profile switch, a drag or a shake in flight). The time-text font is
    -- reapplied on every cast state as before.
    if IconLayoutCurrent(general) then
        ApplyTimeTextFont()
    else
        ApplyIconLayout()
    end
    AttachTimeDriver(state)
end

--- Cooldown-only repaint used by the shared interrupt-ready driver. The cast
--- state and layout remain owned by the focus engine subscriber; this path
--- only updates the visible border after the player's interrupt cooldown
--- starts, changes, or completes.
local function RefreshReadyColor()
    if feedbackActive or not (iconFrame and iconFrame.IsShown and iconFrame:IsShown()) then
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

FocusKick.InitFocusKickIcon = InitFocusKickIcon
FocusKick.UpdateFocusKickIconOptions = UpdateFocusKickIconOptions
Publish("MSUF_UpdateFocusKickIconOptions", FocusKick.UpdateFocusKickIconOptions)
FocusKick.FocusKick_SetPreviewEnabled = SetPreviewEnabled
Publish("MSUF_FocusKick_SetPreviewEnabled", FocusKick.FocusKick_SetPreviewEnabled)
FocusKick.FocusKick_IsPreviewEnabled = IsPreviewEnabled
Publish("MSUF_FocusKick_IsPreviewEnabled", FocusKick.FocusKick_IsPreviewEnabled)
FocusKick.FocusKick_ApplyTimeTextFont = ApplyTimeTextFont
Publish("MSUF_FocusKick_ApplyTimeTextFont", FocusKick.FocusKick_ApplyTimeTextFont)
FocusKick.FocusKick_ApplyCastState = ApplyCastState
FocusKick.FocusKick_RefreshReadyColor = RefreshReadyColor
FocusKick.FocusKick_PlayInterruptFeedback = PlayInterruptFeedbackIfEnabled
