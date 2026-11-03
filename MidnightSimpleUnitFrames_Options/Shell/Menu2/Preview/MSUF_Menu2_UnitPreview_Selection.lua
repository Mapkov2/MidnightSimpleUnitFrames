--- Unit preview selection and write policy.
--- Unit-preview selection, coordinate persistence and history policy.
---
--- Keeps field selection, exact movement, reset and focus on one write path.
--- The input owner calls these same functions for mouse and keyboard gestures.
local _, MSUF = ...
local FILE = "Menu2/UnitPreview_Selection"
local ExportPublic = MSUF.ExportPublic
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
local PreviewCore = MSUF.UFPreviewCore or {}
local PreviewCastbar = MSUF.UFPreviewCastbar or {}
local PreviewZoomPan = MSUF.UFPreviewZoomPan or {}
local M2 = MSUF.MSUF2
local PreviewHelpers = M2.PreviewHelpers or {}
local ViewHandles = MSUF.UFPreviewViewHandles or {}
local ViewChrome = MSUF.UFPreviewViewChrome or {}
local TR = ViewChrome.TR
-- Core providers CommitHandleMove calls on every drag and nudge step. They are
-- plain core exports that load before this addon, so they are resolved once here.
local ApplyPowerBarEmbedLayout = MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", FILE)
local RefreshUnitTextureLayers = MSUF.Require("MSUF_RefreshUnitTextureLayers", FILE)
-- Edit Mode focus export the handle selection calls on every text-handle pick.
local SetEditFocusSelection = MSUF.Require("MSUF_EM2_SetFocusSelection", FILE)
-- Refresh function of each status handle (statusRefresh names the core export),
-- resolved when the handle is built so a move step only indexes this table.
local STATUS_REFRESH = {}
local Fallbacks = M2.Fallbacks or {}
local PreviewModel = Preview.Model or {}
local UNIT_DATA, UnitDB, ForceTextUnit, ApplyPanelUnit = PreviewModel.UNIT_DATA, PreviewModel.UnitDB, PreviewModel.ForceTextUnit, PreviewModel.ApplyPanelUnit
local EnsureUnitPortraitStyle, ApplyPortrait = PreviewModel.EnsureUnitPortraitStyle, PreviewModel.ApplyPortrait
local NormalizeStatusPreviewId = PreviewModel.NormalizeStatusPreviewId
Preview.statusPreviewMode = "all"
Preview.selectedStatusId = nil
local SelectPreviewHandle
function Preview.SetStatusPreviewMode(mode)
    Preview.statusPreviewMode = (mode == "all") and "all" or "current"
    Preview.RequestRefresh("STATUS_PREVIEW_MODE")
end
function Preview.GetStatusPreviewMode()
    return (Preview.statusPreviewMode == "all") and "all" or "current"
end
function Preview.SelectStatusIcon(id)
    Preview.selectedStatusId = NormalizeStatusPreviewId(id)
    local box = Preview.active
    local h = box and box.statusHandles and box.statusHandles[Preview.selectedStatusId]
    if h and SelectPreviewHandle then SelectPreviewHandle(h, true) end
    Preview.RequestRefresh("STATUS_PREVIEW_SELECT")
end
local RoundOffset = PreviewCore.RoundOffset
-- Preview keyboard helpers are shared with ClassPower preview so arrow nudges,
-- EM2 nudge targets, and text-focus guards stay identical across preview types.
local GetNudgeStep = PreviewHelpers.NudgeStep or Fallbacks.One

local CastbarOffsetFields = PreviewCastbar.OffsetFields
-- Handle storage/navigation and chrome helpers live in the *_View_Handles and
-- *_View_Chrome siblings. The ones on the drag/nudge path stay upvalues here.
local RegisterUnitPreviewControl, ApplyCastbarRuntimeForKey = ViewHandles.RegisterUnitPreviewControl, ViewHandles.ApplyCastbarRuntimeForKey
local BeginMenuHistory, CommitMenuHistory = ViewHandles.BeginMenuHistory, ViewHandles.CommitMenuHistory
local CheckpointMenuHistory, OpenPreviewHandleSettings = ViewHandles.CheckpointMenuHistory, ViewHandles.OpenPreviewHandleSettings
local PreviewGuidesVisible, UpdateHandleHint = ViewChrome.PreviewGuidesVisible, ViewChrome.UpdateHandleHint
local RequestPreviewLayoutRefresh = ViewChrome.RequestPreviewLayoutRefresh
local function ResolveHandleFields(preview, fields)
    if fields and fields.castbar then return CastbarOffsetFields(preview and preview.key) end
    return fields and fields.x, fields and fields.y, fields and fields.defaultX or 0, fields and fields.defaultY or 0
