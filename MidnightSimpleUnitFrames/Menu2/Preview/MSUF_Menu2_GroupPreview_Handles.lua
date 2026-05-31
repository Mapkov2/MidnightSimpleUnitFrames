--- Group preview handle, drag, and nudge helpers.
---
--- Native owns the preview host. This module owns interactive handles and the
--- save/write behavior behind drag and keyboard nudges.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local Handles = M.GroupPreviewHandles or {}
M.GroupPreviewHandles = Handles

function Handles.Install(box, deps)
    if not box then return nil end
    deps = deps or {}
    local max = math.max
    local H = deps.H or {}
    local M = deps.M or _G.MSUF2 or {}
    local MSUF = deps.MSUF or MSUF or {}
    local T = deps.T or M.Theme or {}
    local WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
    local GFPreviewTr = deps.TR or function(v) return v end
    local GFPreviewRound = deps.Round or function(value) return math.floor((tonumber(value) or 0) + 0.5) end
    local GFPreviewResolveAnchor = deps.ResolveAnchor or function() return "CENTER" end
    local GFPreviewPointOffset = deps.PointOffset or function() return 0, 0 end
    local GFPreviewHandleOffset = deps.HandleOffset or function() return 0, 0 end
    local GFPreviewOffsetToConfig = deps.OffsetToConfig or function(value) return GFPreviewRound(value) end
    local GFPreviewCurrentStatusSpec = deps.CurrentStatusSpec or function() return nil end
    local GFPreviewCurrentSpellConfig = deps.CurrentSpellConfig or function() return nil end
    local GFPreviewCurrentSpellPlaced = deps.CurrentSpellPlaced or function() return nil end
    local GFPreviewHandleText = deps.HandleText or function(handle) return handle and (handle._previewText or handle._key) or "Handle" end
    local GFPreviewHandleOffsets = deps.HandleOffsets or function() return nil end
    local GFPreviewUpdateHint = deps.UpdateHint or function() end
    local GFPreviewRefreshHandleSelection = deps.RefreshHandleSelection or function() end
    local GFPreviewStatusLabel = deps.StatusLabel or function() return "Status" end
    local GFPreviewStartPan = deps.StartPan or function() return false end
    local GFPreviewStopPan = deps.StopPan or function() end
    local GFPreviewZoomWheel = deps.ZoomWheel or function() end
    box._handles = {}
    box._handleList = {}
    -- The old monolith closed over the native preview mock. After splitting the
    -- file, bind it explicitly so preview handles never fall back to UIParent.
    local mock = box._mock or box
    local dragBounds = UIParent or box
    box._dragFrame = CreateFrame("Frame", nil, box)
    box._dragFrame:SetAllPoints(dragBounds)
    box._dragFrame:EnableMouse(true)
    if box._dragFrame.SetFrameStrata then box._dragFrame:SetFrameStrata("TOOLTIP") end
    box._dragFrame:Hide()

    local function SelectHandle(handle)
        box._selectedHandle = handle
        if box.SetFocus then box:SetFocus() end
        if handle and handle._cfgStatus and handle._statusSpec then
            if type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue("gfStatusIconSelection", handle._statusSpec.value)
            else
                M.gfStatusIconSelection = handle._statusSpec.value
            end
        end
        if handle and handle._cfgTextKind then
            M.gfTextTabSelection = M.gfTextTabSelection or {}
            M.gfTextTabSelection[H.CurrentScope()] = handle._cfgTextKind
            if handle._cfgTextSlot then
                H.SetTextMoveTogether(H.CurrentScope(), handle._cfgTextKind, false)
                M.gfTextSlotSelection = M.gfTextSlotSelection or {}
                M.gfTextSlotSelection[H.CurrentScope()] = M.gfTextSlotSelection[H.CurrentScope()] or {}
                M.gfTextSlotSelection[H.CurrentScope()][handle._cfgTextKind] = handle._cfgTextSlot
            elseif handle._cfgTextKind == "hp" or handle._cfgTextKind == "power" then
                H.SetTextMoveTogether(H.CurrentScope(), handle._cfgTextKind, true)
            end
        end
        GFPreviewRefreshHandleSelection(box)
    end

    local function HandleHistoryLabel(handle, action)
        local text = GFPreviewHandleText(handle)
        return tostring(action or "Move") .. ": " .. tostring(text)
    end

    local function CheckpointHandleHistory(handle, action)
        if not (M and type(M.CheckpointHistory) == "function") then return end
        M.CheckpointHistory(
            HandleHistoryLabel(handle, action),
            "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
        )
    end

    local function RefreshGroupPreviewAfterMove(handle)
        local gf = MSUF and MSUF.GF
        if gf and gf.RefreshVisuals then
            local dirty = gf.DIRTY_VISUAL or 0x02
            if handle and (handle._cfgGroup or handle._cfgSpell) then
                dirty = gf.DIRTY_AURAS or dirty
            end
            gf.RefreshVisuals(H.CurrentScope(), dirty)
        elseif gf and gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_VISUAL or 0x02)
        end
        box:Refresh()
        GFPreviewRefreshHandleSelection(box)
    end

    local function WriteTextHandleOffsets(handle, x, y, action, checkpoint)
        if not handle then return false end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local kind = handle._cfgTextKind or H.CurrentTextKind()
        local xKey, yKey = H.TextOffsetKeys(kind, handle._cfgTextSlot)
        conf[xKey] = GFPreviewRound(x or 0)
        conf[yKey] = GFPreviewRound(y or 0)
        RefreshGroupPreviewAfterMove(handle)
        if checkpoint then CheckpointHandleHistory(handle, action or "Move") end
        return true
    end

    local function SaveHandlePosition(handle, action)
        if not (handle and box._mock) or handle._locked then return end
        if handle._cfgText then return end
        local m = box._mock
        local anchorFrame = (handle._cfgGroup and handle._previewAnchorFrame) or m
        local mL, mT = anchorFrame:GetLeft() or 0, anchorFrame:GetTop() or 0
        local mW, mH = max(1, anchorFrame:GetWidth() or 1), max(1, anchorFrame:GetHeight() or 1)
        local hL, hT = handle:GetLeft() or 0, handle:GetTop() or 0
        local hB = handle:GetBottom() or 0
        local hW, hH = handle:GetWidth() or 1, handle:GetHeight() or 1
        local anchor, offX, offY
        if handle._cfgGroup and handle._previewOriginX and handle._previewOriginY then
            local px = hL + handle._previewOriginX
            local py = hB + handle._previewOriginY
            anchor = GFPreviewResolveAnchor((px - mL) / mW, (mT - py) / mH)
            offX, offY = GFPreviewPointOffset(px, py, anchorFrame, anchor)
        else
            local cx, cy = hL + hW * 0.5, hT - hH * 0.5
            anchor = GFPreviewResolveAnchor((cx - mL) / mW, (mT - cy) / mH)
            offX, offY = GFPreviewHandleOffset(handle, m, anchor)
        end
        local scale = handle._previewWriteScale or handle._previewScale or m._previewScale or 1
        local cfgX, cfgY = GFPreviewOffsetToConfig(offX, scale), GFPreviewOffsetToConfig(offY, scale)
        local conf = H.Conf(H.CurrentScope())

        if handle._cfgGroup then
            conf.auras = conf.auras or {}
            conf.auras[handle._cfgGroup] = conf.auras[handle._cfgGroup] or {}
            conf.auras[handle._cfgGroup].anchor = anchor
            conf.auras[handle._cfgGroup].x = cfgX
            conf.auras[handle._cfgGroup].y = cfgY
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or GFPreviewCurrentStatusSpec()
            if spec then
                conf[spec.anchor] = anchor
                conf[spec.x] = cfgX
                conf[spec.y] = cfgY
            end
        elseif handle._cfgSpell then
            local placed = GFPreviewCurrentSpellPlaced(H.CurrentScope())
            local spellCfg = GFPreviewCurrentSpellConfig(H.CurrentScope())
            if not placed and spellCfg then
                spellCfg.placed = { type = "icon", size = 18 }
                placed = spellCfg.placed
            end
            if placed then
                placed.anchor = anchor
                placed.x = cfgX
                placed.y = cfgY
            end
        end

        RefreshGroupPreviewAfterMove(handle)
        CheckpointHandleHistory(handle, action)
    end

    local function NudgeHandlePosition(handle, dx, dy)
        if not handle then return false end
        if handle._cfgText then
            local _, x, y = GFPreviewHandleOffsets(handle)
            local step = H.NudgeStep()
            return WriteTextHandleOffsets(handle, (tonumber(x) or 0) + (dx * step), (tonumber(y) or 0) + (dy * step), "Nudge", true)
        end

        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local _, x, y = GFPreviewHandleOffsets(handle)
        local step = H.NudgeStep()
        local cfgX, cfgY = GFPreviewRound((tonumber(x) or 0) + (dx * step)), GFPreviewRound((tonumber(y) or 0) + (dy * step))

        if handle._cfgGroup then
            conf.auras = conf.auras or {}
            conf.auras[handle._cfgGroup] = conf.auras[handle._cfgGroup] or {}
            conf.auras[handle._cfgGroup].x = cfgX
            conf.auras[handle._cfgGroup].y = cfgY
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or GFPreviewCurrentStatusSpec()
            if not spec then return false end
            conf[spec.x] = cfgX
            conf[spec.y] = cfgY
        elseif handle._cfgSpell then
            local placed = GFPreviewCurrentSpellPlaced(H.CurrentScope())
            local spellCfg = GFPreviewCurrentSpellConfig(H.CurrentScope())
            if not placed and spellCfg then
                spellCfg.placed = { type = "icon", size = 18 }
                placed = spellCfg.placed
            end
            if not placed then return false end
            placed.x = cfgX
            placed.y = cfgY
        else
            return false
        end

        RefreshGroupPreviewAfterMove(handle)
        CheckpointHandleHistory(handle, "Nudge")
        return true
    end

    local function StopHandleDrag(handle, button)
        if box._stage and box._stage._msufGFPreviewPanning then
            GFPreviewStopPan(box._stage)
        end
        if button and button ~= "LeftButton" then return end
        handle = handle or (box._dragFrame and box._dragFrame._handle)
        local wasDragging = handle and handle._dragging == true
        if box._dragFrame then
            box._dragFrame:SetScript("OnUpdate", nil)
            box._dragFrame._handle = nil
            box._dragFrame:Hide()
        end
        local hadFrozenScale = box._dragFrozenScale ~= nil
        box._dragFrozenScale = nil
        if handle then
            handle._dragging = nil
            handle._dragPoint = nil
            handle._dragRelTo = nil
            handle._dragRelPoint = nil
            handle._dragStartX = nil
            handle._dragStartY = nil
            handle._dragCfgStartX = nil
            handle._dragCfgStartY = nil
            handle._dragCursorX = nil
            handle._dragCursorY = nil
            handle._dragScale = nil
        end
        local didFinalRefresh
        if wasDragging and handle and handle._cfgText then
            if handle._lastDragX ~= nil or handle._lastDragY ~= nil then
                CheckpointHandleHistory(handle, "Move")
            else
                GFPreviewRefreshHandleSelection(box)
            end
        elseif wasDragging then
            SaveHandlePosition(handle, "Move")
            didFinalRefresh = true
        else
            GFPreviewRefreshHandleSelection(box)
        end
        if hadFrozenScale and not box._manualZoom and not didFinalRefresh and box.Refresh then
            box:Refresh()
        end
    end
    box._dragFrame:SetScript("OnMouseUp", function(_, button)
        StopHandleDrag(nil, button)
    end)

    local function UpdateHandleDrag(df)
        local handle = df and df._handle
        if not (handle and handle._dragging) then return end
        local cx, cy = GetCursorPosition()
        if not (cx and cy) then return end
        if handle._cfgText then
            local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if uiScale <= 0 then uiScale = 1 end
            local previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
            if previewScale <= 0 then previewScale = 1 end
            local dx = ((cx - (handle._dragCursorX or cx)) / uiScale) / previewScale
            local dy = ((cy - (handle._dragCursorY or cy)) / uiScale) / previewScale
            local nextX = GFPreviewRound((handle._dragCfgStartX or 0) + dx)
            local nextY = GFPreviewRound((handle._dragCfgStartY or 0) + dy)
            if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
            handle._lastDragX = nextX
            handle._lastDragY = nextY
            WriteTextHandleOffsets(handle, nextX, nextY, "Move", false)
            return
        end
        local scale = handle._dragScale or 1
        if scale <= 0 then scale = 1 end
        local dx = (cx - (handle._dragCursorX or cx)) / scale
        local dy = (cy - (handle._dragCursorY or cy)) / scale
        local nextX = GFPreviewRound((handle._dragStartX or 0) + dx)
        local nextY = GFPreviewRound((handle._dragStartY or 0) + dy)
        if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
        handle._lastDragX = nextX
        handle._lastDragY = nextY
        handle:ClearAllPoints()
        handle:SetPoint(handle._dragPoint or "CENTER", handle._dragRelTo or box._mock, handle._dragRelPoint or "CENTER", nextX, nextY)
        GFPreviewUpdateHint(box, handle)
    end

    local function StartHandleDrag(handle, button)
        if button and button ~= "LeftButton" then return end
        if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and GFPreviewStartPan(box._stage, box, button) then
            handle._suppressNextClick = true
            return
        end
        SelectHandle(handle)
        if not handle or handle._locked then return end
        local point, relativeTo, relativePoint, xOfs, yOfs = handle:GetPoint(1)
        local cx, cy = GetCursorPosition()
        if not (point and cx and cy) then return end
        handle._dragging = true
        box._dragFrozenScale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
        if handle._cfgText then
            local _, cfgX, cfgY = GFPreviewHandleOffsets(handle)
            handle._dragCfgStartX = tonumber(cfgX) or 0
            handle._dragCfgStartY = tonumber(cfgY) or 0
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
        box._dragFrame:SetScript("OnUpdate", UpdateHandleDrag)
        box._dragFrame:Show()
        GFPreviewRefreshHandleSelection(box)
    end

    local function CreatePreviewHandle(key, sectionKey, color, label, width, height, locked)
        local handle = CreateFrame("Button", nil, mock, T.Template())
        handle:SetSize(width or 32, height or 32)
        handle:SetMovable(true)
        handle:EnableMouse(true)
        handle:EnableMouseWheel(true)
        if handle.SetPropagateMouseWheel then handle:SetPropagateMouseWheel(true) end
        if handle.RegisterForDrag then handle:RegisterForDrag("LeftButton") end
        handle:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        handle:SetBackdropColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.42)
        handle:SetBackdropBorderColor(color[1], color[2], color[3], locked and 0.55 or 0.95)
        handle._key = key
        handle._sectionKey = sectionKey
        handle._locked = locked and true or false
        handle._color = color

        local selectFill = handle:CreateTexture(nil, "OVERLAY", nil, 6)
        selectFill:SetAllPoints()
        selectFill:SetColorTexture(color[1], color[2], color[3], 0)
        handle._selectFill = selectFill

        local selectBorder = CreateFrame("Frame", nil, handle, T.Template())
        selectBorder:SetPoint("TOPLEFT", handle, "TOPLEFT", -2, 2)
        selectBorder:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 2, -2)
        selectBorder:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        selectBorder:SetBackdropColor(0, 0, 0, 0)
        selectBorder:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        selectBorder:Hide()
        handle._selectBorder = selectBorder

        local fs = T.Font(handle, "GameFontDisableSmall", label or key, { color[1], color[2], color[3], 0.95 })
        fs:SetPoint("BOTTOM", handle, "TOP", 0, 1)
        fs:SetJustifyH("CENTER")
        handle._label = fs

        handle:SetScript("OnEnter", function(self)
            self._hovering = true
            GFPreviewRefreshHandleSelection(box)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(GFPreviewHandleText(self), 1, 1, 1)
                if self._locked then
                    GameTooltip:AddLine((M.Tr and M.Tr("This preview layer is locked.")) or "This preview layer is locked.", 0.82, 0.82, 0.82, true)
                    GameTooltip:AddLine(GFPreviewTr("Ctrl + left-drag pans the preview canvas."), 0.55, 0.68, 0.86, true)
                else
                    GameTooltip:AddLine((M.Tr and M.Tr("Drag this preview element to adjust the same placement offsets used by Group Frames.")) or "Drag this preview element to adjust the same placement offsets used by Group Frames.", 0.82, 0.82, 0.82, true)
                    GameTooltip:AddLine((M.Tr and M.Tr("Arrow keys nudge the selected element. Shift = 5, Ctrl = 10.")) or "Arrow keys nudge the selected element. Shift = 5, Ctrl = 10.", 0.55, 0.62, 0.72, true)
                    GameTooltip:AddLine(GFPreviewTr("Ctrl + left-drag pans the preview canvas."), 0.55, 0.68, 0.86, true)
                end
                GameTooltip:Show()
            end
        end)
        handle:SetScript("OnLeave", function(self)
            self._hovering = nil
            GFPreviewRefreshHandleSelection(box)
            if GameTooltip then GameTooltip:Hide() end
        end)
        handle:SetScript("OnClick", function(self)
            if self._suppressNextClick then
                self._suppressNextClick = nil
                return
            end
            SelectHandle(self)
        end)
        handle:SetScript("OnMouseWheel", GFPreviewZoomWheel)
        handle:SetScript("OnMouseDown", StartHandleDrag)
        handle:SetScript("OnMouseUp", StopHandleDrag)
        handle:HookScript("OnHide", function(self)
            StopHandleDrag(self)
            if box._selectedHandle == self then SelectHandle(nil) end
        end)
        box._handles[key] = handle
        box._handleList[#box._handleList + 1] = handle
        return handle
    end

    local function AddIconPool(handle, count)
        handle._icons = handle._icons or {}
        for i = 1, count do
            local tex = handle._icons[i] or handle:CreateTexture(nil, "ARTWORK")
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            handle._icons[i] = tex
        end
    end

    local buffHandle = CreatePreviewHandle("buff", "buffs", { 0.36, 0.79, 0.36 }, "BUFFS", 86, 34, false)
    buffHandle._cfgGroup = "buff"
    AddIconPool(buffHandle, 6)

    local debuffHandle = CreatePreviewHandle("debuff", "debuffs", { 0.89, 0.29, 0.29 }, "DEBUFFS", 86, 34, false)
    debuffHandle._cfgGroup = "debuff"
    AddIconPool(debuffHandle, 6)

    local statusHandles = {}
    local statusSpecs = H.StatusSpecs()
    for i = 1, #statusSpecs do
        local spec = statusSpecs[i]
        local statusHandle = CreatePreviewHandle("status_" .. tostring(spec.value or i), "sicons", { 0.80, 0.67, 0.20 }, GFPreviewStatusLabel(spec), 78, 28, false)
        statusHandle._cfgStatus = true
        statusHandle._statusSpec = spec
        statusHandle._statusTex = statusHandle:CreateTexture(nil, "ARTWORK")
        statusHandle._statusTex:SetPoint("TOPLEFT", statusHandle, "TOPLEFT", 0, 0)
        statusHandle._statusTex:SetPoint("BOTTOMRIGHT", statusHandle, "BOTTOMRIGHT", 0, 0)
        statusHandle._statusTex:Hide()
        statusHandle._statusText = T.Font(statusHandle, "GameFontHighlightLarge", "DEAD", { 1, 1, 1, 1 })
        statusHandle._statusText:SetPoint("CENTER")
        statusHandles[#statusHandles + 1] = statusHandle
    end

    local spellHandle = CreatePreviewHandle("si", "si", { 0.69, 0.50, 0.88 }, "SPELL", 44, 44, false)
    spellHandle._cfgSpell = true
    AddIconPool(spellHandle, 1)

    local function ConfigureTextHandle(handle, kind, slot)
        if not handle then return end
        handle._cfgText = true
        handle._cfgTextKind = kind
        handle._cfgTextSlot = slot
        handle._previewText = H.TextLabel(kind, slot)
        if handle.SetBackdropColor then handle:SetBackdropColor(0, 0, 0, 0) end
        if handle.SetBackdropBorderColor then
            local color = handle._color or { 0.55, 0.78, 0.95 }
            handle:SetBackdropBorderColor(color[1], color[2], color[3], 0)
        end
        if handle._label then handle._label:Hide() end
    end

    local nameTextHandle = CreatePreviewHandle("nameText", "text", { 0.30, 0.66, 1.00 }, "NAME", 74, 18, false)
    ConfigureTextHandle(nameTextHandle, "name")
    local hpTextHandle = CreatePreviewHandle("hpText", "text", { 0.25, 0.90, 0.42 }, "HP", 74, 18, false)
    ConfigureTextHandle(hpTextHandle, "hp")
    local hpLeftTextHandle = CreatePreviewHandle("hpTextLeft", "text", { 0.25, 0.90, 0.42 }, "HP L", 74, 18, false)
    ConfigureTextHandle(hpLeftTextHandle, "hp", "left")
    local hpCenterTextHandle = CreatePreviewHandle("hpTextCenter", "text", { 0.25, 0.90, 0.42 }, "HP C", 74, 18, false)
    ConfigureTextHandle(hpCenterTextHandle, "hp", "center")
    local hpRightTextHandle = CreatePreviewHandle("hpTextRight", "text", { 0.25, 0.90, 0.42 }, "HP R", 74, 18, false)
    ConfigureTextHandle(hpRightTextHandle, "hp", "right")
    local powerTextHandle = CreatePreviewHandle("powerText", "text", { 0.95, 0.72, 0.18 }, "POWER", 74, 18, false)
    ConfigureTextHandle(powerTextHandle, "power")
    local powerLeftTextHandle = CreatePreviewHandle("powerTextLeft", "text", { 0.95, 0.72, 0.18 }, "PWR L", 74, 18, false)
    ConfigureTextHandle(powerLeftTextHandle, "power", "left")
    local powerCenterTextHandle = CreatePreviewHandle("powerTextCenter", "text", { 0.95, 0.72, 0.18 }, "PWR C", 74, 18, false)
    ConfigureTextHandle(powerCenterTextHandle, "power", "center")
    local powerRightTextHandle = CreatePreviewHandle("powerTextRight", "text", { 0.95, 0.72, 0.18 }, "PWR R", 74, 18, false)
    ConfigureTextHandle(powerRightTextHandle, "power", "right")
    box._textHandles = {
        name = nameTextHandle,
        hpGroup = hpTextHandle,
        hpLeft = hpLeftTextHandle,
        hpCenter = hpCenterTextHandle,
        hpRight = hpRightTextHandle,
        powerGroup = powerTextHandle,
        powerLeft = powerLeftTextHandle,
        powerCenter = powerCenterTextHandle,
        powerRight = powerRightTextHandle,
    }
    function box:FocusTextSlot(kind, slot, active)
        kind = H.NormalizeTextFocusKind(kind)
        slot = H.NormalizeTextFocusSlot(slot)
        if not kind then
            self._msufMenuTextFocus = nil
        else
            self._msufMenuTextFocus = {
                kind = kind,
                slot = slot,
                active = active == true,
            }
        end
        if self.RequestRefresh then
            self:RequestRefresh(kind and "GROUP_PREVIEW_TEXT_FOCUS" or "GROUP_PREVIEW_TEXT_CLEAR_FOCUS")
        elseif self.Refresh then
            self:Refresh()
        end
        return true
    end


    return {
        buffHandle = buffHandle,
        debuffHandle = debuffHandle,
        statusHandles = statusHandles,
        spellHandle = spellHandle,
        SelectHandle = SelectHandle,
        NudgeHandlePosition = NudgeHandlePosition,
        AddIconPool = AddIconPool,
        StopHandleDrag = StopHandleDrag,
    }
end
