--- EditMode/MSUF_EditMode_Movers.lua - Edit Mode mover registration and dragging

--- MSUF_EM2_Movers.lua

--- MSUF_EM2_Movers.lua ? v9 Ticker-driven
--- Movers are dumb overlays. All drag math lives in Ticker.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Movers = {}
EM2.Movers = Movers

local max = math.max
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local U = EM2.Util or {}
local round = U.Round
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe
local Tr = U.Tr
local ThemeColor = U.ThemeColor
local SharedUI = U.SharedUI
local function FontSize(role)
    local ui = SharedUI and SharedUI()
    return ui and ui.FontSize and ui.FontSize(role) or (role == "micro" and 9 or 11)
end

local function T()
    local legacy = _G.MSUF_THEME or {}
    local bg = ThemeColor("card", { legacy.bgR or 0.08, legacy.bgG or 0.09, legacy.bgB or 0.10, legacy.bgA or 0.55 })
    local edge = ThemeColor("borderSoft", { legacy.edgeR or 0.20, legacy.edgeG or 0.30, legacy.edgeB or 0.50, legacy.edgeA or 0.60 })
    local text = ThemeColor("text", { legacy.textR or 0.92, legacy.textG or 0.94, legacy.textB or 1.00, legacy.textA or 1.00 })
    local accent = ThemeColor("accent", { legacy.titleR or 1.00, legacy.titleG or 0.82, legacy.titleB or 0.00, 1 })
    return {
        bgR = bg[1], bgG = bg[2], bgB = bg[3],
        edgeR = edge[1], edgeG = edge[2], edgeB = edge[3],
        textR = text[1], textG = text[2], textB = text[3],
        titleR = accent[1], titleG = accent[2], titleB = accent[3],
    }
end

local movers = {}
local moverParent
local pendingDragFrame
local pendingDragMover
local pendingDragStartX
local pendingDragStartY
local PENDING_DRAG_THRESHOLD = 3
local guidedCueMover

local function GuidedPlacementPending()
    local tour = MSUF and MSUF.GuidedTour6 or _G.MSUF_GuidedTour6
    if not (tour and type(tour.GetState) == "function") then return false end
    local state = tour:GetState()
    local preferences = state and state.preferences
    if not (state and state.status == "active" and preferences) then return false end
    if state.currentStageId == "group_edit_mode" then
        return preferences.groupEditModeMoved ~= true or preferences.groupEditModePopupOpened ~= true, "gf_party"
    end
    local anchor = preferences.unitframeCooldownAnchor
    return state.currentStageId == "edit_mode"
        and (anchor == "cooldown" or anchor == "independent")
        and (preferences.editModeMoved ~= true or preferences.editModePopupOpened ~= true), "player"
end

local function HideGuidedPlacementCue()
    local cue = guidedCueMover and guidedCueMover._msufGuidedPlacementCue
    if cue then cue:Hide() end
    guidedCueMover = nil
end

local function EnsureGuidedPlacementCue(mover)
    local cue = mover and mover._msufGuidedPlacementCue
    if cue then return cue end
    cue = CreateFrame("Frame", nil, mover)
    cue:SetAllPoints(mover)
    cue:EnableMouse(false)
    cue:SetFrameLevel((mover:GetFrameLevel() or 1) + 20)

    local function CreateArrow(point, relativePoint, x)
        local arrow = cue:CreateTexture(nil, "OVERLAY", nil, 7)
        local usedAtlas = false
        if arrow.SetAtlas then arrow:SetAtlas("NPE_ArrowRight", false); usedAtlas = true end
        if not usedAtlas then arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow") end
        arrow:SetSize(28, 28)
        arrow:SetPoint(point, mover, relativePoint, x, 0)
        local th = T()
        arrow:SetVertexColor(th.titleR, th.titleG, th.titleB, 1)
        return arrow
    end

    cue._leftArrow = CreateArrow("RIGHT", "LEFT", -10)
    cue._rightArrow = CreateArrow("LEFT", "RIGHT", 10)
    if cue._rightArrow.SetRotation then cue._rightArrow:SetRotation(math.pi) end
    cue._label = cue:CreateFontString(nil, "OVERLAY")
    cue._label:SetFont(FONT, FontSize("caption"), "OUTLINE")
    cue._label:SetPoint("BOTTOM", mover, "TOP", 0, 18)
    cue._label:SetText(Tr("Drag this frame once"))
    local th = T()
    cue._label:SetTextColor(th.titleR, th.titleG, th.titleB, 1)
    mover._msufGuidedPlacementCue = cue
    return cue
end

function Movers.RefreshGuidedPlacementCue()
    HideGuidedPlacementCue()
    local pending, preferredKey = GuidedPlacementPending()
    if not (moverParent and moverParent:IsShown() and pending) then return end
    local target = movers[preferredKey] or movers.player
    if not (target and target:IsShown()) then
        for _, mover in pairs(movers) do
            if mover:IsShown() then target = mover break end
        end
    end
    if not target then return end
    guidedCueMover = target
    local cue = EnsureGuidedPlacementCue(target)
    local tour = MSUF and MSUF.GuidedTour6 or _G.MSUF_GuidedTour6
    local state = tour and type(tour.GetState) == "function" and tour:GetState() or nil
    local preferences = state and state.preferences or {}
    local moved = preferredKey == "gf_party"
        and preferences.groupEditModeMoved == true
        or preferredKey ~= "gf_party" and preferences.editModeMoved == true
    cue._label:SetText(Tr(moved and "Click this frame for its size popup" or "Drag this frame once"))
    cue:Show()
end

local function RefreshUFPreview(reason)
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then return end
    if U.RefreshUFPreview then U.RefreshUFPreview(reason or "EM2_MOVERS") end
end

local IsConfigCombatLocked = U.IsConfigCombatLocked
local BlockConfigCombatLocked = U.BlockConfigCombatLocked

local function FrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
        return nil
    end
    if frame.IsShown and not frame:IsShown() then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local fS = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiS = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not fS or fS == 0 then fS = 1 end
    if not uiS or uiS == 0 then uiS = 1 end
    local ratio = fS / uiS
    return l * ratio, r * ratio, t * ratio, b * ratio
end

local function ExpandBounds(bounds, l, r, t, b)
    if not l then return bounds end
    if not bounds then
        return { l = l, r = r, t = t, b = b }
    end
    if l < bounds.l then bounds.l = l end
    if r > bounds.r then bounds.r = r end
    if t > bounds.t then bounds.t = t end
    if b < bounds.b then bounds.b = b end
    return bounds
end

local function ExpandRect(bounds, region)
    return ExpandBounds(bounds, FrameRectToUI(region))
end

local function UnitVisualBounds(frame)
    --- Unitframes can draw important parts outside the root frame
    --- (portrait, an attached powerbar). The edit overlay should match the
    --- visual object owned by the unit mover, while drag math keeps the
    --- root-frame offset stable. A detached powerbar has independent layout
    --- settings and must not stretch the unit mover across the space between it
    --- and the unitframe.
    local bounds = ExpandRect(nil, frame)
    bounds = ExpandRect(bounds, frame and (frame.hpBar or frame.Health))

    local power = frame and (frame.targetPowerBar or frame.powerBar or frame.Power)
    local powerDetached = (frame and frame._msufPowerBarDetached == true)
        or (power and power._msufDetached == true)
    if not powerDetached and power and power.IsShown and power:IsShown() then
        bounds = ExpandRect(bounds, power)
    end

    bounds = ExpandRect(bounds, frame and frame.MSUFPortraitHolder)
    bounds = ExpandRect(bounds, frame and frame.MSUFBorderOverlay)

    if not bounds then return nil end
    return bounds.l, bounds.r, bounds.t, bounds.b