end
local function HandleStore(preview, fields)
    local conf, g, key = UnitDB(preview and preview.key)
    if fields and fields.portrait then EnsureUnitPortraitStyle(key) end
    if fields and (fields.global or fields.castbar) then return g, key, conf, g end
    return conf, key, conf, g
end
function Preview.LegacyTextOffsetAlias(key)
    key = tostring(key or "")
    local prefix, axis = key:match("^(hp)Offset([XY])$")
    if not prefix then prefix, axis = key:match("^(power)Offset([XY])$") end
    if prefix then return prefix .. "TextOffset" .. axis end
    if key == "nameOffsetX" then return "nameTextOffsetX" end
    if key == "nameOffsetY" then return "nameTextOffsetY" end
    local side
    prefix, side, axis = key:match("^(hp)Text([A-Za-z]+)Offset([XY])$")
    if not prefix then prefix, side, axis = key:match("^(power)Text([A-Za-z]+)Offset([XY])$") end
    if prefix and (side == "Left" or side == "Center" or side == "Right") then
        return prefix .. side .. "Offset" .. axis
    end
end
local function ReadStoredOffset(fields, key, store, conf, general)
    if not key then return nil end
    local value = store and store[key]
    if value == nil and fields.text then
        local alias = Preview.LegacyTextOffsetAlias(key)
        if alias then value = conf and conf[alias] end
        if value == nil then value = general and general[key] end
        if value == nil and alias then value = general and general[alias] end
    end
    return tonumber(value)
end
local function ReadHandleOffsets(handle)
    if not handle then return 0, 0 end
    local preview = handle._preview
    local fields = handle._fields or {}
    if fields.readOffsets then
        local x, y, xKey, yKey = fields.readOffsets(handle)
        if x ~= nil and y ~= nil then return x, y, xKey, yKey end
    end
    local xKey, yKey, defX, defY = ResolveHandleFields(preview, fields)
    local store, _, conf, general = HandleStore(preview, fields)
    local x = ReadStoredOffset(fields, xKey, store, conf, general)
    local y = ReadStoredOffset(fields, yKey, store, conf, general)
    if x == nil then x = tonumber(defX) or 0 end
    if y == nil then y = tonumber(defY) or 0 end
    return x, y, xKey, yKey
end
Preview.DirectTextMovePrefixes = Preview.DirectTextMovePrefixes or {
    name = { "directName" },
    hp = { "directHealthLeft", "directHealthCenter", "directHealthRight" },
    hpLeft = { "directHealthLeft" },
    hpCenter = { "directHealthCenter" },
    hpRight = { "directHealthRight" },
    power = { "directPowerLeft", "directPowerCenter", "directPowerRight" },
    powerLeft = { "directPowerLeft" },
    powerCenter = { "directPowerCenter" },
    powerRight = { "directPowerRight" },
}
function Preview.DirectTextMovePrefixesForKey(key)
    return Preview.DirectTextMovePrefixes[tostring(key or "")]
end
function Preview.ActiveDirectTextMovePrefixes(handle, store)
    if not (handle and type(store) == "table" and store.directTextLayout == true) then return nil end
    local prefixes = Preview.DirectTextMovePrefixesForKey(handle._key)
    if not prefixes then return nil end
    -- Detached power text intentionally uses the legacy composite offsets on
    -- the detached bar even while Direct Text Layout owns the other slots.
    local box = handle._preview
    if tostring(handle._key or ""):match("^power")
        and box and box._runtimeDetachedPowerTextOnBar == true
        and box.mock and box.mock.detachedPower and box.mock.detachedPower.IsShown
        and box.mock.detachedPower:IsShown()
    then
        return nil
    end
    return prefixes
