--- EditMode/MSUF_EditMode_HUD_Dock.lua - where the Edit Mode toolbar sits
--- The per-character dock state, auto-hide, the entry slide, the guided tour
--- bridge, the Position popup and dragging the toolbar to a screen edge.
local _, MSUF = ...
local ExportPublic = (MSUF or _G.MSUF_NS or {}).ExportPublic
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local DockUI, Kit, Selection = EM2.HUDDock, EM2.HUDKit, EM2.HUDSelection
local TH, HelpText, W8 = Kit.TH, Kit.HelpText, Kit.W8
local MakeFS, MakeBtn, ApplyHUDMaterial = Kit.MakeFS, Kit.MakeBtn, Kit.ApplyHUDMaterial
local DOCK_ALLOWED, DOCK_EDGE_DEFAULT, DOCK_SNAP_EDGE_PX = Kit.DOCK_ALLOWED, Kit.DOCK_EDGE_DEFAULT, Kit.DOCK_SNAP_EDGE_PX
local DOCK_HORIZONTAL_W, DOCK_HORIZONTAL_H = Kit.DOCK_HORIZONTAL_W, Kit.DOCK_HORIZONTAL_H
local CurrentSelectionKey = Selection.CurrentSelectionKey
local GROUP_KEY_TO_KIND, LABEL_BY_KEY = Selection.GROUP_KEY_TO_KIND, Selection.LABEL_BY_KEY
local floor, max = math.floor, math.max

--- The toolbar frames and its layout pass. MSUF_EditMode_HUD.lua builds them
--- and hands them over through DockUI.AttachToolbar.
local hudFrame, row2Frame, ApplyDockLayout
local RefreshPositionPopup, SetDockExpanded, ScheduleDockAutoHide, StopDockDrag

--- The toolbar is a cold, event-driven workspace preference.  It deliberately
--- lives outside the active unit-frame profile so switching/importing profiles
--- cannot move the user's Edit Mode chrome around the screen.
local DockCharKey = _G.MSUF_GetCharKey

local function ClampDockNumber(value, low, high, fallback)
    value = tonumber(value)
    if not value then value = fallback end
    if value < low then return low end
    if value > high then return high end
    return value
end

local function EnsureDockState()
    if DockUI.state then return DockUI.state end
    ExportPublic("MSUF_GlobalDB", type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {})

    local global = _G.MSUF_GlobalDB
    global.char = type(global.char) == "table" and global.char or {}
    local charKey = DockCharKey()
    local charDB = type(global.char[charKey]) == "table" and global.char[charKey] or {}
    global.char[charKey] = charDB
    local state = type(charDB.editModeHUDState) == "table" and charDB.editModeHUDState or {}
    charDB.editModeHUDState = state
    state.version = 1
    state.dock = DOCK_ALLOWED[state.dock] and state.dock or "TOP"
    state.snapToEdge = state.snapToEdge ~= false
    state.autoHide = state.autoHide == true
    state.edgeOffset = ClampDockNumber(state.edgeOffset, 0, 64, DOCK_EDGE_DEFAULT)
    state.freeX = ClampDockNumber(state.freeX, -4096, 4096, 0)
    state.freeY = ClampDockNumber(state.freeY, -4096, 4096, 0)
    DockUI.state = state
    return state
end

local function IsVerticalDock(dock)
    return dock == "LEFT" or dock == "RIGHT"
end

local function DockContextLabel(key)
    if key == nil then key = CurrentSelectionKey() end
    if GROUP_KEY_TO_KIND[key] then return HelpText("Groups") end
    if key and LABEL_BY_KEY[key] then return HelpText(LABEL_BY_KEY[key]) end
    return HelpText("Frames")
end

local function RefreshDockContext(key)
    local btn = DockUI.contextBtn
    if not (btn and btn._label) then return end
    local text = DockContextLabel(key)
    if btn._msufContextText == text then return end
    btn._msufContextText = text
    btn._label:SetText(text)
end