end

Movers.GetUnitVisualBounds = UnitVisualBounds

local function IsGroupMoverConfig(cfg)
    local popupType = cfg and cfg.popupType
    return popupType == "gf_party" or popupType == "gf_raid" or popupType == "gf_mythicraid"
        or popupType == "gf_priority"
end

local function PositionMoverRegion(region, l, r, t, b)
    if not (region and l and r and t and b) then return false end
    region:ClearAllPoints()
    region:SetSize(max(2, round(r - l)), max(2, round(t - b)))
    region:SetPoint("TOPLEFT", UIParent, "TOPLEFT", round(l), round(t - UIParent:GetHeight()))
    return true
end

local function SyncSupplementalMoverRegions(mover, cfg)
    local getBounds = cfg and cfg.getSupplementalMoverBounds
    if type(getBounds) ~= "function" then return end

    local bounds = getBounds()
    local regions = mover._msufSupplementalRegions or {}
    mover._msufSupplementalRegions = regions

    local count = type(bounds) == "table" and #bounds or 0
    for index = 1, count do
        local region = regions[index]
        if not region then
            region = CreateFrame("Button", nil, moverParent)
            region:SetFrameStrata(mover:GetFrameStrata())
            region:SetFrameLevel(mover:GetFrameLevel())
            region:RegisterForDrag("LeftButton")
            if region.RegisterForClicks then region:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
            region:EnableMouse(true)
            region._msufPrimaryMover = mover

            local function Forward(scriptName, ...)
                local handler = mover:GetScript(scriptName)
                if handler then return handler(mover, ...) end
            end

            region:SetScript("OnEnter", function() Forward("OnEnter") end)
            region:SetScript("OnLeave", function() Forward("OnLeave") end)
            region:SetScript("OnMouseDown", function(_, button) Forward("OnMouseDown", button) end)
            region:SetScript("OnMouseUp", function(_, button) Forward("OnMouseUp", button) end)
            region:SetScript("OnDragStart", function() Forward("OnDragStart", "LeftButton") end)
            region:SetScript("OnDragStop", function() Forward("OnDragStop", "LeftButton") end)
            region:SetScript("OnClick", function(_, button) Forward("OnClick", button) end)
            regions[index] = region
        end

        local rect = bounds[index]
        local l = rect and (rect.l or rect[1])
        local r = rect and (rect.r or rect[2])
        local t = rect and (rect.t or rect[3])
        local b = rect and (rect.b or rect[4])
        if PositionMoverRegion(region, l, r, t, b) then region:Show() else region:Hide() end
    end

    for index = count + 1, #regions do
        regions[index]:Hide()
    end
end

local function SyncMoverToFrame(mover, frame, cfg)
    if not frame then return end
    if mover.SetClampedToScreen then mover:SetClampedToScreen(not IsGroupMoverConfig(cfg)) end
    local l, r, t, b
    if cfg and type(cfg.getMoverBounds) == "function" then
        l, r, t, b = cfg.getMoverBounds()
    elseif cfg and cfg.popupType == "unit" then
        l, r, t, b = UnitVisualBounds(frame)
    else
        l, r, t, b = FrameRectToUI(frame)
    end
    if not (l and r and t and b) then return end
    PositionMoverRegion(mover, l, r, t, b)
    SyncSupplementalMoverRegions(mover, cfg)
end

local function StopPendingDrag(mover)
    if mover and pendingDragMover and pendingDragMover ~= mover then return end
    pendingDragMover = nil
    pendingDragStartX = nil
    pendingDragStartY = nil
    if pendingDragFrame then
        pendingDragFrame:SetScript("OnUpdate", nil)
        pendingDragFrame:Hide()
    end
end

local function EnsurePendingDragFrame()
    if pendingDragFrame then return pendingDragFrame end
    pendingDragFrame = CreateFrame("Frame", "MSUF_EM2_MoverPendingDragFrame", UIParent)
    pendingDragFrame:Hide()
    return pendingDragFrame
end

local UNIT_NAME_POSITION_LABELS = {
    player = "Player Name Position",
    target = "Target Name Position",
    focus = "Focus Name Position",
    targettarget = "Target of Target Name Position",
    focustarget = "Focus Target Name Position",
    pet = "Pet Name Position",
}

local function MoverLabelText(key, cfg)
    if cfg and cfg.popupType == "unit" and key ~= "boss" then
        local named = UNIT_NAME_POSITION_LABELS[key]
        if named then return Tr(named) end
        return string.format(Tr("%s Name Position"), tostring(cfg.label or key))
    end
    return Tr(cfg and cfg.label or key)
end

local function QueuePendingDrag(mover, button)
    if button ~= "LeftButton" or not mover then return end
    if IsConfigCombatLocked and IsConfigCombatLocked() then return end
    local cx, cy = GetCursorPosition()
    if not (cx and cy) then return end
    pendingDragMover = mover
    pendingDragStartX = cx
    pendingDragStartY = cy
    local frame = EnsurePendingDragFrame()
    frame:SetScript("OnUpdate", function()
        local target = pendingDragMover
        if not target then
            StopPendingDrag()
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopPendingDrag(target)
            return
        end
        local mx, my = GetCursorPosition()
        if not (mx and my) then return end
        if max(math.abs(mx - (pendingDragStartX or mx)), math.abs(my - (pendingDragStartY or my))) < PENDING_DRAG_THRESHOLD then
            return
        end
        local begin = target._msufEM2BeginDrag
        StopPendingDrag(target)
        if type(begin) == "function" then begin(target, "LeftButton", "mouse") end
    end)
    frame:Show()
end

