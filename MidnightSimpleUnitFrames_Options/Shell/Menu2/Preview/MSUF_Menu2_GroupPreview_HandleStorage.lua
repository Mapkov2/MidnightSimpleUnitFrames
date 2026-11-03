-- Group preview HandleStorage owner.
local _, MSUF = ...
local M = MSUF.MSUF2
local FILE = "Menu2/GroupPreview_Handles"
local Stage = {}
local max = math.max
local FIXED_OFFSET_KINDS = {
    -- The symbol row keeps its configured anchor; dragging edits the same X/Y offsets shown by Preview. In "one per dispel type"
    -- mode the handle spans the whole row, so the stored offset stays the row origin and the per-type steps are re-derived on render.
    { "_cfgDispelSymbol", "dispelSymbolX", "dispelSymbolY", 0 },
    -- Portrait placement keeps its configured anchor/side. Dragging only edits the X/Y offsets owned by Preview.
    { "_cfgPortrait", "portraitOffsetX", "portraitOffsetY", 0 },
    -- The drag preserved the runtime's TOP -> frame BOTTOM anchor, so the final point offsets are the detached offsets in preview px.
    { "_cfgPower", "detachedPowerBarOffsetX", "detachedPowerBarOffsetY", -4 },
}
-- Per-drag state written by StartHandleDrag and cleared when the drag ends.
local function ManagerCombatLocked(M)
    return type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked()
end
local function RequestBoxRefresh(box, reason)
    if box.RequestRefresh then
        box:RequestRefresh(reason)
    elseif box.Refresh then
        box:Refresh()
    end
end
-- Points the Spell Indicators page at an aura. Multi-spec selection owns the aura dropdown namespace: switch it
-- before recording the aura, otherwise a spell from spec B is written under the previously selected spec A.
local function SelectSpellAura(M, scope, si, specKey, auraName)
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
-- The config keys (X, Y, and the Y value while unset) of a handle kind that stores its offsets directly.
local function FixedOffsetKeys(handle)
    for i = 1, #FIXED_OFFSET_KINDS do
        local kind = FIXED_OFFSET_KINDS[i]
        if handle[kind[1]] then return kind[2], kind[3], kind[4] end
    end
end
local function AuraLaneConf(conf, group)
    conf.auras = conf.auras or {}
    conf.auras.renderer = "CUSTOM"
    conf.auras[group] = conf.auras[group] or {}
    return conf.auras[group]
end