local function DockMouseOver(frame)
    return frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver()
end

local autoHideGeneration = 0
function DockUI.ScheduleLayoutSettle()
    DockUI.layoutGeneration = (DockUI.layoutGeneration or 0) + 1
    local generation = DockUI.layoutGeneration
    C_Timer.After(0, function()
        if generation ~= DockUI.layoutGeneration then return end
        if not (hudFrame and hudFrame:IsShown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        --- The entry slide owns the anchor from the moment it is armed until it
        --- lands; FinishDockIntro re-arms this settle so the measured widths
        --- still get applied.
        if DockUI.introPlaying or DockUI.introArmed then return end
        ApplyDockLayout()
    end)
end

SetDockExpanded = function(expanded)
    if not hudFrame then return end
    local state = EnsureDockState()
    --- Both dropdowns hang off UIParent, so the pointer sitting in one of them no
    --- longer counts as hovering the toolbar. Without this the dock fades out from
    --- under an open list.
    if not state.autoHide or expanded
        or DockMouseOver(DockUI.positionPopup) or DockMouseOver(DockUI.framePicker)
    then
        hudFrame:SetAlpha(1)
        if row2Frame and hudFrame:IsShown() then row2Frame:Show() end
    else
        hudFrame:SetAlpha(0.12)
        if row2Frame then row2Frame:Hide() end
    end
end

ScheduleDockAutoHide = function()
    autoHideGeneration = autoHideGeneration + 1
    local generation = autoHideGeneration
    if not (hudFrame and hudFrame:IsShown()) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local state = EnsureDockState()
    if not state.autoHide then
        SetDockExpanded(true)
        return
    end
    C_Timer.After(0.45, function()
        if generation ~= autoHideGeneration then return end
        if not (hudFrame and hudFrame:IsShown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if DockMouseOver(hudFrame) or DockMouseOver(row2Frame)
            or DockMouseOver(DockUI.positionPopup) or DockMouseOver(DockUI.framePicker)
        then
            return
        end
        SetDockExpanded(false)
    end)
end

local function AttachDockHover(frame)
    if not (frame and frame.HookScript) or frame._msufDockHoverHooked then return end
    frame._msufDockHoverHooked = true
    frame:HookScript("OnEnter", function()
        autoHideGeneration = autoHideGeneration + 1
        SetDockExpanded(true)
    end)
    frame:HookScript("OnLeave", function() ScheduleDockAutoHide() end)
end

--- Dock anchor and entry slide
---
--- One authority places the toolbar against its screen edge.  The entry slide
--- reuses it with a displaced start offset, so the animation can never drift
--- away from the layout geometry - and FREE (a dragged, undocked bar) keeps its
--- own centre offsets.
DockUI.introTravel = 34
DockUI.introDuration = 0.34

DockUI.AnchorDock = function(dock, edge, offsetX, offsetY)
    if not (hudFrame and UIParent) then return end
    offsetX = tonumber(offsetX) or 0
    offsetY = tonumber(offsetY) or 0
    edge = tonumber(edge) or 0
    hudFrame:ClearAllPoints()
    if dock == "LEFT" then
        hudFrame:SetPoint("LEFT", UIParent, "LEFT", edge + offsetX, offsetY)
    elseif dock == "RIGHT" then
        hudFrame:SetPoint("RIGHT", UIParent, "RIGHT", -edge + offsetX, offsetY)
    elseif dock == "BOTTOM" then
        hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", offsetX, edge + offsetY)
    elseif dock == "FREE" then
        local state = EnsureDockState()
        hudFrame:SetPoint("CENTER", UIParent, "CENTER", state.freeX + offsetX, state.freeY + offsetY)
    else
        hudFrame:SetPoint("TOP", UIParent, "TOP", offsetX, -edge + offsetY)
    end
end

--- Where the bar starts before sliding home: outward, past its docked edge.
--- An undocked bar has no edge to come from and only fades.
DockUI.IntroOffset = function(dock)
    local travel = tonumber(DockUI.introTravel) or 0
    if dock == "BOTTOM" then return 0, -travel end
    if dock == "LEFT" then return -travel, 0 end
    if dock == "RIGHT" then return travel, 0 end
    if dock == "FREE" then return 0, 0 end
    return 0, travel
end

--- Restores the toolbar's own anchor, clamping and alpha authority.  Kept
--- idempotent because both OnFinished and an explicit Stop() land here.
DockUI.FinishDockIntro = function()
    if not DockUI.introPlaying then return end
    DockUI.introPlaying = nil
    if not hudFrame then return end
    if DockUI.introUnclamped then
        DockUI.introUnclamped = nil
        hudFrame:SetClampedToScreen(true)
    end
    local state = EnsureDockState()
    DockUI.AnchorDock(state.dock, state.edgeOffset)
    if hudFrame:IsShown() then
        SetDockExpanded(true)
        ScheduleDockAutoHide()
        --- The settle relayout skips itself while the slide owns the anchor,
        --- so re-arm it now that the measured widths matter again.
        DockUI.ScheduleLayoutSettle()
    end
end

DockUI.StopDockIntro = function()
    DockUI.introArmed = nil
    local group = DockUI.introGroup
    if group and DockUI.introPlaying then group:Stop() end
    DockUI.FinishDockIntro()
end

--- The toolbar fades in from whichever screen edge it is docked to.  The whole
--- move is one C-side animation group: no OnUpdate, no per-frame Lua, and no
--- cost at all once it has landed.  Edit Mode exits on PLAYER_REGEN_DISABLED,
--- so none of this can exist during combat.
DockUI.PlayDockIntro = function()
    local group = DockUI.introGroup
    if not (group and hudFrame and hudFrame:IsShown()) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local db = _G.MSUF_DB
    local general = type(db) == "table" and db.general or nil
    if type(general) == "table" and (general.reduceMotion == true or general.reducedMotion == true) then
        return false
    end
    local state = EnsureDockState()
    local offsetX, offsetY = DockUI.IntroOffset(state.dock)
    if DockUI.introPlaying then group:Stop() end
    DockUI.introPlaying = true
    --- Clamping is derived from the anchor, so a start point past the screen
    --- edge would be pulled back before the slide could play.
    if not DockUI.introUnclamped then
        DockUI.introUnclamped = true
        hudFrame:SetClampedToScreen(false)
    end
    DockUI.AnchorDock(state.dock, state.edgeOffset, offsetX, offsetY)
    if DockUI.introSlide then DockUI.introSlide:SetOffset(-offsetX, -offsetY) end
    group:Play()
    return true
end

--- Consumers add their own controls to the toolbar *after* HUD.Show returns -
--- the group-frame bridge wraps it, and the Dominos/Danders slots fill in the
--- same way.  A child anchored into an already-moving parent resolves against
--- the in-flight position and then drifts, so the slide waits one frame until
--- the bar is fully assembled.  Cost is one zero-delay timer per Edit Mode
--- entry, and combat cannot reach any of it.
DockUI.ArmDockIntro = function()
    if not (DockUI.introGroup and hudFrame and hudFrame:IsShown()) then return false end
    if not (C_Timer and C_Timer.After) then return DockUI.PlayDockIntro() end
    DockUI.introArmed = (DockUI.introArmed or 0) + 1
    local token = DockUI.introArmed
    C_Timer.After(0, function()
        if token ~= DockUI.introArmed then return end
        DockUI.introArmed = nil
        DockUI.PlayDockIntro()
    end)
    return true
end

--- The full guided tour now lives inside the native MSUF menu.  Keep this
--- bridge late-bound because Menu2 can be installed after the Edit Mode HUD.
local function ResolveMenu2()
    local menu = type(MSUF) == "table" and MSUF.MSUF2 or nil
    if type(menu) ~= "table" then menu = _G.MSUF2 end
    return type(menu) == "table" and menu or nil
end

local function OpenMenuGuidedTourAtEditMode()
    local menu = ResolveMenu2()
    local menuOpened = false
    if menu and type(menu.Open) == "function" then
        local result = menu.Open()
        menuOpened = result ~= false
    elseif type(_G.MSUF2_Open) == "function" then
        local result = _G.MSUF2_Open()
        menuOpened = result ~= false
    end

    -- Resolve again after opening: lazy menu installation may have populated
    -- MSUF.MSUF2 during the call above.
    menu = ResolveMenu2()
    local openStage = menu and menu.OpenGuidedTourAtStage
    if type(openStage) == "function" then
        if openStage("edit_mode") ~= false then return true end
    end
    return menuOpened
end

--- Help opens the menu-native guided tour at its Edit Mode chapter.
DockUI.OpenGuidedTour = OpenMenuGuidedTourAtEditMode

local function UpdateDockSwitch(row, enabled)
    if not row then return end
    row._enabled = enabled and true or false
    local r, g, b = TH.onR, TH.onG, TH.onB
    if row._track then
        if enabled then row._track:SetColorTexture(r * 0.42, g * 0.42, b * 0.42, 0.98)
        else row._track:SetColorTexture(0.16, 0.19, 0.26, 0.98) end
    end
    if row._knob then
        row._knob:ClearAllPoints()
        row._knob:SetPoint(enabled and "RIGHT" or "LEFT", row, enabled and "RIGHT" or "LEFT", enabled and -3 or 3, 0)
        row._knob:SetColorTexture(enabled and 0.92 or 0.66, enabled and 0.97 or 0.70, enabled and 1.00 or 0.76, 1)
    end
end

local function CreateDockSwitch(parent, labelText, y, stateKey)
    local label = MakeFS(parent, "caption", TH.textR, TH.textG, TH.textB, 0.92)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    label:SetText(HelpText(labelText))
    local row = DockUI.PixelLayoutRegion(CreateFrame("Button", nil, parent))
    row:SetSize(40, 20)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y + 3)
    row:RegisterForClicks("LeftButtonUp")
    local track = DockUI.PixelLayoutRegion(row:CreateTexture(nil, "BACKGROUND"))
    track:SetAllPoints()
    local knob = DockUI.PixelLayoutRegion(row:CreateTexture(nil, "ARTWORK"))
    knob:SetSize(14, 14)
    row._track, row._knob = track, knob
    row:SetScript("OnClick", function()
        local state = EnsureDockState()
        state[stateKey] = not state[stateKey]
        if stateKey == "autoHide" then SetDockExpanded(true) end
        if RefreshPositionPopup then RefreshPositionPopup() end
        if stateKey == "autoHide" then ScheduleDockAutoHide() end
    end)
    AttachDockHover(row)
    return row
end

local function PlacePositionPopup()
    local positionPopup, positionBtn = DockUI.positionPopup, DockUI.positionBtn
    if not (positionPopup and positionBtn) then return end
    local dock = EnsureDockState().dock
    positionPopup:ClearAllPoints()
    if dock == "BOTTOM" then
        positionPopup:SetPoint("BOTTOM", positionBtn, "TOP", 0, 10)
    elseif dock == "LEFT" then
        positionPopup:SetPoint("LEFT", positionBtn, "RIGHT", 10, 0)
    elseif dock == "RIGHT" then
        positionPopup:SetPoint("RIGHT", positionBtn, "LEFT", -10, 0)
    else
        positionPopup:SetPoint("TOP", positionBtn, "BOTTOM", 0, -10)
    end
end

local function EnsurePositionPopup()
    if DockUI.positionPopup then return DockUI.positionPopup end
    local popup = DockUI.PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_HUD_PositionPopup", UIParent, "BackdropTemplate"))
    popup:SetSize(356, 326)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(1300)
    popup:SetClampedToScreen(true)
    DockUI.PixelLayoutRegion(popup, "SetBackdrop", { bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    popup:SetBackdropColor(TH.r1Bg[1], TH.r1Bg[2], TH.r1Bg[3], 0.985)
    popup:SetBackdropBorderColor(TH.onR, TH.onG, TH.onB, 0.62)
    ApplyHUDMaterial(popup, "popup")
    popup:EnableMouse(true)
    popup:Hide()
    DockUI.positionPopup = popup

    local heading = MakeFS(popup, "body", TH.textR, TH.textG, TH.textB, 1)
    heading:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -15)
    heading:SetText(HelpText("Toolbar position"))

    local monitor = DockUI.PixelLayoutRegion(CreateFrame("Frame", nil, popup, "BackdropTemplate"))
    monitor:SetSize(170, 96)
    monitor:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -46)
    DockUI.PixelLayoutRegion(monitor, "SetBackdrop", { bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=2,right=2,top=2,bottom=2} })
    monitor:SetBackdropColor(0.025, 0.055, 0.090, 0.96)
    monitor:SetBackdropBorderColor(TH.edge[1], TH.edge[2], TH.edge[3], 0.85)
    local screen = DockUI.PixelLayoutRegion(monitor:CreateTexture(nil, "BACKGROUND", nil, 1))
    screen:SetPoint("TOPLEFT", monitor, "TOPLEFT", 10, -10)
    screen:SetPoint("BOTTOMRIGHT", monitor, "BOTTOMRIGHT", -10, 10)
    screen:SetColorTexture(0.07, 0.12, 0.18, 0.96)
    popup._dockPreviewDots = {}
    local dotAnchors = {
        TOP = { "TOP", monitor, "TOP", 0, -6 }, BOTTOM = { "BOTTOM", monitor, "BOTTOM", 0, 6 },
        LEFT = { "LEFT", monitor, "LEFT", 6, 0 }, RIGHT = { "RIGHT", monitor, "RIGHT", -6, 0 },
    }
    for dock, point in pairs(dotAnchors) do
        local dot = DockUI.PixelLayoutRegion(monitor:CreateTexture(nil, "OVERLAY"))
        dot:SetSize(10, 10)
        dot:SetPoint(unpack(point))
        dot:SetColorTexture(0.45, 0.53, 0.64, 0.92)
        popup._dockPreviewDots[dock] = dot
    end

    popup._dockButtons = {}
    local choices = { { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" } }
    for i, choice in ipairs(choices) do
        local dock, label = choice[1], choice[2]
        local button = MakeBtn(popup, label, 122, 26, "caption", function()
            local state = EnsureDockState()
            state.dock = dock
            state.snapToEdge = true
            if ApplyDockLayout then
                ApplyDockLayout()
                DockUI.ScheduleLayoutSettle()
            end
            if RefreshPositionPopup then RefreshPositionPopup() end
        end)
        button:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, -43 - (i - 1) * 30)
        popup._dockButtons[dock] = button
        AttachDockHover(button)
    end

    local divider = DockUI.PixelLayoutRegion(popup:CreateTexture(nil, "ARTWORK"))
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -158)
    divider:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, -158)
    divider:SetColorTexture(TH.edge[1], TH.edge[2], TH.edge[3], 0.52)

    popup._snapSwitch = CreateDockSwitch(popup, "Snap to screen edge", -178, "snapToEdge")
    popup._autoHideSwitch = CreateDockSwitch(popup, "Auto-hide", -211, "autoHide")

    local offsetLabel = MakeFS(popup, "caption", TH.textR, TH.textG, TH.textB, 0.92)
    offsetLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 18, -249)
    offsetLabel:SetText(HelpText("Edge offset"))
    local minus = MakeBtn(popup, "-", 28, 24, "body", function()
        local state = EnsureDockState()
        state.edgeOffset = ClampDockNumber(state.edgeOffset - 2, 0, 64, DOCK_EDGE_DEFAULT)
        if ApplyDockLayout then
            ApplyDockLayout()
            DockUI.ScheduleLayoutSettle()
        end
        RefreshPositionPopup()
    end)
    minus:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -102, -243)
    local plus = MakeBtn(popup, "+", 28, 24, "body", function()
        local state = EnsureDockState()
        state.edgeOffset = ClampDockNumber(state.edgeOffset + 2, 0, 64, DOCK_EDGE_DEFAULT)
        if ApplyDockLayout then
            ApplyDockLayout()
            DockUI.ScheduleLayoutSettle()
        end
        RefreshPositionPopup()
    end)
    plus:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -18, -243)
    local offsetValue = MakeFS(popup, "caption", TH.onR, TH.onG, TH.onB, 1)
    offsetValue:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -52, -249)
    offsetValue:SetWidth(46)
    offsetValue:SetJustifyH("CENTER")
    popup._offsetValue = offsetValue
    AttachDockHover(minus)
    AttachDockHover(plus)

    local dragHelp = MakeFS(popup, "micro", TH.mutedR, TH.mutedG, TH.mutedB, 0.76)
    dragHelp:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 18, 14)
    dragHelp:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -18, 14)
    dragHelp:SetJustifyH("LEFT")
    dragHelp:SetText(HelpText("Drag the six-dot handle to move and dock the toolbar."))

    DockUI.positionPopupEventFrame = CreateFrame("Frame")
    DockUI.positionPopupEventFrame:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            local openPopup, button = DockUI.positionPopup, DockUI.positionBtn
            if openPopup and openPopup:IsShown()
                and not DockMouseOver(openPopup) and not DockMouseOver(button) then
                openPopup:Hide()
            end
        end)
    end)
    popup:SetScript("OnShow", function()
        PlacePositionPopup()
        RefreshPositionPopup()
        DockUI.positionPopupEventFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        SetDockExpanded(true)
    end)
    popup:SetScript("OnHide", function()
        DockUI.positionPopupEventFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        local button = DockUI.positionBtn
        if button and button.SetActive then button:SetActive(false) end
        ScheduleDockAutoHide()
    end)
    AttachDockHover(popup)
    AttachDockHover(monitor)
    return popup