end
function Preview.ApplyDirectTextMoveDelta(store, prefixes, dx, dy)
    if not (type(store) == "table" and type(prefixes) == "table") then return false end
    dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        local xKey, yKey = prefix .. "OffsetX", prefix .. "OffsetY"
        store[xKey] = RoundOffset((tonumber(store[xKey]) or 0) + dx)
        store[yKey] = RoundOffset((tonumber(store[yKey]) or 0) + dy)
    end
    return true
end
local MenuTheme = PreviewCore.MenuTheme
local function OpenHandleFromGear(handle) return OpenPreviewHandleSettings(handle, "gear") end
local function GearOptions(shown)
    return { T = MenuTheme and MenuTheme(), Tr = TR, shown = shown, openSettings = OpenHandleFromGear }
end
local function RefreshHandleSelectionVisuals(box)
    if not box then return end
    if not box._selectedHandle and Preview.RestoreQueuedHandle(box) then return end
    local guidesOn = PreviewGuidesVisible(box)
    local selected = box._selectedHandle
    if selected and selected.IsShown and not selected:IsShown() then
        selected = nil
        box._selectedHandle = nil
        Preview.SetArrowBindings(box, false)
        PreviewHelpers.ReleaseKeyboardCapture(box)
    end
    if PreviewHelpers.RefreshSelectedLayerButtons then
        PreviewHelpers.RefreshSelectedLayerButtons(box, selected, "layerButtons")
    end
    for i = 1, #(box.handles or {}) do
        local h = box.handles[i]
        local isSel = h and h == selected
        if h then
            local isHover = h._hovering == true
            if h._selBorder then
                if guidesOn and isSel then h._selBorder:Show() else h._selBorder:Hide() end
            end
            local c = h._color or { 0.7, 0.8, 1.0 }
            local isDrag = h._dragging == true
            local visualOnly = h._fields and h._fields.visualOnly == true
            if h.tex then
                local a = guidesOn and (isDrag and 0.18 or (isHover and 0.14 or (visualOnly and isSel and 0.06 or 0))) or 0
                h.tex:SetColorTexture(c[1], c[2], c[3], a)
            end
            if h.edge then
                local a = guidesOn and (isDrag and 0.18 or (isHover and 0.08 or (visualOnly and isSel and 0.08 or 0))) or 0
                h.edge:SetColorTexture(c[1], c[2], c[3], a)
            end
            if h.SetAlpha then h:SetAlpha(1) end
            if h._msuf2SettingsGear then h._msuf2SettingsGear:SetShown(guidesOn and isSel) end
        end
    end
    if selected and guidesOn and PreviewHelpers.EnsurePreviewHandleGear then
        local gear = PreviewHelpers.EnsurePreviewHandleGear(selected, {
            T = MenuTheme and MenuTheme(),
            Tr = TR,
            shown = true,
            openSettings = OpenHandleFromGear,
        })
        local previewPageKey = box._msuf2PinnedPreviewPageKey or M2.activeKey
        if gear and not gear._msuf2UnitPreviewOpenCommand then
            local targetHandle = selected
            gear._msuf2UnitPreviewOpenCommand = {
                kind = "button",
                historyMode = "none",
                canExecute = function() return targetHandle ~= nil end,
                set = function() return OpenPreviewHandleSettings(targetHandle, "search") end,
            }
        end
        RegisterUnitPreviewControl(gear, "handle." .. tostring(selected._key) .. ".open_settings",
            M2.Format("Open %s settings", TR(tostring(selected._label or selected._key or "preview element"))),
            "button", "action", {
                historyMode = "none",
                help = "Click the highlighted preview button to jump directly to this element's settings below.",
                command = gear and gear._msuf2UnitPreviewOpenCommand,
            }, previewPageKey)
    end
    UpdateHandleHint(box, selected)
end
local function CommitHandleMove(handle, reason)
    if not handle then return end
    local box = handle._preview
    local fields = handle._fields or {}
    local _, _, key = UnitDB(box and box.key)
    local moveReason = reason or "UNIT_PREVIEW_MOVE"
    if fields.text then
        ForceTextUnit(key, moveReason)
    elseif fields.portrait then
        ApplyPortrait(box and box._msufPanel, key, reason or "UNIT_PREVIEW_PORTRAIT_MOVE")
    elseif fields.detachedPower then
        ApplyPowerBarEmbedLayout(key, true)
    elseif fields.castbar then
        ApplyCastbarRuntimeForKey(key)
    elseif fields.texLayer then
        RefreshUnitTextureLayers(key)
    elseif fields.statusRefresh then
        local refresh = STATUS_REFRESH[fields.statusRefresh]
        if refresh then refresh(key, moveReason) end
    end
    ApplyPanelUnit(box and box._msufPanel, key, moveReason)
    RequestPreviewLayoutRefresh(box, moveReason)
    RefreshHandleSelectionVisuals(box)