-- A preview gear is a search action on the Group Frames pages only; inside
-- another page (each Colors category) it stays navigation, as on units.
function Stage.BindSelection(st)
    local H, M, ns, box, OpenSection = st.H, st.M, st.MSUF, st.box, st.OpenSection
    -- Resolved once here, never per drag frame: only used when the GF table has no SpellIndicators registry.
    local spellRegistryFallback = MSUF.Require("MSUF_GF_SpellIndicators", FILE)
    local function SelectHandle(handle)
        box._selectedHandle = handle
        if box.SetFocus then box:SetFocus() end
        if handle then
            -- Preview-only entries have no slot in the Status Icons dropdown;
            -- writing their value into that selection would blank the dropdown and
            -- hide every real status handle.
            local statusSpec = handle._cfgStatus and handle._statusSpec
            if statusSpec and statusSpec.previewOnly ~= true then
                M.SetMenuStateValue("gfStatusIconSelection", statusSpec.value)
            end
            if handle._cfgSpellItem then
                local scope, item = H.CurrentScope(), handle._cfgSpellItem
                local conf = H.Conf(scope)
                SelectSpellAura(M, scope, conf and conf.spellIndicators, item.specKey, item.auraName)
            end
            local textKind = handle._cfgTextKind
            if textKind then
                local scope = H.CurrentScope()
                M.gfTextTabSelection = M.gfTextTabSelection or {}
                M.gfTextTabSelection[scope] = textKind
                if handle._cfgTextSlot then
                    H.SetTextMoveTogether(scope, textKind, false)
                    M.gfTextSlotSelection = M.gfTextSlotSelection or {}
                    M.gfTextSlotSelection[scope] = M.gfTextSlotSelection[scope] or {}
                    M.gfTextSlotSelection[scope][textKind] = handle._cfgTextSlot
                elseif textKind == "hp" or textKind == "power" then
                    H.SetTextMoveTogether(scope, textKind, true)
                end
            end
        end
        st.RefreshHandleSelection(box)
    end
    local function SpellConfigForHandle(handle, create)
        local item = handle and handle._cfgSpellItem
        if not item then return st.CurrentSpellConfig(H.CurrentScope(), create) end
        local specKey, auraName = item.specKey, item.auraName
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
        local entries = si.specs[specKey]
        if create and type(entries[auraName]) ~= "table" then
            -- Preview items may exist only as merged SpecDefaults. Writing
            -- through them must materialize the saved entry with its
            -- default shape, or the write is lost / the icon shape resets.
            local gf = ns.GF
            local registry = (gf and gf.SpellIndicators) or spellRegistryFallback
            if registry and type(registry.MaterializeAuraConfig) == "function" then
                registry.MaterializeAuraConfig(si, specKey, auraName)
            else
                entries[auraName] = { enabled = true, onlyOwn = true }
            end
        end
        return si.specs[specKey][auraName]
    end
    local function SpellPlacedForHandle(handle, create)
        local cfg = SpellConfigForHandle(handle, create)
        if cfg and create and type(cfg.placed) ~= "table" then
            cfg.placed = { type = "icon", anchor = "TOPLEFT", x = 0, y = 0, size = 18, showCooldownSwipe = true }
        end
        if cfg and type(cfg.placed) == "table" then return cfg.placed end
        -- Active multi-spec entries may still exist only in compiled
        -- SpecDefaults. Read the exact geometry that was rendered until the
        -- first write materializes its saved entry.
        local rendered = handle and handle._msufSpellIndicatorPlaced
        if not create and type(rendered) == "table" then return rendered end
        return nil
    end
    local function OpenHandleSettings(handle)
        if handle and handle._sectionKey and type(OpenSection) == "function" then
            OpenSection(handle._sectionKey)
            return true
        end
        return false
    end
    st.SelectHandle, st.OpenHandleSettings = SelectHandle, OpenHandleSettings
    st.SpellConfigForHandle, st.SpellPlacedForHandle = SpellConfigForHandle, SpellPlacedForHandle
end