end

RefreshPositionPopup = function()
    local positionPopup, positionBtn = DockUI.positionPopup, DockUI.positionBtn
    if not positionPopup then return end
    local state = EnsureDockState()
    for dock, button in pairs(positionPopup._dockButtons or {}) do
        if button.SetActive then button:SetActive(state.dock == dock) end
        local dot = positionPopup._dockPreviewDots and positionPopup._dockPreviewDots[dock]
        if dot then
            if state.dock == dock then dot:SetColorTexture(TH.onR, TH.onG, TH.onB, 1)
            else dot:SetColorTexture(0.45, 0.53, 0.64, 0.92) end
        end
    end
    UpdateDockSwitch(positionPopup._snapSwitch, state.snapToEdge)
    UpdateDockSwitch(positionPopup._autoHideSwitch, state.autoHide)
    if positionPopup._offsetValue then positionPopup._offsetValue:SetText(floor(state.edgeOffset + 0.5) .. " px") end
    if positionBtn and positionBtn.SetActive then positionBtn:SetActive(positionPopup:IsShown()) end
    PlacePositionPopup()
end

local function NearestDockEdge()
    if not (hudFrame and UIParent) then return "TOP" end
    local left, right = hudFrame:GetLeft(), hudFrame:GetRight()
    local top, bottom = hudFrame:GetTop(), hudFrame:GetBottom()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not (left and right and top and bottom and width and height) then return "TOP" end
    local distances = { LEFT = left, RIGHT = width - right, TOP = height - top, BOTTOM = bottom }
    local nearest, best = "TOP", math.huge
    for dock, distance in pairs(distances) do
        distance = math.abs(tonumber(distance) or math.huge)
        if distance < best then nearest, best = dock, distance end
    end
    return nearest, best
