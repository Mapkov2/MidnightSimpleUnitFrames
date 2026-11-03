-- Group preview HandleDrag owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local FILE = "Menu2/GroupPreview_Handles"
local Stage = {}
local max = math.max
local RequestBoxRefresh = M.PreviewContracts.RequireFields("GroupHandleDrag.HandleStorage", M.GroupPreviewHandleStorage, "RequestBoxRefresh").RequestBoxRefresh
local HANDLE_CLICK_DRAG_THRESHOLD = 3
local function ResolveTextDragPixelDelta(round, current, startValue, scale, endpointBias)
    endpointBias = tonumber(endpointBias) or 0
    return round(((tonumber(current) or 0) + endpointBias) * scale)
        - round(((tonumber(startValue) or 0) + endpointBias) * scale)
end
local DRAG_STATE_KEYS = {
    "_dragging", "_dragPoint", "_dragRelTo", "_dragRelPoint", "_dragStartX", "_dragStartY", "_dragCfgStartX", "_dragCfgStartY",
    "_dragEndpointBiasX", "_dragEndpointBiasY", "_dragCursorX", "_dragCursorY", "_dragScale", "_suppressSettingsOnRelease", "_didDragMove",
}
-- Region pools every aura handle keeps, one entry per pooled icon.
-- Preview font strings that paint a text handle when H.TextRegions has no answer: the slot picks one, no slot takes all three.
local TEXT_REGION_KEYS = {
    name = { "_nameFS" },
    hp = { "_hpLeftFS", "_hpCenterFS", "_hpRightFS" },
    power = { "_powerLeftFS", "_powerCenterFS", "_powerRightFS" },
}
local TEXT_REGION_SLOT = { left = 1, center = 2, right = 3 }
local function MirrorTextRegions(m, kind, slot)
    local keys = TEXT_REGION_KEYS[kind]
    if not keys then return nil end
    local index = #keys == 1 and 1 or TEXT_REGION_SLOT[slot]
    if index then return { m[keys[index]] } end
    return { m[keys[1]], m[keys[2]], m[keys[3]] }
