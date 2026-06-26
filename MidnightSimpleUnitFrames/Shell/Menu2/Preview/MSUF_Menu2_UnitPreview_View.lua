--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua
--- Cold-path unitframe preview view.
---
--- Owns: preview frame construction, draggable handle interactions, and
--- composed refresh layout. Specs, core visuals, castbar helpers, status
--- elements, DB/model helpers, and public wrappers live in split files.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
MSUF.L = MSUF.L or (_G.MSUF_L) or {}
local L = MSUF.L
if not getmetatable(L) then setmetatable(L, { __index = function(_, k) return k end }) end
local isEn = (MSUF and MSUF.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local format = string.format
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
ExportPublic("MSUF_UFPreview", Preview)
local PreviewCore = MSUF.UFPreviewCore or {}
local PreviewCastbar = MSUF.UFPreviewCastbar or {}
local PreviewStatus = MSUF.UFPreviewStatus or {}
local PreviewAuras = MSUF.UFPreviewAuras or {}
local PreviewRuntime = MSUF.UFPreviewRuntime or {}
local PreviewZoomPan = MSUF.UFPreviewZoomPan or {}
local M2 = MSUF.MSUF2 or _G.MSUF2 or {}
local Pick = M2.Pick
local AssignNamedValues = M2.AssignNamedValues
local F = M2.Fallbacks or {}
local PreviewHelpers = M2.PreviewHelpers or {}
local PreviewModel = Preview.Model or {}
local UNIT_LABELS, UNIT_DATA, PreviewRaidGroupNameAllowed, PreviewRaidGroupNameText, NormalizePreviewRaidGroupNameAnchor, CanonKey, CurrentPanelKey, UnitDB, NormalizeHpMode, NormalizePowerMode, TextScopeGet, TextScopeHasSlots, TextScopeSlotGet, ToTInlineSeparator, ShortenPreviewName, ForceTextUnit, ApplyPanelUnit, EnsureUnitPortraitStyle, PortraitStyleGet, ApplyPortrait, NormalizeStatusPreviewId, ClassColor, HealthColor, HealthBackgroundColor, PowerBackgroundColor, PowerColor, ClassPortraitVisual, UnitPreviewPortraitTexture, FontColor, PreviewNameColor, PreviewToTInlineColor, SetTex, PreviewHealPredictionEnabled, PreviewResolveHealPredAnchorMode, PreviewResolveAbsorbAnchorMode, PreviewAbsorbBarEnabled, LayoutUnitPreviewOverlay, MakeFS, ReadPowerBarEnabled, CanDetachPowerBarKey, ReadPowerBarHeight, ResolveNameAnchor, FormatMode, UnitPreviewText = Pick(PreviewModel, [[UNIT_LABELS UNIT_DATA PreviewRaidGroupNameAllowed PreviewRaidGroupNameText NormalizePreviewRaidGroupNameAnchor CanonKey CurrentPanelKey UnitDB NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet ToTInlineSeparator ShortenPreviewName ForceTextUnit ApplyPanelUnit EnsureUnitPortraitStyle PortraitStyleGet ApplyPortrait NormalizeStatusPreviewId ClassColor HealthColor HealthBackgroundColor PowerBackgroundColor PowerColor ClassPortraitVisual UnitPreviewPortraitTexture FontColor PreviewNameColor PreviewToTInlineColor SetTex PreviewHealPredictionEnabled PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewAbsorbBarEnabled LayoutUnitPreviewOverlay MakeFS ReadPowerBarEnabled CanDetachPowerBarKey ReadPowerBarHeight ResolveNameAnchor FormatMode UnitPreviewText]])
Preview.statusPreviewMode = "current"
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
local PositionFromAnchor, PositionRuntimeLayoutIconPreview, PositionStatusCornerPreview, PositionSameAnchorPreview, PositionLevelPreview = Pick(PreviewStatus, [[PositionFromAnchor PositionRuntimeLayoutIconPreview PositionStatusCornerPreview PositionSameAnchorPreview PositionLevelPreview]])
local RoundOffset = PreviewCore.RoundOffset
-- Preview keyboard helpers are shared with ClassPower preview so arrow nudges,
-- EM2 nudge targets, and text-focus guards stay identical across preview types.
local GetNudgeStep = PreviewHelpers.NudgeStep or F.One
local IsTextInputFocused = PreviewHelpers.IsTextInputFocused or F.False
local CastbarOffsetFields, CastbarDetached, ReadCastbarSize, ReadCastbarNum, FormatCastbarPreviewTime = Pick(PreviewCastbar, [[OffsetFields Detached ReadSize ReadNumber FormatPreviewTime]])
local ClampPreviewLayer = PreviewCore.ClampLayer
local RuntimeSpecForPreviewKey = PreviewRuntime.SpecForPreviewKey or F.Nil
local RuntimeVisualScaleForPreviewKey = PreviewRuntime.VisualScaleForPreviewKey or F.One
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
local function ReadHandleOffsets(handle)
    if not handle then return 0, 0 end
    local preview = handle._preview
    local fields = handle._fields or {}
    if type(fields.readOffsets) == "function" then
        local x, y, xKey, yKey = fields.readOffsets(handle)
        if x ~= nil and y ~= nil then return x, y, xKey, yKey end
    end
    local xKey, yKey, defX, defY = ResolveHandleFields(preview, fields)
    local store = HandleStore(preview, fields)
    local x = xKey and tonumber(store[xKey]) or nil
    local y = yKey and tonumber(store[yKey]) or nil
    if x == nil then x = tonumber(defX) or 0 end
    if y == nil then y = tonumber(defY) or 0 end
    return x, y, xKey, yKey
end
local function UnitPreviewTextMovesTogether(unitKey, kind)
    local m = _G.MSUF2
    local byUnit = m and m.unitTextMoveTogether and m.unitTextMoveTogether[unitKey or "player"]
    local value = byUnit and byUnit[kind]
    if value == nil then return true end
    return value == true
end
local function UnitPreviewSetTextMoveTogether(unitKey, kind, value)
    local m = _G.MSUF2
    if not m then return end
    unitKey = unitKey or "player"
    m.unitTextMoveTogether = m.unitTextMoveTogether or {}
    m.unitTextMoveTogether[unitKey] = m.unitTextMoveTogether[unitKey] or {}
    m.unitTextMoveTogether[unitKey][kind] = value ~= false
end
local function PreviewGuidesEnabled()
    local db = _G.MSUF_DB
    local general = db and db.general
    if type(general) == "table" and general.unitPreviewGuidesEnabled ~= nil then return general.unitPreviewGuidesEnabled ~= false end
    return true
end
local function SetPreviewGuidesEnabled(enabled)
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    _G.MSUF_DB.general.unitPreviewGuidesEnabled = enabled ~= false
end
local function PreviewGuidesVisible(box)
    local layers = box and box.layerVisibility
    if type(layers) == "table" and layers.guides ~= nil then return layers.guides ~= false end
    return PreviewGuidesEnabled()
end
local function DefaultPreviewHint(box)
    if box and not PreviewGuidesVisible(box) then return TR("guides hidden - selected element still nudges with arrows - turn Guides on to drag another element") end
    return TR("drag elements - arrows nudge selected - Ctrl+wheel zoom - Ctrl+left drag pans")
end
local function UpdateHandleHint(box, handle)
    if not box or not box.hint then return end
    if not handle then
        box.hint:SetText(DefaultPreviewHint(box))
        return
    end
    local x, y = ReadHandleOffsets(handle)
    local help = PreviewGuidesVisible(box)
        and TR("arrows nudge, Shift=5, Ctrl=10 - Ctrl+left drag pans")
        or TR("guides hidden - arrows still nudge selected element")
    box.hint:SetText(format("%s   x: %d   y: %d   %s", TR(handle._label or handle._key or "?"), x, y, help))
end
local function RefreshHandleSelectionVisuals(box)
    if not box then return end
    local guidesOn = PreviewGuidesVisible(box)
    local selected = box._selectedHandle
    if selected and selected.IsShown and not selected:IsShown() then selected = nil; box._selectedHandle = nil end
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
        end
    end
    UpdateHandleHint(box, selected)
end
local function ApplyCastbarRuntimeForKey(key)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(key)
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then _G.MSUF_SyncCastbarPositionPopup(key) end
end
local function RequestPreviewLayoutRefresh(box, reason)
    if not box then return end
    if type(Preview.RequestRefreshForBox) == "function" then
        Preview.RequestRefreshForBox(box, reason)
    elseif type(Preview.RequestRefresh) == "function" and (not Preview.active or Preview.active == box) then
        Preview.RequestRefresh(reason)
    elseif type(Preview.Refresh) == "function" then
        Preview.Refresh(box, reason)
    end
end
local function CommitHandleMove(handle, reason)
    if not handle then return end
    local box = handle._preview
    local fields = handle._fields or {}
    local _, _, key = UnitDB(box and box.key)
    if fields.text then
        ForceTextUnit(key, reason or "UNIT_PREVIEW_MOVE")
    elseif fields.portrait then
        ApplyPortrait(box and box._msufPanel, key, reason or "UNIT_PREVIEW_PORTRAIT_MOVE")
    elseif fields.detachedPower then
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true) end
    elseif fields.castbar then
        ApplyCastbarRuntimeForKey(key)
    elseif fields.statusRefresh then
        local fn = _G[fields.statusRefresh]
        if type(fn) == "function" then fn() end
    end
    ApplyPanelUnit(box and box._msufPanel, key, reason or "UNIT_PREVIEW_MOVE")
    RequestPreviewLayoutRefresh(box, reason or "UNIT_PREVIEW_MOVE")
    RefreshHandleSelectionVisuals(box)