local function CreateMover(key, cfg)
    local th = T()

    local mover = CreateFrame("Button", nil, moverParent)
    mover:SetSize(100, 30)
    mover:SetFrameStrata("FULLSCREEN")
    mover:SetFrameLevel(cfg.popupType == "castbar" and 340 or 300)
    mover:SetMovable(true); mover:RegisterForDrag("LeftButton")
    if mover.RegisterForClicks then mover:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    mover:EnableMouse(true); mover:SetClampedToScreen(true)
    mover._barKey = key

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
    mover._bg = bg

    local brd = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    brd:SetAllPoints(); brd:SetFrameLevel(max(0, mover:GetFrameLevel() - 1))
    brd:SetBackdrop({ edgeFile = W8, edgeSize = 1 })
    brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
    mover._brd = brd

    local label = mover:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, FontSize("caption"), "OUTLINE"); label:SetPoint("CENTER")
    label:SetTextColor(th.textR, th.textG, th.textB, 0.85); label:SetText(MoverLabelText(key, cfg))
    mover._label = label

    local coordFS = mover:CreateFontString(nil, "OVERLAY")
    coordFS:SetFont(FONT, FontSize("micro"), "OUTLINE"); coordFS:SetPoint("TOP", mover, "BOTTOM", 0, -2)
    coordFS:SetTextColor(th.titleR, th.titleG, th.titleB, 0.90); coordFS:Hide()
    mover._coordFS = coordFS

    mover:SetScript("OnEnter", function(self)
        if self._dragging then return end
        local t = T()
        self._bg:SetColorTexture(t.bgR+0.05, t.bgG+0.05, t.bgB+0.08, 0.75)
        self._brd:SetBackdropBorderColor(t.titleR, t.titleG, t.titleB, 0.80)
        if self._label:IsShown() then self._label:SetTextColor(1, 1, 1, 1) end
        if EM2.Focus and EM2.Focus.SetHover then
            EM2.Focus.SetHover(key, nil, nil, { source = "mover" })
        end
    end)
    mover:SetScript("OnLeave", function(self)
        if self._dragging then return end
        local t = T()
        if self._label:IsShown() then self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85) end
        --- Hover may temporarily expose the mover chrome. Restore the current
        --- preview/non-preview presentation instead of leaving that chrome behind.
        self:UpdateLabelVisibility()
        if EM2.Focus and EM2.Focus.ClearHover then
            EM2.Focus.ClearHover("mover")
        end
    end)

    --- Unit movers keep the name-position label visible while preview frames are
    --- active so hidden/offset name text can still be inspected.
    function mover:UpdateLabelVisibility()
        if self._label then self._label:SetText(MoverLabelText(key, cfg)) end
        if _G.MSUF_PreviewTestMode and not (_G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown())) then
            if cfg.externalPublicElement then
                --- External elements (Dominos/Danders/Blizzard) have no MSUF
                --- preview frame underneath, so the tinted band + label stay
                --- visible as the "MSUF controls this" marker.
                self._label:Show()
                self._bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
                self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
                return
            end
            if cfg.popupType == "unit" and key ~= "boss" and not self._dragging then
                self._label:Show()
            else
                self._label:Hide()
            end
            self._bg:SetColorTexture(0, 0, 0, 0)
            --- The mover remains the full mouse hit surface; the live preview is
            --- the only drag visual, so no detached rectangle can leak through.
            self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0)
        else
            self._label:Show()
            self._bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
            self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
        end
    end

    --- Drag ? delegate to Ticker
    local function BeginMoverDrag(self, button)
        if button and button ~= "LeftButton" then return end
        StopPendingDrag(self)
        if self._dragging then return true end
        if BlockConfigCombatLocked() then return end
        if _G.MSUF_EM2_SetPreviewNudgeTarget then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        local externalHistoryStarted = false
        if cfg.externalPublicElement == true then
            if type(_G.MSUF_EM_UndoBeginChange) ~= "function"
                or _G.MSUF_EM_UndoBeginChange("external", key, "Move") ~= true then
                return false
            end
            externalHistoryStarted = true
        end
        if not (EM2.Ticker and EM2.Ticker.BeginDrag and EM2.Ticker.BeginDrag(self, key, cfg)) then
            if externalHistoryStarted and EM2.Undo and EM2.Undo.CancelChange then EM2.Undo.CancelChange() end
            return false
        end
        self._dragging = true
        if type(_G.GetCursorPosition) == "function" then
            self._msufDragCursorX, self._msufDragCursorY = _G.GetCursorPosition()
        else
            self._msufDragCursorX, self._msufDragCursorY = nil, nil
        end
        self:UpdateLabelVisibility()
        if self._msufGuidedPlacementCue then self._msufGuidedPlacementCue:Hide() end
        self._coordFS:Show()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("drag") end

        if externalHistoryStarted then
            self._msufHistoryDrag = true
        else
            local historyCategory = cfg.popupType == "castbar" and "castbar" or "unit"
            local historyKey = cfg.popupType == "castbar" and (cfg.castbarUnit or key:sub(9)) or key
            if type(_G.MSUF_EM_UndoBeginChange) == "function" then
                self._msufHistoryDrag = _G.MSUF_EM_UndoBeginChange(historyCategory, historyKey, "Move") == true
            elseif _G.MSUF_EM_UndoBeforeChange then
                _G.MSUF_EM_UndoBeforeChange(historyCategory, historyKey)
            end
        end

        if EM2.Focus and EM2.Focus.SetSelection then EM2.Focus.SetSelection(key, nil, nil, { source = "drag" }) end
        return true
    end

    local function EndMoverDrag(self, button)
        if button and button ~= "LeftButton" then return end
        StopPendingDrag(self)
        if not self._dragging then return false end
        self._dragging = false
        self._coordFS:Hide()

        if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

        local moved = false
        if EM2.Ticker then moved = EM2.Ticker.EndDrag() end
        if self._msufHistoryDrag and type(_G.MSUF_EM_UndoCommitChange) == "function" then
            self._msufHistoryDrag = nil
            _G.MSUF_EM_UndoCommitChange()
        end

        --- Restore hover
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85)
        self:UpdateLabelVisibility()
        --- A steady click still jitters a pixel or two while the Ticker's
        --- commit threshold is 0.5px — without a click slop the follow-up
        --- OnClick (select + open popup) gets eaten on the first click of a
        --- new element. Only a real cursor drag suppresses it.
        local suppress = moved
        if suppress and self._msufDragCursorX and type(_G.GetCursorPosition) == "function" then
            local cursorX, cursorY = _G.GetCursorPosition()
            if cursorX and math.abs(cursorX - self._msufDragCursorX) <= 4
                and math.abs(cursorY - (self._msufDragCursorY or 0)) <= 4 then
                suppress = false
            end
        end
        if suppress then self._suppressNextClick = true end
        if EM2.Focus and EM2.Focus.SetHover and self:IsMouseOver() then
            EM2.Focus.SetHover(key, nil, nil, { source = "mover", force = true })
        end
        Movers.RefreshGuidedPlacementCue()
        return moved
    end

    mover._msufEM2BeginDrag = BeginMoverDrag
    mover._msufEM2EndDrag = EndMoverDrag
    mover:SetScript("OnMouseDown", BeginMoverDrag)
    mover:SetScript("OnMouseUp", EndMoverDrag)
    mover:SetScript("OnDragStart", BeginMoverDrag)
    mover:SetScript("OnDragStop", EndMoverDrag)
    mover:SetScript("OnHide", function(self)
        StopPendingDrag(self)
        if self._dragging then EndMoverDrag(self, "LeftButton") end
        for _, region in ipairs(self._msufSupplementalRegions or {}) do region:Hide() end
    end)

    --- Click keeps the legacy edit-mode behavior: select the item and open
    --- its popup. Focus visuals are handled separately by the popup veil.
    mover:SetScript("OnClick", function(self, button)
        if self._suppressNextClick then
            self._suppressNextClick = nil
            return
        end
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        if _G.MSUF_EM2_SetPreviewNudgeTarget then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        if EM2.State then EM2.State.SetUnitKey(key) end
        if EM2.HUD then EM2.HUD.RefreshUnitSelector() end
        if EM2.Focus and EM2.Focus.SetSelection then EM2.Focus.SetSelection(key, nil, nil, { source = "mover" }) end
        if EM2.Popups and EM2.Popups.Open then
            EM2.Popups.Open(key, self)
        elseif EM2.Focus and EM2.Focus.NotifyPositionChanged then
            EM2.Focus.NotifyPositionChanged(key)
        end
    end)

    movers[key] = mover
    local frame = cfg.getFrame and cfg.getFrame()
    if frame then SyncMoverToFrame(mover, frame, cfg) end
    return mover