end
-- Deltas stored by the controls are unit-frame coordinates. The handle lives on the outer stage; engine texts
-- live inside the zoomed scene. Convert through each real region's effective scale, as the group preview does.
local DRAG_TEXT_FIELD = {
    hpLeft = "hpTextLeft", hpCenter = "hpTextCenter", hpRight = "hpText",
    powerLeft = "powerTextLeft", powerCenter = "powerTextCenter", powerRight = "powerText",
}
local function DragSceneText(handle, dx, dy)
    local box, key = handle._preview, handle._key
    local mock = box and box.mock
    if not (mock and mock._body) then return end
    local body, regions = mock._body, {}
    if key == "name" then
        regions[1] = body._msufNameClipFrame and body._msufNameClipFrame:IsShown() and body._msufNameClipFrame or body.nameText
    elseif key == "hp" then regions = { body.hpTextLeft, body.hpTextCenter, body.hpText }
    elseif key == "power" then regions = { body.powerTextLeft, body.powerTextCenter, body.powerText }
    else
        local field = DRAG_TEXT_FIELD[key]
        if field then regions[1] = body[field] end
    end
    local stageScale = mock:GetEffectiveScale()
    local outerX, outerY = dx * box._mockEffectiveScale, dy * box._mockEffectiveScale
    -- Canvas rectangles move independently; a fallback anchored to the text follows its native anchor chain.
    local _, relative = handle:GetPoint(1)
    if relative == box.canvas or relative == mock then regions.handle = handle end
    for _, region in pairs(regions) do
        if region and region:IsShown() then
            local ratio = region:GetEffectiveScale() / stageScale
            local points = {}
            for index = 1, region:GetNumPoints() do points[index] = { region:GetPoint(index) } end
            region:ClearAllPoints()
            for i = 1, #points do
                local point = points[i]
                region:SetPoint(point[1], point[2], point[3], (point[4] or 0) + outerX / ratio, (point[5] or 0) + outerY / ratio)
            end
            region._msufX, region._msufY, region._msufPoint, region._msufRelPoint, region._msufRelativeTo = nil, nil, nil, nil, nil
        end
    end
end

local function WriteHandleOffsets(handle, x, y, reason)
    if not handle then return false end
    local box = handle._preview
    local fields = handle._fields or {}
    if fields.writeOffsets then
        if not fields.writeOffsets(handle, x, y, reason) then return false end
        local fastDrag = reason == "UNIT_PREVIEW_DRAG"
            and fields.visualOnly == true
            and fields.dragOffsets
            and fields.dragOffsets(handle, x, y) == true
        if not fastDrag then RequestPreviewLayoutRefresh(box, reason or "UNIT_PREVIEW_MOVE") end
        RefreshHandleSelectionVisuals(box)
        if not handle._msuf2PreviewHistoryTx then CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move") end
        return true
    end
    local xKey, yKey = ResolveHandleFields(box, fields)
    if not xKey or not yKey then return false end
    local store = HandleStore(box, fields)
    local beforeX, beforeY = ReadHandleOffsets(handle)
    local nextX, nextY = RoundOffset(x), RoundOffset(y)
    store[xKey], store[yKey] = nextX, nextY
    local directPrefixes = fields.text and Preview.ActiveDirectTextMovePrefixes(handle, store)
    if directPrefixes then
        if reason == "PREVIEW_RESET_OFFSET" and M2.SyncDirectTextOffsets then
            -- Reset is an explicit request to return this handle to its
            -- canonical layout, so its active direct values may be rebuilt.
            M2.SyncDirectTextOffsets(store, xKey)
            M2.SyncDirectTextOffsets(store, yKey)
        else
            -- Imported profiles may legitimately contain direct-layout offsets
            -- that differ from their legacy twins. Move the active direct values
            -- by the requested delta instead of rebuilding them from stale legacy
            -- values and snapping the text to another position.
            Preview.ApplyDirectTextMoveDelta(store, directPrefixes, nextX - beforeX, nextY - beforeY)
        end
    elseif fields.text and M2.SyncDirectTextOffsets then
        M2.SyncDirectTextOffsets(store, xKey)
        M2.SyncDirectTextOffsets(store, yKey)
    end
    if fields.text and reason == "UNIT_PREVIEW_DRAG" then
        local dx, dy = nextX - beforeX, nextY - beforeY
        if not directPrefixes and fields.resolveOffsetDelta then
            dx, dy = fields.resolveOffsetDelta(handle, dx, dy)
        end
        DragSceneText(handle, dx, dy)
    end
    CommitHandleMove(handle, reason)
    if not handle._msuf2PreviewHistoryTx then CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move") end
    return true