end
-- Capture every point so grouped HP/Power regions and their focus frame
-- retain their complete geometry during the temporary drag preview.
local function CaptureTextDragFrame(list, frame)
    if not (list and frame and frame.GetPoint and frame.ClearAllPoints and frame.SetPoint) then return end
    if frame.IsShown and not frame:IsShown() then return end
    local count = (frame.GetNumPoints and frame:GetNumPoints()) or 1
    if count < 1 then return end
    local points
    for i = 1, count do
        local point, relTo, relPoint, xOfs, yOfs = frame:GetPoint(i)
        if point then
            points = points or {}
            points[#points + 1] = { point = point, relTo = relTo, relPoint = relPoint, x = xOfs or 0, y = yOfs or 0 }
        end
    end
    if not points then return end
    list[#list + 1] = { frame = frame, points = points }
end
-- Group Aura lanes only render in the CUSTOM renderer: moving one has to show.
function Stage.BindTextDrag(st)
    local H, Round, box, UpdateHint, RefreshHandleSelection = st.H, st.Round, st.box, st.UpdateHint, st.RefreshHandleSelection
    local RefreshGroupPreviewAfterMove, CheckpointHandleHistory = st.RefreshGroupPreviewAfterMove, st.CheckpointHandleHistory
    local function TextRegionsForHandle(handle)
        if not (handle and box._mock) then return nil end
        local kind = handle._cfgTextKind or H.CurrentTextKind()
        local slot = handle._cfgTextSlot
        if kind == "hp" and (slot == "left" or slot == "right") then
            -- Under reverse order the configured left slot renders on the
            -- physical right FontString (and vice versa); pair the handle with
            -- the FontString that shows its slot's content.
            local conf = H.Conf(H.CurrentScope())
            if conf and conf.hpTextReverse == true then
                slot = slot == "left" and "right" or "left"
            end
        end
        if type(H.TextRegions) == "function" then
            local regions = H.TextRegions(box._mock, kind, slot)
            if regions then return regions end
        end
        return MirrorTextRegions(box._mock, kind, slot)
    end
    local function CaptureTextDragRegions(handle)
        if not handle then return end
        local captured = {}
        local regions = TextRegionsForHandle(handle)
        if regions then
            for i = 1, #regions do
                CaptureTextDragFrame(captured, regions[i])
            end
        end
        local focus = box._msufMenuTextFocus
        if focus and focus.kind == (handle._cfgTextKind or H.CurrentTextKind()) and focus.slot == handle._cfgTextSlot then
            CaptureTextDragFrame(captured, box._msufMenuTextFocusFrame)
        end
        handle._textDragRegions = captured
    end
    local function ApplyTextRegionDrag(handle, nextX, nextY)
        if not handle then return false end
        local previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
        if previewScale <= 0 then previewScale = 1 end
        local dx = ResolveTextDragPixelDelta(Round, nextX, handle._dragCfgStartX or 0, previewScale, handle._dragEndpointBiasX)
        local dy = ResolveTextDragPixelDelta(Round, nextY, handle._dragCfgStartY or 0, previewScale, handle._dragEndpointBiasY)
        local moved = false
        local captured = handle._textDragRegions
        if captured then
            -- The delta is in the units of the outer preview frame. The engine texts sit in the zoomed cell, whose
            -- offsets are in the cell's own units: the same screen distance is the delta over the scale ratio.
            local mockScale = box._mock and box._mock.GetEffectiveScale and box._mock:GetEffectiveScale() or 1
            for i = 1, #captured do
                local item = captured[i]
                local frame = item and item.frame
                local points = item and item.points
                if frame and points and frame.ClearAllPoints and frame.SetPoint then
                    local owner = frame.GetEffectiveScale and frame or (frame.GetParent and frame:GetParent())
                    local frameScale = owner and owner.GetEffectiveScale and owner:GetEffectiveScale() or mockScale
                    local k = (mockScale and mockScale > 0 and frameScale and frameScale > 0) and mockScale / frameScale or 1
                    frame:ClearAllPoints()
                    for j = 1, #points do
                        local p = points[j]
                        frame:SetPoint(p.point, p.relTo or box._mock, p.relPoint or p.point, (p.x or 0) + dx * k, (p.y or 0) + dy * k)
                    end
                    -- Direct drag painting temporarily mutates the same region
                    -- cached by Group Preview Name layout. Mark it dirty so the
                    -- next render reasserts saved geometry even if a write was
                    -- rejected or rounded back to its starting value.
                    if frame._msufPreviewNameNaturalWidth == true then
                        frame._msufPreviewNameGeometryDirty = true
                    end
                    moved = true
                end
            end
        end
        if handle._dragPoint then
            handle:ClearAllPoints()
            handle:SetPoint(handle._dragPoint, handle._dragRelTo or box._mock, handle._dragRelPoint or handle._dragPoint, (handle._dragStartX or 0) + dx,
                (handle._dragStartY or 0) + dy)
            moved = true
        end
        return moved
    end
    local function ReleaseTextDragRegions(handle)
        if handle then handle._textDragRegions = nil end
    end
    local function WriteTextHandleOffsets(handle, x, y, action, checkpoint, previewOnly)
        if not handle then return false end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local kind = handle._cfgTextKind or H.CurrentTextKind()
        local xKey, yKey = H.TextOffsetKeys(kind, handle._cfgTextSlot)
        conf[xKey] = Round(x or 0)
        conf[yKey] = Round(y or 0)
        if previewOnly then
            UpdateHint(box, handle)
            RefreshHandleSelection(box)
        else
            RefreshGroupPreviewAfterMove(handle)
        end
        if checkpoint then CheckpointHandleHistory(handle, action or "Move") end
        return true
    end
    st.ApplyTextRegionDrag, st.CaptureTextDragRegions = ApplyTextRegionDrag, CaptureTextDragRegions
    st.ReleaseTextDragRegions, st.WriteTextHandleOffsets = ReleaseTextDragRegions, WriteTextHandleOffsets
end

--- Position writer: saving a dragged handle into the config.
function Stage.BindDrag(st)
    local M, PreviewHelpers, box, Round = st.M, st.PreviewHelpers, st.box, st.Round
    local ConfigCombatLocked, RefreshHandleSelection, SaveHandlePosition = st.ConfigCombatLocked, st.RefreshHandleSelection, st.SaveHandlePosition
    local ApplyTextRegionDrag, ReleaseTextDragRegions = st.ApplyTextRegionDrag, st.ReleaseTextDragRegions
    local StopPan, UpdateHint, WriteTextHandleOffsets = st.StopPan, st.UpdateHint, st.WriteTextHandleOffsets
    local function StopHandleDrag(handle, button, allowOpenSettings)
        if box._stage and box._stage._msufGFPreviewPanning then StopPan(box._stage) end
        if button and button ~= "LeftButton" then return end
        handle = handle or (box._dragFrame and box._dragFrame._handle)
        local wasDragging = handle and handle._dragging == true
        local textDrag = handle and handle._cfgText
        local didMove = handle and handle._didDragMove == true
        if didMove and PreviewHelpers.NotePreviewElementMoved then PreviewHelpers.NotePreviewElementMoved() end
        local openSettingsOnRelease = handle and allowOpenSettings == true
            and button == "LeftButton"
            and handle._suppressSettingsOnRelease ~= true
            and not didMove
        if box._dragFrame then
            box._dragFrame:SetScript("OnUpdate", nil)
            box._dragFrame._handle = nil
            box._dragFrame:Hide()
        end
        local hadFrozenScale = box._dragFrozenScale ~= nil
        if not textDrag then box._dragFrozenScale = nil end
        if handle then
            if textDrag and box.SetTextDragRefreshSuppressed then box:SetTextDragRefreshSuppressed(false) end
            for i = 1, #DRAG_STATE_KEYS do
                handle[DRAG_STATE_KEYS[i]] = nil
            end
        end
        local didFinalRefresh
        if wasDragging and textDrag then
            if handle._lastDragX ~= nil or handle._lastDragY ~= nil then
                st.RefreshGroupPreviewAfterMove(handle, true)
                if box.Refresh then box:Refresh("GROUP_PREVIEW_TEXT_DRAG_END") end
                if M.RequestRefresh then M.RequestRefresh(nil, "gf-text-drag-controls") end
                st.CheckpointHandleHistory(handle, "Move")
                didFinalRefresh = true
            else
                RefreshHandleSelection(box)
            end
        elseif wasDragging and didMove then
            SaveHandlePosition(handle, "Move")
            didFinalRefresh = true
        else
            RefreshHandleSelection(box)
        end
        if hadFrozenScale and not box._manualZoom and not didFinalRefresh and not openSettingsOnRelease then
            RequestBoxRefresh(box, "GROUP_PREVIEW_DRAG_END")
        end
        if textDrag then
            ReleaseTextDragRegions(handle)
            box._dragFrozenScale = nil
        end
        if openSettingsOnRelease then st.OpenHandleSettings(handle) end
    end
    box._dragFrame:SetScript("OnMouseUp", function(_, button)
        StopHandleDrag(nil, button, true)
    end)
    local function UpdateHandleDrag(df)
        local handle = df and df._handle
        if not (handle and handle._dragging) then return end
        if ConfigCombatLocked() then
            StopHandleDrag(handle, "LeftButton")
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            StopHandleDrag(handle, "LeftButton", true)
            return
        end
        local cx, cy = GetCursorPosition()
        if not (cx and cy) then return end
        local cursorX, cursorY = handle._dragCursorX or cx, handle._dragCursorY or cy
        if handle._didDragMove ~= true then
            local cursorDX, cursorDY = cx - cursorX, cy - cursorY
            if cursorDX * cursorDX + cursorDY * cursorDY < HANDLE_CLICK_DRAG_THRESHOLD * HANDLE_CLICK_DRAG_THRESHOLD then
                return
            end
            handle._didDragMove = true
        end
        -- Text handles drag in config units (screen delta over UI and preview scale); every other handle drags in
        -- screen pixels over the scale of the frame it is anchored to.
        local startX, startY, scale, previewScale
        if handle._cfgText then
            startX, startY = handle._dragCfgStartX, handle._dragCfgStartY
            scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if scale <= 0 then scale = 1 end
            previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
            if previewScale <= 0 then previewScale = 1 end
        else
            startX, startY, scale, previewScale = handle._dragStartX, handle._dragStartY, handle._dragScale or 1, 1
            if scale <= 0 then scale = 1 end
        end
        local nextX = Round((startX or 0) + (cx - cursorX) / scale / previewScale)
        local nextY = Round((startY or 0) + (cy - cursorY) / scale / previewScale)
        if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
        handle._lastDragX = nextX
        handle._lastDragY = nextY
        if handle._cfgText then
            ApplyTextRegionDrag(handle, nextX, nextY)
            WriteTextHandleOffsets(handle, nextX, nextY, "Move", false, true)
            return
        end
        handle:ClearAllPoints()
        handle:SetPoint(handle._dragPoint or "CENTER", handle._dragRelTo or box._mock, handle._dragRelPoint or "CENTER", nextX, nextY)
        UpdateHint(box, handle)
        SaveHandlePosition(handle, "Move", true)
    end
    st.StopHandleDrag, st.UpdateHandleDrag = StopHandleDrag, UpdateHandleDrag
end

--- Pointer drag start: selection, the pan shortcut and the drag origin of every
--- handle kind.
function Stage.BindDragStart(st)
    local PreviewHelpers, box, ConfigCombatLocked, SelectHandle = st.PreviewHelpers, st.box, st.ConfigCombatLocked, st.SelectHandle
    local RefreshHandleSelection, StartPan, UpdateHandleDrag = st.RefreshHandleSelection, st.StartPan, st.UpdateHandleDrag
    local function StartHandleDrag(handle, button)
        if ConfigCombatLocked() then return end
        if button and button ~= "LeftButton" then return end
        if handle then handle._didDragMove = nil end
        if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and StartPan(box._stage, box, button) then
            handle._suppressNextClick = true
            handle._suppressSettingsOnRelease = true
            return
        end
        SelectHandle(handle)
        if PreviewHelpers.ShowPreviewMoveCue then PreviewHelpers.ShowPreviewMoveCue(box, handle) end
        if not handle or handle._locked then return end
        local point, relativeTo, relativePoint, xOfs, yOfs = handle:GetPoint(1)
        local cx, cy = GetCursorPosition()
        if not (point and cx and cy) then return end
        handle._dragging = true
        box._dragFrozenScale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
        if handle._cfgText then
            local _, cfgX, cfgY = st.HandleOffsets(handle)
            handle._dragCfgStartX = tonumber(cfgX) or 0
            handle._dragCfgStartY = tonumber(cfgY) or 0
            if handle._cfgTextKind == "name" then
                local fs = box._mock and box._mock._nameFS
                handle._dragEndpointBiasX = (tonumber(fs and fs._msufPreviewNameEndpointX)
                    or handle._dragCfgStartX) - handle._dragCfgStartX
                handle._dragEndpointBiasY = (tonumber(fs and fs._msufPreviewNameEndpointY)
                    or handle._dragCfgStartY) - handle._dragCfgStartY
            end
            st.CaptureTextDragRegions(handle)
            if box.SetTextDragRefreshSuppressed then
                box:SetTextDragRefreshSuppressed(true)
            elseif box.CancelPendingRefresh then
                box:CancelPendingRefresh()
            end
        end
        handle._dragPoint = point
        handle._dragRelTo = relativeTo or box._mock
        handle._dragRelPoint = relativePoint or point
        handle._dragStartX = xOfs or 0
        handle._dragStartY = yOfs or 0
        handle._dragCursorX = cx
        handle._dragCursorY = cy
        handle._lastDragX = nil
        handle._lastDragY = nil
        local rel = handle._dragRelTo
        handle._dragScale = (rel and rel.GetEffectiveScale and rel:GetEffectiveScale())
            or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
            or 1
        box._dragFrame._handle = handle
        if box._dragFrame.SetAllPoints then box._dragFrame:SetAllPoints(box._stage or box) end
        box._dragFrame:SetScript("OnUpdate", UpdateHandleDrag)
        box._dragFrame:Show()
        RefreshHandleSelection(box)
    end
    st.StartHandleDrag = StartHandleDrag
end

--- Handle factory: the preview handle button (scripts, tooltip, quick actions,
--- control registration).
M.GroupPreviewHandleDrag = Stage
Stage.ResolveTextDragPixelDelta = ResolveTextDragPixelDelta