end

function Movers.Show()
    if not moverParent then
        moverParent = CreateFrame("Frame", "MSUF_EM2_MoverParent", UIParent)
        moverParent:SetAllPoints(UIParent); moverParent:SetFrameStrata("FULLSCREEN")
    end
    moverParent:Show()
    local reg = EM2.Registry and EM2.Registry.All()
    if not reg then return end
    for k, c in pairs(reg) do
        if not movers[k] then CreateMover(k, c) end
        local m = movers[k]
        local f = c.getFrame and c.getFrame()
        if f then SyncMoverToFrame(m, f, c); m:Show(); m:UpdateLabelVisibility() else m:Hide() end
    end
    Movers.RefreshGuidedPlacementCue()
end

function Movers.Hide()
    HideGuidedPlacementCue()
    if moverParent then moverParent:Hide() end
    for _, m in pairs(movers) do m:Hide() end
end
function Movers.IsShown() return moverParent and moverParent:IsShown() or false end
function Movers.All() return movers end
function Movers.Get(k) return movers[k] end

function Movers.Remove(key)
    local mover = key and movers[key]
    if not mover then return false end
    StopPendingDrag(mover)
    if mover._dragging and type(mover._msufEM2EndDrag) == "function" then
        mover:_msufEM2EndDrag("LeftButton")
    end
    mover:Hide()
    mover:EnableMouse(false)
    for _, region in ipairs(mover._msufSupplementalRegions or {}) do
        region:Hide()
        if region.EnableMouse then region:EnableMouse(false) end
    end
    movers[key] = nil
    return true
end

function Movers.SyncAll()
    if not moverParent or not moverParent:IsShown() then return end
    if EM2.Ticker and EM2.Ticker.IsDragging() then return end
    local reg = EM2.Registry and EM2.Registry.All()
    if not reg then return end
    for k, c in pairs(reg) do
        if c then
            if not movers[k] then CreateMover(k, c) end
            local m = movers[k]
            local f = c.getFrame and c.getFrame()
            if f then
                SyncMoverToFrame(m, f, c)
                m:Show()
                m:UpdateLabelVisibility()
            elseif m then
                m:Hide()
            end
        end
    end
    Movers.RefreshGuidedPlacementCue()
end

--- MSUF_EM2_Elements.lua

--- MSUF_EM2_Elements.lua
--- Registers all existing MSUF elements with the EM2 Registry.
--- Deferred to PLAYER_LOGIN so unit frames exist.
if not EM2.Registry then return end

local Reg = EM2.Registry

--- Frame resolvers (always live, no cached refs)
local function GetUF(key)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.GetFrame) == "function" then
        local frame = UF.GetFrame(key)
        if frame then return frame end
    end
    local uf = UF and UF.frames
    if uf and uf[key] then return uf[key] end
    return _G["MSUF_" .. key]
end

local function GetBossUF(i)
    return GetUF("boss" .. i)
end

local function GetBossCastbarFrame(index)
    if index == 1 then
        return _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1 or _G.MSUF_BossCastbar1
    end
    return _G["MSUF_BossCastbarPreview" .. index] or _G["MSUF_BossCastbar" .. index]
end