--- History checkpoints, the combat gate and the post-move refresh of the
--- live group frames.
function Stage.BindRefresh(st)
    local H, M, ns, box, HandleText, RefreshHandleSelection = st.H, st.M, st.MSUF, st.box, st.HandleText, st.RefreshHandleSelection
    -- Collaborators the refresh paths use when the GF table lacks the method, and the apply service. They are
    -- resolved once here: the drag-frame and key-repeat nudge paths must never call MSUF.Require.
    local refreshAurasFallback = MSUF.Require("MSUF_GF_RefreshPreviewAuras", FILE)
    local refreshSpellsFallback = MSUF.Require("MSUF_GF_RefreshPreviewSpellIndicators", FILE)
    local ApplyService = MSUF.Require("MSUF_Menu2_ApplyService", FILE)
    local function HandleHistoryLabel(handle, action)
        return tostring(action or "Move") .. ": " .. tostring(HandleText(handle))
    end
    local function CheckpointHandleHistory(handle, action)
        if type(M.CheckpointHistory) ~= "function" then return end
        M.CheckpointHistory(
            HandleHistoryLabel(handle, action),
            "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
        )
    end
    -- Runs every drag frame and every key-repeat nudge: keep the combat check inline.
    local function ConfigCombatLocked()
        if type(M.IsConfigCombatLocked) == "function" and M.IsConfigCombatLocked() then return true end
        return type(InCombatLockdown) == "function" and InCombatLockdown() == true
    end
    -- Runs on every drag frame of an aura or spell handle.
    local function RefreshGroupIndicatorDragPreview(handle)
        if ConfigCombatLocked() then return false end
        local gf = ns.GF
        local refreshKind = H.CurrentScope()
        if handle and handle._cfgSpell then
            if gf and type(gf.RefreshPreviewSpellIndicators) == "function" then
                return gf.RefreshPreviewSpellIndicators(refreshKind) == true
            end
            return refreshSpellsFallback(refreshKind) == true
        end
        if gf and type(gf.RefreshPreviewAuras) == "function" then
            return gf.RefreshPreviewAuras(refreshKind) == true
        end
        return refreshAurasFallback(refreshKind) == true
    end
    -- Runs on every key-repeat nudge as well as on release.
    local function RefreshGroupPreviewAfterMove(handle, skipPreviewRefresh)
        if ConfigCombatLocked() then return false end
        local gf, a3 = ns.GF, ns.MSUF_Auras3
        local refreshKind = H.CurrentScope()
        local auraGroupMove = handle and handle._cfgGroup
        if gf and type(gf.InvalidateCompiledSpecs) == "function" then
            gf.InvalidateCompiledSpecs(refreshKind)
        end
        if handle and handle._cfgSpell and gf and gf.SpellIndicators and type(gf.SpellIndicators.InvalidateRuntimeCaches) == "function" then
            gf.SpellIndicators.InvalidateRuntimeCaches()
        end
        if auraGroupMove then
            ApplyService.RequestAuras(refreshKind, "MSUF2_GROUP_PREVIEW_AURA_MOVE")
            ApplyService.Flush()
        elseif gf and gf.RefreshVisuals then
            local dirty = gf.DIRTY_VISUAL or 0x02
            if handle and (handle._cfgGroup or handle._cfgSpell) then dirty = gf.DIRTY_AURAS or dirty end
            gf.RefreshVisuals(refreshKind, dirty)
        elseif gf and gf.MarkAllDirty then
            gf.MarkAllDirty(gf.DIRTY_VISUAL or 0x02)
        end
        if auraGroupMove and not (a3 and type(a3.RequestScope) == "function")
            and a3 and type(a3.NotifyPreview) == "function" then
            a3.NotifyPreview("MSUF2_GROUP_PREVIEW_AURA_MOVE", refreshKind)
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
    st.CheckpointHandleHistory, st.ConfigCombatLocked, st.HandleHistoryLabel = CheckpointHandleHistory, ConfigCombatLocked, HandleHistoryLabel
    st.RefreshGroupIndicatorDragPreview, st.RefreshGroupPreviewAfterMove = RefreshGroupIndicatorDragPreview, RefreshGroupPreviewAfterMove
end