end
local function EnsureBarsDB()
    ExportPublic("MSUF_DB", _G.MSUF_DB or {})
    _G.MSUF_DB.bars = _G.MSUF_DB.bars or {}
    return _G.MSUF_DB.bars
end
local function ReadBarsHandleOffsets(handle)
    local fields = handle and handle._fields or {}
    local bars = (_G.MSUF_DB and _G.MSUF_DB.bars) or {}
    local xKey, yKey = fields.barsX, fields.barsY
    local x = xKey and tonumber(bars[xKey]) or nil
    local y = yKey and tonumber(bars[yKey]) or nil
    if x == nil then x = tonumber(fields.defaultX) or 0 end
    if y == nil then y = tonumber(fields.defaultY) or 0 end
    return x, y, xKey, yKey
end
local function RefreshClassPowerRuntime(box, reason)
    if type(_G.MSUF_ClassPower_Refresh) == "function" then _G.MSUF_ClassPower_Refresh() end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true) end
    ApplyPanelUnit(box and box._msufPanel, "player", reason or "UNIT_PREVIEW_CLASS_POWER_MOVE")
end
local function WriteBarsHandleOffsets(handle, x, y, reason)
    local fields = handle and handle._fields or {}
    local xKey, yKey = fields.barsX, fields.barsY
    if not xKey or not yKey then return false end
    local bars = EnsureBarsDB()
    bars[xKey] = RoundOffset(x)
    bars[yKey] = RoundOffset(y)
    if fields.classPower then RefreshClassPowerRuntime(handle and handle._preview, reason) end
    return true
end
local function RefreshCastbarRuntime(box, key, reason)
    ApplyCastbarRuntimeForKey(key)
    ApplyPanelUnit(box and box._msufPanel, key, reason or "UNIT_PREVIEW_CASTBAR_ELEMENT_MOVE")
end
local function CastbarSubOffsetKey(unitKey, suffix, bossKey)
    unitKey = CanonKey(unitKey)
    if unitKey == "boss" then return bossKey end
    local prefix = PreviewCastbar.Prefix and PreviewCastbar.Prefix(unitKey) or nil
    return prefix and (prefix .. suffix) or nil
end
local function CastbarDefaultFromG(g, fields, axis)
    local key = axis == "x" and fields.defaultXFromG or fields.defaultYFromG
    local fallback = axis == "x" and fields.defaultX or fields.defaultY
    if key and g and tonumber(g[key]) ~= nil then return tonumber(g[key]) end
    return tonumber(fallback) or 0
end
local function ReadCastbarSubOffsets(handle)
    local fields = handle and handle._fields or {}
    local box = handle and handle._preview
    local _, g, key = UnitDB(box and box.key)
    local xKey = CastbarSubOffsetKey(key, fields.suffixX, fields.bossX)
    local yKey = CastbarSubOffsetKey(key, fields.suffixY, fields.bossY)
    local x = xKey and g and tonumber(g[xKey]) or nil
    local y = yKey and g and tonumber(g[yKey]) or nil
    if CanonKey(key) == "boss" and fields.bossBaseX ~= nil then x = (tonumber(fields.bossBaseX) or 0) + (x or 0) end
    if CanonKey(key) == "boss" and fields.bossBaseY ~= nil then y = (tonumber(fields.bossBaseY) or 0) + (y or 0) end
    if x == nil and fields.iconFallback and fields.suffixX then x = g and tonumber(g[fields.suffixX:gsub("^Icon", "castbarIcon")]) or nil end
    if y == nil and fields.iconFallback and fields.suffixY then y = g and tonumber(g[fields.suffixY:gsub("^Icon", "castbarIcon")]) or nil end
    if x == nil then x = CastbarDefaultFromG(g, fields, "x") end
    if y == nil then y = CastbarDefaultFromG(g, fields, "y") end
    return x, y, xKey, yKey
end
local function WriteCastbarSubOffsets(handle, x, y, reason)
    local fields = handle and handle._fields or {}
    local box = handle and handle._preview
    local _, g, key = UnitDB(box and box.key)
    local xKey = CastbarSubOffsetKey(key, fields.suffixX, fields.bossX)
    local yKey = CastbarSubOffsetKey(key, fields.suffixY, fields.bossY)
    if not xKey or not yKey then return false end
    if CanonKey(key) == "boss" and fields.bossBaseX ~= nil then x = (tonumber(x) or 0) - (tonumber(fields.bossBaseX) or 0) end
    if CanonKey(key) == "boss" and fields.bossBaseY ~= nil then y = (tonumber(y) or 0) - (tonumber(fields.bossBaseY) or 0) end
    g[xKey] = RoundOffset(x)
    g[yKey] = RoundOffset(y)
    RefreshCastbarRuntime(box, key, reason)
    return true
end
local function MenuHistoryLabel(handle, action)
    local label = handle and (handle._label or handle._key) or "Preview element"
    return tostring(action or "Move") .. ": " .. tostring(label or "Preview element")