local function GetBossSupplementalMoverBounds()
    local bounds = {}
    for i = 2, 5 do
        local l, r, t, b = UnitVisualBounds(GetBossUF(i))
        if l then
            bounds[#bounds + 1] = { l = l, r = r, t = t, b = b }
        end
    end
    return bounds
end

local function GetConf(key)
    local db = _G.MSUF_DB
    return db and db[key]
end

--- isEnabled: true when the unit frame exists and unit tracking is on
local function UnitEnabled(key)
    return function()
        local f = GetUF(key)
        if not f then return false end
        local db = _G.MSUF_DB
        if not db or not db[key] then return true end
        if db[key].enabled == false then return false end
        return true
    end
end

local function BossEnabled(i)
    return function()
        local f = GetBossUF(i)
        if not f then return false end
        local db = _G.MSUF_DB
        if not db or not db.boss then return true end
        if db.boss.enabled == false then return false end
        return true
    end
end

local function GetCastbarFrame(unit)
    local frame
    if unit == "player" then
        frame = _G.MSUF_PlayerCastbarPreview or _G.MSUF_PlayerCastbar
    elseif unit == "target" then
        frame = _G.MSUF_TargetCastbarPreview or _G.MSUF_TargetCastbar
    elseif unit == "focus" then
        frame = _G.MSUF_FocusCastbarPreview or _G.MSUF_FocusCastbar
    elseif unit == "boss" then
        frame = GetBossCastbarFrame(1)
    end
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    return frame
end


local function GetBossCastbarSupplementalMoverBounds()
    local bounds = {}
    for i = 2, 5 do
        local l, r, t, b = FrameRectToUI(GetBossCastbarFrame(i))
        if l then
            bounds[#bounds + 1] = { l = l, r = r, t = t, b = b }
        end
    end
    return bounds
end

local function GetCastbarConf()
    if type(_G.MSUF_EnsureDB) == "function" then _G.MSUF_EnsureDB() end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        ExportPublic("MSUF_DB", {})
        db = _G.MSUF_DB
    end
    db.general = db.general or {}
    return db.general
end

local function CastbarEnabled(unit)
    return function()
        local db = _G.MSUF_DB
        local g = db and db.general or nil
        if not g or g.castbarPlayerPreviewEnabled == false then return false end
        local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
        if type(shouldUse) == "function" and not shouldUse(unit, g) then return false end
        if type(shouldUse) ~= "function" then
            if unit == "player" and g.enablePlayerCastbar == false then return false end
            if unit == "target" and g.enableTargetCastbar == false then return false end
            if unit == "focus" and g.enableFocusCastbar == false then return false end
            if unit == "boss" and g.enableBossCastbar == false then return false end
        end
        return GetCastbarFrame(unit) ~= nil
    end
end

local function RegisterCastbarMover(unit, label, order)
    Reg.Register({
        key         = "castbar_" .. unit,
        label       = label,
        order       = order,
        popupType   = "castbar",
        canResize   = false,
        canNudge    = true,
        castbarUnit = unit,
        getFrame    = function() return GetCastbarFrame(unit) end,
        getSupplementalMoverBounds = unit == "boss" and GetBossCastbarSupplementalMoverBounds or nil,
        getConf     = GetCastbarConf,
        isEnabled   = CastbarEnabled(unit),
    })
end

--- Registration (deferred)
local function RegisterAll()
    --- Core unit frames
    local units = {
        { key = "player",       label = "Player",           order = 10 },
        { key = "target",       label = "Target",           order = 20 },
        { key = "focus",        label = "Focus",            order = 30 },
        { key = "targettarget", label = "Target of Target", order = 40 },
        { key = "focustarget",  label = "Focus Target",     order = 45 },
        { key = "pet",          label = "Pet",              order = 50 },
    }

    for _, u in ipairs(units) do
        Reg.Register({
            key       = u.key,
            label     = u.label,
            order     = u.order,
            popupType = "unit",
            canResize = true,
            canNudge  = true,
            getFrame  = function() return GetUF(u.key) end,
            getConf   = function() return GetConf(u.key) end,
            isEnabled = UnitEnabled(u.key),
        })
    end

    --- Boss 1-5 share one mover/config, but use one mouse region per frame.
    --- This keeps the gaps and independently editable boss castbars clickable
    --- while dragging any boss unitframe still moves the complete boss group.
    Reg.Register({
        key       = "boss",
        label     = "Boss",
        order     = 61,
        popupType = "unit",
        canResize = true,
        canNudge  = true,
        getFrame  = function() return GetBossUF(1) end,
        getSupplementalMoverBounds = GetBossSupplementalMoverBounds,
        getConf   = function() return GetConf("boss") end,
        isEnabled = BossEnabled(1),
    })

    RegisterCastbarMover("player", "Player Castbar", 110)
    RegisterCastbarMover("target", "Target Castbar", 111)
    RegisterCastbarMover("focus", "Focus Castbar", 112)
    RegisterCastbarMover("boss", "Boss Castbar", 113)

    --- Future Phase 2 registrations:
    --- Auras3 groups (per-unit)
    --- Class Power bar
    --- These will register when their respective modules load.
end

RegisterAll()

--- MSUF_EM2_Compat.lua

--- MSUF_EM2_Compat.lua
--- Legacy global stubs so external files (30+) continue to work after
--- MSUF_EditMode.lua is deleted. Every function listed here was exported
--- by the old EditMode and is called from at least one other file.
--- --- Edit namespace (old code references _G.MSUF_Edit.*) ---
ExportPublic("MSUF_Edit", _G.MSUF_Edit or {})
local Edit = _G.MSUF_Edit
Edit.Popups = Edit.Popups or {}
Edit.Flow   = Edit.Flow   or {}
Edit.Util   = Edit.Util   or {}
Edit.UI     = Edit.UI     or {}

--- --- MSUF_EditState table (rawget'd by A2, Util, etc.) ---
if not _G.MSUF_EditState then
    ExportPublic("MSUF_EditState", { active = false, unitKey = nil, popupOpen = false })
end

--- --- MSUF_IsInEditMode ---
local function MSUF_IsInEditMode()
    if EM2.State then return EM2.State.IsActive() end
    return _G.MSUF_UnitEditModeActive == true
end
ExportPublic("MSUF_IsInEditMode", MSUF_IsInEditMode)

--- --- MSUF_GetAnchorFrame ---
local function MSUF_GetAnchorFrame()
    local db = _G.MSUF_DB
    local g = db and db.general or {}
    local isCooldownAnchorEnabled = _G.MSUF_IsCooldownAnchorEnabled
    local cooldownAnchorEnabled = type(isCooldownAnchorEnabled) == "function"
        and isCooldownAnchorEnabled(g) == true
        or g.anchorToCooldown == true
    if cooldownAnchorEnabled then
        local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer")) or _G["EssentialCooldownViewer"]
        if ecv then return ecv end
        return UIParent
    end
    local anchorName = g.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local f = _G[anchorName]
        if f then return f end
    end
    return UIParent
end
ExportPublic("MSUF_GetAnchorFrame", MSUF_GetAnchorFrame)

--- --- MSUF_GetCurrentGridStep ---
local function MSUF_GetCurrentGridStep()
    if EM2.Grid then return EM2.Grid.GetGridStep() end
    local db = _G.MSUF_DB
    return (db and db.general and db.general.editModeGridStep) or 20
end
ExportPublic("MSUF_GetCurrentGridStep", MSUF_GetCurrentGridStep)

--- --- MSUF_MakeBlizzardOptionsMovable ---
local function MSUF_MakeBlizzardOptionsMovable()
    if BlockConfigCombatLocked() then return false end
    local frame = _G.SettingsPanel or _G.InterfaceOptionsFrame
    if not frame then return end
    if frame.MSUF_Movable then return end
    frame.MSUF_Movable = true
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    local drag = CreateFrame("Frame", "MSUF_SettingsPanelDragHandle", frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -4)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -60, -4)
    drag:SetHeight(22)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    local function StartPanelDrag(self, button)
        if button and button ~= "LeftButton" then return end
        if BlockConfigCombatLocked() then return end
        local p = self:GetParent()
        if p and p.StartMoving then p:StartMoving() end
    end
    local function StopPanelDrag(self, button)
        if button and button ~= "LeftButton" then return end
        local p = self:GetParent()
        if p and p.StopMovingOrSizing then p:StopMovingOrSizing() end
    end
    drag:SetScript("OnMouseDown", StartPanelDrag)
    drag:SetScript("OnMouseUp", StopPanelDrag)
    drag:SetScript("OnDragStart", StartPanelDrag)
    drag:SetScript("OnDragStop", StopPanelDrag)
    drag:SetScript("OnHide", StopPanelDrag)
end
ExportPublic("MSUF_MakeBlizzardOptionsMovable", MSUF_MakeBlizzardOptionsMovable)

--- --- MSUF_ResetCurrentEditUnit ---
local function MSUF_ResetCurrentEditUnit()
    local key = _G.MSUF_CurrentEditUnitKey
    if not key then return end
    local db = _G.MSUF_DB
    local conf = db and db[key]
    if not conf then return end
    conf.width = nil; conf.height = nil; conf.offsetX = nil; conf.offsetY = nil
    conf.anchorFrameName = nil
    conf.anchorToUnitframe = "GLOBAL"
    if db.general then
        db.general.anchorToCooldown = false
        db.general.anchorName = "UIParent"
    end
    if not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
end
ExportPublic("MSUF_ResetCurrentEditUnit", MSUF_ResetCurrentEditUnit)

local function LegacyNoop() end
local function UpdateGridOverlay()
    if EM2.State and EM2.State.IsActive() then
        if EM2.Grid then EM2.Grid.Show() end
    else
        if EM2.Grid then EM2.Grid.Hide() end
    end
end
local function OpenMoverPopup(prefix, fallback, unit, parent)
    if EM2.Popups then
        EM2.Popups.Open(prefix and (prefix .. tostring(unit or "")) or unit, parent)
    elseif fallback and fallback.Open then
        fallback.Open(unit, parent)
    end
end

ExportPublic("MSUF_UpdateEditModeInfo", LegacyNoop)
ExportPublic("MSUF_UpdateCastbarEditInfo", LegacyNoop)
ExportPublic("MSUF_UpdateGridOverlay", UpdateGridOverlay)
ExportPublic("MSUF_UpdateEditModeVisuals", UpdateGridOverlay)

local function MSUF_CreateGridFrame()
    if EM2.Grid then EM2.Grid.Show() end
end
ExportPublic("MSUF_CreateGridFrame", MSUF_CreateGridFrame)

local function MSUF_OpenPositionPopup(unit, parent)
    OpenMoverPopup(nil, nil, unit, parent)
end
ExportPublic("MSUF_OpenPositionPopup", MSUF_OpenPositionPopup)

local function MSUF_OpenCastbarPositionPopup(unit, parent)
    OpenMoverPopup("castbar_", EM2.CastPopup, unit, parent)
end
ExportPublic("MSUF_OpenCastbarPositionPopup", MSUF_OpenCastbarPositionPopup)

local function MSUF_OpenAuras3PositionPopup(unit, parent)
    OpenMoverPopup("aura_", EM2.AuraPopup, unit, parent)
end
ExportPublic("MSUF_OpenAuras3PositionPopup", MSUF_OpenAuras3PositionPopup)

--- --- MSUF_SyncUnitPositionPopup ---
local function MSUF_SyncUnitPositionPopup(unit)
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_UNIT_POPUP", unit)
end
ExportPublic("MSUF_SyncUnitPositionPopup", MSUF_SyncUnitPositionPopup)

--- --- MSUF_SyncCastbarPositionPopup ---
local function MSUF_SyncCastbarPositionPopup(unit)
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_CASTBAR_POPUP", unit)
end
ExportPublic("MSUF_SyncCastbarPositionPopup", MSUF_SyncCastbarPositionPopup)

--- --- MSUF_SyncAuras3PositionPopup ---
local function MSUF_SyncAuras3PositionPopup(unit)
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
    local menu = MSUF and MSUF.MSUF2
    if menu and type(menu.SyncAuras3PositionSettings) == "function" then
        menu.SyncAuras3PositionSettings(unit, rawget(_G, "MSUF_EM2_ActiveAuraGroup"))
    end
end
ExportPublic("MSUF_SyncAuras3PositionPopup", MSUF_SyncAuras3PositionPopup)

--- --- MSUF_SetMSUFEditModeDirect (THE primary entry point) ---
local function MSUF_SetMSUFEditModeDirect(active, unitKey)
    if not EM2.State then return end
    if active and type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return false end
    if active and IsConfigCombatLocked() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return false
    end
    if active and type(_G.MSUF_EnsureOptionsLoaded) == "function"
        and not _G.MSUF_EnsureOptionsLoaded("edit-mode")
    then
        return false
    end
    if active and type(_G.MSUF_TryOpenExternalEditMode) == "function"
        and _G.MSUF_TryOpenExternalEditMode(unitKey) then
        return true
    end
    if not active and type(_G.MSUF_TryCloseExternalEditMode) == "function"
        and _G.MSUF_TryCloseExternalEditMode() then
        return true
    end
    if active then EM2.State.Enter(unitKey)
    else EM2.State.Exit("direct") end
    return true
end
ExportPublic("MSUF_SetMSUFEditModeDirect", MSUF_SetMSUFEditModeDirect)

--- --- MSUF_SetMSUFEditModeFromBlizzard ---
local function MSUF_SetMSUFEditModeFromBlizzard(active)
    MSUF_SetMSUFEditModeDirect(active, nil)
end
ExportPublic("MSUF_SetMSUFEditModeFromBlizzard", MSUF_SetMSUFEditModeFromBlizzard)

--- --- Preview System ---
--- One global flag: MSUF_PreviewTestMode. Mirrors MSUF_BossTestMode exactly.
--- The core's visibility driver (line 2000) checks this flag to force-show.
--- The core's UpdateSimpleUnitFrame (line 4017) already applies EditPrev data.
--- Zero hooks, zero timers, zero pipeline fighting.
ExportPublic("MSUF_UnitPreviewActive", false)
ExportPublic("MSUF_PreviewTestMode", false)

local PREVIEW_UNITS = { "target", "focus", "focustarget", "targettarget", "pet" }
local CASTBAR_TEST_FUNCS = {
    "MSUF_SetPlayerCastbarTestMode",
    "MSUF_SetTargetCastbarTestMode",
    "MSUF_SetFocusCastbarTestMode",
    "MSUF_SetBossCastbarTestMode",
}
local previewMoverSyncQueued = false
local previewReforceQueued = false

local function SchedulePreviewMoverSync(delay)
    if not (EM2.Movers and EM2.Movers.SyncAll) then return end
    if previewMoverSyncQueued then return end
    previewMoverSyncQueued = true
    local function Run()
        previewMoverSyncQueued = false
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end
    C_Timer.After(delay or 0.08, Run)
end

local function GetPreviewFrame(unitKey)
    local UF = MSUF and MSUF.UF
    if UF and type(UF.GetFrame) == "function" then
        local frame = UF.GetFrame(unitKey)
        if frame then return frame end
    end
    local frames = UF and UF.frames
    return (frames and frames[unitKey])
        or _G["MSUF_" .. unitKey]
end

local function ForPreviewFrames(fn)
    for _, unitKey in ipairs(PREVIEW_UNITS) do
        local frame = GetPreviewFrame(unitKey)
        if frame then fn(frame, unitKey) end
    end
end

local function MSUF_EM2_ReforcePreviewFrames()
    if not _G.MSUF_PreviewTestMode then return end
    if IsConfigCombatLocked() then return end
    ForPreviewFrames(function(frame)
        if frame.ForceUpdate then frame:ForceUpdate("EM2_PREVIEW") end
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.EnableMouse then frame:EnableMouse(true) end
    end)
    if EM2.Movers and EM2.Movers.SyncAll then
        EM2.Movers.SyncAll()
        C_Timer.After(0, function()
            if _G.MSUF_PreviewTestMode and EM2.Movers and EM2.Movers.SyncAll then
                EM2.Movers.SyncAll()
            end
        end)
    end
end
ExportPublic("MSUF_EM2_ReforcePreviewFrames", MSUF_EM2_ReforcePreviewFrames)

local function MSUF_EM2_SchedulePreviewReforce()
    if previewReforceQueued then return end
    previewReforceQueued = true
    C_Timer.After(0.1, function()
        previewReforceQueued = false
        MSUF_EM2_ReforcePreviewFrames()
    end)
end
ExportPublic("MSUF_EM2_SchedulePreviewReforce", MSUF_EM2_SchedulePreviewReforce)

local function MSUF_SyncAllUnitPreviews()
    local active = _G.MSUF_UnitPreviewActive and true or false
    local editOn = EM2.State and EM2.State.IsActive()
    local want = active and editOn

    if IsConfigCombatLocked() then
        ExportPublic("MSUF_PreviewTestMode", false)
        ExportPublic("MSUF_BossTestMode", false)
        if type(_G.MSUF_HideAllCastbarPreviews) == "function" then
            _G.MSUF_HideAllCastbarPreviews()
        end
        return
    end

    --- Set preview flag (core visibility driver reads this)
    ExportPublic("MSUF_PreviewTestMode", want)

    --- 1) Boss: existing system
    ExportPublic("MSUF_BossTestMode", want)
    if _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
        _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end

    --- 2) Non-player: refresh visibility drivers (reads MSUF_PreviewTestMode),
    --- then update each frame (pipeline calls EditPrev for unitless frames)
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
    end

    ForPreviewFrames(function(frame)
        if frame.ForceUpdate then frame:ForceUpdate("EM2_PREVIEW") end
        if want then
            frame:Show()
            if frame.SetAlpha then frame:SetAlpha(1) end
            if frame.EnableMouse then frame:EnableMouse(true) end
        end
    end)
    --- 3) Castbars
    local beginBossBatch = _G.MSUF_BeginBossCastbarPreviewBatch
    local endBossBatch = _G.MSUF_EndBossCastbarPreviewBatch
    local batchingBossPreview = type(beginBossBatch) == "function" and type(endBossBatch) == "function"
    if batchingBossPreview then beginBossBatch() end
    if _G.MSUF_SyncCastbarEditModeWithUnitEdit then
        _G.MSUF_SyncCastbarEditModeWithUnitEdit()
    end
    --- Animated castbar motion is owned by the on-demand preview animation driver.
    for _, fn in ipairs(CASTBAR_TEST_FUNCS) do
        local f = _G[fn]; if type(f) == "function" then f(false, true) end
    end
    if batchingBossPreview then endBossBatch() end

    --- 4) Aura refresh
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RefreshEditPreview) == "function" then
        a3.RefreshEditPreview()
    elseif a3 and type(a3.RefreshAll) == "function" then
        a3.RefreshAll()
    end

    --- 5) Sync movers
    SchedulePreviewMoverSync(0.08)
    if want then
        MSUF_EM2_SchedulePreviewReforce()
    end