--- Text handle drag: captured region geometry, live drag painting and the
--- offset writer behind name/HP/power text moves.
function Stage.BindPositionWriters(st)
    local H, OffsetToConfig, box, ResolveAnchor = st.H, st.OffsetToConfig, st.box, st.ResolveAnchor
    local ConfigCombatLocked, CheckpointHandleHistory = st.ConfigCombatLocked, st.CheckpointHandleHistory
    local RefreshGroupPreviewAfterMove, SpellPlacedForHandle = st.RefreshGroupPreviewAfterMove, st.SpellPlacedForHandle
    local CurrentStatusSpec, HandleOffset, PointOffset = st.CurrentStatusSpec, st.HandleOffset, st.PointOffset
    local RefreshGroupIndicatorDragPreview = st.RefreshGroupIndicatorDragPreview
    -- Runs on every drag frame (previewOnly) and on release; no helper calls beyond the original path.
    -- hot path: kept whole (perf rule)
    local function SaveHandlePosition(handle, action, previewOnly)
        if not (handle and box._mock) or handle._locked or ConfigCombatLocked() then return false end
        if handle._cfgText then return end
        local m = box._mock
        for i = 1, #FIXED_OFFSET_KINDS do
            local kind = FIXED_OFFSET_KINDS[i]
            if handle[kind[1]] then
                local _, _, _, offX, offY = handle:GetPoint(1)
                local scale = handle._previewWriteScale or handle._previewScale or m._previewScale or 1
                local conf = H.Conf(H.CurrentScope())
                if not conf then return end
                conf[kind[2]] = OffsetToConfig((offX or 0) - (handle._msufEngineOffsetX or 0), scale)
                conf[kind[3]] = OffsetToConfig((offY or 0) - (handle._msufEngineOffsetY or 0), scale)
                if not previewOnly then
                    RefreshGroupPreviewAfterMove(handle)
                    CheckpointHandleHistory(handle, action)
                end
                return true
            end
        end
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
            anchor = ResolveAnchor((px - mL) / mW, (mT - py) / mH)
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
            local lane = AuraLaneConf(conf, handle._cfgGroup)
            if handle._cfgTrackedBuff then
                lane.trackedAnchor, lane.trackedX, lane.trackedY = anchor, cfgX, cfgY
            else
                lane.anchor, lane.x, lane.y = anchor, cfgX, cfgY
            end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if spec then conf[spec.anchor], conf[spec.x], conf[spec.y] = anchor, cfgX, cfgY end
        elseif handle._cfgSpell then
            -- create=true: items rendered purely from SpecDefaults have no
            -- saved entry yet; a read-only lookup silently dropped this write.
            local placed = SpellPlacedForHandle(handle, true)
            if placed then placed.anchor, placed.x, placed.y = anchor, cfgX, cfgY end
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
    st.SaveHandlePosition = SaveHandlePosition
end

--- Arrow-key nudge. It runs on every key-repeat press, so the ladder stays inline.
function Stage.BindNudge(st)
    local H, Round = st.H, st.Round
    local CheckpointHandleHistory, RefreshGroupPreviewAfterMove = st.CheckpointHandleHistory, st.RefreshGroupPreviewAfterMove
    local CurrentStatusSpec, HandleOffsets = st.CurrentStatusSpec, st.HandleOffsets
    local SpellPlacedForHandle, WriteTextHandleOffsets = st.SpellPlacedForHandle, st.WriteTextHandleOffsets
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
            local _
            _, x, y = HandleOffsets(handle)
        end
        local step = H.NudgeStep()
        local cfgX, cfgY = Round((tonumber(x) or 0) + (dx * step)), Round((tonumber(y) or 0) + (dy * step))
        if handle._cfgGroup then
            local lane = AuraLaneConf(conf, handle._cfgGroup)
            if handle._cfgTrackedBuff then
                lane.trackedX, lane.trackedY = cfgX, cfgY
            else
                lane.x, lane.y = cfgX, cfgY
            end
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if not spec then return false end
            conf[spec.x], conf[spec.y] = cfgX, cfgY
        elseif handle._cfgSpell then
            local placed = SpellPlacedForHandle(handle, true)
            if not placed then return false end
            placed.x, placed.y = cfgX, cfgY
        else
            local fixed
            for i = 1, #FIXED_OFFSET_KINDS do
                if handle[FIXED_OFFSET_KINDS[i][1]] then
                    fixed = FIXED_OFFSET_KINDS[i]
                    break
                end
            end
            if not fixed or handle._locked then return false end
            conf[fixed[2]], conf[fixed[3]] = cfgX, cfgY
        end
        RefreshGroupPreviewAfterMove(handle)
        CheckpointHandleHistory(handle, "Nudge")
        return true
    end
    st.NudgeHandlePosition = NudgeHandlePosition
end