end
local function MenuHistorySource(handle, action)
    local box = handle and handle._preview
    return "unitPreview:" .. tostring(box and box.key or "unit") .. ":" .. tostring(handle and handle._key or "handle") .. ":" .. tostring(action or "move")
end
local function BeginMenuHistory(handle, action)
    local h = _G.MSUF2
    if not (h and type(h.BeginHistoryTransaction) == "function") then return false end
    return h.BeginHistoryTransaction(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action))
end
local function CommitMenuHistory()
    local h = _G.MSUF2
    if h and type(h.CommitHistoryTransaction) == "function" then return h.CommitHistoryTransaction() end
    return false
end
local function CheckpointMenuHistory(handle, action)
    local h = _G.MSUF2
    if h and type(h.CheckpointHistory) == "function" then return h.CheckpointHistory(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action)) end
    return false
end
local function WriteHandleOffsets(handle, x, y, reason)
    if not handle then return false end
    local box = handle._preview
    local fields = handle._fields or {}
    if type(fields.writeOffsets) == "function" then
        if not fields.writeOffsets(handle, x, y, reason) then return false end
        local fastDrag = reason == "UNIT_PREVIEW_DRAG"
            and fields.visualOnly == true
            and type(fields.dragOffsets) == "function"
            and fields.dragOffsets(handle, x, y) == true
        if not fastDrag then RequestPreviewLayoutRefresh(box, reason or "UNIT_PREVIEW_MOVE") end
        RefreshHandleSelectionVisuals(box)
        if not handle._msuf2PreviewHistoryTx then CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move") end
        return true
    end
    local xKey, yKey = ResolveHandleFields(box, fields)
    if not xKey or not yKey then return false end
    local store = HandleStore(box, fields)
    store[xKey] = RoundOffset(x)
    store[yKey] = RoundOffset(y)
    CommitHandleMove(handle, reason)
    if not handle._msuf2PreviewHistoryTx then CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move") end
    return true
end
local function ShouldSkipDuplicateNudge(box, dx, dy)
    return PreviewHelpers.ShouldSkipDuplicateNudge and PreviewHelpers.ShouldSkipDuplicateNudge(box, dx, dy) or false
end
local function NudgeSelectedHandle(box, dx, dy)
    local h = box and box._selectedHandle
    if not h or not h.IsShown or not h:IsShown() then return false end
    local x, y = ReadHandleOffsets(h)
    local step = GetNudgeStep()
    local ndx, ndy = dx * step, dy * step
    if ShouldSkipDuplicateNudge(box, ndx, ndy) then return true end
    return WriteHandleOffsets(h, x + ndx, y + ndy, "UNIT_PREVIEW_NUDGE")
end
local function NudgeSelectedHandleDelta(box, dx, dy)
    local h = box and box._selectedHandle
    if not h or not h.IsShown or not h:IsShown() then return false end
    local x, y = ReadHandleOffsets(h)
    local ndx, ndy = tonumber(dx) or 0, tonumber(dy) or 0
    if ShouldSkipDuplicateNudge(box, ndx, ndy) then return true end
    return WriteHandleOffsets(h, x + ndx, y + ndy, "UNIT_PREVIEW_EM2_NUDGE")
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
    getActive = function() return _G.MSUF_UFPreview_ActiveNudgeBox or Preview.active end,
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
local TEXT_HANDLE_SELECTION = {
    name = { "name" },
    hp = { "hp" }, hpLeft = { "hp", "left" }, hpCenter = { "hp", "center" }, hpRight = { "hp", "right" },
    power = { "power" }, powerLeft = { "power", "left" }, powerCenter = { "power", "center" }, powerRight = { "power", "right" },
}
local function PreviewTextKindSlotForKey(key)
    local spec = TEXT_HANDLE_SELECTION[key]
    if spec then return spec[1], spec[2] end
end
local function StorePreviewTextSelection(menu, unitKey, kind, slot)
    if not (menu and (kind == "hp" or kind == "power")) then return end
    unitKey = unitKey or "player"
    UnitPreviewSetTextMoveTogether(unitKey, kind, slot == nil)
    menu.unitTextTabSelection = menu.unitTextTabSelection or {}
    menu.unitTextTabSelection[unitKey] = kind
    if slot then
        menu.unitTextSlotSelection = menu.unitTextSlotSelection or {}
        menu.unitTextSlotSelection[unitKey] = menu.unitTextSlotSelection[unitKey] or {}
        menu.unitTextSlotSelection[unitKey][kind] = slot
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
        local menu = _G.MSUF2
        RegisterPreviewNudgeTarget(box)
        if fields.statusRefresh then
            Preview.selectedStatusId = NormalizeStatusPreviewId(handle._key)
            if not skipSectionOpen and p and type(p._msufUFStatusSet) == "function" then p._msufUFStatusSet("selected", handle._key) end
        end
        local textKind, textSlot = PreviewTextKindSlotForKey(handle._key)
        StorePreviewTextSelection(menu, box.key, textKind, textSlot)
        if menu and (handle._key == "auraBuffs" or handle._key == "auraDebuffs") then
            menu.unitAuraTabSelection = menu.unitAuraTabSelection or {}
            menu.unitAuraTabSelection[box.key or "player"] = handle._key == "auraDebuffs" and "debuff" or "buff"
        end
        do
            local focus = _G.MSUF_EM2_SetFocusSelection
            if type(focus) == "function" then
                local kind, slot = PreviewTextKindSlotForKey(handle._key)
                if kind then focus(box.key or "player", kind, slot, { source = "unit-preview", clearHover = true }) end
            end
        end
        FocusPreviewKeyboardTarget(box, handle, true)
    end
    RefreshHandleSelectionVisuals(box)
end
local NormalizePreviewTextFocusKind = PreviewHelpers.NormalizeTextFocusKind or function(kind)
    if kind == "name" or kind == "hp" or kind == "power" then return kind end
    return nil
end
local NormalizePreviewTextFocusSlot = PreviewHelpers.NormalizeTextFocusSlot or function(slot)
    if slot == "left" or slot == "center" or slot == "right" then return slot end
    return nil
end
local function PreviewTextFocusRegions(mock, kind, slot)
    if not mock then return nil end
    if kind == "name" then
        return { mock.nameText, mock.totInlineSep, mock.totInlineText, mock.raidGroupNameText }
    elseif kind == "hp" then
        if slot == "left" then return { mock.hpTextLeft } end
        if slot == "center" then return { mock.hpTextCenter } end
        if slot == "right" then return { mock.hpText } end
        return { mock.hpTextLeft, mock.hpTextCenter, mock.hpText }
    elseif kind == "power" then
        if slot == "left" then return { mock.powerTextLeft } end
        if slot == "center" then return { mock.powerTextCenter } end
        if slot == "right" then return { mock.powerText } end
        return { mock.powerTextLeft, mock.powerTextCenter, mock.powerText }
    end
    return nil
end
local function ApplyPreviewTextFocus(box, canvas, mock)
    return PreviewHelpers.ApplyTextFocus(box, canvas, mock, {
        Regions = PreviewTextFocusRegions,
        Place = UnitPreviewText.PlaceHandleAroundRegions,
    })