end

ExportPublic("MSUF_SyncAllUnitPreviews", MSUF_SyncAllUnitPreviews)

--- --- Auto-reforce wrappers ---
--- Visual update functions can overwrite preview text/bars/colors while Edit
--- Mode preview is active. Wrap MSUF-owned entry points only for the active
--- preview window, then restore originals when preview mode stops.
do
    local PIPELINE_REFORCE_NAMES = {
        "MSUF_UpdateAllFonts",
        "MSUF_UpdateAllFonts_Immediate",
        "MSUF_RefreshAllIdentityColors",
        "MSUF_RefreshAllPowerTextColors",
        "MSUF_UpdateAllBarTextures",
        "MSUF_UpdateAllBarTextures_Immediate",
        "MSUF_ApplyBarOutlineThickness_All",
        "MSUF_ApplyPowerBarBorder_All",
        "MSUF_ApplyReverseFillBars",
        "MSUF_UpdateCastbarVisuals",
        "MSUF_UpdateCastbarVisuals_Immediate",
        "MSUF_UpdateCastbarTextures",
        "MSUF_UpdateCastbarTextures_Immediate",
        "MSUF_RefreshDispelOutlineStates",
        "MSUF_ApplyAllAlpha",
    }
    local wrapped = {}
    local wrappers = {}
    local unpackResults = table.unpack or unpack

    local function ScheduleReforce(delay)
        if not _G.MSUF_PreviewTestMode then return end
        if IsConfigCombatLocked() then return end
        C_Timer.After(delay or 0, function()
            if not _G.MSUF_PreviewTestMode then return end
            if IsConfigCombatLocked() then return end
            MSUF_EM2_ReforcePreviewFrames()
        end)
    end

    local function UninstallPipelineWrappers()
        for name, original in pairs(wrapped) do
            if _G[name] == wrappers[name] then
                _G[name] = original
            end
            wrapped[name] = nil
            wrappers[name] = nil
        end
    end

    local function InstallPipelineWrappers()
        if not _G.MSUF_PreviewTestMode then return end
        for _, name in ipairs(PIPELINE_REFORCE_NAMES) do
            if not wrapped[name] and type(_G[name]) == "function" then
                local original = _G[name]
                local function wrapper(...)
                    if not _G.MSUF_PreviewTestMode then
                        UninstallPipelineWrappers()
                        return original(...)
                    end
                    local results = { original(...) }
                    ScheduleReforce(0.05)
                    return unpackResults(results)
                end
                wrapped[name] = original
                wrappers[name] = wrapper
                _G[name] = wrapper
            end
        end
    end

    local originalSyncAllUnitPreviews = MSUF_SyncAllUnitPreviews
    local function SyncAllUnitPreviewsWithPipelineWrappers(...)
        if _G.MSUF_PreviewTestMode then
            InstallPipelineWrappers()
        else
            UninstallPipelineWrappers()
        end

        local results = { originalSyncAllUnitPreviews(...) }

        if _G.MSUF_PreviewTestMode then
            InstallPipelineWrappers()
            ScheduleReforce(0.05)
            ScheduleReforce(0.20)
        else
            UninstallPipelineWrappers()
        end

        return unpackResults(results)
    end

    MSUF_SyncAllUnitPreviews = SyncAllUnitPreviewsWithPipelineWrappers
    ExportPublic("MSUF_SyncAllUnitPreviews", SyncAllUnitPreviewsWithPipelineWrappers)

    local asyncPreviewSerial = 0
    local function SyncAllUnitPreviewsAsync()
        asyncPreviewSerial = asyncPreviewSerial + 1
        local serial = asyncPreviewSerial
        local active = _G.MSUF_UnitPreviewActive and true or false
        local editOn = EM2.State and EM2.State.IsActive()
        local want = active and editOn

        if IsConfigCombatLocked() then
            ExportPublic("MSUF_PreviewTestMode", false)
            ExportPublic("MSUF_BossTestMode", false)
            if type(_G.MSUF_HideAllCastbarPreviews) == "function" then
                _G.MSUF_HideAllCastbarPreviews()
            end
            UninstallPipelineWrappers()
            return
        end

        ExportPublic("MSUF_PreviewTestMode", want)
        ExportPublic("MSUF_BossTestMode", want)
        if want then
            InstallPipelineWrappers()
        else
            UninstallPipelineWrappers()
        end

        local timer = C_Timer
        if not (timer and type(timer.After) == "function") then
            return SyncAllUnitPreviewsWithPipelineWrappers()
        end

        local function Alive()
            if serial ~= asyncPreviewSerial then return false end
            if IsConfigCombatLocked() then return false end
            if want and not (_G.MSUF_UnitPreviewActive and EM2.State and EM2.State.IsActive()) then return false end
            return true
        end

        local function Phase(delay, fn)
            timer.After(delay, function()
                if not Alive() then return end
                fn()
            end)
        end

        Phase(0, function()
            if _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
                _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
            end
        end)

        Phase(0.02, function()
            if _G.MSUF_RefreshAllUnitVisibilityDrivers then
                _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
            end
        end)

        Phase(0.04, function()
            ForPreviewFrames(function(frame)
                if frame.ForceUpdate then frame:ForceUpdate("EM2_PREVIEW") end
                if want then
                    frame:Show()
                    if frame.SetAlpha then frame:SetAlpha(1) end
                    if frame.EnableMouse then frame:EnableMouse(true) end
                end
            end)
        end)

        Phase(0.06, function()
            local beginBossBatch = _G.MSUF_BeginBossCastbarPreviewBatch
            local endBossBatch = _G.MSUF_EndBossCastbarPreviewBatch
            local batchingBossPreview = type(beginBossBatch) == "function" and type(endBossBatch) == "function"
            if batchingBossPreview then beginBossBatch() end
            if _G.MSUF_SyncCastbarEditModeWithUnitEdit then _G.MSUF_SyncCastbarEditModeWithUnitEdit() end
            --- Animated castbar motion is owned by the on-demand preview animation driver.
            for _, fn in ipairs(CASTBAR_TEST_FUNCS) do
                local f = _G[fn]; if type(f) == "function" then f(false, true) end
            end
            if batchingBossPreview then endBossBatch() end
        end)

        Phase(0.08, function()
            local a3 = MSUF and MSUF.MSUF_Auras3
            if a3 and type(a3.RefreshEditPreview) == "function" then
                a3.RefreshEditPreview()
            elseif a3 and type(a3.RefreshAll) == "function" then
                a3.RefreshAll()
            end
        end)

        Phase(0.10, function()
            SchedulePreviewMoverSync(0.02)
            if want then
                MSUF_EM2_SchedulePreviewReforce()
                ScheduleReforce(0.05)
                ScheduleReforce(0.20)
                InstallPipelineWrappers()
            else
                UninstallPipelineWrappers()
            end
        end)
    end
    ExportPublic("MSUF_SyncAllUnitPreviewsAsync", SyncAllUnitPreviewsAsync)