end
local function ShouldSkipDuplicateNudge(box, dx, dy)
    return PreviewHelpers.ShouldSkipDuplicateNudge and PreviewHelpers.ShouldSkipDuplicateNudge(box, dx, dy) or false
end
local function StoredHandleDelta(handle, dx, dy)
    local fields = handle and handle._fields
    if fields and fields.resolveOffsetDelta then
        return fields.resolveOffsetDelta(handle, dx, dy)
    end
    return dx, dy
end
function Preview.ActiveHandleDelta(handle, dx, dy)
    local fields = handle and handle._fields
    if fields and fields.text then
        local store = HandleStore(handle._preview, fields)
        if Preview.ActiveDirectTextMovePrefixes(handle, store) then return dx, dy end
    end
    return StoredHandleDelta(handle, dx, dy)
end
local function NudgeSelectedHandle(box, dx, dy)
    local h = box and box._selectedHandle
    if not h or not h.IsShown or not h:IsShown() then return false end
    local x, y = ReadHandleOffsets(h)
    local step = GetNudgeStep()
    local ndx, ndy = dx * step, dy * step
    if ShouldSkipDuplicateNudge(box, ndx, ndy) then return true end
    ndx, ndy = Preview.ActiveHandleDelta(h, ndx, ndy)
    return WriteHandleOffsets(h, x + ndx, y + ndy, "UNIT_PREVIEW_NUDGE")
end
local function NudgeSelectedHandleDelta(box, dx, dy)
    local h = box and box._selectedHandle
    if not h or not h.IsShown or not h:IsShown() then return false end
    local x, y = ReadHandleOffsets(h)
    local ndx, ndy = tonumber(dx) or 0, tonumber(dy) or 0
    if ShouldSkipDuplicateNudge(box, ndx, ndy) then return true end
    ndx, ndy = Preview.ActiveHandleDelta(h, ndx, ndy)
    return WriteHandleOffsets(h, x + ndx, y + ndy, "UNIT_PREVIEW_EM2_NUDGE")
end
function Preview.ReadSelectionCoordinates(box, handle)
    local selection = M2.PreviewSelectionBar
    local x, y
    if selection and selection.ReadRenderedCoordinates then
        x, y = selection.ReadRenderedCoordinates(handle, box and box.mock,
            box and (box._mockEffectiveScale or box._mockScale or box._mockAutoScale) or 1)
    end
    if x == nil or y == nil then x, y = ReadHandleOffsets(handle) end
    return RoundOffset(x), RoundOffset(y)
end
function Preview.WriteSelectionCoordinates(box, handle, x, y, reason)
    if not handle then return false end
    local currentX, currentY = Preview.ReadSelectionCoordinates(box, handle)
    local storedX, storedY = ReadHandleOffsets(handle)
    local dx, dy = (tonumber(x) or currentX) - currentX, (tonumber(y) or currentY) - currentY
    dx, dy = Preview.ActiveHandleDelta(handle, dx, dy)
    return WriteHandleOffsets(handle, storedX + dx, storedY + dy, reason)