end
function Preview.FocusTextSlot(unitKey, kind, slot, active)
    local box = Preview.active
    if not (box and box.IsShown and box:IsShown()) then return false end
    local targetKey = CanonKey(unitKey or box.key or "player")
    local boxKey = CanonKey(box.key or targetKey)
    if targetKey and boxKey and targetKey ~= boxKey then return false end
    kind = NormalizePreviewTextFocusKind(kind)
    slot = NormalizePreviewTextFocusSlot(slot)
    if not kind then
        box._msufMenuTextFocus = nil
        if type(Preview.RequestRefresh) == "function" then
            Preview.RequestRefresh("MENU_TEXT_CLEAR_FOCUS")
        else
            Preview.Refresh(box, "MENU_TEXT_CLEAR_FOCUS")
        end
        return true
    end
    box._msufMenuTextFocus = {
        kind = kind,
        slot = slot,
        active = active == true,
    }
    if type(Preview.RequestRefresh) == "function" then
        Preview.RequestRefresh("MENU_TEXT_FOCUS")
    else
        Preview.Refresh(box, "MENU_TEXT_FOCUS")
    end
    return true
end
ExportPublic("MSUF_UFPreview_FocusTextSlot", function(unitKey, kind, slot, active)
    return Preview.FocusTextSlot(unitKey, kind, slot, active)
end)
ExportPublic("MSUF_UFPreview_ClearTextFocus", function()
    return Preview.FocusTextSlot(nil, nil, nil, false)
end)
local function PreviewArrowKeyDown(self, keyName)
    if PreviewHelpers.ArrowKeyDown then
        return PreviewHelpers.ArrowKeyDown(self, keyName, {
            active = function() return Preview.active end,
            selectedField = "_selectedHandle",
            nudge = NudgeSelectedHandle,
        })
    end
