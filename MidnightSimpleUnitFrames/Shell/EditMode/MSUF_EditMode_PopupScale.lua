--- MSUF_EditMode_PopupScale.lua - shared bottom-right scale grip for EM2 popups
-- Handles popup resize UI only; persisted geometry writes stay in EditMode popup owners.

local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local abs = math.abs
local floor = math.floor
local format = string.format
local max, min = math.max, math.min
local pairs = pairs

local MIN_SCALE = 0.75
local MAX_SCALE = 1.50
local DEFAULT_SCALE = 1.00

local scaledFrames = {}

local function ClampScale(value)
    value = tonumber(value) or DEFAULT_SCALE
    return max(MIN_SCALE, min(MAX_SCALE, value))
end

local function General(create)
    local db = _G.MSUF_DB
    if not db then return nil end
    if create then db.general = db.general or {} end
    return db.general
end

local function ReadScale()
    local g = General(false)
    return ClampScale(g and g.editModePopupScale)
end

local function WriteScale(value)
    local g = General(true)
    if g then g.editModePopupScale = ClampScale(value) end
end

--- Per-popup saved positions (TOPLEFT offsets in the popup's own frame space).
--- Keyed by frame name so each popup reopens where the user left it.
local function PopupName(frame)
    return frame and frame.GetName and frame:GetName() or nil
end

local function ReadPopupPos(frame)
    local g = General(false)
    local name = PopupName(frame)
    local store = g and g.editModePopupPos
    local pos = name and store and store[name]
    if type(pos) == "table" then return tonumber(pos.left), tonumber(pos.top) end
    return nil, nil
end

local function WritePopupPos(frame, left, top)
    local name = PopupName(frame)
    if not (name and left and top) then return end
    local g = General(true)
    if not g then return end
    g.editModePopupPos = g.editModePopupPos or {}
    g.editModePopupPos[name] = { left = left, top = top }
end

local function CursorPositionInUIParent()
    if not (UIParent and GetCursorPosition) then return nil, nil end
    local scale = UIParent.GetEffectiveScale and (UIParent:GetEffectiveScale() or 1) or 1
    if scale <= 0 then scale = 1 end
    local x, y = GetCursorPosition()
    return (x or 0) / scale, (y or 0) / scale
end

local function FrameScaleToUIParent(frame)
    local frameScale = frame and frame.GetEffectiveScale and (frame:GetEffectiveScale() or 1) or 1
    local uiScale = UIParent and UIParent.GetEffectiveScale and (UIParent:GetEffectiveScale() or 1) or 1
    if frameScale <= 0 then frameScale = 1 end
    if uiScale <= 0 then uiScale = 1 end
    local ratio = frameScale / uiScale
    return ratio > 0 and ratio or 1
end

local function FrameRectToUIParent(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local ratio = FrameScaleToUIParent(frame)
    return l * ratio, r * ratio, t * ratio, b * ratio
end

local function ClampVisualIntoScreen(left, top, visualW, visualH)
    if not (UIParent and UIParent.GetWidth and UIParent.GetHeight) then return left, top end
    local screenW = UIParent:GetWidth() or 0
    local screenH = UIParent:GetHeight() or 0
    visualW = max(1, tonumber(visualW) or 1)
    visualH = max(1, tonumber(visualH) or 1)
    left = max(0, min(tonumber(left) or 0, max(0, screenW - visualW)))
    top = max(visualH, min(tonumber(top) or screenH, screenH))
    return left, top
end

--- Clamp the frame fully inside UIParent. SetClampedToScreen only kicks in
--- on drag/resize, not on a programmatic SetPoint after a scale change, so a
--- scaled-up popup can hang off-screen. We pull the TOPLEFT anchor offsets
--- (which live in the frame's own scaled coordinate space) back into view.
local function ClampIntoScreen(frame, left, top)
    if not (frame and UIParent and frame.GetWidth and frame.GetHeight) then return left, top end
    local f2u = FrameScaleToUIParent(frame)
    --- Screen extents in UIParent space.
    local screenW = UIParent:GetWidth() or 0
    local screenH = UIParent:GetHeight() or 0
    --- Frame size in UIParent space.
    local w = (frame:GetWidth() or 0) * f2u
    local h = (frame:GetHeight() or 0) * f2u
    --- Anchor is TOPLEFT relative to UIParent BOTTOMLEFT, offsets in frame space.
    --- Convert to UIParent space, clamp, convert back.
    local uLeft = (left or 0) * f2u
    local uTop = (top or 0) * f2u
    uLeft = max(0, min(uLeft, max(0, screenW - w)))
    uTop = max(h, min(uTop, screenH))
    return uLeft / f2u, uTop / f2u
end

local function AnchorTopLeft(frame, left, top)
    if not (frame and frame.GetLeft and frame.GetTop and frame.ClearAllPoints and frame.SetPoint) then return nil, nil end
    left, top = left or frame:GetLeft(), top or frame:GetTop()
    if not (left and top) then return nil, nil end
    left, top = ClampIntoScreen(frame, left, top)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    return left, top
end

local function AnchorTopLeftVisual(frame, uiLeft, uiTop)
    if not (frame and frame.GetWidth and frame.GetHeight) then return nil, nil end
    local scale = FrameScaleToUIParent(frame)
    local visualW = (frame:GetWidth() or 0) * scale
    local visualH = (frame:GetHeight() or 0) * scale
    uiLeft, uiTop = ClampVisualIntoScreen(uiLeft, uiTop, visualW, visualH)
    return AnchorTopLeft(frame, (uiLeft or 0) / scale, (uiTop or 0) / scale)
end

local function ApplyProxyPriority(proxy, owner)
    if not proxy then return end
    local strata = owner and owner.GetFrameStrata and owner:GetFrameStrata() or "DIALOG"
    local level = owner and owner.GetFrameLevel and owner:GetFrameLevel() or 200
    if proxy.SetFrameStrata then proxy:SetFrameStrata(strata) end
    if proxy.SetFrameLevel then proxy:SetFrameLevel(level + 80) end
    if proxy.SetToplevel then proxy:SetToplevel(false) end
end

local function EnsureScaleProxy(frame)
    if frame._msufEM2ScaleProxy then return frame._msufEM2ScaleProxy end
    local proxy = CreateFrame("Frame", nil, UIParent)
    ApplyProxyPriority(proxy, frame)
    proxy:Hide()

    local fill = proxy:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0.02, 0.06, 0.09, 0.18)
    proxy.fill = fill

    local function Edge(pointA, pointB, width, height)
        local tex = proxy:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(0.00, 0.72, 1.00, 0.72)
        tex:SetPoint(unpack(pointA))
        tex:SetPoint(unpack(pointB))
        if width then tex:SetWidth(width) end
        if height then tex:SetHeight(height) end
        return tex
    end
    Edge({ "TOPLEFT", proxy, "TOPLEFT", 0, 0 }, { "TOPRIGHT", proxy, "TOPRIGHT", 0, 0 }, nil, 2)
    Edge({ "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 0, 0 }, nil, 2)
    Edge({ "TOPLEFT", proxy, "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0 }, 2, nil)
    Edge({ "TOPRIGHT", proxy, "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 0, 0 }, 2, nil)

    local label = proxy:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local ui = (type(MSUF) == "table" and MSUF.UI) or _G.MSUF_UI
    if ui and ui.ApplyFontSize then ui.ApplyFontSize(label, "caption") end
    label:SetPoint("BOTTOMRIGHT", proxy, "TOPRIGHT", 0, 4)
    label:SetJustifyH("RIGHT")
    if label.SetTextColor then label:SetTextColor(0.22, 0.78, 0.94, 1) end
    proxy.sizeLabel = label

    frame._msufEM2ScaleProxy = proxy
    return proxy
end

local function ShowScaleProxy(frame, state, scale)
    if not (frame and state) then return end
    local proxy = EnsureScaleProxy(frame)
    ApplyProxyPriority(proxy, frame)
    local visualW = (state.baseW or 440) * scale
    local visualH = (state.baseH or 292) * scale
    local left, top = ClampVisualIntoScreen(state.uiLeft or 0, state.uiTop or 0, visualW, visualH)
    proxy:ClearAllPoints()
    proxy:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    proxy:SetSize(visualW, visualH)
    if proxy.sizeLabel then
        proxy.sizeLabel:SetText(format("%d%%  %d x %d", floor(scale * 100 + 0.5), floor(visualW + 0.5), floor(visualH + 0.5)))
    end
    proxy:Show()
end

local function HideScaleProxy(frame)
    local proxy = frame and frame._msufEM2ScaleProxy
    if proxy then
        proxy:SetScript("OnUpdate", nil)
        proxy:Hide()
    end
end

local function ApplyScale(scale)
    scale = ClampScale(scale)
    for frame in pairs(scaledFrames) do
        if frame and frame.SetScale then frame:SetScale(scale) end
    end
end

function EM2.GetPopupScale()
    return ReadScale()
end

function EM2.SetPopupScale(scale)
    scale = ClampScale(scale)
    WriteScale(scale)
    ApplyScale(scale)
    return scale
end

function EM2.AttachPopupScaleGrip(frame)
    if not (frame and frame.CreateTexture and frame.SetScale) or frame._msufEM2ScaleGrip then return frame end

    scaledFrames[frame] = true
    frame._msufEM2BaseW = frame.GetWidth and frame:GetWidth() or 440
    frame._msufEM2BaseH = frame.GetHeight and frame:GetHeight() or 292
    frame:SetScale(ReadScale())

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    if frame.GetFrameLevel and grip.SetFrameLevel then grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 30) end
    if grip.RegisterForClicks then grip:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp") end
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local finish
    local function update()
        local state = frame._msufEM2ScaleDrag
        if not state then return end
        if not frame._msufEM2FinishingScale and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            if finish then finish(true) end
            return
        end
        local x, y = CursorPositionInUIParent()
        if not x then return end
        local scaleW = (state.visualW + (x - state.cursorX)) / state.baseW
        local scaleH = (state.visualH + (state.cursorY - y)) / state.baseH
        local nextScale = (abs(scaleW - state.startScale) >= abs(scaleH - state.startScale)) and scaleW or scaleH
        nextScale = ClampScale(nextScale)
        frame._msufEM2PendingScale = nextScale
        ShowScaleProxy(frame, state, nextScale)
    end

    local function begin(button)
        if button == "RightButton" then
            local uiLeft, _, uiTop = FrameRectToUIParent(frame)
            EM2.SetPopupScale(DEFAULT_SCALE)
            if uiLeft and uiTop then AnchorTopLeftVisual(frame, uiLeft, uiTop) else AnchorTopLeft(frame) end
            return
        end
        if button ~= "LeftButton" then return end
        local x, y = CursorPositionInUIParent()
        if not x then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if not (left and top) then return end
        local uiLeft, _, uiTop = FrameRectToUIParent(frame)
        local currentScale = ClampScale(frame.GetScale and frame:GetScale() or ReadScale())
        local baseW = frame.GetWidth and frame:GetWidth() or frame._msufEM2BaseW or 440
        local baseH = frame.GetHeight and frame:GetHeight() or frame._msufEM2BaseH or 292
        frame._msufEM2ScaleDrag = {
            cursorX = x,
            cursorY = y,
            startScale = currentScale,
            baseW = baseW,
            baseH = baseH,
            visualW = baseW * currentScale,
            visualH = baseH * currentScale,
            left = left,
            top = top,
            uiLeft = uiLeft or (left * currentScale),
            uiTop = uiTop or (top * currentScale),
        }
        frame._msufEM2PendingScale = currentScale
        grip:SetScript("OnUpdate", update)
        update()
    end

    finish = function(apply)
        local state = frame._msufEM2ScaleDrag
        frame._msufEM2FinishingScale = true
        if state then update() end
        grip:SetScript("OnUpdate", nil)
        frame._msufEM2ScaleDrag = nil
        HideScaleProxy(frame)
        if apply and state then
            --- Apply scale first so AnchorTopLeft/ClampIntoScreen see the new
            --- scale and frame size when pulling the popup back on-screen.
            EM2.SetPopupScale(frame._msufEM2PendingScale or state.startScale or ReadScale())
            AnchorTopLeftVisual(frame, state.uiLeft, state.uiTop)
            if frame._msufEM2SavePosition then frame._msufEM2SavePosition() end
        end
        frame._msufEM2PendingScale = nil
        frame._msufEM2FinishingScale = nil
    end

    grip:SetScript("OnMouseDown", function(_, button) begin(button) end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then return end
        finish(true)
    end)
    grip:SetScript("OnHide", function() finish(false) end)

    local function SavePosition()
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then WritePopupPos(frame, left, top) end
    end
    frame._msufEM2SavePosition = SavePosition

    --- Persist position when the user finishes dragging the popup.
    frame:HookScript("OnDragStop", SavePosition)

    frame:HookScript("OnShow", function(self)
        self:SetScale(ReadScale())
        --- Restore the saved position, then re-clamp: a popup could have been
        --- left off-screen, or the scale may have changed (via another popup)
        --- while this one was hidden.
        local function Place()
            if not self:IsShown() then return end
            local left, top = ReadPopupPos(self)
            AnchorTopLeft(self, left, top)
        end
        C_Timer.After(0, Place)
    end)
    frame:HookScript("OnHide", function(self)
        finish(false)
        SavePosition()
    end)

    frame._msufEM2ScaleGrip = grip
    return frame
end