end

--- --- MSUF_SyncCastbarEditModeWithUnitEdit (castbar preview sync) ---
local function MSUF_SyncCastbarEditModeWithUnitEdit()
    local db = _G.MSUF_DB
    if not db then return end
    db.general = db.general or {}
    local g = db.general
    local active = EM2.State and EM2.State.IsActive()
    g.castbarPlayerPreviewEnabled = active and true or false
    if not active and type(_G.MSUF_HideAllCastbarPreviews) == "function" then
        _G.MSUF_HideAllCastbarPreviews()
    end

    if type(_G.MSUF_UpdatePlayerCastbarPreview) == "function" then
        _G.MSUF_UpdatePlayerCastbarPreview()
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    elseif not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and type(_G.MSUF_UpdateBossCastbarPreview) == "function"
    then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end
ExportPublic("MSUF_SyncCastbarEditModeWithUnitEdit", MSUF_SyncCastbarEditModeWithUnitEdit)

--- --- MSUF_SyncBossUnitframePreviewWithUnitEdit ---
local MSUF_SyncBossUnitframePreviewWithUnitEdit = _G.MSUF_SyncBossUnitframePreviewWithUnitEdit or function()
    --- Provided by MidnightSimpleUnitFrames.lua; stub if not yet available
end
ExportPublic("MSUF_SyncBossUnitframePreviewWithUnitEdit", MSUF_SyncBossUnitframePreviewWithUnitEdit)