end
local StartPreviewPan, StopPreviewPan
local HANDLE_BORDER_SPECS = {
    top = { "TOPLEFT", "TOPRIGHT", "SetHeight" },
    bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
    left = { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
    right = { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
}
local function MakeHandle(preview, key, fields, label, color)
    local h = CreateFrame("Button", nil, preview.canvas)
    h:SetFrameLevel((preview.canvas:GetFrameLevel() or 0) + 30)
    h:SetSize(20, 20)
    h:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    if h.RegisterForDrag then h:RegisterForDrag("LeftButton") end
    h:EnableMouse(true)
    h:EnableKeyboard(true)
    if h.SetPropagateKeyboardInput then h:SetPropagateKeyboardInput(true) end
    h.tex = h:CreateTexture(nil, "OVERLAY")
    h.tex:SetAllPoints()
    h.tex:SetColorTexture(color[1], color[2], color[3], 0)
    h.edge = h:CreateTexture(nil, "BORDER")
    h.edge:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
    h.edge:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    h.edge:SetColorTexture(color[1], color[2], color[3], 0)
    h._label = label
    h._fields = fields
    h._key = key
    h._preview = preview
    h._color = color
    h._selBorder = CreateFrame("Frame", nil, h)
    h._selBorder:SetPoint("TOPLEFT", h, "TOPLEFT", -1, 1)
    h._selBorder:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 1, -1)
    for side, spec in pairs(HANDLE_BORDER_SPECS) do
        local line = h._selBorder:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0.30, 0.58, 0.95, 0.70)
        line:SetPoint(spec[1])
        line:SetPoint(spec[2])
        line[spec[3]](line, 1)
        h._selBorder[side] = line
    end
    h._selBorder:Hide()
    h:SetScript("OnEnter", function(self)
        self._hovering = true
        RefreshHandleSelectionVisuals(preview)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR(label), 1, 1, 1)
            GameTooltip:AddLine(TR("Drag this preview element to adjust the same X/Y offsets used by Edit Mode."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Arrow keys nudge the selected element. Shift = 5, Ctrl = 10."), 0.55, 0.62, 0.72, true)
            GameTooltip:AddLine(TR("Ctrl + left-drag pans the preview canvas without moving this element."), 0.55, 0.68, 0.86, true)
            GameTooltip:Show()
        end
    end)
    h:SetScript("OnLeave", function(self)
        self._hovering = nil
        RefreshHandleSelectionVisuals(preview)
        if GameTooltip then GameTooltip:Hide() end
    end)
    h:SetScript("OnClick", function(self)
        if self._suppressNextClick then
            self._suppressNextClick = nil
            return
        end
        SelectPreviewHandle(self)
    end)
    local function StartHandleDrag(self, button)
        if button and button ~= "LeftButton" then return end
        if self._dragging == true or preview.dragFrame._handle == self or (preview.canvas and preview.canvas._msufPreviewPanning) then return true end
        if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and StartPreviewPan and StartPreviewPan(preview.canvas, preview, button) then
            self._suppressNextClick = true
            return
        end
        SelectPreviewHandle(self, true)
        local x, y = ReadHandleOffsets(self)
        self._startX = x
        self._startY = y
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragging = true
        preview._dragFrozenScale = tonumber(preview._mockScale) or tonumber(preview._mockAutoScale) or 1
        self._msuf2PreviewHistoryTx = BeginMenuHistory(self, "Move")
        local cx, cy = GetCursorPosition()
        self._cursorX, self._cursorY = cx, cy
        self._dragPoint, self._dragRelTo, self._dragRelPoint, self._dragOffsetX, self._dragOffsetY = self:GetPoint(1)
        preview.dragFrame._handle = self
        if preview.dragFrame.SetAllPoints then preview.dragFrame:SetAllPoints(preview.canvas) end
        preview.dragFrame:SetScript("OnUpdate", preview._onDragUpdate)
        preview.dragFrame:SetScript("OnMouseUp", function(df, upButton)
            local activeHandle = df and df._handle
            local stop = activeHandle and activeHandle.GetScript and activeHandle:GetScript("OnMouseUp")
            if type(stop) == "function" then stop(activeHandle, upButton) end
        end)
        preview.dragFrame:Show()
        RefreshHandleSelectionVisuals(preview)
    end
    local function StopHandleDrag(self, button)
        if StopPreviewPan and preview.canvas and preview.canvas._msufPreviewPanning then StopPreviewPan(preview.canvas) end
        if button and button ~= "LeftButton" then return end
        local wasDragging = self._dragging == true or preview.dragFrame._handle == self
        if not wasDragging then return end
        if preview.dragFrame._handle == self then
            preview.dragFrame:SetScript("OnUpdate", nil)
            preview.dragFrame:SetScript("OnMouseUp", nil)
            preview.dragFrame._handle = nil
            preview.dragFrame:Hide()
        end
        local fields = self._fields or {}
        if type(fields.commitOffsets) == "function" then fields.commitOffsets(self, "UNIT_PREVIEW_DRAG_END") end
        if self._msuf2PreviewHistoryTx then
            self._msuf2PreviewHistoryTx = nil
            CommitMenuHistory()
        end
        local hadFrozenScale = preview._dragFrozenScale ~= nil
        preview._dragFrozenScale = nil
        if type(fields.clearDragOffsets) == "function" then fields.clearDragOffsets(self) end
        self._dragging = nil
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragPoint = nil
        self._dragRelTo = nil
        self._dragRelPoint = nil
        self._dragOffsetX = nil
        self._dragOffsetY = nil
        RefreshHandleSelectionVisuals(preview)
        if hadFrozenScale and not preview._manualZoom then RequestPreviewLayoutRefresh(preview, "UNIT_PREVIEW_DRAG_END") end
    end
    h:SetScript("OnMouseDown", StartHandleDrag)
    h:SetScript("OnMouseUp", StopHandleDrag)
    h:SetScript("OnDragStart", StartHandleDrag)
    h:SetScript("OnDragStop", StopHandleDrag)
    h:SetScript("OnHide", StopHandleDrag)
    h:SetScript("OnKeyDown", PreviewArrowKeyDown)
    h:Hide()
    preview.handles[#preview.handles + 1] = h
    return h
end
local CreateIcon = PreviewStatus.CreateIcon
local SetPreviewIconTexture = PreviewStatus.SetIconTexture
local ResolveStatusPreviewAnchor = PreviewStatus.ResolveAnchor
local MenuTheme = PreviewCore.MenuTheme
local ApplyPreviewBackdrop = PreviewCore.ApplyBackdrop
local PreviewBaseEdgeColor = PreviewCore.BaseEdgeColor
local STATUS_PREVIEW = (MSUF.UFPreviewSpecs and MSUF.UFPreviewSpecs.StatusPreview) or {}
local PREVIEW_LAYERS = (MSUF.UFPreviewSpecs and MSUF.UFPreviewSpecs.PreviewLayers) or {}
local ZOOM_MIN = tonumber(PreviewZoomPan.MIN) or 0.35
if PreviewZoomPan.Configure then PreviewZoomPan.Configure({ Preview = Preview, TR = TR, TEX_W8 = TEX_W8, UpdateHandleHint = UpdateHandleHint }) end
local function ZoomOrOne(v) return tonumber(v) or 1 end
local ClampPreviewZoom = PreviewZoomPan.Clamp or ZoomOrOne
local UpdatePreviewZoomControls = PreviewZoomPan.UpdateControls or F.Noop
local SetPreviewZoom = PreviewZoomPan.SetZoom or F.Noop
local StepPreviewZoom = PreviewZoomPan.Step or F.Noop
StartPreviewPan = PreviewZoomPan.Start or StartPreviewPan
StopPreviewPan = PreviewZoomPan.Stop or StopPreviewPan
local function BuildPreview(parent, panel, width, height)
    local sideW = 72
    local T = MenuTheme()
    local colors = (T and T.colors) or {}
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width or 632, height or 228)
    ApplyPreviewBackdrop(
        box,
        colors.panel2 or { 0.035, 0.043, 0.058, 0.96 },
        colors.border or { 0.19, 0.25, 0.34, 0.95 }
    )
    box._msufStaticH = height or 228
    box._msufPanel = panel
    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    title:SetText(TR("Unit Frame Preview"))
    box.title = title
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetText(DefaultPreviewHint())
    box.hint = hint
    local canvas = CreateFrame("Frame", nil, box, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(sideW + 18), 12)
    ApplyPreviewBackdrop(
        canvas,
        { 0, 0, 0, 1 },
        colors.borderSoft or { 1, 1, 1, 0.06 },
        { backdrop = { bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 }, bg = { 0.01, 0.012, 0.018, 0.86 } }
    )
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    if canvas.SetPropagateMouseWheel then canvas:SetPropagateMouseWheel(true) end
    box.canvas = canvas
    PreviewHelpers.BuildZoomBar(box, canvas, {
        texture = TEX_W8,
        CreateZoomButton = PreviewZoomPan.CreateButton,
        Tr = TR,
        StepZoom = StepPreviewZoom,
        SetZoom = SetPreviewZoom,
        StartPan = StartPreviewPan,
        StopPan = StopPreviewPan,
        fitReason = "UNIT_PREVIEW_ZOOM_FIT",
        oneReason = "UNIT_PREVIEW_ZOOM_1TO1",
    })
    local sidebar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", canvas, "TOPRIGHT", 6, 0)
    sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    ApplyPreviewBackdrop(
        sidebar,
        colors.panel or { 0.025, 0.028, 0.04, 0.82 },
        colors.borderSoft or { 0.10, 0.13, 0.18, 0.65 },
        { backdrop = { bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 } }
    )
    box.sidebar = sidebar
    local sHdr = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sHdr:SetPoint("TOP", sidebar, "TOP", 0, -5)
    sHdr:SetText(TR("LAYERS"))
    sHdr:SetTextColor(0.45, 0.50, 0.62, 0.8)
    box.layerVisibility = {}
    box.layerButtons = {}
    local function UnitLayerAvailable(owner, key)
        return not (owner and owner.layerAvailable and owner.layerAvailable[key] == false)
    end
    local unitLayerButtonOpts = {
        Tr = TR,
        IsAvailable = UnitLayerAvailable,
        IsOn = function(owner, key) return UnitLayerAvailable(owner, key) and owner.layerVisibility[key] ~= false end,
        OnClick = function(self, owner)
            if owner.layerAvailable and owner.layerAvailable[self.key] == false then
                owner.hint:SetText(TR("This layer is off in settings and cannot be shown in preview."))
                return
            end
            owner.layerVisibility[self.key] = owner.layerVisibility[self.key] == false
            if self.key == "guides" then SetPreviewGuidesEnabled(owner.layerVisibility[self.key] ~= false) end
            for j = 1, #owner.layerButtons do owner.layerButtons[j]:refresh() end
            RequestPreviewLayoutRefresh(owner, "UNIT_PREVIEW_LAYER")
            RefreshHandleSelectionVisuals(owner)
        end,
        OnEnter = function(self, owner, available, on, tr)
            if not available then
                self.bg:SetColorTexture(0.045, 0.045, 0.055, 0.62)
                self.fs:SetTextColor(0.42, 0.42, 0.48, 0.75)
                owner.hint:SetText(TR("This layer is off in settings and cannot be shown in preview."))
                return
            end
            if GameTooltip and self.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tr(self.fs and self.fs:GetText() or self.key), 1, 1, 1)
                GameTooltip:AddLine(tr(self.tooltip), 0.82, 0.82, 0.82, true)
                if self.key == "guides" then GameTooltip:AddLine(tr(on and "Turn off to inspect the frame without mover outlines. The selected element can still be nudged with arrow keys." or "Guides are hidden. Turn this back on to see drag handles and selected borders."), 0.55, 0.68, 0.86, true) end
                GameTooltip:Show()
            elseif GameTooltip then
                GameTooltip:Hide()
            end
        end,
        OnLeave = function(_, owner) UpdateHandleHint(owner, owner._selectedHandle) end,
    }
    for i = 1, #PREVIEW_LAYERS do
        local def = PREVIEW_LAYERS[i]
        box.layerVisibility[def.key] = (def.key == "guides") and PreviewGuidesEnabled() or true
        local btn = PreviewHelpers.CreateLayerButton(sidebar, box, def, i, sideW, unitLayerButtonOpts)
        if M2.AddTooltip then
            M2.AddTooltip(btn, "Layer disabled", "Turn this feature on in settings to make the preview layer available.", {
                hook = true,
                enabled = function(self) return UnitLayerAvailable(box, self.key) == false end,
            })
        end
        box.layerButtons[#box.layerButtons + 1] = btn
    end
    local mock = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock:SetBackdropColor(0, 0, 0, 0.92)
    do
        local r, g, b = PreviewBaseEdgeColor()
        mock:SetBackdropBorderColor(r, g, b, 1)
    end
    box.mock = mock
    local function MockTexture(field, layer, texture, color, mode)
        local tex = mock:CreateTexture(nil, layer)
        if mode == "settex" then SetTex(tex, texture or TEX_W8) else tex:SetTexture(texture or TEX_W8) end
        if color then
            if mode == "color" then tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
            else tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
        end
        mock[field] = tex
        return tex
    end
    local function FillFrame(parentFrame)
        local frame = CreateFrame("Frame", nil, parentFrame)
        frame:SetAllPoints(parentFrame)
        return frame
    end
    local function MakeTextSet(layer, ...)
        for i = 1, select("#", ...) do
            mock[select(i, ...)] = MakeFS(layer, "OVERLAY", 12)
        end
    end
    mock.bounds = CreateFrame("Frame", nil, mock, "BackdropTemplate")
    mock.bounds:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.bounds:SetBackdropColor(0, 0, 0, 0)
    mock.bounds:SetBackdropBorderColor(1, 0.14, 0.08, 0.95)
    mock.bounds:SetFrameLevel((mock:GetFrameLevel() or 0) + 28)
    mock.bounds:SetAllPoints(mock)
    mock.sizeTag = mock.bounds:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.sizeTag:SetPoint("BOTTOM", mock.bounds, "TOP", 0, 2)
    mock.sizeTag:SetTextColor(1, 0.35, 0.25, 0.95)
    MockTexture("hpBG", "BACKGROUND", TEX_W8, { 0, 0, 0, 0.82 }, "color")
    MockTexture("hp", "ARTWORK", type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8, nil, "settex")
    MockTexture("healPred", "ARTWORK", TEX_W8, { 0, 1, 0.4, 0.55 })
    MockTexture("absorb", "ARTWORK", TEX_W8, { 0.55, 0.70, 1, 0.58 })
    MockTexture("powerBG", "BACKGROUND", TEX_W8, { 0, 0, 0, 0.9 }, "color")
    MockTexture("power", "ARTWORK", type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8, nil, "settex")
    mock.classPower = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.classPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.classPower:SetBackdropColor(0, 0, 0, 0.55)
    mock.classPower:SetBackdropBorderColor(0, 0, 0, 1)
    mock.classPower.segments = {}
    mock.classPower.segmentBgs = {}
    mock.classPower.segmentEdges = {}
    mock.classPower.runeTexts = {}
    local function ClassPowerTexture(bucket, index, layer, subLevel, hidden)
        local tex = mock.classPower:CreateTexture(nil, layer, nil, subLevel)
        tex:SetTexture(TEX_W8)
        if hidden ~= false then tex:Hide() end
        mock.classPower[bucket][index] = tex
        return tex
    end
    for i = 1, 10 do
        ClassPowerTexture("segmentBgs", i, "BACKGROUND")
        ClassPowerTexture("segments", i, "ARTWORK", nil, false)
        ClassPowerTexture("segmentEdges", i, "OVERLAY")
        local rfs = MakeFS(mock.classPower, "OVERLAY", 8)
        rfs:SetJustifyH("CENTER")
        if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
        if rfs.SetShadowColor then rfs:SetShadowColor(0, 0, 0, 1) end
        if rfs.SetShadowOffset then rfs:SetShadowOffset(1, -1) end
        rfs:Hide()
        mock.classPower.runeTexts[i] = rfs
    end
    mock.classPower.text = MakeFS(mock.classPower, "OVERLAY", 12)
    mock.classPower.text:SetJustifyH("CENTER")
    if mock.classPower.text.SetJustifyV then mock.classPower.text:SetJustifyV("MIDDLE") end
    mock.classPower.text:SetPoint("CENTER", mock.classPower, "CENTER", 0, 0)
    mock.classPower.text:SetText("5")
    mock.classPower.text:Hide()
    mock.detachedPower = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.detachedPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.detachedPower:SetBackdropColor(0, 0, 0, 0.82)
    mock.detachedPower:SetBackdropBorderColor(0, 0, 0, 1)
    mock.detachedPower.bg = mock.detachedPower:CreateTexture(nil, "BACKGROUND")
    mock.detachedPower.bg:SetAllPoints(mock.detachedPower)
    mock.detachedPower.bg:SetTexture(TEX_W8)
    mock.detachedPower.bg:SetVertexColor(0, 0, 0, 0)
    mock.detachedPower.fill = mock.detachedPower:CreateTexture(nil, "ARTWORK")
    SetTex(mock.detachedPower.fill, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    mock.detachedPower.fill:SetPoint("TOPLEFT", mock.detachedPower, "TOPLEFT", 1, -1)
    mock.detachedPower.fill:SetPoint("BOTTOMLEFT", mock.detachedPower, "BOTTOMLEFT", 1, 1)
    mock.detachedPower.edge = mock.detachedPower:CreateTexture(nil, "OVERLAY")
    mock.detachedPower.edge:SetAllPoints(mock.detachedPower)
    mock.detachedPower.edge:SetTexture(TEX_W8)
    mock.detachedPower.edge:SetVertexColor(0, 0, 0, 1)
    mock.detachedPower.edge:Hide()
    mock.portrait = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.portrait:SetBackdrop({ bgFile = TEX_W8 })
    mock.portrait:SetBackdropColor(0, 0, 0, 0)
    mock.portrait.bg = mock.portrait:CreateTexture(nil, "BACKGROUND")
    mock.portrait.bg:SetAllPoints()
    mock.portrait.bg:SetTexture(TEX_W8)
    mock.portrait.bg:Hide()
    mock.portrait.tex = mock.portrait:CreateTexture(nil, "ARTWORK")
    mock.portrait.tex:SetAllPoints()
    mock.portrait.border = CreateFrame("Frame", nil, mock.portrait)
    mock.portrait.border:SetAllPoints()
    mock.portrait.border.edges = {}
    mock.portrait.initial = MakeFS(mock.portrait, "OVERLAY", 22)
    mock.portrait.initial:SetPoint("CENTER")
    mock.textFrame = FillFrame(mock)
    mock.nameLayer = FillFrame(mock.textFrame)
    mock.hpLayer = FillFrame(mock.textFrame)
    mock.powerLayer = FillFrame(mock.textFrame)
    MakeTextSet(mock.nameLayer, "nameText", "raidGroupNameText", "totInlineSep", "totInlineText")
    MakeTextSet(mock.hpLayer, "hpTextLeft", "hpTextCenter", "hpText", "hpTextPct")
    MakeTextSet(mock.powerLayer, "powerTextLeft", "powerTextCenter", "powerText", "powerTextPct")
    mock.cast = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.cast:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.cast:SetBackdropColor(0, 0, 0, 0.92)
    mock.cast:SetBackdropBorderColor(0, 0, 0, 1)
    mock.cast:EnableMouse(true)
    mock.cast:SetScript("OnMouseDown", function(_, button)
        StartPreviewPan(canvas, box, button)
    end)
    mock.cast:SetScript("OnMouseUp", function(_, button)
        if canvas._msufPreviewPanning then
            StopPreviewPan(canvas)
            return
        end
        if button and button ~= "LeftButton" then return end
    end)
    mock.cast:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Castbar"), 1, 1, 1)
            GameTooltip:AddLine(TR("Preview follows the current castbar visibility, icon, text, and global color settings."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Ctrl + left-drag pans the preview canvas."), 0.55, 0.68, 0.86, true)
            GameTooltip:Show()
        end
    end)
    mock.cast:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    mock.cast.fill = mock.cast:CreateTexture(nil, "ARTWORK")
    SetTex(mock.cast.fill, type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture() or TEX_W8)
    mock.cast.fill:SetPoint("TOPLEFT", 1, -1)
    mock.cast.fill:SetPoint("BOTTOMRIGHT", -60, 1)
    mock.cast.icon = CreateFrame("Frame", nil, mock.cast, "BackdropTemplate")
    mock.cast.icon:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.cast.icon:SetBackdropColor(0.08, 0.12, 0.22, 1)
    mock.cast.icon:SetBackdropBorderColor(0.2, 0.28, 0.40, 1)
    mock.cast.text = MakeFS(mock.cast, "OVERLAY", 11)
    mock.cast.text:SetPoint("LEFT", mock.cast, "LEFT", 24, 0)
    mock.cast.time = MakeFS(mock.cast, "OVERLAY", 11)
    mock.cast.time:SetPoint("RIGHT", mock.cast, "RIGHT", -6, 0)
    mock.cast.sizeTag = mock.cast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.cast.sizeTag:SetPoint("BOTTOM", mock.cast, "TOP", 0, 2)
    mock.cast.sizeTag:SetTextColor(0.20, 0.90, 0.85, 0.95)
    mock.icons = {}
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        mock.icons[spec.id] = CreateIcon(canvas, spec.color, spec.text)
    end
    box.handles = {}
    box.dragFrame = CreateFrame("Frame", nil, canvas)
    box.dragFrame:EnableMouse(true)
    box.dragFrame:Hide()
    box._onDragUpdate = function(df)
        local h = df._handle
        if not h then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            local stop = h.GetScript and h:GetScript("OnMouseUp")
            if type(stop) == "function" then stop(h, "LeftButton") end
            return
        end
        local cx, cy = GetCursorPosition()
        local scale = box._mockEffectiveScale or box._mockScale or 1
        local uiScale = (box.canvas and box.canvas.GetEffectiveScale and box.canvas:GetEffectiveScale())
            or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
            or 1
        if uiScale <= 0 then uiScale = 1 end
        local dx = (((cx or 0) - (h._cursorX or 0)) / uiScale) / scale
        local dy = (((cy or 0) - (h._cursorY or 0)) / uiScale) / scale
        local nextX = RoundOffset((h._startX or 0) + dx)
        local nextY = RoundOffset((h._startY or 0) + dy)
        if h._lastDragX == nextX and h._lastDragY == nextY then return end
        h._lastDragX = nextX
        h._lastDragY = nextY
        WriteHandleOffsets(h, nextX, nextY, "UNIT_PREVIEW_DRAG")
    end
    box.handleName = MakeHandle(box, "name", { x = "nameOffsetX", y = "nameOffsetY", defaultX = 4, defaultY = -4, text = true, section = "text" }, "Name text", { 0.30, 0.66, 1.0 })
    box.handleRaidGroupName = MakeHandle(box, "raidgroupname", { x = "raidGroupNameOffsetX", y = "raidGroupNameOffsetY", defaultX = 3, defaultY = 0, statusRefresh = "MSUF_RefreshRaidGroupNameFrames", section = "status" }, "Raid group", { 0.45, 0.70, 1.0 })
    box.handleHP = MakeHandle(box, "hp", { x = "hpOffsetX", y = "hpOffsetY", defaultX = -4, defaultY = -4, text = true, section = "text" }, "HP text", { 0.25, 0.90, 0.42 })
    box.handleHPLeft = MakeHandle(box, "hpLeft", { x = "hpTextLeftOffsetX", y = "hpTextLeftOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "HP left text", { 0.25, 0.90, 0.42 })
    box.handleHPCenter = MakeHandle(box, "hpCenter", { x = "hpTextCenterOffsetX", y = "hpTextCenterOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "HP center text", { 0.25, 0.90, 0.42 })
    box.handleHPRight = MakeHandle(box, "hpRight", { x = "hpTextRightOffsetX", y = "hpTextRightOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "HP right text", { 0.25, 0.90, 0.42 })
    box.handlePower = MakeHandle(box, "power", { x = "powerOffsetX", y = "powerOffsetY", defaultX = -4, defaultY = 4, text = true, section = "text" }, "Power text", { 0.95, 0.72, 0.18 })
    box.handlePowerLeft = MakeHandle(box, "powerLeft", { x = "powerTextLeftOffsetX", y = "powerTextLeftOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "Power left text", { 0.95, 0.72, 0.18 })
    box.handlePowerCenter = MakeHandle(box, "powerCenter", { x = "powerTextCenterOffsetX", y = "powerTextCenterOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "Power center text", { 0.95, 0.72, 0.18 })
    box.handlePowerRight = MakeHandle(box, "powerRight", { x = "powerTextRightOffsetX", y = "powerTextRightOffsetY", defaultX = 0, defaultY = 0, text = true, section = "text" }, "Power right text", { 0.95, 0.72, 0.18 })
    box.handlePortrait = MakeHandle(box, "portrait", { x = "portraitOffsetX", y = "portraitOffsetY", defaultX = 0, defaultY = 0, portrait = true, section = "portrait" }, "Portrait", { 0.90, 0.42, 1.0 })
    box.handleDetachedPower = MakeHandle(box, "detachedPower", { x = "detachedPowerBarOffsetX", y = "detachedPowerBarOffsetY", defaultX = 0, defaultY = -4, detachedPower = true, section = "power" }, "Detached power bar", { 0.95, 0.72, 0.18 })
    box.handleClassPower = MakeHandle(box, "classPower", { barsX = "classPowerOffsetX", barsY = "classPowerOffsetY", defaultX = 0, defaultY = 0, classPower = true, readOffsets = ReadBarsHandleOffsets, writeOffsets = WriteBarsHandleOffsets, section = "classPower" }, "Class power", { 0.30, 0.78, 0.55 })
    box.handleClassPowerText = MakeHandle(box, "classPowerText", { barsX = "classPowerTextOffsetX", barsY = "classPowerTextOffsetY", defaultX = 0, defaultY = 0, classPower = true, readOffsets = ReadBarsHandleOffsets, writeOffsets = WriteBarsHandleOffsets, section = "classPower" }, "Class power text", { 0.30, 0.78, 0.55 })
    box.handleCastbar = MakeHandle(box, "castbar", { castbar = true, global = true, section = "castbar" }, "Castbar", { 0.20, 0.90, 0.85 })
    box.handleCastbarIcon = MakeHandle(box, "castbarIcon", { suffixX = "IconOffsetX", suffixY = "IconOffsetY", bossX = "bossCastIconOffsetX", bossY = "bossCastIconOffsetY", defaultX = 0, defaultY = 0, iconFallback = true, readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar" }, "Castbar icon", { 0.20, 0.90, 0.85 })
    box.handleCastbarText = MakeHandle(box, "castbarText", { suffixX = "TextOffsetX", suffixY = "TextOffsetY", bossX = "bossCastTextOffsetX", bossY = "bossCastTextOffsetY", defaultX = 0, defaultY = 0, readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar" }, "Castbar text", { 0.20, 0.90, 0.85 })
    box.handleCastbarTime = MakeHandle(box, "castbarTime", { suffixX = "TimeOffsetX", suffixY = "TimeOffsetY", bossX = "bossCastTimeOffsetX", bossY = "bossCastTimeOffsetY", bossBaseX = -2, defaultX = -2, defaultY = 0, defaultXFromG = "castbarPlayerTimeOffsetX", defaultYFromG = "castbarPlayerTimeOffsetY", readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar" }, "Castbar time", { 0.20, 0.90, 0.85 })
    if type(PreviewAuras.CreateHandles) == "function" then PreviewAuras.CreateHandles(box, MakeHandle) end
    box.statusHandles = { raidgroupname = box.handleRaidGroupName }
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        box.statusHandles[spec.id] = MakeHandle(box, spec.id, { x = spec.x, y = spec.y, defaultX = spec.defaultX or 0, defaultY = spec.defaultY or 0, statusRefresh = spec.refresh, section = "status" }, spec.label, spec.color)
    end
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", PreviewArrowKeyDown)
    box:SetScript("OnShow", function(self)
        Preview.active = self
        if self.RegisterEvent then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
        end
        Preview.RequestRefresh("SHOW")
    end)
    box:SetScript("OnHide", function(self)
        self._refreshSerial = (tonumber(self._refreshSerial) or 0) + 1
        self._refreshQueued = nil
        self._refreshReason = nil
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
        self._selectedHandle = nil
        Preview.SetArrowBindings(self, false)
        RefreshHandleSelectionVisuals(self)
        if Preview.active == self then Preview.active = nil end
        if type(Preview.UninstallRefreshHooks) == "function" then Preview.UninstallRefreshHooks() end
        self.dragFrame:SetScript("OnUpdate", nil)
        self.dragFrame:SetScript("OnMouseUp", nil)
        self.dragFrame._handle = nil
        if self._msufPreviewNudgeTarget and rawget(_G, "MSUF_EM2_ActivePreviewNudgeTarget") == self._msufPreviewNudgeTarget and type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
    end)
    box:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            Preview.RequestRefresh("COMBAT_ALPHA")
        elseif event == "PLAYER_REGEN_DISABLED" then
            box._refreshReason = nil
            box._refreshQueued = nil
        end
    end)
    return box
end
local CastbarEnabled = PreviewCastbar.Enabled
local CastbarShowIcon = PreviewCastbar.ShowIcon
local CastbarShowText = PreviewCastbar.ShowText
local PlaceHandle = PreviewCore.PlaceHandle
local SetShownSafe = PreviewCore.SetShownSafe
local PreviewRoundedOutlineThickness = PreviewCore.RoundedOutlineThickness
local ApplyPreviewRounded = PreviewCore.ApplyRounded
local ApplyPreviewFrameBorder = PreviewCore.ApplyFrameBorder
local ApplyPreviewBoundsGuide = PreviewCore.ApplyBoundsGuide
local ApplyPreviewLayerVisibility = PreviewCore.ApplyLayerVisibility
local PreviewInCombat = PreviewCore.InCombat
do
    local deps = Preview.RefreshDeps or {}
    Preview.RefreshDeps = deps
    AssignNamedValues(deps, [[
        PreviewInCombat TR PortraitStyleGet RuntimeSpecForPreviewKey RuntimeVisualScaleForPreviewKey ClampPreviewZoom UpdatePreviewZoomControls ZOOM_MIN
        max min abs floor format TEX_W8 FONT STATUS_PREVIEW CurrentPanelKey UnitDB UNIT_DATA UNIT_LABELS ReadPowerBarEnabled ReadPowerBarHeight
        PreviewRaidGroupNameAllowed PreviewRaidGroupNameText NormalizeRaidGroupNameAnchor CastbarEnabled CastbarShowIcon CastbarShowText ReadCastbarSize ReadCastbarNum FormatCastbarPreviewTime
        CastbarOffsetFields CastbarDetached CanDetachPowerBarKey ClampPreviewLayer SetTex PlaceHandle PlaceHandleAroundRegions UnitPreviewText UnitPreviewTextMovesTogether
        NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet FormatMode ShortenPreviewName ToTInlineSeparator ResolveNameAnchor ClassColor HealthColor
        HealthBackgroundColor PowerBackgroundColor PowerColor FontColor PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewHealPredictionEnabled PreviewAbsorbBarEnabled
        UnitPreviewPortraitTexture ClassPortraitVisual PreviewNameColor PreviewToTInlineColor LayoutUnitPreviewOverlay PositionFromAnchor PositionRuntimeLayoutIconPreview
        PositionStatusCornerPreview PositionSameAnchorPreview PositionLevelPreview ResolveStatusPreviewAnchor SetPreviewIconTexture NormalizeStatusPreviewId
        ApplyPreviewTextFocus ApplyPreviewRounded ApplyPreviewFrameBorder PreviewRoundedOutlineThickness ApplyPreviewBoundsGuide SetShownSafe ApplyPreviewLayerVisibility
        ApplyPreviewTransparency RefreshHandleSelectionVisuals Auras
    ]],
        PreviewInCombat, TR, PortraitStyleGet, RuntimeSpecForPreviewKey, RuntimeVisualScaleForPreviewKey, ClampPreviewZoom, UpdatePreviewZoomControls, ZOOM_MIN,
        max, min, abs, floor, format, TEX_W8, FONT, STATUS_PREVIEW, CurrentPanelKey, UnitDB, UNIT_DATA, UNIT_LABELS, ReadPowerBarEnabled, ReadPowerBarHeight,
        PreviewRaidGroupNameAllowed, PreviewRaidGroupNameText, NormalizePreviewRaidGroupNameAnchor, CastbarEnabled, CastbarShowIcon, CastbarShowText, ReadCastbarSize, ReadCastbarNum, FormatCastbarPreviewTime,
        CastbarOffsetFields, CastbarDetached, CanDetachPowerBarKey, ClampPreviewLayer, SetTex, PlaceHandle, UnitPreviewText.PlaceHandleAroundRegions, UnitPreviewText, UnitPreviewTextMovesTogether,
        NormalizeHpMode, NormalizePowerMode, TextScopeGet, TextScopeHasSlots, TextScopeSlotGet, FormatMode, ShortenPreviewName, ToTInlineSeparator, ResolveNameAnchor, ClassColor, HealthColor,
        HealthBackgroundColor, PowerBackgroundColor, PowerColor, FontColor, PreviewResolveHealPredAnchorMode, PreviewResolveAbsorbAnchorMode, PreviewHealPredictionEnabled, PreviewAbsorbBarEnabled,
        UnitPreviewPortraitTexture, ClassPortraitVisual, PreviewNameColor, PreviewToTInlineColor, LayoutUnitPreviewOverlay, PositionFromAnchor, PositionRuntimeLayoutIconPreview,
        PositionStatusCornerPreview, PositionSameAnchorPreview, PositionLevelPreview, ResolveStatusPreviewAnchor, SetPreviewIconTexture, NormalizeStatusPreviewId,
        ApplyPreviewTextFocus, ApplyPreviewRounded, ApplyPreviewFrameBorder, PreviewRoundedOutlineThickness, ApplyPreviewBoundsGuide, SetShownSafe, ApplyPreviewLayerVisibility,
        Preview.ApplyPreviewTransparency, RefreshHandleSelectionVisuals, PreviewAuras)
end
if MSUF.UFPreviewRender and MSUF.UFPreviewRender.Install then MSUF.UFPreviewRender.Install(Preview, Preview.RefreshDeps) end
Preview._BuildPreview = BuildPreview
Preview._PreviewInCombat = PreviewInCombat