end
local selectionDefaults
function Preview.DefaultSelectionOffsets(_, handle)
    if not handle then return 0, 0 end
    -- Client defaults are immutable. Resolve once on menu selection, never on
    -- an animation or drag tick.
    if not selectionDefaults then selectionDefaults = MSUF.MSUF_CreateFactoryDefaultProfile() or {} end
    local fields, box = handle._fields or {}, handle._preview
    local _, _, key = UnitDB(box and box.key)
    local _, _, xKey, yKey = ReadHandleOffsets(handle)
    local _, _, fallbackX, fallbackY = ResolveHandleFields(box, fields)
    local general = selectionDefaults.general or {}
    local source = selectionDefaults[key] or {}
    if fields.auraPreviewKind then
        local auras = selectionDefaults.auras3 or {}
        local customIndex = tonumber(fields.auraPreviewKind:match("^custom(%d)$"))
        if customIndex then
            local containers = auras.customContainers
            local record = containers and containers.perUnit and containers.perUnit[key]
            local item = record and record.items and record.items[customIndex]
            source = item and item.placed or {}
        else
            local unit = key == "boss" and "boss1" or key == "arena" and "arena1" or key
            local record = auras.perUnit and auras.perUnit[unit]
            source = record and record.layout or {}
        end
    elseif fields.global or fields.castbar or fields.suffixX then source = general
    elseif fields.barsX then source = selectionDefaults.bars or {} end
    local function Read(field, axis)
        local value = field and source[field]
        if value == nil and fields.text then
            local alias = Preview.LegacyTextOffsetAlias(field)
            value = alias and source[alias]
            if value == nil then value = general[field] or (alias and general[alias]) end
        end
        if value == nil and fields.iconFallback then
            local suffix = axis == "x" and fields.suffixX or fields.suffixY
            value = suffix and general[suffix:gsub("^Icon", "castbarIcon")]
        end
        if value == nil then
            local defaultKey = axis == "x" and fields.defaultXFromG or fields.defaultYFromG
            value = defaultKey and general[defaultKey]
        end
        if value == nil then value = axis == "x" and fallbackX or fallbackY end
        local base = axis == "x" and fields.bossBaseX or fields.bossBaseY
        if fields.suffixX and (key == "boss" or key == "arena") and base ~= nil then
            value = (tonumber(field and general[field]) or 0) + base
        end
        return tonumber(value) or 0
    end
    return Read(xKey, "x"), Read(yKey, "y")
end
function Preview.ResetSelectionOffsets(owner, handle, reason)
    local x, y = Preview.DefaultSelectionOffsets(owner, handle)
    return WriteHandleOffsets(handle, x, y, reason)
end
local function FocusPreviewKeyboardTarget(box, handle, defer)
    if PreviewHelpers.FocusKeyboardTarget then return PreviewHelpers.FocusKeyboardTarget(box, handle, defer, { selectedField = "_selectedHandle" }) end
end
local function OnUFPreviewArrowDisable(box)
    if box and box._msufArrowPoller then
        box._msufArrowPoller:SetScript("OnUpdate", nil)
        box._msufArrowPoller:Hide()
    end
end
local function OnUFPreviewArrowNudge(active, dx, dy)
    if NudgeSelectedHandle(active, dx, dy) then FocusPreviewKeyboardTarget(active, active and active._selectedHandle, true) end
end
local UF_PREVIEW_ARROW_BINDINGS = {
    ownerName = "MSUF_UFPreview_NudgeOwner",
    activeName = "MSUF_UFPreview_ActiveNudgeBox",
    buttonPrefix = "MSUF_UFPreview_Nudge",
    getActive = function() return MSUF_UFPreview_ActiveNudgeBox or Preview.active end,
    onClick = OnUFPreviewArrowNudge,
    onDisable = OnUFPreviewArrowDisable,
}
Preview.SetArrowBindings = function(box, enabled)
    return M2.SetPreviewArrowBindings and M2.SetPreviewArrowBindings(box, enabled, UF_PREVIEW_ARROW_BINDINGS)
end
local function RegisterPreviewNudgeTarget(box)
    if PreviewHelpers.RegisterEditModeNudgeTarget then
        PreviewHelpers.RegisterEditModeNudgeTarget(box, {
            targetField = "_msufPreviewNudgeTarget",
            selectedField = "_selectedHandle",
            nudgeDelta = NudgeSelectedHandleDelta,
        })
    end
