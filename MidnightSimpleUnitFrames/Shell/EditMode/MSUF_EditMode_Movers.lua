local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
--- EditMode/MSUF_EditMode_Movers.lua - Edit Mode mover overlays
--- Movers are dumb overlays. All drag math lives in the drag ticker
--- (MSUF_EditMode_Layout.lua). Elements and Compat load right after this file.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic
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
    cue = PixelLayoutRegion(CreateFrame("Frame", nil, mover))
    cue:SetAllPoints(mover)
    cue:EnableMouse(false)
    cue:SetFrameLevel((mover:GetFrameLevel() or 1) + 20)

    local function CreateArrow(point, relativePoint, x)
        local arrow = PixelLayoutRegion(cue:CreateTexture(nil, "OVERLAY", nil, 7))
        local usedAtlas = false
        -- Classic Era / TBC clients do not ship the NPE atlas; SetAtlas on an
        -- unknown name raises, so probe the atlas before using it.
        local atlasAPI = _G.C_Texture
        local hasAtlas = arrow.SetAtlas and atlasAPI and type(atlasAPI.GetAtlasInfo) == "function"
            and atlasAPI.GetAtlasInfo("NPE_ArrowRight") ~= nil
        if hasAtlas then arrow:SetAtlas("NPE_ArrowRight", false); usedAtlas = true end
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
    cue._label = PixelLayoutRegion(cue:CreateFontString(nil, "OVERLAY"))
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
--- Compat refreshes the unit preview the same way.
Movers.RefreshUFPreview = RefreshUFPreview

local IsConfigCombatLocked = U.IsConfigCombatLocked
local BlockConfigCombatLocked = U.BlockConfigCombatLocked

local FrameRectToUI = _G.MSUF_UF_FrameRectToUI

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
            region = PixelLayoutRegion(CreateFrame("Button", nil, moverParent), true)
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

local UNIT_NAME_POSITION_LABELS = {
    player = "Player Name Position",
    target = "Target Name Position",
    focus = "Focus Name Position",
    targettarget = "Target of Target Name Position",
    focustarget = "Focus Target Name Position",
    pet = "Pet Name Position",
    pettarget = "Pet Target Name Position",
}

local function MoverLabelText(key, cfg)
    if cfg and cfg.popupType == "unit" and key ~= "boss" and key ~= "arena" then
        local named = UNIT_NAME_POSITION_LABELS[key]
        if named then return Tr(named) end
        return string.format(Tr("%s Name Position"), tostring(cfg.label or key))
    end
    if U.ElementLabel then return U.ElementLabel(key, cfg) end
    return Tr(cfg and cfg.label or key)
end

local function CreateMover(key, cfg)
    local th = T()

    local mover = PixelLayoutRegion(CreateFrame("Button", nil, moverParent), true)
    mover:SetSize(100, 30)
    mover:SetFrameStrata("FULLSCREEN")
    mover:SetFrameLevel(cfg.popupType == "castbar" and 340 or cfg.popupType == "resource" and 330 or 300)
    mover:SetMovable(true); mover:RegisterForDrag("LeftButton")
    if mover.RegisterForClicks then mover:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    mover:EnableMouse(true); mover:SetClampedToScreen(true)
    mover._barKey = key

    local bg = PixelLayoutRegion(mover:CreateTexture(nil, "BACKGROUND"))
    bg:SetAllPoints(); bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
    mover._bg = bg

    local brd = PixelLayoutRegion(CreateFrame("Frame", nil, mover, "BackdropTemplate"))
    brd:SetAllPoints(); brd:SetFrameLevel(max(0, mover:GetFrameLevel() - 1))
    PixelLayoutRegion(brd, "SetBackdrop", { edgeFile = W8, edgeSize = 1 })
    brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
    mover._brd = brd

    local label = PixelLayoutRegion(mover:CreateFontString(nil, "OVERLAY"))
    label:SetFont(FONT, FontSize("caption"), "OUTLINE"); label:SetPoint("CENTER")
    label:SetTextColor(th.textR, th.textG, th.textB, 0.85); label:SetText(MoverLabelText(key, cfg))
    mover._label = label

    local coordFS = PixelLayoutRegion(mover:CreateFontString(nil, "OVERLAY"))
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
            if cfg.externalPublicElement or cfg.popupType == "resource" then
                --- Resources can be only a few pixels tall or use a hidden
                --- layout anchor. Keep their drag surface visible in preview.
                self._label:Show()
                self._bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
                self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
                return
            end
            if cfg.popupType == "unit" and key ~= "boss" and key ~= "arena" and not self._dragging then
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
            local historyCategory = cfg.historyCategory or (cfg.popupType == "castbar" and "castbar" or "unit")
            local historyKey = cfg.historyKey or (cfg.popupType == "castbar" and (cfg.castbarUnit or key:sub(9)) or key)
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
        moverParent = PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_MoverParent", UIParent), true)
        moverParent:SetAllPoints(UIParent); moverParent:SetFrameStrata("FULLSCREEN")
    end
    moverParent:Show()
    local reg = EM2.Registry and EM2.Registry.All()
    if not reg then return end
    for k, c in pairs(reg) do
        local f = c.getFrame and c.getFrame()
        if not movers[k] and (c.popupType ~= "resource" or f) then CreateMover(k, c) end
        local m = movers[k]
        if m then
            if f then SyncMoverToFrame(m, f, c); m:Show(); m:UpdateLabelVisibility() else m:Hide() end
        end
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
            local f = c.getFrame and c.getFrame()
            if not movers[k] and (c.popupType ~= "resource" or f) then CreateMover(k, c) end
            local m = movers[k]
            if m then
                if f then
                    SyncMoverToFrame(m, f, c)
                    m:Show()
                    m:UpdateLabelVisibility()
                else
                    m:Hide()
                end
            end
        end
    end
    Movers.RefreshGuidedPlacementCue()
end

--- Puts one existing mover back on its frame, for code that moved a single
--- frame. Showing, hiding and labels stay with SyncAll.
function Movers.SyncKey(key)
    local m = movers[key]
    if not (m and moverParent and moverParent:IsShown()) then return false end
    if EM2.Ticker and EM2.Ticker.IsDragging() then return false end
    local c = EM2.Registry and EM2.Registry.Get and EM2.Registry.Get(key)
    local f = c and c.getFrame and c.getFrame()
    if not f then return false end
    SyncMoverToFrame(m, f, c)
    return true
end