end

local function CursorPositionInUIParent()
    if not (UIParent and UIParent.GetEffectiveScale and GetCursorPosition) then return nil, nil end
    local scale = tonumber(UIParent:GetEffectiveScale()) or 1
    if scale == 0 then scale = 1 end
    local x, y = GetCursorPosition()
    if not (x and y) then return nil, nil end
    return x / scale, y / scale
end

local function ClampDockDragOffset(offsetX, offsetY)
    local screenW = tonumber(UIParent and UIParent:GetWidth()) or 1920
    local screenH = tonumber(UIParent and UIParent:GetHeight()) or 1080
    local frameW = tonumber(hudFrame and hudFrame:GetWidth()) or DOCK_HORIZONTAL_W
    local frameH = tonumber(hudFrame and hudFrame:GetHeight()) or DOCK_HORIZONTAL_H
    local maxX = max(0, (screenW - frameW) * 0.5)
    local maxY = max(0, (screenH - frameH) * 0.5)
    return ClampDockNumber(offsetX, -maxX, maxX, 0), ClampDockNumber(offsetY, -maxY, maxY, 0)
end

local function UpdateDockDrag()
    local drag = DockUI.drag
    if not (drag and hudFrame and UIParent) then return end
    if (InCombatLockdown and InCombatLockdown())
        or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
        StopDockDrag()
        return
    end
    local cursorX, cursorY = CursorPositionInUIParent()
    if not cursorX then return end
    local offsetX = drag.frameX + cursorX - drag.cursorX
    local offsetY = drag.frameY + cursorY - drag.cursorY
    offsetX, offsetY = ClampDockDragOffset(offsetX, offsetY)
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
end