--- Exact (scripted) nudges: read/write one handle's configured position and
--- the transactional box:NudgeHandleExact API.
function Stage.BindExactNudge(st)
    local H, M, Round, box = st.H, st.M, st.Round, st.box
    local CurrentStatusSpec, SelectHandle = st.CurrentStatusSpec, st.SelectHandle
    local SpellPlacedForHandle, WriteTextHandleOffsets = st.SpellPlacedForHandle, st.WriteTextHandleOffsets
    local ExactPreviewDelta = MSUF.MSUF2.PreviewHelpers.ExactPreviewDelta
    -- Where a handle keeps its position: the table, its X/Y keys, the anchor key and the Y value used while unset.
    -- create makes the missing aura lane / spell entry (a nil table with keys means nothing is saved yet); nil keys
    -- mean the handle has no stored position. Only these scripted nudges use it; the drag and key-repeat paths above
    -- keep their own inline ladders.
    local function OffsetSlot(handle, conf, create)
        if handle._cfgGroup then
            local lane = create and AuraLaneConf(conf, handle._cfgGroup) or (conf.auras and conf.auras[handle._cfgGroup])
            if handle._cfgTrackedBuff then return lane, "trackedX", "trackedY", "trackedAnchor" end
            return lane, "x", "y", "anchor"
        elseif handle._cfgStatus then
            local spec = handle._statusSpec or CurrentStatusSpec()
            if spec and spec.x and spec.y then return conf, spec.x, spec.y, spec.anchor end
            return nil
        elseif handle._cfgSpell then
            -- create=true: items rendered purely from SpecDefaults have no
            -- saved entry yet; a read-only lookup silently dropped the write.
            return SpellPlacedForHandle(handle, create), "x", "y", "anchor"
        end
        local xKey, yKey, defaultY = FixedOffsetKeys(handle)
        return conf, xKey, yKey, nil, defaultY
    end
    local function ReadHandlePositionExact(handle)
        local conf = handle and H.Conf(H.CurrentScope())
        if not conf then return nil end
        local slot, xKey, yKey, _, defaultY
        if handle._cfgText then
            slot = conf
            xKey, yKey = H.TextOffsetKeys(handle._cfgTextKind or H.CurrentTextKind(), handle._cfgTextSlot)
        else
            slot, xKey, yKey, _, defaultY = OffsetSlot(handle, conf, false)
        end
        if not (xKey and yKey) then return nil end
        return tonumber(slot and slot[xKey]) or 0, tonumber(slot and slot[yKey]) or defaultY or 0
    end
    local function WriteHandlePositionExact(handle, x, y, reason)
        if not handle then return false end
        x, y = Round(x), Round(y)
        if handle._cfgText then
            return WriteTextHandleOffsets(handle, x, y, reason or "Nudge", false, false)
        end
        local conf = H.Conf(H.CurrentScope())
        if not conf then return false end
        local slot, xKey, yKey = OffsetSlot(handle, conf, true)
        if not (slot and xKey) then return false end
        slot[xKey], slot[yKey] = x, y
        st.RefreshGroupPreviewAfterMove(handle)
        return true
    end
    local function RestoreGroupPreviewSelection(previous)
        if previous and previous._key and box._handles[previous._key] == previous then SelectHandle(previous) else SelectHandle(nil) end
    end

    --- Move one explicitly named handle on this exact Group preview surface.
    --- No Edit Mode mover or shared/stale preview target participates.
    function box:NudgeHandleExact(handleKey, dx, dy)
        if ManagerCombatLocked(M) then return false, "combat-locked" end
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
            M.CaptureHistory(st.HandleHistoryLabel(handle, "Nudge"),
                "groupPreview:" .. tostring(H.CurrentScope()) .. ":" .. handleKey .. ":exact-nudge", Mutate)
        else
            Mutate()
            if outcome and outcome[1] then st.CheckpointHandleHistory(handle, "Nudge") end
        end
        if not (outcome and outcome[1]) then RestoreGroupPreviewSelection(previous) end
        if outcome and outcome[1] then return true, outcome[2], outcome[3], outcome[4], outcome[5] end
        return false, (outcome and outcome[2]) or "write-failed"
    end
end

M.GroupPreviewHandleStorage = Stage
Stage.ManagerCombatLocked = ManagerCombatLocked
Stage.RequestBoxRefresh = RequestBoxRefresh
Stage.SelectSpellAura = SelectSpellAura
