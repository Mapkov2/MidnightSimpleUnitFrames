--- Group preview handle, drag, and nudge helpers.
---
--- Native owns the preview host. This module owns interactive handles and the
--- save/write behavior behind drag and keyboard nudges.
local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local Handles = M.GroupPreviewHandles or {}
M.GroupPreviewHandles = Handles
local F = M.Fallbacks or {}
local HANDLE_CLICK_DRAG_THRESHOLD = 3
local HANDLE_LABEL_HIT_HEIGHT = 14
local function ResolveTextDragPixelDelta(round, current, startValue, scale, endpointBias)
    endpointBias = tonumber(endpointBias) or 0
    return round(((tonumber(current) or 0) + endpointBias) * scale)
        - round(((tonumber(startValue) or 0) + endpointBias) * scale)
end
Handles._ResolveTextDragPixelDelta = ResolveTextDragPixelDelta
local function FallbackHandleText(handle)
    return handle and (handle._previewText or handle._key) or "Handle"
end
local HANDLE_FALLBACKS = {
    TR = F.Identity, Round = F.Round, ResolveAnchor = F.Center, PointOffset = F.ZeroPair, HandleOffset = F.ZeroPair, OffsetToConfig = F.Round,
    CurrentStatusSpec = F.Nil, CurrentSpellConfig = F.Nil, CurrentSpellPlaced = F.Nil, HandleText = FallbackHandleText, HandleOffsets = F.Nil,
    UpdateHint = F.Noop, RefreshHandleSelection = F.Noop, StatusLabel = F.Status, StartPan = F.False, StopPan = F.Noop, ZoomWheel = F.Noop,
}
local SPELL_DROP_ANCHOR_FRAC = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local GROUP_HANDLE_LAYER_BY_KEY = {
    buff = "buff",
    trackedBuff = "trackedBuff",
    debuff = "debuff",
    external = "external",
    powerBar = "power",
    portrait = "portrait",
    dispelSymbol = "dispelSymbol",
    si = "si",
}
local GROUP_SECTION_LAYER = {
    text = "text",
    power = "power",
    portrait = "portrait",
    buffs = "buff",
    debuffs = "debuff",
    externals = "external",
    sicons = "status",
    si = "si",
    dispel = "dispelSymbol",
    dispelSymbol = "dispelSymbol",
}
function Handles.Install(box, deps)
    if not box then return nil end
    deps = deps or {}
    local max = math.max
    local H = deps.H or {}
    local M = deps.M or _G.MSUF2 or {}
    local MSUF = deps.MSUF or MSUF or {}
    local function AuraDurationBarColor()
        local auras3 = MSUF.MSUF_Auras3
        local resolver = auras3 and auras3.GetDurationBarColor
        if type(resolver) == "function" then return resolver() end
        return 1, 1, 1
    end
    local T = deps.T or M.Theme or {}
    local PreviewHelpers = M.PreviewHelpers or {}
    local RegisterPreviewControl = deps.RegisterPreviewControl or function(widget, semanticPath, label, kind, classification, extra)
        local page = M.GroupPage
        if page and type(page.RegisterControl) == "function" then
            page.RegisterControl(widget, { key = M.activeKey }, "preview." .. tostring(semanticPath), label, kind, classification, extra)
        end
        return widget
    end
    local OpenSection = deps.OpenSection or (M.GroupPreview and M.GroupPreview.OpenSection)
    local WHITE8X8 = deps.WHITE8X8 or "Interface\\Buttons\\WHITE8X8"
    local Tr, Round, ResolveAnchor, PointOffset, HandleOffset, OffsetToConfig, CurrentStatusSpec, CurrentSpellConfig, CurrentSpellPlaced, HandleText, HandleOffsets, UpdateHint, RefreshHandleSelection, StatusLabel, StartPan, StopPan, ZoomWheel = M.PickFallbacks(deps, HANDLE_FALLBACKS, [[
        TR Round ResolveAnchor PointOffset HandleOffset OffsetToConfig CurrentStatusSpec CurrentSpellConfig CurrentSpellPlaced HandleText HandleOffsets UpdateHint RefreshHandleSelection StatusLabel StartPan StopPan ZoomWheel
    ]])
    if not deps.OffsetToConfig then OffsetToConfig = Round end
    box._handles = {}
    box._handleList = {}
    -- The old monolith closed over the native preview mock. After splitting the
    -- file, bind it explicitly so preview handles never fall back to UIParent.
    local mock = box._mock or box
    local dragParent = box._stage or box
    local function InteractionLevel(extra)
        local core = MSUF.UFPreviewCore
        if core and type(core.InteractionFrameLevel) == "function" then
            return core.InteractionFrameLevel(mock, extra)
        end
        return ((mock.GetFrameLevel and mock:GetFrameLevel()) or 0) + 140 + (tonumber(extra) or 0)
    end
    box._dragFrame = CreateFrame("Frame", nil, dragParent)
    box._dragFrame:SetAllPoints(dragParent)
    box._dragFrame:EnableMouse(true)
    box._dragFrame:EnableMouseWheel(true)
    if box._dragFrame.SetPropagateMouseWheel then box._dragFrame:SetPropagateMouseWheel(false) end
    box._dragFrame:SetScript("OnMouseWheel", ZoomWheel)
    if box._dragFrame.SetFrameLevel then
        box._dragFrame:SetFrameLevel(InteractionLevel(2))
    end
    box._dragFrame:Hide()
    local function SelectHandle(handle)
        box._selectedHandle = handle
        if box.SetFocus then box:SetFocus() end
        -- Preview-only entries have no slot in the Status Icons dropdown;
        -- writing their value into that selection would blank the dropdown and
        -- hide every real status handle.
        if handle and handle._cfgStatus and handle._statusSpec and handle._statusSpec.previewOnly ~= true then
            M.SetMenuStateValue("gfStatusIconSelection", handle._statusSpec.value)
        end
        if handle and handle._cfgSpellItem then
            local scope = H.CurrentScope()
            local specKey = handle._cfgSpellItem.specKey
            local auraName = handle._cfgSpellItem.auraName
            local conf = H.Conf(scope)
            local si = conf and conf.spellIndicators
            -- Multi-spec selection owns the aura dropdown namespace. Switch
            -- it before recording the clicked aura, otherwise a spell from
            -- spec B is written under the previously selected spec A.
            if si and si.spec == "multi" then
                M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
                M.gfSpellMultiSpecSelection[scope] = specKey
            end
            local gp = M.GroupPage or {}
            if type(gp.SetCurrentSpellAura) == "function" then
                gp.SetCurrentSpellAura(scope, auraName, specKey)
            else
                M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
                M.gfSpellIndicatorSelection[scope] = auraName
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
        RefreshHandleSelection(box)
    end
    local function SpellConfigForHandle(handle, create)
        if handle and handle._cfgSpellItem then
            local specKey = handle._cfgSpellItem.specKey
            local auraName = handle._cfgSpellItem.auraName
            if not (specKey and auraName and auraName ~= "") then return nil end
            local conf = H.Conf(H.CurrentScope())
            if not conf then return nil end
            if type(conf.spellIndicators) ~= "table" then
                if not create then return nil end
                conf.spellIndicators = { enabled = true, spec = "auto", specs = {}, layer = 9 }
            end
            local si = conf.spellIndicators
            si.specs = si.specs or {}
            si.specs[specKey] = si.specs[specKey] or {}
            if create and type(si.specs[specKey][auraName]) ~= "table" then
                -- Preview items may exist only as merged SpecDefaults. Writing
                -- through them must materialize the saved entry with its
                -- default shape, or the write is lost / the icon shape resets.
                local gf = MSUF and MSUF.GF
                local registry = (gf and gf.SpellIndicators) or _G.MSUF_GF_SpellIndicators
                if registry and type(registry.MaterializeAuraConfig) == "function" then
                    registry.MaterializeAuraConfig(si, specKey, auraName)
                else
                    si.specs[specKey][auraName] = { enabled = true, onlyOwn = true }
                end
            end
            return si.specs[specKey][auraName]
        end
        return CurrentSpellConfig(H.CurrentScope(), create)
    end
    local function SpellPlacedForHandle(handle, create)
        local cfg = SpellConfigForHandle(handle, create)
        if not cfg then
            if not create and handle and type(handle._msufSpellIndicatorPlaced) == "table" then
                return handle._msufSpellIndicatorPlaced
            end
            return nil
        end
        if create and type(cfg.placed) ~= "table" then
            cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true }
        end
        if type(cfg.placed) == "table" then return cfg.placed end
        -- Active multi-spec entries may still exist only in compiled
        -- SpecDefaults. Read the exact geometry that was rendered until the
        -- first write materializes its saved entry.
        if not create and handle and type(handle._msufSpellIndicatorPlaced) == "table" then
            return handle._msufSpellIndicatorPlaced
        end
        return nil
    end
    local function OpenHandleSettings(handle)
        if handle and handle._sectionKey and type(OpenSection) == "function" then
            OpenSection(handle._sectionKey)
            return true
        end
        return false
    end
    local function HandleHistoryLabel(handle, action)
        local text = HandleText(handle)
        return tostring(action or "Move") .. ": " .. tostring(text)
    end
    local function CheckpointHandleHistory(handle, action)
        if not (M and type(M.CheckpointHistory) == "function") then return end
        M.CheckpointHistory(
            HandleHistoryLabel(handle, action),
            "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
        )
    end
    local function ConfigCombatLocked()
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return true end
        return type(InCombatLockdown) == "function" and InCombatLockdown() == true
    end
    local function RefreshGroupIndicatorDragPreview(handle)
        if ConfigCombatLocked() then return false end
        local gf = MSUF and MSUF.GF
        local refreshKind = H.CurrentScope()
        if handle and handle._cfgSpell then
            if gf and type(gf.RefreshPreviewSpellIndicators) == "function" then
                return gf.RefreshPreviewSpellIndicators(refreshKind) == true
            end
            local refreshSpell = _G.MSUF_GF_RefreshPreviewSpellIndicators
            if type(refreshSpell) == "function" then return refreshSpell(refreshKind) == true end
            return false
        end
        if gf and type(gf.RefreshPreviewAuras) == "function" then
            return gf.RefreshPreviewAuras(refreshKind) == true
        end
        local refresh = _G.MSUF_GF_RefreshPreviewAuras
        if type(refresh) == "function" then return refresh(refreshKind) == true end
        return false
    end
    local function RefreshGroupPreviewAfterMove(handle, skipPreviewRefresh)
        if ConfigCombatLocked() then return false end
        local gf = MSUF and MSUF.GF
        local refreshKind = H.CurrentScope()
        local auraGroupMove = handle and handle._cfgGroup
        local a3 = MSUF and MSUF.MSUF_Auras3
        local apply = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
        if gf and type(gf.InvalidateCompiledSpecs) == "function" then
            gf.InvalidateCompiledSpecs(refreshKind)
        end
        if handle and handle._cfgSpell and gf and gf.SpellIndicators and type(gf.SpellIndicators.InvalidateRuntimeCaches) == "function" then
            gf.SpellIndicators.InvalidateRuntimeCaches()
        end
        if auraGroupMove and apply and type(apply.RequestAuras) == "function" then
            apply.RequestAuras(refreshKind, "MSUF2_GROUP_PREVIEW_AURA_MOVE")
            if type(apply.Flush) == "function" then apply.Flush() end
        elseif auraGroupMove and a3 and type(a3.RequestScope) == "function" then
            a3.RequestScope(refreshKind, "MSUF2_GROUP_PREVIEW_AURA_MOVE")
        elseif gf and gf.RefreshVisuals then
            local dirty = gf.DIRTY_VISUAL or 0x02
            if handle and (handle._cfgGroup or handle._cfgSpell) then dirty = gf.DIRTY_AURAS or dirty end
            gf.RefreshVisuals(refreshKind, dirty)
        elseif gf and gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_VISUAL or 0x02)
        end
        if auraGroupMove and (not (a3 and type(a3.RequestScope) == "function")) and a3 and type(a3._NotifyAuraColdpathPreview) == "function" then
            a3._NotifyAuraColdpathPreview("MSUF2_GROUP_PREVIEW_AURA_MOVE", refreshKind)
        end
        if not skipPreviewRefresh then
            if box.RequestRefresh then
                box:RequestRefresh("GROUP_PREVIEW_HANDLE_MOVE")
            elseif box.Refresh then
                box:Refresh()
            end
        end
        RefreshHandleSelection(box)
        return true
    end
    local function RefreshTextDragPreview(handle)
        UpdateHint(box, handle)
        RefreshHandleSelection(box)
    end
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
        local m = box._mock
        if kind == "name" then
            return { m._nameFS }
        elseif kind == "hp" then
            if slot == "left" then return { m._hpLeftFS } end
            if slot == "center" then return { m._hpCenterFS } end
            if slot == "right" then return { m._hpRightFS } end
            return { m._hpLeftFS, m._hpCenterFS, m._hpRightFS }
        elseif kind == "power" then
            if slot == "left" then return { m._powerLeftFS } end
            if slot == "center" then return { m._powerCenterFS } end
            if slot == "right" then return { m._powerRightFS } end
            return { m._powerLeftFS, m._powerCenterFS, m._powerRightFS }
        end
        return nil
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
            for i = 1, #captured do
                local item = captured[i]
                local frame = item and item.frame
                local points = item and item.points
                if frame and points and frame.ClearAllPoints and frame.SetPoint then
                    frame:ClearAllPoints()
                    for j = 1, #points do
                        local p = points[j]
                        frame:SetPoint(p.point, p.relTo or box._mock, p.relPoint or p.point, (p.x or 0) + dx, (p.y or 0) + dy)
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
            handle:SetPoint(handle._dragPoint, handle._dragRelTo or box._mock, handle._dragRelPoint or handle._dragPoint, (handle._dragStartX or 0) + dx, (handle._dragStartY or 0) + dy)
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
            RefreshTextDragPreview(handle)
        else
            RefreshGroupPreviewAfterMove(handle)
        end
        if checkpoint then CheckpointHandleHistory(handle, action or "Move") end
        return true
    end
    local function ResolveGroupAuraAnchor(rx, ry)
        return ResolveAnchor(rx, ry)
    end
    local function SaveHandlePosition(handle, action, previewOnly)
        if not (handle and box._mock) or handle._locked or ConfigCombatLocked() then return false end
        if handle._cfgText then return end
        if handle._cfgDispelSymbol then
            -- The symbol row keeps its configured anchor; dragging edits the same
            -- X/Y offsets shown by Preview. In "one per dispel type"
            -- mode the handle spans the whole row, so the stored offset stays the
            -- row origin and the per-type steps are re-derived on render.
            local _, _, _, offX, offY = handle:GetPoint(1)
            local scale = handle._previewWriteScale or handle._previewScale or box._mock._previewScale or 1
            local conf = H.Conf(H.CurrentScope())
            if not conf then return end
            conf.dispelSymbolX = OffsetToConfig(offX or 0, scale)
            conf.dispelSymbolY = OffsetToConfig(offY or 0, scale)
            if not previewOnly then RefreshGroupPreviewAfterMove(handle); CheckpointHandleHistory(handle, action) end
            return true
        end
        if handle._cfgPortrait then
            -- Portrait placement keeps its configured anchor/side. Dragging only
            -- edits the X/Y offsets owned by Preview.
            local _, _, _, offX, offY = handle:GetPoint(1)
            local scale = handle._previewWriteScale or handle._previewScale or box._mock._previewScale or 1
            local conf = H.Conf(H.CurrentScope())
            if not conf then return end
            conf.portraitOffsetX = OffsetToConfig(offX or 0, scale)
            conf.portraitOffsetY = OffsetToConfig(offY or 0, scale)
            if not previewOnly then RefreshGroupPreviewAfterMove(handle); CheckpointHandleHistory(handle, action) end
            return true
        end
        if handle._cfgPower then
            -- The drag preserved the runtime's TOP -> frame BOTTOM anchor, so
            -- the final point offsets are the detached offsets in preview px.
            local _, _, _, offX, offY = handle:GetPoint(1)
            local scale = handle._previewWriteScale or handle._previewScale or box._mock._previewScale or 1
            local conf = H.Conf(H.CurrentScope())
            if not conf then return end
            conf.detachedPowerBarOffsetX = OffsetToConfig(offX or 0, scale)
            conf.detachedPowerBarOffsetY = OffsetToConfig(offY or 0, scale)
            if not previewOnly then RefreshGroupPreviewAfterMove(handle); CheckpointHandleHistory(handle, action) end
            return true
        end
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
            anchor = ResolveGroupAuraAnchor((px - mL) / mW, (mT - py) / mH)
            offX, offY = PointOffset(px, py, anchorFrame, anchor)
        else
            local cx, cy = hL + hW * 0.5, hT - hH * 0.5
            anchor = ResolveAnchor((cx - mL) / mW, (mT - cy) / mH)
            offX, offY = HandleOffset(handle, m, anchor)
        end
        local scale = handle._previewWriteScale or handle._previewScale or m._previewScale or 1
        local cfgX, cfgY = OffsetToConfig(offX, scale), OffsetToConfig(offY, scale)
        local conf = H.Conf(H.CurrentScope())
        if handle._cfgGroup then
            conf.auras = conf.auras or {}
            conf.auras[handle._cfgGroup] = conf.auras[handle._cfgGroup] or {}
            if handle._cfgTrackedBuff then
                conf.auras[handle._cfgGroup].trackedAnchor = anchor
                conf.auras[handle._cfgGroup].trackedX = cfgX
                conf.auras[handle._cfgGroup].trackedY = cfgY
            else
                conf.auras[handle._cfgGroup].anchor = anchor
                conf.auras[handle._cfgGroup].x = cfgX
                conf.auras[handle._cfgGroup].y = cfgY
            end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if spec then
                conf[spec.anchor] = anchor
                conf[spec.x] = cfgX
                conf[spec.y] = cfgY
            end
        elseif handle._cfgSpell then
            -- create=true: items rendered purely from SpecDefaults have no
            -- saved entry yet; a read-only lookup silently dropped this write.
            local placed = SpellPlacedForHandle(handle, true)
            if placed then
                placed.anchor = anchor
                placed.x = cfgX
                placed.y = cfgY
            end
        end
        if previewOnly then
            -- Pointer-drag hot path: Aura/Spell handles repaint their pooled
            -- dummy indicators. Runtime group frames,
            -- history, and the full preview refresh remain release-only.
            if handle._cfgGroup or handle._cfgSpell then RefreshGroupIndicatorDragPreview(handle) end
        else
            RefreshGroupPreviewAfterMove(handle)
            CheckpointHandleHistory(handle, action)
        end
        return true
    end
    local function NudgeHandlePosition(handle, dx, dy)
        if not handle then return false end
        if handle._cfgText then
            local _, x, y = HandleOffsets(handle)
            local step = H.NudgeStep()
            return WriteTextHandleOffsets(handle, (tonumber(x) or 0) + (dx * step), (tonumber(y) or 0) + (dy * step), "Nudge", true)
        end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local x, y
        if handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, false)
            x, y = placed and placed.x, placed and placed.y
        else
            _, x, y = HandleOffsets(handle)
        end
        local step = H.NudgeStep()
        local cfgX, cfgY = Round((tonumber(x) or 0) + (dx * step)), Round((tonumber(y) or 0) + (dy * step))
        if handle._cfgGroup then
            conf.auras = conf.auras or {}
            conf.auras[handle._cfgGroup] = conf.auras[handle._cfgGroup] or {}
            if handle._cfgTrackedBuff then
                conf.auras[handle._cfgGroup].trackedX = cfgX
                conf.auras[handle._cfgGroup].trackedY = cfgY
            else
                conf.auras[handle._cfgGroup].x = cfgX
                conf.auras[handle._cfgGroup].y = cfgY
            end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if not spec then return false end
            conf[spec.x] = cfgX
            conf[spec.y] = cfgY
        elseif handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, true)
            if not placed then return false end
            placed.x = cfgX
            placed.y = cfgY
        elseif handle._cfgDispelSymbol then
            if handle._locked then return false end
            conf.dispelSymbolX = cfgX
            conf.dispelSymbolY = cfgY
        elseif handle._cfgPortrait then
            if handle._locked then return false end
            conf.portraitOffsetX = cfgX
            conf.portraitOffsetY = cfgY
        elseif handle._cfgPower then
            if handle._locked then return false end
            conf.detachedPowerBarOffsetX = cfgX
            conf.detachedPowerBarOffsetY = cfgY
        else
            return false
        end
        RefreshGroupPreviewAfterMove(handle)
        CheckpointHandleHistory(handle, "Nudge")
        return true
    end
    local function ExactPreviewDelta(value)
        value = tonumber(value)
        if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    local function ReadHandlePositionExact(handle)
        if not handle then return nil end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return nil end
        if handle._cfgText then
            local kind = handle._cfgTextKind or H.CurrentTextKind()
            local xKey, yKey = H.TextOffsetKeys(kind, handle._cfgTextSlot)
            if not (xKey and yKey) then return nil end
            return tonumber(conf[xKey]) or 0, tonumber(conf[yKey]) or 0
        elseif handle._cfgGroup then
            local cfg = conf.auras and conf.auras[handle._cfgGroup]
            if handle._cfgTrackedBuff then return tonumber(cfg and cfg.trackedX) or 0, tonumber(cfg and cfg.trackedY) or 0 end
            return tonumber(cfg and cfg.x) or 0, tonumber(cfg and cfg.y) or 0
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if not (spec and spec.x and spec.y) then return nil end
            return tonumber(conf[spec.x]) or 0, tonumber(conf[spec.y]) or 0
        elseif handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, false)
            return tonumber(placed and placed.x) or 0, tonumber(placed and placed.y) or 0
        elseif handle._cfgDispelSymbol then
            return tonumber(conf.dispelSymbolX) or 0, tonumber(conf.dispelSymbolY) or 0
        elseif handle._cfgPortrait then
            return tonumber(conf.portraitOffsetX) or 0, tonumber(conf.portraitOffsetY) or 0
        elseif handle._cfgPower then
            return tonumber(conf.detachedPowerBarOffsetX) or 0, tonumber(conf.detachedPowerBarOffsetY) or -4
        end
        return nil
    end
    local function WriteHandlePositionExact(handle, x, y, reason)
        if not handle then return false end
        x, y = Round(x), Round(y)
        if handle._cfgText then
            return WriteTextHandleOffsets(handle, x, y, reason or "Nudge", false, false)
        end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        if handle._cfgGroup then
            conf.auras = conf.auras or {}
            conf.auras[handle._cfgGroup] = conf.auras[handle._cfgGroup] or {}
            local cfg = conf.auras[handle._cfgGroup]
            if handle._cfgTrackedBuff then cfg.trackedX, cfg.trackedY = x, y else cfg.x, cfg.y = x, y end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if not (spec and spec.x and spec.y) then return false end
            conf[spec.x], conf[spec.y] = x, y
        elseif handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, true)
            if not placed then return false end
            placed.x, placed.y = x, y
        elseif handle._cfgDispelSymbol then
            conf.dispelSymbolX, conf.dispelSymbolY = x, y
        elseif handle._cfgPortrait then
            conf.portraitOffsetX, conf.portraitOffsetY = x, y
        elseif handle._cfgPower then
            conf.detachedPowerBarOffsetX, conf.detachedPowerBarOffsetY = x, y
        else
            return false
        end
        RefreshGroupPreviewAfterMove(handle)
        return true
    end
    local function RestoreGroupPreviewSelection(previous)
        if previous and previous._key and box._handles[previous._key] == previous then SelectHandle(previous) else SelectHandle(nil) end
    end

    --- Move one explicitly named handle on this exact Group preview surface.
    --- No Edit Mode mover or shared/stale preview target participates.
    function box:NudgeHandleExact(handleKey, dx, dy)
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false, "combat-locked" end
        if type(handleKey) ~= "string" or handleKey == "" then return false, "handle-required" end
        dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
        if dx == nil or dy == nil then return false, "invalid-delta" end
        if self._msufGFNativePreviewDisposed then return false, "preview-disposed" end
        if not (self.IsShown and self:IsShown() and (not self.IsVisible or self:IsVisible())) then return false, "preview-not-visible" end
        local handle = self._handles and self._handles[handleKey]
        if not handle then return false, "unknown-handle" end
        if handle._dragging == true or (self._dragFrame and self._dragFrame._handle) then return false, "handle-busy" end
        if handle._locked or (handle.IsShown and not handle:IsShown()) then return false, "handle-not-visible" end
        local beforeX, beforeY = ReadHandlePositionExact(handle)
        if tonumber(beforeX) == nil or tonumber(beforeY) == nil then return false, "handle-not-readable" end
        beforeX, beforeY = tonumber(beforeX), tonumber(beforeY)
        local expectedX, expectedY = Round(beforeX + dx), Round(beforeY + dy)
        local previous = self._selectedHandle
        SelectHandle(handle)
        if self._selectedHandle ~= handle then
            RestoreGroupPreviewSelection(previous)
            return false, "selection-failed"
        end
        if expectedX == beforeX and expectedY == beforeY then return true, beforeX, beforeY, beforeX, beforeY end

        local outcome
        local function Mutate()
            local wrote = WriteHandlePositionExact(handle, expectedX, expectedY, "Exact nudge") == true
            local afterX, afterY = ReadHandlePositionExact(handle)
            afterX, afterY = tonumber(afterX), tonumber(afterY)
            if wrote and afterX == expectedX and afterY == expectedY then
                outcome = { true, beforeX, beforeY, afterX, afterY }
                return true
            end
            local rolledBack = WriteHandlePositionExact(handle, beforeX, beforeY, "Exact nudge rollback") == true
            local restoredX, restoredY = ReadHandlePositionExact(handle)
            local reason = (not rolledBack or tonumber(restoredX) ~= beforeX or tonumber(restoredY) ~= beforeY)
                and "rollback-failed" or (wrote and "readback-mismatch" or "write-failed")
            outcome = { false, reason }
            return false
        end
        local capturing = type(M.IsHistoryCapturing) == "function" and M.IsHistoryCapturing()
        if type(M.CaptureHistory) == "function" and not capturing then
            M.CaptureHistory(HandleHistoryLabel(handle, "Nudge"),
                "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. handleKey .. ":exact-nudge", Mutate)
        else
            Mutate()
            if outcome and outcome[1] then CheckpointHandleHistory(handle, "Nudge") end
        end
        if not (outcome and outcome[1]) then RestoreGroupPreviewSelection(previous) end
        if outcome and outcome[1] then return true, outcome[2], outcome[3], outcome[4], outcome[5] end
        return false, (outcome and outcome[2]) or "write-failed"
    end
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
            if textDrag then
                if box.SetTextDragRefreshSuppressed then box:SetTextDragRefreshSuppressed(false) end
            end
            handle._dragging = nil
            handle._dragPoint = nil
            handle._dragRelTo = nil
            handle._dragRelPoint = nil
            handle._dragStartX = nil
            handle._dragStartY = nil
            handle._dragCfgStartX = nil
            handle._dragCfgStartY = nil
            handle._dragEndpointBiasX = nil
            handle._dragEndpointBiasY = nil
            handle._dragCursorX = nil
            handle._dragCursorY = nil
            handle._dragScale = nil
            handle._suppressSettingsOnRelease = nil
            handle._didDragMove = nil
        end
        local didFinalRefresh
        if wasDragging and textDrag then
            if handle._lastDragX ~= nil or handle._lastDragY ~= nil then
                RefreshGroupPreviewAfterMove(handle, true)
                if box.Refresh then box:Refresh("GROUP_PREVIEW_TEXT_DRAG_END") end
                if M.RequestRefresh then M.RequestRefresh(nil, "gf-text-drag-controls") end
                CheckpointHandleHistory(handle, "Move")
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
            if box.RequestRefresh then box:RequestRefresh("GROUP_PREVIEW_DRAG_END") elseif box.Refresh then box:Refresh() end
        end
        if textDrag then
            ReleaseTextDragRegions(handle)
            box._dragFrozenScale = nil
        end
        if openSettingsOnRelease then OpenHandleSettings(handle) end
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
        if handle._didDragMove ~= true then
            local cursorDX = cx - (handle._dragCursorX or cx)
            local cursorDY = cy - (handle._dragCursorY or cy)
            if cursorDX * cursorDX + cursorDY * cursorDY < HANDLE_CLICK_DRAG_THRESHOLD * HANDLE_CLICK_DRAG_THRESHOLD then
                return
            end
            handle._didDragMove = true
        end
        if handle._cfgText then
            local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if uiScale <= 0 then uiScale = 1 end
            local previewScale = handle._previewScale or (box._mock and box._mock._previewScale) or 1
            if previewScale <= 0 then previewScale = 1 end
            local dx = ((cx - (handle._dragCursorX or cx)) / uiScale) / previewScale
            local dy = ((cy - (handle._dragCursorY or cy)) / uiScale) / previewScale
            local nextX = Round((handle._dragCfgStartX or 0) + dx)
            local nextY = Round((handle._dragCfgStartY or 0) + dy)
            if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
            handle._lastDragX = nextX
            handle._lastDragY = nextY
            ApplyTextRegionDrag(handle, nextX, nextY)
            WriteTextHandleOffsets(handle, nextX, nextY, "Move", false, true)
            return
        end
        local scale = handle._dragScale or 1
        if scale <= 0 then scale = 1 end
        local dx = (cx - (handle._dragCursorX or cx)) / scale
        local dy = (cy - (handle._dragCursorY or cy)) / scale
        local nextX = Round((handle._dragStartX or 0) + dx)
        local nextY = Round((handle._dragStartY or 0) + dy)
        if handle._lastDragX == nextX and handle._lastDragY == nextY then return end
        handle._lastDragX = nextX
        handle._lastDragY = nextY
        handle:ClearAllPoints()
        handle:SetPoint(handle._dragPoint or "CENTER", handle._dragRelTo or box._mock, handle._dragRelPoint or "CENTER", nextX, nextY)
        UpdateHint(box, handle)
        SaveHandlePosition(handle, "Move", true)
    end
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
            local _, cfgX, cfgY = HandleOffsets(handle)
            handle._dragCfgStartX = tonumber(cfgX) or 0
            handle._dragCfgStartY = tonumber(cfgY) or 0
            if handle._cfgTextKind == "name" then
                local fs = box._mock and box._mock._nameFS
                handle._dragEndpointBiasX = (tonumber(fs and fs._msufPreviewNameEndpointX)
                    or handle._dragCfgStartX) - handle._dragCfgStartX
                handle._dragEndpointBiasY = (tonumber(fs and fs._msufPreviewNameEndpointY)
                    or handle._dragCfgStartY) - handle._dragCfgStartY
            end
            CaptureTextDragRegions(handle)
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
    local function CreatePreviewHandle(key, sectionKey, color, label, width, height, locked, parent)
        local handle = CreateFrame("Button", nil, parent or mock, T.Template())
        handle:SetSize(width or 32, height or 32)
        -- The colored label is part of the visible affordance. Without this,
        -- clicking its glyphs falls through to a different overlapping handle
        -- or the preview canvas and appears to route randomly.
        if handle.SetHitRectInsets then handle:SetHitRectInsets(0, 0, -HANDLE_LABEL_HIT_HEIGHT, 0) end
        handle:SetMovable(true)
        handle:EnableMouse(true)
        handle:EnableMouseWheel(true)
        if handle.SetPropagateMouseWheel then handle:SetPropagateMouseWheel(false) end
        if handle.RegisterForClicks then handle:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp") end
        if handle.RegisterForDrag then handle:RegisterForDrag("LeftButton") end
        handle:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
        handle:SetBackdropColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.42)
        handle:SetBackdropBorderColor(color[1], color[2], color[3], locked and 0.55 or 0.95)
        handle._key = key
        handle._sectionKey = sectionKey
        handle._previewLayerKey = GROUP_HANDLE_LAYER_BY_KEY[key] or GROUP_SECTION_LAYER[sectionKey]
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
            RefreshHandleSelection(box)
            local showTooltip = GameTooltip and (not PreviewHelpers.ShouldShowPreviewHandleTooltip
                or PreviewHelpers.ShouldShowPreviewHandleTooltip(box))
            if showTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(HandleText(self), 1, 1, 1)
                if self._locked then
                    GameTooltip:AddLine((M.Tr and M.Tr("This preview layer is locked.")) or "This preview layer is locked.", 0.82, 0.82, 0.82, true)
                    GameTooltip:AddLine(Tr("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
                else
                    GameTooltip:AddLine(Tr("Drag to move. Arrow keys nudge."), 0.82, 0.82, 0.82, true)
                    GameTooltip:AddLine(Tr("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
                end
                GameTooltip:Show()
            end
        end)
        handle:SetScript("OnLeave", function(self)
            self._hovering = nil
            RefreshHandleSelection(box)
            if GameTooltip then GameTooltip:Hide() end
        end)
        handle:SetScript("OnClick", function(self, button)
            if self._suppressNextClick then
                self._suppressNextClick = nil
                return
            end
            if button == "RightButton" then
                SelectHandle(self)
                if self._openSettingsOnRightClick == true then
                    OpenHandleSettings(self)
                    return
                end
                if PreviewHelpers.ShowPreviewHandleContext then
                    PreviewHelpers.ShowPreviewHandleContext(self, {
                        M = M,
                        T = T,
                        Tr = Tr,
                        title = HandleText(self),
                        openSettings = OpenHandleSettings,
                    })
                end
                return
            end
            SelectHandle(self)
        end)
        handle:SetScript("OnMouseWheel", ZoomWheel)
        handle:SetScript("OnMouseDown", StartHandleDrag)
        handle:SetScript("OnMouseUp", function(self, button) StopHandleDrag(self, button, true) end)
        handle:SetScript("OnDragStart", StartHandleDrag)
        handle:SetScript("OnDragStop", function(self, button) StopHandleDrag(self, button, false) end)
        handle:HookScript("OnHide", function(self)
            StopHandleDrag(self, nil, false)
            if box._selectedHandle == self then SelectHandle(nil) end
        end)
        handle._msuf2CommandAction = {
            kind = "button",
            historyMode = "none",
            interaction = "preview.handle.select",
            previewSurface = "group",
            previewHandleKey = key,
            previewScope = H.CurrentScope(),
            set = function()
                if handle.IsShown and not handle:IsShown() then return false end
                SelectHandle(handle)
                return box._selectedHandle == handle
            end,
        }
        RegisterPreviewControl(handle, "handle." .. tostring(key), label or key, "button", "ephemeral")
        if PreviewHelpers.EnsurePreviewHandleGear then
            local gear = PreviewHelpers.EnsurePreviewHandleGear(handle, {
                T = T,
                Tr = Tr,
                shown = false,
                openSettings = OpenHandleSettings,
            })
            if gear then
                gear._msuf2GroupPreviewOpenCommand = gear._msuf2GroupPreviewOpenCommand or {
                    kind = "button",
                    historyMode = "none",
                    set = function() return OpenHandleSettings(handle) end,
                }
                RegisterPreviewControl(gear, "handle." .. tostring(key) .. ".open_settings",
                    "Open " .. tostring(label or key) .. " settings", "button", "action", {
                        historyMode = "none",
                        help = "Opens the exact Group Frames settings section for this preview element.",
                        command = gear._msuf2GroupPreviewOpenCommand,
                    })
            end
        end
        box._handles[key] = handle
        box._handleList[#box._handleList + 1] = handle
        return handle
    end
    local function AddIconPool(handle, count)
        handle._icons = handle._icons or {}
        handle._iconSwipes = handle._iconSwipes or {}
        handle._iconBorders = handle._iconBorders or {}
        handle._iconStacks = handle._iconStacks or {}
        handle._iconTimers = handle._iconTimers or {}
        handle._iconDurationBars = handle._iconDurationBars or {}
        -- Runtime AuraButtons keep the duration bar, cooldown swipe and text on
        -- separate child frames inside the selected universal Layer slot.  The
        -- preview used to create every region directly on the handle, which
        -- made all of them inherit the icon's base level and let overlapping
        -- text lie about the real runtime ordering.
        local function EnsureDetailLayer(key)
            local layer = handle[key]
            if not layer then
                layer = CreateFrame("Frame", nil, handle)
                layer:SetAllPoints(handle)
                layer:EnableMouse(false)
                if layer.SetMouseMotionEnabled then layer:SetMouseMotionEnabled(false) end
                handle[key] = layer
            end
            return layer
        end
        local durationLayer = EnsureDetailLayer("_iconDurationLayer")
        local swipeLayer = EnsureDetailLayer("_iconSwipeLayer")
        local textLayer = EnsureDetailLayer("_iconTextLayer")
        for i = 1, count do
            local tex = handle._icons[i] or handle:CreateTexture(nil, "ARTWORK")
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            handle._icons[i] = tex
            local swipe = handle._iconSwipes[i] or swipeLayer:CreateTexture(nil, "ARTWORK")
            swipe:SetTexture(WHITE8X8)
            swipe:SetVertexColor(0, 0, 0, 0.58)
            swipe:Hide()
            handle._iconSwipes[i] = swipe
            local border = handle._iconBorders[i] or handle:CreateTexture(nil, "OVERLAY")
            border:Hide()
            handle._iconBorders[i] = border
            local stack = handle._iconStacks[i] or textLayer:CreateFontString(nil, "OVERLAY")
            if stack.SetFont and stack._msufGFPreviewFont ~= true then
                stack:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE")
                stack._msufGFPreviewFont = true
            end
            if stack.SetDrawLayer then stack:SetDrawLayer("OVERLAY", 6) end
            stack:Hide()
            handle._iconStacks[i] = stack
            local timer = handle._iconTimers[i] or textLayer:CreateFontString(nil, "OVERLAY")
            if timer.SetFont and timer._msufGFPreviewFont ~= true then
                timer:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", T.FontSize("micro"), "OUTLINE")
                timer._msufGFPreviewFont = true
            end
            if timer.SetDrawLayer then timer:SetDrawLayer("OVERLAY", 7) end
            timer:Hide()
            handle._iconTimers[i] = timer
            local durationBar = handle._iconDurationBars[i] or durationLayer:CreateTexture(nil, "OVERLAY")
            durationBar:SetTexture(WHITE8X8)
            local durationR, durationG, durationB = AuraDurationBarColor()
            durationBar:SetVertexColor(durationR, durationG, durationB, 0.92)
            durationBar:Hide()
            handle._iconDurationBars[i] = durationBar
        end
    end
    local buffHandle = CreatePreviewHandle("buff", "buffs", { 0.36, 0.79, 0.36 }, "BUFFS", 86, 34, false)
    buffHandle._cfgGroup = "buff"
    AddIconPool(buffHandle, 6)
    local trackedBuffHandle = CreatePreviewHandle("trackedBuff", "buffs", { 0.62, 0.78, 1.00 }, "TRACKED", 86, 34, false)
    trackedBuffHandle._cfgGroup = "buff"
    trackedBuffHandle._cfgTrackedBuff = true
    trackedBuffHandle._previewText = "Tracked Buff Icons"
    AddIconPool(trackedBuffHandle, 4)
    local debuffHandle = CreatePreviewHandle("debuff", "debuffs", { 0.89, 0.29, 0.29 }, "DEBUFFS", 86, 34, false)
    debuffHandle._cfgGroup = "debuff"
    AddIconPool(debuffHandle, 6)
    local externalHandle = CreatePreviewHandle("external", "externals", { 0.30, 0.72, 1.00 }, "EXTERNAL", 86, 34, false)
    externalHandle._cfgGroup = "externals"
    externalHandle._openSettingsOnRightClick = true
    -- Keep the long-standing explicit contract for the blue External label;
    -- CreatePreviewHandle now applies the same hit area to every label.
    if externalHandle.SetHitRectInsets then externalHandle:SetHitRectInsets(0, 0, -14, 0) end
    AddIconPool(externalHandle, 2)
    -- Resource bar handle. Live parity: only the detached bar owns free
    -- offsets (the embedded bar's texture cannot move on the live frame), so
    -- the render locks this handle while the bar is embedded; a simple click
    -- still opens its owning settings section like any other layer.
    local powerBarHandle = CreatePreviewHandle("powerBar", "power", { 0.30, 0.62, 0.98 }, "POWER", 86, 16, false)
    powerBarHandle._cfgPower = true
    powerBarHandle._previewText = "Resource Bar"
    -- Attached portraits can sit completely outside the mock frame. Keep their
    -- mouse handle on the preview stage so WoW does not clip hit-testing to
    -- the mock parent's bounds; rendering/offsets remain anchored to the mock.
    local portraitHandle = CreatePreviewHandle("portrait", "portrait", { 0.90, 0.42, 1.00 }, "PORTRAIT", 36, 36, false, dragParent)
    portraitHandle._cfgPortrait = true
    portraitHandle._previewText = "Portrait"
    -- Dispel-type symbol row. Like the portrait it can sit outside the mock
    -- frame, so its mouse handle lives on the preview stage; rendering and
    -- offsets stay anchored to the mock. Five icon slots: one per dispel type in
    -- "one per dispel type" mode, of which only the first is used in TOP mode.
    local dispelSymbolHandle = CreatePreviewHandle("dispelSymbol", "dispelSymbol", { 0.30, 0.80, 1.00 }, "DISPEL", 44, 20, false, dragParent)
    dispelSymbolHandle._cfgDispelSymbol = true
    dispelSymbolHandle._previewText = "Dispel Symbol"
    AddIconPool(dispelSymbolHandle, 5)
    local statusHandles = {}
    local statusSpecs = H.StatusSpecs()
    for i = 1, #statusSpecs do
        local spec = statusSpecs[i]
        local statusHandle = CreatePreviewHandle("status_" .. tostring(spec.value or i), "sicons", { 0.80, 0.67, 0.20 }, StatusLabel(spec), 78, 28, false)
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
    spellHandle._sectionKey = "si"
    AddIconPool(spellHandle, 1)
    local spellIndicatorHandles = {}
    local function SpellIndicatorHandleKey(item, index)
        local key = tostring(item and (item.key or item.slotKey) or index or "spell")
        key = key:gsub("[^%w_]+", "_")
        if key == "" then key = tostring(index or "spell") end
        return "si_" .. key
    end
    function box:EnsureSpellIndicatorHandle(item, index)
        if type(item) ~= "table" then return nil end
        local key = SpellIndicatorHandleKey(item, index)
        local handle = spellIndicatorHandles[key]
        if not handle then
            local c = item.color or { 0.69, 0.50, 0.88 }
            handle = CreatePreviewHandle(key, "si", { c[1] or 0.69, c[2] or 0.50, c[3] or 0.88 }, tostring(item.display or item.auraName or "SPELL"):upper(), 44, 44, false)
            handle._cfgSpell = true
            handle._sectionKey = "si"
            AddIconPool(handle, 1)
            spellIndicatorHandles[key] = handle
        end
        handle._cfgSpellItem = {
            specKey = item.specKey,
            auraName = item.auraName,
        }
        handle._msufSpellIndicatorPlaced = item.spellIndicatorSlot == true and item or item.placed
        handle._previewText = item.display or item.auraName or "Spell"
        handle._msufSpellIndicatorPreviewKey = key
        return handle
    end
    function box:HideUnusedSpellIndicatorHandles(active)
        active = active or {}
        for key, handle in pairs(spellIndicatorHandles) do
            if not active[key] then handle:Hide() end
        end
    end
    local function CursorPositionInUI()
        local x, y = GetCursorPosition()
        if not (x and y) then return nil end
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        return x / scale, y / scale
    end
    local function CursorInsideFrame(frame)
        if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return false end
        local x, y = CursorPositionInUI()
        if not (x and y) then return false end
        local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        return left and right and top and bottom and x >= left and x <= right and y >= bottom and y <= top or false
    end
    local function EnsureSpellDropGuide()
        if box._spellDropGuide then return box._spellDropGuide end
        local guide = CreateFrame("Frame", nil, mock, T.Template())
        guide:SetAllPoints(mock)
        guide:EnableMouse(false)
        if guide.SetFrameLevel then guide:SetFrameLevel(InteractionLevel(1)) end
        guide:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 2 })
        guide._text = T.Font(guide, "GameFontNormal", Tr("Drop to place spell icon"), { 0.72, 0.90, 1, 1 })
        guide._text:SetPoint("BOTTOM", guide, "TOP", 0, 6)
        guide:Hide()
        box._spellDropGuide = guide
        return guide
    end
    function box:SetSpellDropTarget(active, spellLabel)
        local guide = EnsureSpellDropGuide()
        if not active then
            guide:Hide()
            guide._dropInside = nil
            guide._dropLabel = nil
            if self._hint then UpdateHint(self, self._selectedHandle) end
            return false
        end
        local inside = CursorInsideFrame(mock)
        if guide._dropInside ~= inside then
            guide._dropInside = inside
            if inside then
                guide:SetBackdropColor(0.12, 0.72, 0.38, 0.10)
                guide:SetBackdropBorderColor(0.22, 1.00, 0.55, 1)
                guide._text:SetText(Tr("Release to place and position"))
                guide._text:SetTextColor(0.42, 1.00, 0.65, 1)
            else
                guide:SetBackdropColor(0.12, 0.50, 0.82, 0.07)
                guide:SetBackdropBorderColor(0.32, 0.76, 1.00, 0.95)
                guide._text:SetText(Tr("Drag onto the frame to place"))
                guide._text:SetTextColor(0.72, 0.90, 1.00, 1)
            end
        end
        guide:Show()
        if self._hint and (guide._dropLabel ~= spellLabel or guide._hintInside ~= inside) then
            guide._dropLabel = spellLabel
            guide._hintInside = inside
            self._hint:SetText(string.format("%s   %s", tostring(spellLabel or Tr("Spell icon")),
                Tr(inside and "release to place at this position" or "drag onto the unit frame")))
        end
        return inside
    end
    function box:DropSpellIndicatorAtCursor(specKey, auraName)
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return false, "combat-locked" end
        if not (specKey and auraName and auraName ~= "") then return false, "spell-required" end
        if not CursorInsideFrame(mock) then return false, "outside-frame" end
        local cursorX, cursorY = CursorPositionInUI()
        local left, bottom = mock:GetLeft(), mock:GetBottom()
        local width, height = mock:GetWidth(), mock:GetHeight()
        if not (cursorX and cursorY and left and bottom and width and height and width > 0 and height > 0) then
            return false, "preview-geometry-unavailable"
        end
        local kind = H.CurrentScope()
        local dropHandle = {
            _key = "si_drop_" .. tostring(specKey) .. ":" .. tostring(auraName),
            _cfgSpell = true,
            _cfgSpellItem = { specKey = specKey, auraName = auraName },
            _previewText = auraName,
        }
        local existingCfg = SpellConfigForHandle(dropHandle, false)
        local placedForSize = existingCfg and type(existingCfg.placed) == "table" and existingCfg.placed or {}
        local previewScale = tonumber(box._mockScale) or tonumber(box._mockAutoScale) or 1
        if previewScale <= 0 then previewScale = 1 end
        local iconWidth = tonumber(placedForSize.size) or 18
        if (placedForSize.type or "icon") == "bar" then iconWidth = tonumber(placedForSize.barWidth) or (iconWidth * 3) end
        local iconHeight = tonumber(placedForSize.size) or 18
        iconWidth, iconHeight = iconWidth * previewScale, iconHeight * previewScale
        local rx = (cursorX - left) / width
        local ry = 1 - ((cursorY - bottom) / height)
        local anchor = ResolveAnchor(rx, ry)
        local frac = SPELL_DROP_ANCHOR_FRAC[anchor] or SPELL_DROP_ANCHOR_FRAC.CENTER
        local anchorX = cursorX + ((frac[1] - 0.5) * iconWidth)
        local anchorY = cursorY + ((frac[2] - 0.5) * iconHeight)
        local offX, offY = PointOffset(anchorX, anchorY, mock, anchor)
        local nextX, nextY = OffsetToConfig(offX, previewScale), OffsetToConfig(offY, previewScale)
        local placedSuccessfully = false
        local function PlaceSpellIcon()
            local cfg = SpellConfigForHandle(dropHandle, true)
            local placed = SpellPlacedForHandle(dropHandle, true)
            if not (placed and cfg) then return false end
            local conf = H.Conf(kind)
            local si = conf and conf.spellIndicators
            if si then si.enabled = true end
            cfg.enabled = true
            placed.type = (placed.type and placed.type ~= "none") and placed.type or "icon"
            placed.anchor, placed.x, placed.y = anchor, nextX, nextY
            if si and si.spec == "multi" then
                M.gfSpellMultiSpecSelection = M.gfSpellMultiSpecSelection or {}
                M.gfSpellMultiSpecSelection[kind] = specKey
            end
            local gp = M.GroupPage or {}
            if type(gp.SetCurrentSpellAura) == "function" then
                gp.SetCurrentSpellAura(kind, auraName, specKey)
            else
                M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
                M.gfSpellIndicatorSelection[kind] = auraName
            end
            RefreshGroupPreviewAfterMove(dropHandle)
            placedSuccessfully = true
            return true
        end
        local historyKey = "group:spellDrop:" .. tostring(kind) .. ":" .. tostring(specKey) .. ":" .. tostring(auraName)
        if type(M.RunWithHistory) == "function" then
            M.RunWithHistory("Place Spell Indicator", historyKey, PlaceSpellIcon)
        else
            PlaceSpellIcon()
            if placedSuccessfully then CheckpointHandleHistory(dropHandle, "Place") end
        end
        if not placedSuccessfully then return false, "spell-config-unavailable" end
        if M.RequestRefresh then M.RequestRefresh(nil, "gf-spell-drop-controls") end
        return true, anchor, nextX, nextY
    end
    box._spellIndicatorHandles = spellIndicatorHandles
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
        trackedBuffHandle = trackedBuffHandle,
        debuffHandle = debuffHandle,
        externalHandle = externalHandle,
        powerBarHandle = powerBarHandle,
        portraitHandle = portraitHandle,
        dispelSymbolHandle = dispelSymbolHandle,
        statusHandles = statusHandles,
        spellHandle = spellHandle,
        SelectHandle = SelectHandle,
        NudgeHandlePosition = NudgeHandlePosition,
        AddIconPool = AddIconPool,
        StopHandleDrag = StopHandleDrag,
    }
end

local function VisibleGroupPreview()
    local found
    local previews = M._gfNativePreviews
    for i = 1, #(previews or {}) do
        local box = previews[i]
        local visible = box
            and not box._msufGFNativePreviewDisposed
            and box.IsShown and box:IsShown()
            and (not box.IsVisible or box:IsVisible())
        if visible then
            if found and found ~= box then return nil, "ambiguous-preview" end
            found = box
        end
    end
    if not found then return nil, "preview-not-visible" end
    return found
end
M.GroupPreview = M.GroupPreview or {}
function M.GroupPreview.UpdateSpellDropTarget(active, spellLabel)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.SetSpellDropTarget) ~= "function" then return false, "spell-drop-api-unavailable" end
    return box:SetSpellDropTarget(active == true, spellLabel)
end
function M.GroupPreview.DropSpellIndicatorAtCursor(specKey, auraName)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.DropSpellIndicatorAtCursor) ~= "function" then return false, "spell-drop-api-unavailable" end
    return box:DropSpellIndicatorAtCursor(specKey, auraName)
end
function M.GroupPreview.NudgeHandle(handleKey, dx, dy)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.NudgeHandleExact) ~= "function" then return false, "nudge-api-unavailable" end
    return box:NudgeHandleExact(handleKey, dx, dy)
end
function M.GroupPreview.Pan(dx, dy)
    local box, reason = VisibleGroupPreview()
    if not box then return false, reason end
    if type(box.PanExact) ~= "function" then return false, "pan-api-unavailable" end
    return box:PanExact(dx, dy)
end
ExportPublic("MSUF_GroupPreview_NudgeHandle", function(handleKey, dx, dy)
    return M.GroupPreview.NudgeHandle(handleKey, dx, dy)
end)
ExportPublic("MSUF_GroupPreview_Pan", function(dx, dy)
    return M.GroupPreview.Pan(dx, dy)
end)