end
SelectPreviewHandle = function(handle, skipSectionOpen)
    local box = handle and handle._preview or Preview.active
    if not box then return end
    do
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.IsObjectType and focus:IsObjectType("EditBox") and focus.ClearFocus then focus:ClearFocus() end
    end
    box._selectedHandle = handle
    FocusPreviewKeyboardTarget(box, handle, false)
    Preview.SetArrowBindings(box, handle ~= nil)
    if handle then
        local p = box._msufPanel
        local fields = handle._fields or {}
        RegisterPreviewNudgeTarget(box)
        if fields.statusRefresh then
            Preview.selectedStatusId = NormalizeStatusPreviewId(handle._key)
            if not skipSectionOpen and p and p._msufUFStatusSet then p._msufUFStatusSet("selected", handle._key) end
        end
        local textKind, textSlot = ViewHandles.PreviewTextKindSlotForKey(handle._key)
        ViewHandles.StorePreviewTextSelection(M2, box.key, textKind, textSlot)
        if textKind then
            SetEditFocusSelection(box.key or "player", textKind, textSlot,
                { source = "unit-preview", clearHover = true })
        end
        FocusPreviewKeyboardTarget(box, handle, true)
    end
    RefreshHandleSelectionVisuals(box)
end

local ExactPreviewDelta = MSUF.MSUF2.PreviewHelpers.ExactPreviewDelta
local function ExactUnitPreviewKey(value)
    if type(value) ~= "string" or value == "" then return nil end
    value = value:lower()
    if UNIT_DATA[value] then return value end
    if value == "tot" then return "targettarget" end
    if value == "focus_target" or value == "focustargettarget" then return "focustarget" end
    if value:match("^boss%d+$") then return "boss" end
    if value:match("^arena%d+$") then return "arena" end
    return nil
end
local function FindUnitPreviewHandle(box, handleKey)
    if not (box and type(handleKey) == "string" and handleKey ~= "") then return nil end
    local handles = box.handles
    for i = 1, #(handles or {}) do
        local handle = handles[i]
        if handle and handle._key == handleKey then return handle end
    end
    return nil
end
function Preview.RestoreQueuedHandle(box)
    local sameSourceGeneration = box and box == Preview._restoreSourceBox
        and (tonumber(box._msuf2PreviewShowSerial) or 0) <= (tonumber(Preview._restoreSourceShowSerial) or 0)
    if not (box and not sameSourceGeneration and SelectPreviewHandle and Preview._restoreHandleKey
        and tostring(box.key) == tostring(Preview._restoreHandleUnit)
        and (not box.IsShown or box:IsShown()))
    then return false end
    local handle = FindUnitPreviewHandle(box, Preview._restoreHandleKey)
    if not (handle and handle._msufPlaced ~= false and (not handle.IsShown or handle:IsShown())) then return false end
    Preview._restoreHandleUnit, Preview._restoreHandleKey, Preview._restoreSourceBox, Preview._restoreSourceShowSerial = nil, nil, nil, nil
    SelectPreviewHandle(handle, true)
    return true
end
local function RestoreUnitPreviewSelection(box, previous)
    if not box then return end
    if previous and previous._preview == box then
        SelectPreviewHandle(previous, true)
    else
        SelectPreviewHandle(nil, true)
    end
end