--- --- Edit.Flow.Exit ---
Edit.Flow.Exit = function(source, opts)
    if EM2.State then EM2.State.Exit(source or "flow") end
end

--- --- Edit.Transitions ---
Edit.Transitions = Edit.Transitions or {}
Edit.Transitions.SetMSUFEditModeDirect = MSUF_SetMSUFEditModeDirect

--- --- AnyEditMode listeners (registration handled in State.lua) ---

--- --- Castbar anchor toggle (detach/attach to unitframe) ---
local function CastbarToggleFrameCenter(unit)
    local preview, runtime
    if unit == "player" then
        preview = _G.MSUF_PlayerCastbarPreview
        runtime = _G.MSUF_PlayerCastbar
    elseif unit == "target" then
        preview = _G.MSUF_TargetCastbarPreview
        runtime = _G.MSUF_TargetCastbar or _G.MSUF_TargetCastBar
    elseif unit == "focus" then
        preview = _G.MSUF_FocusCastbarPreview
        runtime = _G.MSUF_FocusCastbar or _G.MSUF_FocusCastBar
    elseif unit == "boss" then
        preview = _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1
        local bossCastbars = _G.MSUF_BossCastbars
        runtime = (bossCastbars and bossCastbars[1])
            or _G.MSUF_BossCastbar1
            or _G.MSUF_boss1CastBar
    end

    local function Center(frame)
        local left, right, top, bottom = FrameRectToUI(frame)
        if left then return frame, (left + right) * 0.5, (top + bottom) * 0.5 end
    end

    local frame, x, y = Center(preview)
    if frame then return frame, x, y end
    return Center(runtime)
end

local function ApplyCastbarAnchorState(unit)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(unit)
    else
        local reanchorFns = {
            player = "MSUF_ReanchorPlayerCastBar",
            target = "MSUF_ReanchorTargetCastBar",
            focus  = "MSUF_ReanchorFocusCastBar",
            boss   = "MSUF_ApplyBossCastbarPositionSetting",
        }
        local ra = reanchorFns[unit]
        if ra and type(_G[ra]) == "function" then _G[ra]() end
        if type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
            _G.MSUF_ApplyCastbarVisualsForUnit(unit)
        elseif _G.MSUF_UpdateCastbarVisuals then
            _G.MSUF_UpdateCastbarVisuals(unit)
        end
    end

    if type(_G.MSUF_PositionCastbarPreviewUnit) == "function" then
        _G.MSUF_PositionCastbarPreviewUnit(unit)
    end
end

local function RoundCastbarOffset(value)
    value = tonumber(value) or 0
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

local MSUF_EM_SetCastbarAnchoredToUnit = _G.MSUF_EM_SetCastbarAnchoredToUnit or function(unit, anchored)
    if not unit then return end
    local db = _G.MSUF_DB; if not db then return end
    db.general = db.general or {}
    local g = db.general

    local detachedKey, oxKey, oyKey
    if unit == "boss" then
        detachedKey = "bossCastbarDetached"
        oxKey = "bossCastbarOffsetX"
        oyKey = "bossCastbarOffsetY"
    else
        local prefix = _G.MSUF_GetCastbarPrefix and _G.MSUF_GetCastbarPrefix(unit)
        if not prefix then return end
        detachedKey = prefix .. "Detached"
        oxKey = prefix .. "OffsetX"
        oyKey = prefix .. "OffsetY"
    end

    local wantDetached = (anchored == false)
    if (g[detachedKey] == true) == wantDetached then return end

    local castbar, beforeX, beforeY = CastbarToggleFrameCenter(unit)
    g[detachedKey] = wantDetached or nil
    ApplyCastbarAnchorState(unit)

    if castbar and beforeX and beforeY then
        local left, right, top, bottom = FrameRectToUI(castbar)
        if left then
            local afterX = (left + right) * 0.5
            local afterY = (top + bottom) * 0.5
            local frameScale = castbar.GetEffectiveScale and tonumber(castbar:GetEffectiveScale()) or 1
            local uiScale = UIParent.GetEffectiveScale and tonumber(UIParent:GetEffectiveScale()) or 1
            if not frameScale or frameScale <= 0 then frameScale = 1 end
            if not uiScale or uiScale <= 0 then uiScale = 1 end

            local defaultX, defaultY = 0, 0
            if type(_G.MSUF_GetCastbarDefaultOffsets) == "function" then
                defaultX, defaultY = _G.MSUF_GetCastbarDefaultOffsets(unit)
            end
            local currentX = tonumber(g[oxKey]) or tonumber(defaultX) or 0
            local currentY = tonumber(g[oyKey]) or tonumber(defaultY) or 0
            local localPerUI = uiScale / frameScale
            local nextX = RoundCastbarOffset(currentX + (beforeX - afterX) * localPerUI)
            local nextY = RoundCastbarOffset(currentY + (beforeY - afterY) * localPerUI)
            if nextX ~= currentX or nextY ~= currentY then
                g[oxKey], g[oyKey] = nextX, nextY
                ApplyCastbarAnchorState(unit)
            end
        end
    end

    RefreshUFPreview("EM2_CASTBAR_ANCHOR_TOGGLE", unit)
end
ExportPublic("MSUF_EM_SetCastbarAnchoredToUnit", MSUF_EM_SetCastbarAnchoredToUnit)