StopDockDrag = function()
    if not hudFrame then return end
    DockUI.drag = nil
    hudFrame:SetScript("OnUpdate", nil)
    if DockUI.grip then DockUI.grip._dockDragging = nil end
    local state = EnsureDockState()
    local nearestDock, nearestDistance = NearestDockEdge()
    if state.snapToEdge and nearestDistance <= DOCK_SNAP_EDGE_PX then
        state.dock = nearestDock
    else
        local cx, cy = hudFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            state.freeX = ClampDockNumber(cx - ux, -4096, 4096, 0)
            state.freeY = ClampDockNumber(cy - uy, -4096, 4096, 0)
        end
        state.dock = "FREE"
    end
    ApplyDockLayout()
    DockUI.ScheduleLayoutSettle()
    RefreshPositionPopup()
end

DockUI.BeginDrag = function()
    if not (hudFrame and UIParent) or (InCombatLockdown and InCombatLockdown()) then return false end
    --- Dragging measures the frame's live centre, so the slide has to land
    --- before the first sample is taken.
    DockUI.StopDockIntro()
    local cursorX, cursorY = CursorPositionInUIParent()
    local frameX, frameY = hudFrame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not (cursorX and cursorY and frameX and frameY and parentX and parentY) then return false end
    DockUI.drag = {
        cursorX = cursorX,
        cursorY = cursorY,
        frameX = frameX - parentX,
        frameY = frameY - parentY,
    }
    hudFrame:SetScript("OnUpdate", UpdateDockDrag)
    return true
end

function DockUI.AttachToolbar(frame, row2, applyLayout)
    hudFrame, row2Frame, ApplyDockLayout = frame, row2, applyLayout
end

--- Hiding the toolbar drops a pending auto-hide fade.
function DockUI.CancelAutoHide()
    autoHideGeneration = autoHideGeneration + 1
end

--- The frame picker and the toolbar read these.
DockUI.EnsureDockState, DockUI.ClampDockNumber, DockUI.IsVerticalDock = EnsureDockState, ClampDockNumber, IsVerticalDock
DockUI.RefreshDockContext, DockUI.AttachDockHover = RefreshDockContext, AttachDockHover
DockUI.PlacePositionPopup, DockUI.EnsurePositionPopup, DockUI.RefreshPositionPopup = PlacePositionPopup, EnsurePositionPopup, RefreshPositionPopup
DockUI.SetDockExpanded, DockUI.ScheduleDockAutoHide, DockUI.StopDockDrag = SetDockExpanded, ScheduleDockAutoHide, StopDockDrag