--- Move one explicitly named handle on the currently visible Unit preview.
---
--- This is the deterministic Search/Edit Mode entry point. It deliberately
--- does not consult the shared Edit Mode nudge target or the currently selected
--- mover. The write is accepted only after exact DB readback; a failed readback
--- is rolled back before returning false.
function Preview.NudgeHandle(unitKey, handleKey, dx, dy)
    if M2.IsConfigCombatLocked and M2.IsConfigCombatLocked() then return false, "combat-locked" end
    unitKey = ExactUnitPreviewKey(unitKey)
    if not unitKey then return false, "unknown-unit" end
    if type(handleKey) ~= "string" or handleKey == "" then return false, "handle-required" end
    dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
    if dx == nil or dy == nil then return false, "invalid-delta" end

    local box = Preview.active
    if not (box and box.IsShown and box:IsShown() and (not box.IsVisible or box:IsVisible())) then return false, "preview-not-visible" end
    if unitKey ~= ExactUnitPreviewKey(box.key) then return false, "unit-preview-mismatch" end
    local handle = FindUnitPreviewHandle(box, handleKey)
    if not handle then return false, "unknown-handle" end
    if handle._dragging == true or handle._msuf2PreviewHistoryTx then return false, "handle-busy" end
    if handle._msufPlaced == false or (handle.IsShown and not handle:IsShown()) then return false, "handle-not-visible" end

    local beforeX, beforeY, xKey, yKey = ReadHandleOffsets(handle)
    if tonumber(beforeX) == nil or tonumber(beforeY) == nil or not xKey or not yKey then return false, "handle-not-readable" end
    beforeX, beforeY = tonumber(beforeX), tonumber(beforeY)
    local expectedX, expectedY = RoundOffset(beforeX + dx), RoundOffset(beforeY + dy)
    local previous = box._selectedHandle
    SelectPreviewHandle(handle, true)
    if box._selectedHandle ~= handle then
        RestoreUnitPreviewSelection(box, previous)
        return false, "selection-failed"
    end
    if expectedX == beforeX and expectedY == beforeY then return true, beforeX, beforeY, beforeX, beforeY end

    local historyStarted = BeginMenuHistory(handle, "Nudge") == true
    handle._msuf2PreviewHistoryTx = true
    local wrote = WriteHandleOffsets(handle, expectedX, expectedY, "UNIT_PREVIEW_EXACT_NUDGE") == true
    local afterX, afterY = ReadHandleOffsets(handle)
    afterX, afterY = tonumber(afterX), tonumber(afterY)
    local success = wrote and afterX == expectedX and afterY == expectedY
    local failureReason
    if not success then
        local rolledBack = WriteHandleOffsets(handle, beforeX, beforeY, "UNIT_PREVIEW_EXACT_NUDGE_ROLLBACK") == true
        local restoredX, restoredY = ReadHandleOffsets(handle)
        if not rolledBack or tonumber(restoredX) ~= beforeX or tonumber(restoredY) ~= beforeY then
            failureReason = "rollback-failed"
        else
            failureReason = wrote and "readback-mismatch" or "write-failed"
        end
    end
    handle._msuf2PreviewHistoryTx = nil
    if historyStarted then
        CommitMenuHistory()
    elseif success then
        CheckpointMenuHistory(handle, "Nudge")
    end
    if not success then
        RestoreUnitPreviewSelection(box, previous)
        return false, failureReason
    end
    return true, beforeX, beforeY, afterX, afterY
end
function Preview.Pan(unitKey, dx, dy)
    if M2.IsConfigCombatLocked and M2.IsConfigCombatLocked() then return false, "combat-locked" end
    unitKey = ExactUnitPreviewKey(unitKey)
    if not unitKey then return false, "unknown-unit" end
    dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
    if dx == nil or dy == nil then return false, "invalid-delta" end
    local box = Preview.active
    if not (box and box.IsShown and box:IsShown() and (not box.IsVisible or box:IsVisible())) then return false, "preview-not-visible" end
    if unitKey ~= ExactUnitPreviewKey(box.key) then return false, "unit-preview-mismatch" end
    if (box.canvas and box.canvas._msufPreviewPanning) or (box.dragFrame and box.dragFrame._handle) then return false, "preview-busy" end
    if not PreviewZoomPan.NudgePan then return false, "pan-api-unavailable" end
    return PreviewZoomPan.NudgePan(box, dx, dy)
end
ExportPublic("MSUF_UFPreview_NudgeHandle", function(unitKey, handleKey, dx, dy)
    return Preview.NudgeHandle(unitKey, handleKey, dx, dy)
end)
ExportPublic("MSUF_UFPreview_Pan", function(unitKey, dx, dy)
    return Preview.Pan(unitKey, dx, dy)
end)
-- Captured once by View and Input; no per-event wrapper or provider lookup.
MSUF.UFPreviewSelection = {
    SelectHandle = SelectPreviewHandle,
    RefreshVisuals = RefreshHandleSelectionVisuals,
    ReadOffsets = ReadHandleOffsets,
    WriteOffsets = WriteHandleOffsets,
    NudgeSelected = NudgeSelectedHandle,
    NudgeSelectedDelta = NudgeSelectedHandleDelta,
    StatusRefresh = STATUS_REFRESH,
    GearOptions = GearOptions,
}
