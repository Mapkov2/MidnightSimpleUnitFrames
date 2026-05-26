--- Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua
--- Cold-path unitframe preview view.
---
--- Owns: preview frame construction, draggable handle interactions, and
--- composed refresh layout. Specs, core visuals, castbar helpers, status
--- elements, DB/model helpers, and public wrappers live in split files.
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

MSUF.L = MSUF.L or (_G.MSUF_L) or {}
local L = MSUF.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(_, k) return k end })
end
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
_G.MSUF_UFPreview = Preview
local PreviewCore = MSUF.UFPreviewCore or {}
local PreviewCastbar = MSUF.UFPreviewCastbar or {}
local PreviewStatus = MSUF.UFPreviewStatus or {}
local PreviewAuras = MSUF.UFPreviewAuras or {}

local PreviewModel = Preview.Model or {}
local UNIT_KEYS = PreviewModel.UNIT_KEYS
local UNIT_SET = PreviewModel.UNIT_SET
local UNIT_LABELS = PreviewModel.UNIT_LABELS
local UNIT_DATA = PreviewModel.UNIT_DATA
local PreviewRaidGroupNameAllowed = PreviewModel.PreviewRaidGroupNameAllowed
local PreviewRaidGroupNameText = PreviewModel.PreviewRaidGroupNameText
local NormalizePreviewRaidGroupNameAnchor = PreviewModel.NormalizePreviewRaidGroupNameAnchor
local TEXT_ANCHORS = PreviewModel.TEXT_ANCHORS
local HP_MODES = PreviewModel.HP_MODES
local POWER_MODES = PreviewModel.POWER_MODES
local SEP_ITEMS = PreviewModel.SEP_ITEMS
local PORTRAIT_MODE_ITEMS = PreviewModel.PORTRAIT_MODE_ITEMS
local PORTRAIT_RENDER_ITEMS = PreviewModel.PORTRAIT_RENDER_ITEMS
local PortraitClassItems = PreviewModel.PortraitClassItems
local PORTRAIT_SHAPE_ITEMS = PreviewModel.PORTRAIT_SHAPE_ITEMS
local PORTRAIT_BORDER_ITEMS = PreviewModel.PORTRAIT_BORDER_ITEMS
local PORTRAIT_STYLE_DEFAULTS = PreviewModel.PORTRAIT_STYLE_DEFAULTS
local CanonKey = PreviewModel.CanonKey
local EnsureDB = PreviewModel.EnsureDB
local CurrentPanelKey = PreviewModel.CurrentPanelKey
local UnitDB = PreviewModel.UnitDB
local SeedTextFromGeneral = PreviewModel.SeedTextFromGeneral
local NormalizeHpMode = PreviewModel.NormalizeHpMode
local NormalizePowerMode = PreviewModel.NormalizePowerMode
local TextScopeGet = PreviewModel.TextScopeGet
local TextScopeHasSlots = PreviewModel.TextScopeHasSlots
local TextScopeSlotGet = PreviewModel.TextScopeSlotGet
local TOTINLINE_SEP_VALID = PreviewModel.TOTINLINE_SEP_VALID
local TOTINLINE_CUSTOM_SEPARATOR = PreviewModel.TOTINLINE_CUSTOM_SEPARATOR
local TOTINLINE_CUSTOM_SEPARATOR_MAX = PreviewModel.TOTINLINE_CUSTOM_SEPARATOR_MAX
local TruncateUtf8Chars = PreviewModel.TruncateUtf8Chars
local CleanToTInlineCustomSeparator = PreviewModel.CleanToTInlineCustomSeparator
local ToTInlineSeparator = PreviewModel.ToTInlineSeparator
local ShortenPreviewName = PreviewModel.ShortenPreviewName
local TextScopeSet = PreviewModel.TextScopeSet
local ForceTextUnit = PreviewModel.ForceTextUnit
local ApplyPanelUnit = PreviewModel.ApplyPanelUnit
local RefreshAllControls = PreviewModel.RefreshAllControls
local Label = PreviewModel.Label
local PlaceTopLeft = PreviewModel.PlaceTopLeft
local SetOptionWidth = PreviewModel.SetOptionWidth
local AddOptionDivider = PreviewModel.AddOptionDivider
local SetWidgetEnabled = PreviewModel.SetWidgetEnabled
local AddPlainCheck = PreviewModel.AddPlainCheck
local NormalizePortraitClassStyle = PreviewModel.NormalizePortraitClassStyle
local EnsureUnitPortraitStyle = PreviewModel.EnsureUnitPortraitStyle
local PortraitStyleGet = PreviewModel.PortraitStyleGet
local PortraitStyleSet = PreviewModel.PortraitStyleSet
local ApplyPortrait = PreviewModel.ApplyPortrait
local NormalizeStatusPreviewId = PreviewModel.NormalizeStatusPreviewId
local ClassColor = PreviewModel.ClassColor
local Clamp01 = PreviewModel.Clamp01
local SettingsCache = PreviewModel.SettingsCache
local PreviewNPCKind = PreviewModel.PreviewNPCKind
local NPCColor = PreviewModel.NPCColor
local GradientPreviewColor = PreviewModel.GradientPreviewColor
local HealthColor = PreviewModel.HealthColor
local DarkMatchHPColor = PreviewModel.DarkMatchHPColor
local HealthBackgroundColor = PreviewModel.HealthBackgroundColor
local PowerBackgroundColor = PreviewModel.PowerBackgroundColor
local PowerColor = PreviewModel.PowerColor
local ClassPortraitVisual = PreviewModel.ClassPortraitVisual
local UnitPreviewPortraitTexture = PreviewModel.UnitPreviewPortraitTexture
local FontColor = PreviewModel.FontColor
local NormalizeToTInlineColorMode = PreviewModel.NormalizeToTInlineColorMode
local PreviewNameColorFlags = PreviewModel.PreviewNameColorFlags
local PreviewNameColor = PreviewModel.PreviewNameColor
local PreviewToTInlineColor = PreviewModel.PreviewToTInlineColor
local SetTex = PreviewModel.SetTex
local NormalizePreviewAnchorMode = PreviewModel.NormalizePreviewAnchorMode
local UnitPreviewBarOverrideEnabled = PreviewModel.UnitPreviewBarOverrideEnabled
local PreviewHealPredictionEnabled = PreviewModel.PreviewHealPredictionEnabled
local PreviewResolveHealPredAnchorMode = PreviewModel.PreviewResolveHealPredAnchorMode
local PreviewResolveAbsorbAnchorMode = PreviewModel.PreviewResolveAbsorbAnchorMode
local PreviewAbsorbBarEnabled = PreviewModel.PreviewAbsorbBarEnabled
local PreviewOverlayWidth = PreviewModel.PreviewOverlayWidth
local LayoutUnitPreviewOverlay = PreviewModel.LayoutUnitPreviewOverlay
local MakeFS = PreviewModel.MakeFS
local ReadPowerBarEnabled = PreviewModel.ReadPowerBarEnabled
local CanDetachPowerBarKey = PreviewModel.CanDetachPowerBarKey
local ReadPowerBarHeight = PreviewModel.ReadPowerBarHeight
local ResolveNameAnchor = PreviewModel.ResolveNameAnchor
local NumText = PreviewModel.NumText
local JoinSep = PreviewModel.JoinSep
local FormatMode = PreviewModel.FormatMode
local UnitPreviewText = PreviewModel.UnitPreviewText

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

local PositionFromAnchor = PreviewStatus.PositionFromAnchor
local PositionRuntimeLayoutIconPreview = PreviewStatus.PositionRuntimeLayoutIconPreview
local PositionStatusCornerPreview = PreviewStatus.PositionStatusCornerPreview
local PositionSameAnchorPreview = PreviewStatus.PositionSameAnchorPreview
local PositionLevelPreview = PreviewStatus.PositionLevelPreview
local RoundOffset = PreviewCore.RoundOffset

local function GetNudgeStep()
    if IsControlKeyDown and IsControlKeyDown() then return 10 end
    if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
    return 1
end

local function IsTextInputFocused()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus and focus.IsObjectType and focus:IsObjectType("EditBox")
end

local CastbarOffsetFields = PreviewCastbar.OffsetFields
local CastbarDetached = PreviewCastbar.Detached
local ReadCastbarSize = PreviewCastbar.ReadSize
local ReadCastbarNum = PreviewCastbar.ReadNumber
local FormatCastbarPreviewTime = PreviewCastbar.FormatPreviewTime
local ClampPreviewLayer = PreviewCore.ClampLayer

local function RuntimeSpecForPreviewKey(key)
    local uf = MSUF and MSUF.UF
    local config = uf and uf.Config
    if not config then return nil end
    local runtimeUnit = key == "boss" and "boss1" or key
    if config.GetSpec and runtimeUnit then
        local spec = config.GetSpec(runtimeUnit)
        if spec then return spec end
    end
    if config.RefreshUnit and runtimeUnit then
        return config.RefreshUnit(runtimeUnit)
    end
    return nil
end

local function ClampRuntimeVisualScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return 1 end
    if scale < 0.25 then return 0.25 end
    if scale > 1.5 then return 1.5 end
    return scale
end

local function RuntimeVisualScaleForPreviewKey(key)
    local runtimeUnit = key == "boss" and "boss1" or key
    local frames = _G.MSUF_UnitFrames
    local frame = runtimeUnit and ((frames and frames[runtimeUnit]) or _G["MSUF_" .. runtimeUnit])
    local scale = frame and frame.GetScale and frame:GetScale()
    if scale then return ClampRuntimeVisualScale(scale) end

    local db = _G.MSUF_DB
    local g = db and db.general
    return ClampRuntimeVisualScale(g and (g.msufUiScale or g.uiScale) or 1)
end

local function ResolveHandleFields(preview, fields)
    if fields and fields.castbar then
        return CastbarOffsetFields(preview and preview.key)
    end
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
    if type(general) == "table" and general.unitPreviewGuidesEnabled ~= nil then
        return general.unitPreviewGuidesEnabled ~= false
    end
    return true
end

local function SetPreviewGuidesEnabled(enabled)
    _G.MSUF_DB = _G.MSUF_DB or {}
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    _G.MSUF_DB.general.unitPreviewGuidesEnabled = enabled ~= false
end

local function PreviewGuidesVisible(box)
    local layers = box and box.layerVisibility
    if type(layers) == "table" and layers.guides ~= nil then
        return layers.guides ~= false
    end
    return PreviewGuidesEnabled()
end

local function DefaultPreviewHint(box)
    if box and not PreviewGuidesVisible(box) then
        return TR("guides hidden - selected element still nudges with arrows - turn Guides on to drag another element")
    end
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
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
            _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true)
        end
    elseif fields.castbar then
        if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
            _G.MSUF_ApplyCastbarUnitAndSync(key)
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            _G.MSUF_UpdateCastbarVisuals()
        end
        if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
            _G.MSUF_SyncCastbarPositionPopup(key)
        end
    elseif fields.statusRefresh then
        local fn = _G[fields.statusRefresh]
        if type(fn) == "function" then fn() end
    end
    ApplyPanelUnit(box and box._msufPanel, key, reason or "UNIT_PREVIEW_MOVE")
    Preview.Refresh(box)
    RefreshHandleSelectionVisuals(box)
end

local function EnsureBarsDB()
    _G.MSUF_DB = _G.MSUF_DB or {}
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
    if type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)
    end
    ApplyPanelUnit(box and box._msufPanel, "player", reason or "UNIT_PREVIEW_CLASS_POWER_MOVE")
end

local function WriteBarsHandleOffsets(handle, x, y, reason)
    local fields = handle and handle._fields or {}
    local xKey, yKey = fields.barsX, fields.barsY
    if not xKey or not yKey then return false end
    local bars = EnsureBarsDB()
    bars[xKey] = RoundOffset(x)
    bars[yKey] = RoundOffset(y)
    if fields.classPower then
        RefreshClassPowerRuntime(handle and handle._preview, reason)
    end
    return true
end

local function RefreshCastbarRuntime(box, key, reason)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(key)
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
        _G.MSUF_SyncCastbarPositionPopup(key)
    end
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
    if CanonKey(key) == "boss" and fields.bossBaseX ~= nil then
        x = (tonumber(fields.bossBaseX) or 0) + (x or 0)
    end
    if CanonKey(key) == "boss" and fields.bossBaseY ~= nil then
        y = (tonumber(fields.bossBaseY) or 0) + (y or 0)
    end
    if x == nil and fields.iconFallback and fields.suffixX then
        x = g and tonumber(g[fields.suffixX:gsub("^Icon", "castbarIcon")]) or nil
    end
    if y == nil and fields.iconFallback and fields.suffixY then
        y = g and tonumber(g[fields.suffixY:gsub("^Icon", "castbarIcon")]) or nil
    end
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
    if CanonKey(key) == "boss" and fields.bossBaseX ~= nil then
        x = (tonumber(x) or 0) - (tonumber(fields.bossBaseX) or 0)
    end
    if CanonKey(key) == "boss" and fields.bossBaseY ~= nil then
        y = (tonumber(y) or 0) - (tonumber(fields.bossBaseY) or 0)
    end
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
    if h and type(h.CheckpointHistory) == "function" then
        return h.CheckpointHistory(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action))
    end
    return false
end

local function WriteHandleOffsets(handle, x, y, reason)
    if not handle then return false end
    local box = handle._preview
    local fields = handle._fields or {}
    if type(fields.writeOffsets) == "function" then
        if not fields.writeOffsets(handle, x, y, reason) then return false end
        Preview.Refresh(box, reason or "UNIT_PREVIEW_MOVE")
        RefreshHandleSelectionVisuals(box)
        if not handle._msuf2PreviewHistoryTx then
            CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move")
        end
        return true
    end
    local xKey, yKey = ResolveHandleFields(box, fields)
    if not xKey or not yKey then return false end
    local store = HandleStore(box, fields)
    store[xKey] = RoundOffset(x)
    store[yKey] = RoundOffset(y)
    CommitHandleMove(handle, reason)
    if not handle._msuf2PreviewHistoryTx then
        CheckpointMenuHistory(handle, reason == "UNIT_PREVIEW_NUDGE" and "Nudge" or "Move")
    end
    return true
end

local function ShouldSkipDuplicateNudge(box, dx, dy)
    if not box then return false end
    local now = GetTime and GetTime() or 0
    if now <= 0 then return false end
    local sig = tostring(dx or 0) .. ":" .. tostring(dy or 0)
    if box._msufLastNudgeSig == sig and (now - (box._msufLastNudgeAt or 0)) < 0.02 then
        return true
    end
    box._msufLastNudgeSig = sig
    box._msufLastNudgeAt = now
    return false
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
    if not box then return end
    handle = handle or box._selectedHandle
    if box.EnableKeyboard then box:EnableKeyboard(true) end
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(handle and false or true) end
    if handle and handle.EnableKeyboard then handle:EnableKeyboard(true) end
    if handle and handle.SetPropagateKeyboardInput then handle:SetPropagateKeyboardInput(false) end
    if handle and handle.SetFocus then
        handle:SetFocus()
    elseif box.SetFocus then
        box:SetFocus()
    end
    if defer and _G.C_Timer and _G.C_Timer.After then
        local selected = handle
        _G.C_Timer.After(0, function()
            if not (box and box.IsShown and box:IsShown()) then return end
            if selected and selected.IsShown and not selected:IsShown() then return end
            if selected and box._selectedHandle ~= selected then return end
            FocusPreviewKeyboardTarget(box, selected, false)
        end)
    end
end

Preview.SetArrowBindings = function(box, enabled)
    if InCombatLockdown and InCombatLockdown() then return end
    local owner = _G.MSUF_UFPreview_NudgeOwner
    if owner and ClearOverrideBindings then ClearOverrideBindings(owner) end
    if owner and owner.Hide then owner:Hide() end
    if not enabled or not box then
        if box and box._msufArrowPoller then
            box._msufArrowPoller:SetScript("OnUpdate", nil)
            box._msufArrowPoller:Hide()
        end
        if _G.MSUF_UFPreview_ActiveNudgeBox == box or box == nil then
            _G.MSUF_UFPreview_ActiveNudgeBox = nil
        end
        return
    end
    _G.MSUF_UFPreview_ActiveNudgeBox = box
    if not owner then
        owner = CreateFrame("Frame", "MSUF_UFPreview_NudgeOwner", UIParent)
        _G.MSUF_UFPreview_NudgeOwner = owner
    end
    owner:Show()
    local dirs = {
        LEFT = { -1, 0 },
        RIGHT = { 1, 0 },
        UP = { 0, 1 },
        DOWN = { 0, -1 },
    }
    for dir, delta in pairs(dirs) do
        local btnName = "MSUF_UFPreview_Nudge" .. dir
        local btn = _G[btnName]
        if not btn then
            btn = CreateFrame("Button", btnName, owner, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", function(self)
                local active = _G.MSUF_UFPreview_ActiveNudgeBox or Preview.active
                if NudgeSelectedHandle(active, self._msufDx or 0, self._msufDy or 0) then
                    FocusPreviewKeyboardTarget(active, active and active._selectedHandle, true)
                end
            end)
        end
        btn._msufDx, btn._msufDy = delta[1], delta[2]
        if SetOverrideBindingClick then
            SetOverrideBindingClick(owner, false, dir, btnName)
            SetOverrideBindingClick(owner, false, "SHIFT-" .. dir, btnName)
            SetOverrideBindingClick(owner, false, "CTRL-" .. dir, btnName)
            SetOverrideBindingClick(owner, false, "CTRL-SHIFT-" .. dir, btnName)
            SetOverrideBindingClick(owner, false, "SHIFT-CTRL-" .. dir, btnName)
        end
    end
end

local function RegisterPreviewNudgeTarget(box)
    local fn = _G.MSUF_EM2_SetPreviewNudgeTarget
    if type(fn) ~= "function" or not box then return end
    box._msufPreviewNudgeTarget = box._msufPreviewNudgeTarget or {
        frame = box,
        IsActive = function()
            return box and box.IsShown and box:IsShown() and box._selectedHandle ~= nil and not IsTextInputFocused()
        end,
        Nudge = function(_, dx, dy)
            if NudgeSelectedHandleDelta(box, dx, dy) then
                FocusPreviewKeyboardTarget(box, box._selectedHandle, true)
            end
        end,
    }
    fn(box._msufPreviewNudgeTarget)
end

SelectPreviewHandle = function(handle, skipSectionOpen)
    local box = handle and handle._preview or Preview.active
    if not box then return end
    do
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.IsObjectType and focus:IsObjectType("EditBox") and focus.ClearFocus then
            focus:ClearFocus()
        end
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
            if not skipSectionOpen and p and type(p._msufUFStatusSet) == "function" then
                p._msufUFStatusSet("selected", handle._key)
            end
        end
        if menu and (handle._key == "hpLeft" or handle._key == "hpCenter" or handle._key == "hpRight") then
            UnitPreviewSetTextMoveTogether(box.key, "hp", false)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextSlotSelection = menu.unitTextSlotSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "hp"
            menu.unitTextSlotSelection[box.key or "player"] = menu.unitTextSlotSelection[box.key or "player"] or {}
            menu.unitTextSlotSelection[box.key or "player"].hp = (handle._key == "hpLeft" and "left") or (handle._key == "hpRight" and "right") or "center"
        elseif menu and handle._key == "hp" then
            UnitPreviewSetTextMoveTogether(box.key, "hp", true)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "hp"
        elseif menu and (handle._key == "powerLeft" or handle._key == "powerCenter" or handle._key == "powerRight") then
            UnitPreviewSetTextMoveTogether(box.key, "power", false)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextSlotSelection = menu.unitTextSlotSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "power"
            menu.unitTextSlotSelection[box.key or "player"] = menu.unitTextSlotSelection[box.key or "player"] or {}
            menu.unitTextSlotSelection[box.key or "player"].power = (handle._key == "powerLeft" and "left") or (handle._key == "powerRight" and "right") or "center"
        elseif menu and handle._key == "power" then
            UnitPreviewSetTextMoveTogether(box.key, "power", true)
            menu.unitTextTabSelection = menu.unitTextTabSelection or {}
            menu.unitTextTabSelection[box.key or "player"] = "power"
        end
        if not skipSectionOpen and p and type(p._msufOpenUnitSection) == "function" then
            p._msufOpenUnitSection(fields.section or "text")
        end
        FocusPreviewKeyboardTarget(box, handle, true)
    end
    RefreshHandleSelectionVisuals(box)
end

local function PreviewArrowKeyDown(self, keyName)
    local box = (self and self._preview) or self or Preview.active
    local dx, dy = 0, 0
    if keyName == "LEFT" then
        dx = -1
    elseif keyName == "RIGHT" then
        dx = 1
    elseif keyName == "UP" then
        dy = 1
    elseif keyName == "DOWN" then
        dy = -1
    else
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        return
    end

    if IsTextInputFocused() then
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        if box and box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
        return
    end

    if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
    if box and box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(false) end
    if NudgeSelectedHandle(box, dx, dy) then
        FocusPreviewKeyboardTarget(box, box and box._selectedHandle, true)
    else
        if self and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        if box and box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    end
end

local StartPreviewPan, StopPreviewPan

local function MakeHandle(preview, key, fields, label, color)
    local h = CreateFrame("Button", nil, preview.canvas)
    h:SetFrameLevel((preview.canvas:GetFrameLevel() or 0) + 30)
    h:SetSize(20, 20)
    h:RegisterForClicks("LeftButtonUp")
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
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local line = h._selBorder:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0.30, 0.58, 0.95, 0.70)
        h._selBorder[side] = line
    end
    h._selBorder.top:SetPoint("TOPLEFT")
    h._selBorder.top:SetPoint("TOPRIGHT")
    h._selBorder.top:SetHeight(1)
    h._selBorder.bottom:SetPoint("BOTTOMLEFT")
    h._selBorder.bottom:SetPoint("BOTTOMRIGHT")
    h._selBorder.bottom:SetHeight(1)
    h._selBorder.left:SetPoint("TOPLEFT")
    h._selBorder.left:SetPoint("BOTTOMLEFT")
    h._selBorder.left:SetWidth(1)
    h._selBorder.right:SetPoint("TOPRIGHT")
    h._selBorder.right:SetPoint("BOTTOMRIGHT")
    h._selBorder.right:SetWidth(1)
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
        preview.dragFrame:SetScript("OnUpdate", preview._onDragUpdate)
        preview.dragFrame:Show()
        RefreshHandleSelectionVisuals(preview)
    end
    local function StopHandleDrag(self, button)
        if StopPreviewPan and preview.canvas and preview.canvas._msufPreviewPanning then
            StopPreviewPan(preview.canvas)
        end
        if button and button ~= "LeftButton" then return end
        local wasDragging = self._dragging == true or preview.dragFrame._handle == self
        if not wasDragging then return end
        if preview.dragFrame._handle == self then
            preview.dragFrame:SetScript("OnUpdate", nil)
            preview.dragFrame._handle = nil
            preview.dragFrame:Hide()
        end
        local fields = self._fields or {}
        if type(fields.commitOffsets) == "function" then
            fields.commitOffsets(self, "UNIT_PREVIEW_DRAG_END")
        end
        if self._msuf2PreviewHistoryTx then
            self._msuf2PreviewHistoryTx = nil
            CommitMenuHistory()
        end
        local hadFrozenScale = preview._dragFrozenScale ~= nil
        preview._dragFrozenScale = nil
        self._dragging = nil
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragPoint = nil
        self._dragRelTo = nil
        self._dragRelPoint = nil
        self._dragOffsetX = nil
        self._dragOffsetY = nil
        RefreshHandleSelectionVisuals(preview)
        if hadFrozenScale and not preview._manualZoom and Preview.Refresh then
            Preview.Refresh(preview, "UNIT_PREVIEW_DRAG_END")
        end
    end
    h:SetScript("OnMouseDown", StartHandleDrag)
    h:SetScript("OnMouseUp", StopHandleDrag)
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

local ZOOM_MIN, ZOOM_MAX = 0.35, 4.0
local ZOOM_STEPS = { 0.35, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 3.00, 4.00 }

local function ClampPreviewZoom(v)
    v = tonumber(v) or 1
    if v < ZOOM_MIN then return ZOOM_MIN end
    if v > ZOOM_MAX then return ZOOM_MAX end
    return floor(v * 100 + 0.5) / 100
end

local function UpdatePreviewZoomControls(box)
    if not box then return end
    local zoom = box._manualZoom
    local scale = tonumber(box._mockScale) or tonumber(zoom) or tonumber(box._mockAutoScale) or 1
    if box.zoomReadout then
        local pct = floor(scale * 100 + 0.5)
        if zoom then
            box.zoomReadout:SetText(format("%d%%", pct))
        else
            box.zoomReadout:SetText(format("Fit %d%%", pct))
        end
    end
    if box.zoomFitButton and box.zoomFitButton.fs then
        box.zoomFitButton.fs:SetTextColor(zoom and 0.72 or 0.25, zoom and 0.78 or 0.95, zoom and 0.90 or 1.00, 1)
    end
end

local function SetPreviewZoom(box, zoom, reason)
    if not box then return end
    if zoom == nil or zoom == "fit" then
        box._manualZoom = nil
        box._zoomPanX, box._zoomPanY = 0, 0
    else
        box._manualZoom = ClampPreviewZoom(zoom)
    end
    UpdatePreviewZoomControls(box)
    Preview.Refresh(box, reason or "UNIT_PREVIEW_ZOOM")
end

local function StepPreviewZoom(box, dir)
    if not box then return end
    local current = ClampPreviewZoom(box._manualZoom or box._mockScale or box._mockAutoScale or 1)
    local nextZoom = current
    if (tonumber(dir) or 0) > 0 then
        for i = 1, #ZOOM_STEPS do
            if ZOOM_STEPS[i] > current + 0.001 then
                nextZoom = ZOOM_STEPS[i]
                break
            end
        end
    else
        for i = #ZOOM_STEPS, 1, -1 do
            if ZOOM_STEPS[i] < current - 0.001 then
                nextZoom = ZOOM_STEPS[i]
                break
            end
        end
    end
    SetPreviewZoom(box, nextZoom, "UNIT_PREVIEW_ZOOM_STEP")
end

local function CreateZoomButton(parent, text, width, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 24, 18)
    btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    btn:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
    btn:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("CENTER")
    btn.fs:SetText(text)
    btn.fs:SetTextColor(0.78, 0.84, 0.96, 1)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.05, 0.07, 0.11, 0.98)
        self:SetBackdropBorderColor(0.28, 0.42, 0.68, 1)
        if GameTooltip and tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR(tooltip), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.025, 0.030, 0.045, 0.88)
        self:SetBackdropBorderColor(0.12, 0.16, 0.24, 0.92)
        if GameTooltip then GameTooltip:Hide() end
    end)
    return btn
end

local function ApplyPreviewPan(box)
    if not (box and box.canvas and box.mock) then return end
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box.mock:ClearAllPoints()
    box.mock:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._mockBaseOffsetX) or 0) + panX, (tonumber(box._mockBaseOffsetY) or 0) + panY)
    if box._detachedCastPreview and box.mock.cast and box.mock.cast:IsShown() then
        box.mock.cast:ClearAllPoints()
        box.mock.cast:SetPoint("CENTER", box.canvas, "CENTER", (tonumber(box._detachedCastBaseOffsetX) or 0) + panX, (tonumber(box._detachedCastBaseOffsetY) or 0) + panY)
    end
end

function StopPreviewPan(canvas)
    if not canvas then return end
    local box = canvas._msufPreviewPanBox
    canvas._msufPreviewPanning = nil
    canvas._msufPreviewPanBox = nil
    canvas._msufPreviewPanCursorX = nil
    canvas._msufPreviewPanCursorY = nil
    canvas._msufPreviewPanStartX = nil
    canvas._msufPreviewPanStartY = nil
    canvas:SetScript("OnUpdate", nil)
    if box then UpdateHandleHint(box, box._selectedHandle) end
end

function StartPreviewPan(canvas, box, button)
    if not (canvas and box) then return false end
    local ctrlLeft = button == "LeftButton" and IsControlKeyDown and IsControlKeyDown()
    if not (ctrlLeft or button == "RightButton" or button == "MiddleButton") then return false end
    if not box._manualZoom then
        box._manualZoom = ClampPreviewZoom(box._mockScale or box._mockAutoScale or 1)
        UpdatePreviewZoomControls(box)
    end
    local cx, cy = GetCursorPosition()
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if uiScale <= 0 then uiScale = 1 end
    canvas._msufPreviewPanning = true
    canvas._msufPreviewPanBox = box
    canvas._msufPreviewPanCursorX = (cx or 0) / uiScale
    canvas._msufPreviewPanCursorY = (cy or 0) / uiScale
    canvas._msufPreviewPanStartX = tonumber(box._zoomPanX) or 0
    canvas._msufPreviewPanStartY = tonumber(box._zoomPanY) or 0
    if box.hint then box.hint:SetText(TR("moving preview canvas - release mouse to stop - Fit recenters")) end
    canvas:SetScript("OnUpdate", function(self)
        if not self._msufPreviewPanning then return end
        local mx, my = GetCursorPosition()
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        if scale <= 0 then scale = 1 end
        local nextX = floor((self._msufPreviewPanStartX or 0) + ((mx or 0) / scale - (self._msufPreviewPanCursorX or 0)) + 0.5)
        local nextY = floor((self._msufPreviewPanStartY or 0) + ((my or 0) / scale - (self._msufPreviewPanCursorY or 0)) + 0.5)
        if box._zoomPanX ~= nextX or box._zoomPanY ~= nextY then
            box._zoomPanX, box._zoomPanY = nextX, nextY
            ApplyPreviewPan(box)
        end
    end)
    return true
end

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

    local zoomBar = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    zoomBar:SetSize(160, 22)
    zoomBar:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -8, -6)
    zoomBar:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    zoomBar:SetBackdropColor(0.015, 0.018, 0.030, 0.86)
    zoomBar:SetBackdropBorderColor(0.10, 0.14, 0.22, 0.92)
    if zoomBar.SetFrameLevel then zoomBar:SetFrameLevel((canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 80) end
    zoomBar:EnableMouse(true)
    zoomBar:EnableMouseWheel(true)
    if zoomBar.SetPropagateMouseWheel then zoomBar:SetPropagateMouseWheel(false) end
    box.zoomBar = zoomBar
    zoomBar:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Preview zoom"), 1, 1, 1)
            GameTooltip:AddLine(TR("Use the buttons or Ctrl + mouse wheel to zoom."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Ctrl + left-drag moves the preview canvas. Fit recenters it."), 0.55, 0.68, 0.86, true)
            GameTooltip:Show()
        end
    end)
    zoomBar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local zoomOut = CreateZoomButton(zoomBar, "-", 18, "Zoom out", function() StepPreviewZoom(box, -1) end)
    zoomOut:SetPoint("LEFT", zoomBar, "LEFT", 3, 0)
    box.zoomOutButton = zoomOut

    local readout = zoomBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    readout:SetPoint("LEFT", zoomOut, "RIGHT", 3, 0)
    readout:SetSize(54, 18)
    readout:SetJustifyH("CENTER")
    readout:SetTextColor(0.72, 0.78, 0.90, 1)
    box.zoomReadout = readout

    local fitButton = CreateZoomButton(zoomBar, "Fit", 28, "Fit preview", function() SetPreviewZoom(box, nil, "UNIT_PREVIEW_ZOOM_FIT") end)
    fitButton:SetPoint("LEFT", readout, "RIGHT", 3, 0)
    box.zoomFitButton = fitButton

    local oneButton = CreateZoomButton(zoomBar, "1:1", 30, "Pixel preview", function() SetPreviewZoom(box, 1, "UNIT_PREVIEW_ZOOM_1TO1") end)
    oneButton:SetPoint("LEFT", fitButton, "RIGHT", 3, 0)
    box.zoomOneButton = oneButton

    local zoomIn = CreateZoomButton(zoomBar, "+", 18, "Zoom in", function() StepPreviewZoom(box, 1) end)
    zoomIn:SetPoint("LEFT", oneButton, "RIGHT", 3, 0)
    box.zoomInButton = zoomIn

    local function PreviewZoomWheel(self, delta)
        local dir = (delta or 0) > 0 and 1 or -1
        if IsControlKeyDown and IsControlKeyDown() then
            if self.SetPropagateMouseWheel then self:SetPropagateMouseWheel(false) end
            StepPreviewZoom(box, dir)
        elseif self.SetPropagateMouseWheel then
            self:SetPropagateMouseWheel(true)
        end
    end
    canvas:SetScript("OnMouseWheel", PreviewZoomWheel)
    zoomBar:SetScript("OnMouseWheel", function(_, delta) StepPreviewZoom(box, (delta or 0) > 0 and 1 or -1) end)
    canvas:SetScript("OnMouseDown", function(self, button) StartPreviewPan(self, box, button) end)
    canvas:SetScript("OnMouseUp", StopPreviewPan)
    canvas:SetScript("OnHide", StopPreviewPan)

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
    for i = 1, #PREVIEW_LAYERS do
        local def = PREVIEW_LAYERS[i]
        box.layerVisibility[def.key] = (def.key == "guides") and PreviewGuidesEnabled() or true
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(sideW - 10, 18)
        btn:SetPoint("TOP", sidebar, "TOP", 0, -(20 + (i - 1) * 18))
        btn:EnableMouse(true)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bg = bg
        local bar = btn:CreateTexture(nil, "ARTWORK")
        bar:SetSize(2, 14)
        bar:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn.bar = bar
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("LEFT", bar, "RIGHT", 5, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(TR(def.label))
        btn.fs = fs
        local off = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        off:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        off:SetText("OFF")
        off:SetJustifyH("RIGHT")
        off:Hide()
        btn.off = off
        btn.key = def.key
        btn.color = def.color
        btn.tooltip = def.tooltip
        btn.refresh = function(self)
            local on = box.layerVisibility[self.key] ~= false
            local available = not (box.layerAvailable and box.layerAvailable[self.key] == false)
            local c = self.color
            self.off:SetText("OFF")
            self.off:SetShown((not available) or (self.key == "guides" and not on))
            if not available then
                self.bg:SetColorTexture(0.020, 0.020, 0.028, 0.48)
                self.bar:SetColorTexture(0.18, 0.18, 0.22, 0.35)
                self.fs:SetTextColor(0.30, 0.30, 0.36, 0.55)
                self.off:SetTextColor(0.36, 0.36, 0.42, 0.65)
            elseif on then
                self.bg:SetColorTexture(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 0.58)
                self.bar:SetColorTexture(c[1], c[2], c[3], 0.88)
                self.fs:SetTextColor(0.76, 0.80, 0.90, 0.95)
                self.off:SetTextColor(0.36, 0.36, 0.42, 0.65)
            else
                self.bg:SetColorTexture(0.035, 0.035, 0.045, 0.35)
                self.bar:SetColorTexture(0.18, 0.18, 0.22, 0.32)
                self.fs:SetTextColor(0.30, 0.30, 0.36, 0.55)
                self.off:SetTextColor(0.40, 0.42, 0.50, 0.78)
            end
        end
        btn:SetScript("OnClick", function(self)
            if box.layerAvailable and box.layerAvailable[self.key] == false then
                box.hint:SetText(TR("This layer is off in settings and cannot be shown in preview."))
                return
            end
            box.layerVisibility[self.key] = (box.layerVisibility[self.key] == false)
            if self.key == "guides" then
                SetPreviewGuidesEnabled(box.layerVisibility[self.key] ~= false)
            end
            for j = 1, #box.layerButtons do box.layerButtons[j]:refresh() end
            Preview.Refresh(box)
            RefreshHandleSelectionVisuals(box)
        end)
        btn:SetScript("OnEnter", function(self)
            local c = self.color
            if box.layerAvailable and box.layerAvailable[self.key] == false then
                self.bg:SetColorTexture(0.045, 0.045, 0.055, 0.62)
                self.fs:SetTextColor(0.42, 0.42, 0.48, 0.75)
                box.hint:SetText(TR("This layer is off in settings and cannot be shown in preview."))
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(TR("Layer disabled"), 1, 1, 1)
                    GameTooltip:AddLine(TR("Turn this feature on in settings to make the preview layer available."), 0.82, 0.82, 0.82, true)
                    GameTooltip:Show()
                end
            elseif box.layerVisibility[self.key] ~= false then
                self.bg:SetColorTexture(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 0.78)
                if GameTooltip and self.tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(TR(self.fs and self.fs:GetText() or self.key), 1, 1, 1)
                    GameTooltip:AddLine(TR(self.tooltip), 0.82, 0.82, 0.82, true)
                    if self.key == "guides" then
                        GameTooltip:AddLine(TR("Turn off to inspect the frame without mover outlines. The selected element can still be nudged with arrow keys."), 0.55, 0.68, 0.86, true)
                    end
                    GameTooltip:Show()
                elseif GameTooltip then
                    GameTooltip:Hide()
                end
            else
                self.bg:SetColorTexture(0.08, 0.08, 0.10, 0.55)
                if GameTooltip and self.tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(TR(self.fs and self.fs:GetText() or self.key), 1, 1, 1)
                    GameTooltip:AddLine(TR(self.tooltip), 0.82, 0.82, 0.82, true)
                    if self.key == "guides" then
                        GameTooltip:AddLine(TR("Guides are hidden. Turn this back on to see drag handles and selected borders."), 0.55, 0.68, 0.86, true)
                    end
                    GameTooltip:Show()
                elseif GameTooltip then
                    GameTooltip:Hide()
                end
            end
            if not (box.layerAvailable and box.layerAvailable[self.key] == false) then
                self.fs:SetTextColor(0.90, 0.92, 1.0, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if GameTooltip then GameTooltip:Hide() end
            self:refresh()
            UpdateHandleHint(box, box._selectedHandle)
        end)
        box.layerButtons[#box.layerButtons + 1] = btn
        btn:refresh()
    end

    local mock = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock:SetBackdropColor(0, 0, 0, 0.92)
    do
        local r, g, b = PreviewBaseEdgeColor()
        mock:SetBackdropBorderColor(r, g, b, 1)
    end
    box.mock = mock

    mock.bounds = CreateFrame("Frame", nil, mock, "BackdropTemplate")
    mock.bounds:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.bounds:SetBackdropColor(0, 0, 0, 0)
    mock.bounds:SetBackdropBorderColor(1, 0.14, 0.08, 0.95)
    mock.bounds:SetFrameLevel((mock:GetFrameLevel() or 0) + 28)
    mock.bounds:SetAllPoints(mock)

    mock.sizeTag = mock.bounds:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.sizeTag:SetPoint("BOTTOM", mock.bounds, "TOP", 0, 2)
    mock.sizeTag:SetTextColor(1, 0.35, 0.25, 0.95)

    mock.hpBG = mock:CreateTexture(nil, "BACKGROUND")
    mock.hpBG:SetTexture(TEX_W8)
    mock.hpBG:SetColorTexture(0, 0, 0, 0.82)
    mock.hp = mock:CreateTexture(nil, "ARTWORK")
    SetTex(mock.hp, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    mock.healPred = mock:CreateTexture(nil, "ARTWORK")
    mock.healPred:SetTexture(TEX_W8)
    mock.healPred:SetVertexColor(0, 1, 0.4, 0.55)
    mock.absorb = mock:CreateTexture(nil, "ARTWORK")
    mock.absorb:SetTexture(TEX_W8)
    mock.absorb:SetVertexColor(0.55, 0.70, 1, 0.58)
    mock.powerBG = mock:CreateTexture(nil, "BACKGROUND")
    mock.powerBG:SetTexture(TEX_W8)
    mock.powerBG:SetColorTexture(0, 0, 0, 0.9)
    mock.power = mock:CreateTexture(nil, "ARTWORK")
    SetTex(mock.power, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)

    mock.classPower = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.classPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.classPower:SetBackdropColor(0, 0, 0, 0.55)
    mock.classPower:SetBackdropBorderColor(0, 0, 0, 1)
    mock.classPower.segments = {}
    for i = 1, 6 do
        local seg = mock.classPower:CreateTexture(nil, "ARTWORK")
        seg:SetTexture(TEX_W8)
        mock.classPower.segments[i] = seg
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
    mock.detachedPower.fill = mock.detachedPower:CreateTexture(nil, "ARTWORK")
    SetTex(mock.detachedPower.fill, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    mock.detachedPower.fill:SetPoint("TOPLEFT", mock.detachedPower, "TOPLEFT", 1, -1)
    mock.detachedPower.fill:SetPoint("BOTTOMLEFT", mock.detachedPower, "BOTTOMLEFT", 1, 1)

    mock.portrait = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.portrait:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.portrait:SetBackdropColor(0.03, 0.035, 0.05, 1)
    mock.portrait:SetBackdropBorderColor(0.72, 0.72, 0.80, 0.82)
    mock.portrait.tex = mock.portrait:CreateTexture(nil, "ARTWORK")
    mock.portrait.tex:SetPoint("TOPLEFT", 2, -2)
    mock.portrait.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    mock.portrait.initial = MakeFS(mock.portrait, "OVERLAY", 22)
    mock.portrait.initial:SetPoint("CENTER")

    mock.textFrame = CreateFrame("Frame", nil, mock)
    mock.textFrame:SetAllPoints(mock)
    mock.nameLayer = CreateFrame("Frame", nil, mock.textFrame)
    mock.nameLayer:SetAllPoints(mock.textFrame)
    mock.hpLayer = CreateFrame("Frame", nil, mock.textFrame)
    mock.hpLayer:SetAllPoints(mock.textFrame)
    mock.powerLayer = CreateFrame("Frame", nil, mock.textFrame)
    mock.powerLayer:SetAllPoints(mock.textFrame)
    mock.nameText = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.raidGroupNameText = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.totInlineSep = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.totInlineText = MakeFS(mock.nameLayer, "OVERLAY", 12)
    mock.hpTextLeft = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.hpTextCenter = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.hpText = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.hpTextPct = MakeFS(mock.hpLayer, "OVERLAY", 12)
    mock.powerTextLeft = MakeFS(mock.powerLayer, "OVERLAY", 12)
    mock.powerTextCenter = MakeFS(mock.powerLayer, "OVERLAY", 12)
    mock.powerText = MakeFS(mock.powerLayer, "OVERLAY", 12)
    mock.powerTextPct = MakeFS(mock.powerLayer, "OVERLAY", 12)

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
        local p = box and box._msufPanel
        if p and type(p._msufOpenUnitSection) == "function" then p._msufOpenUnitSection("castbar") end
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
    box.dragFrame:Hide()
    box._onDragUpdate = function(df)
        local h = df._handle
        if not h then return end
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
    if type(PreviewAuras.CreateHandles) == "function" then
        PreviewAuras.CreateHandles(box, MakeHandle)
    end
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
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
        self._selectedHandle = nil
        Preview.SetArrowBindings(self, false)
        RefreshHandleSelectionVisuals(self)
        if Preview.active == self then Preview.active = nil end
        self.dragFrame:SetScript("OnUpdate", nil)
        self.dragFrame._handle = nil
        if self._msufPreviewNudgeTarget and rawget(_G, "MSUF_EM2_ActivePreviewNudgeTarget") == self._msufPreviewNudgeTarget and type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function" then
            _G.MSUF_EM2_SetPreviewNudgeTarget(nil)
        end
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
    deps.PreviewInCombat = PreviewInCombat
    deps.TR = TR
    deps.PortraitStyleGet = PortraitStyleGet
    deps.max = max
    deps.min = min
    deps.abs = abs
    deps.floor = floor
    deps.format = format
    deps.TEX_W8 = TEX_W8
    deps.FONT = FONT
    deps.CurrentPanelKey = CurrentPanelKey
    deps.UnitDB = UnitDB
    deps.UNIT_DATA = UNIT_DATA
    deps.UNIT_LABELS = UNIT_LABELS
    deps.ReadPowerBarEnabled = ReadPowerBarEnabled
    deps.PreviewRaidGroupNameAllowed = PreviewRaidGroupNameAllowed
    deps.PreviewRaidGroupNameText = PreviewRaidGroupNameText
    deps.NormalizeRaidGroupNameAnchor = NormalizePreviewRaidGroupNameAnchor
    deps.STATUS_PREVIEW = STATUS_PREVIEW
    deps.CastbarEnabled = CastbarEnabled
    deps.ReadCastbarSize = ReadCastbarSize
    deps.CastbarOffsetFields = CastbarOffsetFields
    deps.CastbarDetached = CastbarDetached
    deps.CanDetachPowerBarKey = CanDetachPowerBarKey
    deps.ClampPreviewLayer = ClampPreviewLayer
    deps.SetTex = SetTex
    deps.ReadPowerBarHeight = ReadPowerBarHeight
    deps.PlaceHandle = PlaceHandle
    deps.UnitPreviewText = UnitPreviewText
    deps.UnitPreviewTextMovesTogether = UnitPreviewTextMovesTogether
    deps.SetShownSafe = SetShownSafe
    deps.ApplyPreviewLayerVisibility = ApplyPreviewLayerVisibility
    deps.ApplyPreviewTransparency = Preview.ApplyPreviewTransparency
    deps.RefreshHandleSelectionVisuals = RefreshHandleSelectionVisuals
    deps.Auras = PreviewAuras
end
function Preview.Refresh(box, reason)
    box = box or Preview.active
    if not box or not box:IsShown() then return end
    local D = Preview.RefreshDeps
    local PreviewInCombat = D.PreviewInCombat
    if PreviewInCombat() then return end
    local TR = D.TR
    local PortraitStyleGet = D.PortraitStyleGet
    local max, min, abs, floor = D.max, D.min, D.abs, D.floor
    local format, TEX_W8, FONT = D.format, D.TEX_W8, D.FONT
    local CastbarEnabled = D.CastbarEnabled
    local ReadCastbarSize = D.ReadCastbarSize
    local CastbarOffsetFields = D.CastbarOffsetFields
    local CastbarDetached = D.CastbarDetached
    local CanDetachPowerBarKey = D.CanDetachPowerBarKey
    local ClampPreviewLayer = D.ClampPreviewLayer
    local SetTex = D.SetTex
    local ReadPowerBarHeight = D.ReadPowerBarHeight
    local PlaceHandle = D.PlaceHandle
    local UnitPreviewText = D.UnitPreviewText
    local UnitPreviewTextMovesTogether = D.UnitPreviewTextMovesTogether
    local SetShownSafe = D.SetShownSafe
    local ApplyPreviewLayerVisibility = D.ApplyPreviewLayerVisibility
    local ApplyPreviewTransparency = D.ApplyPreviewTransparency
    local RefreshHandleSelectionVisuals = D.RefreshHandleSelectionVisuals
    local Auras = D.Auras
    local panel = box._msufPanel
    local key = D.CurrentPanelKey(panel)
    local conf, g = D.UnitDB(key)
    local data = D.UNIT_DATA[key] or D.UNIT_DATA.player
    local runtimeSpec = RuntimeSpecForPreviewKey(key)
    box.key = key
    local skipControlRefresh = (reason == "OPTIONS_APPLY_DB" or reason == "UNIT_MENU_ENTER" or reason == "UNIT_MENU_REENTER")
        or reason == "UNIT_PREVIEW_DRAG"
        or reason == "UNIT_PREVIEW_ZOOM"
        or reason == "UNIT_PREVIEW_ZOOM_STEP"
        or reason == "UNIT_PREVIEW_ZOOM_FIT"
        or reason == "UNIT_PREVIEW_ZOOM_1TO1"
    if panel and panel._msufRefreshUnitTextControls and not skipControlRefresh and not box._refreshingControls then
        box._refreshingControls = true
        panel._msufRefreshUnitTextControls()
        if panel._msufRefreshUnitPortraitControls then panel._msufRefreshUnitPortraitControls() end
        if panel._msufRefreshUnitPowerControls then panel._msufRefreshUnitPowerControls() end
        box._refreshingControls = nil
    end
    if box.title then box.title:SetText(TR("Unit Frame Preview") .. " - " .. TR(D.UNIT_LABELS[key] or key)) end
    local canvas = box.canvas
    local cw = canvas:GetWidth() or 600
    local ch = canvas:GetHeight() or 180
    if cw <= 1 then cw = 600 end
    if ch <= 1 then ch = 180 end
    local w = tonumber(runtimeSpec and runtimeSpec.width) or tonumber(conf.width or conf.frameWidth) or (key == "boss" and 180 or (key == "focus" and 180 or 275))
    local h = tonumber(runtimeSpec and runtimeSpec.height) or tonumber(conf.height or conf.frameHeight) or (key == "boss" and 30 or (key == "focus" and 30 or 40))
    if w < 60 then w = 60 elseif w > 520 then w = 520 end
    if h < 18 then h = 18 elseif h > 140 then h = 140 end
    local mode = conf.portraitMode
    local hasPortrait = (mode == "LEFT" or mode == "RIGHT")
    local pSize = hasPortrait and (tonumber(PortraitStyleGet(key, "portraitSizeOverride", 0)) or 0) or 0
    if pSize <= 0 then pSize = max(22, h - 4) end
    local castEnabled = CastbarEnabled(key, g)
    local castW, castBarH = ReadCastbarSize(key, g, w, key == "boss" and 12 or 18)
    local castH = castEnabled and castBarH or 0
    local castXKey, castYKey, castDefX, castDefY = CastbarOffsetFields(key)
    local castOffsetX = castXKey and tonumber(g[castXKey]) or nil
    local castOffsetY = castYKey and tonumber(g[castYKey]) or nil
    if castOffsetX == nil then castOffsetX = tonumber(castDefX) or 0 end
    if castOffsetY == nil then castOffsetY = tonumber(castDefY) or 0 end
    local castDetached = castEnabled and CastbarDetached(key, g)
    local castPreviewVisible = castEnabled
    local bars = _G.MSUF_DB and _G.MSUF_DB.bars or {}
    local detachedPower = CanDetachPowerBarKey(key) and conf.powerBarDetached == true and D.ReadPowerBarEnabled(conf, key)
    local classPowerOn = key == "player" and (bars.showClassPower == true or detachedPower)
    local powerFrac = tonumber(data.power) or 1
    if not detachedPower and key ~= "player" then powerFrac = 1 end
    if powerFrac < 0 then powerFrac = 0 elseif powerFrac > 1 then powerFrac = 1 end
    local cpH = classPowerOn and (tonumber(bars.classPowerHeight) or 4) or 0
    if cpH < 2 then cpH = 2 elseif cpH > 30 then cpH = 30 end
    local detachedH = detachedPower and (tonumber(conf.detachedPowerBarHeight) or 6) or 0
    if detachedH < 2 then detachedH = 2 elseif detachedH > 80 then detachedH = 80 end
    local wideW = w
    if classPowerOn and bars.classPowerWidthMode == "custom" then wideW = max(wideW, tonumber(bars.classPowerWidth) or w) end
    if detachedPower then wideW = max(wideW, tonumber(conf.detachedPowerBarWidth) or w) end
    local minX, maxX, minY, maxY = 0, w, 0, h
    if hasPortrait then
        local poX = tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0
        local poY = tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0
        local left, right
        if mode == "RIGHT" then
            left, right = w + 4 + poX, w + 4 + poX + pSize
        else
            left, right = -4 + poX - pSize, -4 + poX
        end
        minX, maxX = min(minX, left), max(maxX, right)
        minY, maxY = min(minY, poY - pSize * 0.5 + h * 0.5), max(maxY, poY + pSize * 0.5 + h * 0.5)
    end
    if classPowerOn then
        local cpW = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (w - 4)) or (w - 4)
        local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
        local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
        minX, maxX = min(minX, cx), max(maxX, cx + cpW)
        minY, maxY = min(minY, cy), max(maxY, cy + cpH)
    end
    if detachedPower then
        local dW = tonumber(conf.detachedPowerBarWidth) or w
        local dx = tonumber(conf.detachedPowerBarOffsetX) or 0
        local dy = tonumber(conf.detachedPowerBarOffsetY) or -4
        local dLeft, dBottom = dx, -detachedH + dy
        if key == "player" and conf.detachedPowerBarAnchorToClassPower == true and classPowerOn then
            local cpW = (bars.classPowerWidthMode == "custom") and (tonumber(bars.classPowerWidth) or (w - 4)) or (w - 4)
            local cx = 2 + (tonumber(bars.classPowerOffsetX) or 0)
            local cy = h + 4 + (tonumber(bars.classPowerOffsetY) or 0)
            dLeft = cx + (cpW - dW) * 0.5 + dx
            dBottom = cy - detachedH + dy
        end
        minX, maxX = min(minX, dLeft), max(maxX, dLeft + dW)
        minY, maxY = min(minY, dBottom), max(maxY, dBottom + detachedH)
    end
    if castEnabled then
        local cLeft, cBottom
        if castDetached then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = (h - castBarH) * 0.5 + castOffsetY
        elseif key == "player" then
            cLeft = (w - castW) * 0.5 + castOffsetX
            cBottom = h + castOffsetY
        else
            cLeft = castOffsetX
            cBottom = h + castOffsetY + ((key == "boss") and 2 or 0)
        end
        local tooFar
        if castDetached then
            tooFar = (abs(castOffsetX) > 260 or abs(castOffsetY) > 180)
        else
            local limitX = max(w * 1.25, 180)
            local limitY = max(h * 3.0, 120)
            tooFar = (cLeft > w + limitX)
                or ((cLeft + castW) < -limitX)
                or (cBottom > h + limitY)
                or ((cBottom + castBarH) < -limitY)
        end
        castPreviewVisible = not tooFar
        if castPreviewVisible then
            wideW = max(wideW, castW)
            minX, maxX = min(minX, cLeft), max(maxX, cLeft + castW)
            minY, maxY = min(minY, cBottom), max(maxY, cBottom + castBarH)
        end
    end
    local auraPreviewState = Auras and Auras.BuildState and Auras.BuildState(key, w, h)
    local centerMinX, centerMaxX, centerMinY, centerMaxY = minX, maxX, minY, maxY
    if auraPreviewState and Auras.ExpandFootprint then
        minX, maxX, minY, maxY = Auras.ExpandFootprint(auraPreviewState, minX, maxX, minY, maxY)
    end
    local footprintW = max(wideW, maxX - minX)
    local footprintH = max(h, maxY - minY)
    local runtimeScale = RuntimeVisualScaleForPreviewKey(key)
    local autoScale = min(1.0, (cw - 60) / max(footprintW * runtimeScale, 1), (ch - 42) / max(footprintH * runtimeScale, 1))
    if autoScale < ZOOM_MIN then autoScale = ZOOM_MIN end
    local manualZoom = tonumber(box._manualZoom)
    local frozenScale = tonumber(box._dragFrozenScale)
    local previewScale = manualZoom and ClampPreviewZoom(manualZoom) or (frozenScale and ClampPreviewZoom(frozenScale) or autoScale)
    local scale = runtimeScale * previewScale
    box._mockRuntimeScale = runtimeScale
    box._mockAutoScale = autoScale
    box._mockScale = previewScale
    box._mockEffectiveScale = scale
    UpdatePreviewZoomControls(box)
    local function S(v) return floor((tonumber(v) or 0) * scale + 0.5) end
    local sw, sh, sp = S(w), S(h), S(pSize)
    local mockOffsetX = -S(((centerMinX + centerMaxX) * 0.5) - (w * 0.5))
    local mockOffsetY = -S(((centerMinY + centerMaxY) * 0.5) - (h * 0.5))
    local panX, panY = tonumber(box._zoomPanX) or 0, tonumber(box._zoomPanY) or 0
    box._mockBaseOffsetX, box._mockBaseOffsetY = mockOffsetX, mockOffsetY
    box._detachedCastPreview = nil
    box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = nil, nil
    local mock = box.mock
    local baseLevel = (canvas.GetFrameLevel and canvas:GetFrameLevel() or 0) + 2
    if mock.SetFrameLevel then mock:SetFrameLevel(baseLevel + 4) end
    if mock.classPower and mock.classPower.SetFrameLevel then
        mock.classPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(bars.classPowerFrameLevelOffset, 5))
    end
    if mock.detachedPower and mock.detachedPower.SetFrameLevel then
        mock.detachedPower:SetFrameLevel(baseLevel + 4 + ClampPreviewLayer(conf.detachedPowerBarFrameLevelOffset, 6))
    end
    if mock.portrait and mock.portrait.SetFrameLevel then mock.portrait:SetFrameLevel(baseLevel + 7) end
    if mock.cast and mock.cast.SetFrameLevel then mock.cast:SetFrameLevel(baseLevel + 6) end
    if mock.textFrame and mock.textFrame.SetFrameLevel then mock.textFrame:SetFrameLevel(baseLevel + 10) end
    local textBase = baseLevel + 12
    if mock.nameLayer and mock.nameLayer.SetFrameLevel then mock.nameLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.nameTextLayer, 5)) end
    if mock.hpLayer and mock.hpLayer.SetFrameLevel then mock.hpLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.hpTextLayer, 5)) end
    if mock.powerLayer and mock.powerLayer.SetFrameLevel then mock.powerLayer:SetFrameLevel(textBase + ClampPreviewLayer(conf.powerTextLayer, 2)) end
    if mock.bounds and mock.bounds.SetFrameLevel then mock.bounds:SetFrameLevel(baseLevel + 48) end
    SetTex(mock.hp, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    SetTex(mock.power, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    SetTex(mock.hpBG, type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture() or TEX_W8)
    SetTex(mock.powerBG, type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture() or TEX_W8)
    SetTex(mock.detachedPower.fill, type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    SetTex(mock.cast.fill, type(_G.MSUF_GetCastbarTexture) == "function" and _G.MSUF_GetCastbarTexture() or TEX_W8)
    mock:SetSize(sw, sh)
    if mock.sizeTag then mock.sizeTag:SetText(format("%d x %d", w, h)) end
    mock:ClearAllPoints()
    mock:SetPoint("CENTER", canvas, "CENTER", mockOffsetX + panX, mockOffsetY + panY)
    local runtimePower = runtimeSpec and runtimeSpec.power
    local powerEnabled = runtimePower and runtimePower.enabled == true
    if runtimePower == nil then powerEnabled = D.ReadPowerBarEnabled(conf, key) end
    local powerOn = powerEnabled and not detachedPower
    local powerH = powerOn and S((runtimePower and runtimePower.height) or ReadPowerBarHeight(conf)) or 0
    if powerOn and powerH < 2 then powerH = 2 end
    mock.hpBG:ClearAllPoints()
    mock.hpBG:SetAllPoints(mock)
    mock.hp:ClearAllPoints()
    local hpReverse = conf.reverseFillBars == true
    if hpReverse then
        mock.hp:SetPoint("TOPRIGHT", mock.hpBG, "TOPRIGHT", 0, 0)
        mock.hp:SetPoint("BOTTOMRIGHT", mock.hpBG, "BOTTOMRIGHT", 0, 0)
    else
        mock.hp:SetPoint("TOPLEFT", mock.hpBG, "TOPLEFT", 0, 0)
        mock.hp:SetPoint("BOTTOMLEFT", mock.hpBG, "BOTTOMLEFT", 0, 0)
    end
    local hpAreaW = max(1, sw)
    local hpFrac = max(0, min(1, tonumber(data.hp) or 0.6))
    mock.hp:SetWidth(max(1, hpAreaW * hpFrac))
    local healPredMode = PreviewResolveHealPredAnchorMode(conf, g)
    local absorbMode = PreviewResolveAbsorbAnchorMode(conf, g)
    local healPredShown = PreviewHealPredictionEnabled(conf, g)
    local absorbShown = PreviewAbsorbBarEnabled(conf, g, key)
    local healPredFrac = ((healPredMode == 3) and min(0.14, max(0.02, 1 - hpFrac))) or 0.14
    if healPredShown then
        local r = tonumber(g and g.healPredColorR) or 0
        local gg = tonumber(g and g.healPredColorG) or 1
        local b = tonumber(g and g.healPredColorB) or 0.4
        mock.healPred:SetVertexColor(r, gg, b, 0.55)
        LayoutUnitPreviewOverlay(mock.healPred, mock.hpBG, mock.hp, healPredMode, healPredFrac, hpReverse, nil, hpAreaW)
    else
        mock.healPred:Hide()
    end
    if absorbShown then
        local absorbAnchor = nil
        if healPredShown and mock.healPred:IsShown() and (healPredMode == 3 or healPredMode == 4) and (absorbMode == 3 or absorbMode == 4) then
            absorbAnchor = mock.healPred
        end
        LayoutUnitPreviewOverlay(mock.absorb, mock.hpBG, mock.hp, absorbMode, 0.10, hpReverse, absorbAnchor, hpAreaW)
    else
        mock.absorb:Hide()
    end
    local hr, hg, hb = HealthColor(key, data)
    local hbr, hbg, hbb, hba = HealthBackgroundColor(hr, hg, hb, data)
    mock.hpBG:SetVertexColor(hbr, hbg, hbb, hba)
    mock.hp:SetVertexColor(hr, hg, hb, 1)
    if powerOn then
        mock.powerBG:Show(); mock.power:Show()
        mock.powerBG:ClearAllPoints()
        mock.powerBG:SetPoint("BOTTOMLEFT", mock, "BOTTOMLEFT", 0, 0)
        mock.powerBG:SetPoint("BOTTOMRIGHT", mock, "BOTTOMRIGHT", 0, 0)
        mock.powerBG:SetHeight(powerH)
        local pr, pg, pb = PowerColor(data.powerToken)
        local pbr, pbg, pbb, pba = PowerBackgroundColor(pr, pg, pb, hr, hg, hb)
        mock.powerBG:SetVertexColor(pbr, pbg, pbb, pba)
        mock.power:ClearAllPoints()
        mock.power:SetPoint("TOPLEFT", mock.powerBG, "TOPLEFT", 0, 0)
        mock.power:SetPoint("BOTTOMLEFT", mock.powerBG, "BOTTOMLEFT", 0, 0)
        mock.power:SetWidth(max(1, sw * powerFrac))
        mock.power:SetVertexColor(pr, pg, pb, 1)
    else
        mock.powerBG:Hide(); mock.power:Hide()
    end
    local fr, fg, fb = FontColor()
    local pr, pg, pb = PowerColor(data.powerToken)
    if classPowerOn then
        mock.classPower:Show()
        local cpW
        if bars.classPowerWidthMode == "custom" then cpW = tonumber(bars.classPowerWidth) or (w - 4) else cpW = w - 4 end
        if cpW < 30 then cpW = w - 4 elseif cpW > 800 then cpW = 800 end
        mock.classPower:SetSize(S(cpW), max(2, S(cpH)))
        mock.classPower:ClearAllPoints()
        mock.classPower:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(2 + (tonumber(bars.classPowerOffsetX) or 0)), S(4 + (tonumber(bars.classPowerOffsetY) or 0)))
        local segCount = 5
        local gap = max(0, S(tonumber(bars.classPowerGap) or 0))
        local segW = floor((S(cpW) - (segCount - 1) * gap) / segCount)
        for i = 1, #mock.classPower.segments do
            local seg = mock.classPower.segments[i]
            if i <= segCount then
                seg:Show()
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", mock.classPower, "TOPLEFT", (i - 1) * (segW + gap), 0)
                seg:SetPoint("BOTTOMLEFT", mock.classPower, "BOTTOMLEFT", (i - 1) * (segW + gap), 0)
                seg:SetWidth(i == segCount and (S(cpW) - (i - 1) * (segW + gap)) or segW)
                local filled = i <= 3
                seg:SetColorTexture(pr, pg, pb, filled and 0.95 or 0.28)
            else
                seg:Hide()
            end
        end
        local classTextOn = bars.classPowerShowText == true
        if classTextOn then
            local cpTextSize = S(tonumber(bars.classPowerFontSize) or 16)
            if cpTextSize < 7 then cpTextSize = 7 end
            mock.classPower.text:SetFont(FONT, cpTextSize, "OUTLINE")
            mock.classPower.text:SetText("3")
            mock.classPower.text:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
            mock.classPower.text:ClearAllPoints()
            mock.classPower.text:SetPoint("CENTER", mock.classPower, "CENTER", S(tonumber(bars.classPowerTextOffsetX) or 0), S(tonumber(bars.classPowerTextOffsetY) or 0))
            mock.classPower.text:Show()
            box.handleClassPowerText:SetSize(max(26, mock.classPower.text:GetStringWidth() + 10), max(18, mock.classPower.text:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleClassPowerText, canvas, { mock.classPower.text }, 3) then
                PlaceHandle(box.handleClassPowerText, mock.classPower.text)
            end
        else
            mock.classPower.text:Hide()
            box.handleClassPowerText:Hide()
        end
        box.handleClassPower:SetSize(max(36, S(cpW)), max(18, max(2, S(cpH)) + 8))
        PlaceHandle(box.handleClassPower, mock.classPower)
    else
        mock.classPower:Hide()
        for i = 1, #mock.classPower.segments do mock.classPower.segments[i]:Hide() end
        if mock.classPower.text then mock.classPower.text:Hide() end
        box.handleClassPower:Hide()
        box.handleClassPowerText:Hide()
    end
    if detachedPower then
        mock.detachedPower:Show()
        local dW = tonumber(conf.detachedPowerBarWidth) or w
        if key == "player" and bars.detachedPowerBarWidthMode and bars.detachedPowerBarWidthMode ~= "manual" then
            dW = classPowerOn and (mock.classPower:GetWidth() / max(scale, 0.01)) or w
        end
        if dW < 20 then dW = 20 elseif dW > 800 then dW = 800 end
        mock.detachedPower:SetSize(S(dW), max(2, S(detachedH)))
        mock.detachedPower:ClearAllPoints()
        local dx = S(tonumber(conf.detachedPowerBarOffsetX) or 0)
        local dy = S(tonumber(conf.detachedPowerBarOffsetY) or -4)
        if key == "player" and conf.detachedPowerBarAnchorToClassPower == true and classPowerOn and mock.classPower:IsShown() then
            mock.detachedPower:SetPoint("TOP", mock.classPower, "BOTTOM", dx, dy)
        else
            mock.detachedPower:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", dx, dy)
        end
        mock.detachedPower.fill:SetVertexColor(pr, pg, pb, 1)
        mock.detachedPower.fill:SetWidth(max(1, S(dW) * powerFrac - 2))
        box.handleDetachedPower:SetSize(max(36, S(dW)), max(18, S(detachedH) + 8))
        PlaceHandle(box.handleDetachedPower, mock.detachedPower)
    else
        mock.detachedPower:Hide()
        box.handleDetachedPower:Hide()
    end
    ApplyPreviewRounded(box, key, powerOn, PreviewRoundedOutlineThickness(key, conf, scale))
    if ApplyPreviewFrameBorder then
        ApplyPreviewFrameBorder(box, runtimeSpec and runtimeSpec.border, scale)
    end
    if ApplyPreviewBoundsGuide then
        local guideEdge = 1
        if mock._msufPreviewRoundedActive == true then
            guideEdge = PreviewRoundedOutlineThickness(key, conf, scale)
        elseif runtimeSpec and runtimeSpec.border and runtimeSpec.border.enabled == true then
            guideEdge = floor(((tonumber(runtimeSpec.border.thickness) or 1) * scale) + 0.5)
        end
        ApplyPreviewBoundsGuide(box, guideEdge)
    end
    local fr, fg, fb = FontColor()
    local baseTextSize = tonumber(g.fontSize) or 14
    local nameSize = S(tonumber(conf.nameFontSize) or tonumber(g.nameFontSize) or baseTextSize); if nameSize < 7 then nameSize = 7 end
    local hpSize = S(tonumber(conf.hpFontSize) or tonumber(g.hpFontSize) or baseTextSize); if hpSize < 7 then hpSize = 7 end
    local pwrSize = S(tonumber(conf.powerFontSize) or tonumber(g.powerFontSize) or baseTextSize); if pwrSize < 7 then pwrSize = 7 end
    mock.nameText:SetFont(FONT, nameSize, "OUTLINE")
    mock.raidGroupNameText:SetFont(FONT, nameSize, "OUTLINE")
    mock.totInlineSep:SetFont(FONT, nameSize, "OUTLINE")
    mock.totInlineText:SetFont(FONT, nameSize, "OUTLINE")
    mock.hpTextLeft:SetFont(FONT, hpSize, "OUTLINE")
    mock.hpTextCenter:SetFont(FONT, hpSize, "OUTLINE")
    mock.hpText:SetFont(FONT, hpSize, "OUTLINE")
    mock.hpTextPct:SetFont(FONT, hpSize, "OUTLINE")
    mock.powerTextLeft:SetFont(FONT, pwrSize, "OUTLINE")
    mock.powerTextCenter:SetFont(FONT, pwrSize, "OUTLINE")
    mock.powerText:SetFont(FONT, pwrSize, "OUTLINE")
    mock.powerTextPct:SetFont(FONT, pwrSize, "OUTLINE")
    mock.nameText:SetTextColor(fr, fg, fb, 1)
    mock.raidGroupNameText:SetTextColor(fr, fg, fb, 1)
    mock.totInlineSep:SetTextColor(0.72, 0.76, 0.84, 1)
    mock.totInlineText:SetTextColor(fr, fg, fb, 1)
    mock.hpTextLeft:SetTextColor(fr, fg, fb, 1)
    mock.hpTextCenter:SetTextColor(fr, fg, fb, 1)
    mock.hpText:SetTextColor(fr, fg, fb, 1)
    mock.hpTextPct:SetTextColor(fr, fg, fb, 1)
    if g.colorPowerTextByType == true then
        local prt, pgt, pbt = PowerColor(data.powerToken)
        mock.powerTextLeft:SetTextColor(prt, pgt, pbt, 1)
        mock.powerTextCenter:SetTextColor(prt, pgt, pbt, 1)
        mock.powerText:SetTextColor(prt, pgt, pbt, 1)
        mock.powerTextPct:SetTextColor(prt, pgt, pbt, 1)
    else
        mock.powerTextLeft:SetTextColor(fr, fg, fb, 1)
        mock.powerTextCenter:SetTextColor(fr, fg, fb, 1)
        mock.powerText:SetTextColor(fr, fg, fb, 1)
        mock.powerTextPct:SetTextColor(fr, fg, fb, 1)
    end
    mock.nameText:SetText(ShortenPreviewName(data.name, key, conf))
    mock.raidGroupNameText:SetText(D.PreviewRaidGroupNameText(conf))
    local hpMax, pMax = 1000000, 240000
    local hpCur, pCur = floor(hpMax * data.hp + 0.5), floor(pMax * powerFrac + 0.5)
    local hpSlots = TextScopeHasSlots(key, "textLeft", "textCenter", "textRight")
    local hpLeftMode, hpCenterMode, hpRightMode
    if hpSlots then
        hpLeftMode = TextScopeSlotGet(key, "textLeft", "NONE", NormalizeHpMode)
        hpCenterMode = TextScopeSlotGet(key, "textCenter", "NONE", NormalizeHpMode)
        hpRightMode = TextScopeSlotGet(key, "textRight", "CURPERCENT", NormalizeHpMode)
    else
        hpLeftMode, hpCenterMode, hpRightMode = "NONE", "NONE", NormalizeHpMode(TextScopeGet(key, "hpTextMode", "CURPERCENT"))
    end
    if TextScopeGet(key, "hpTextReverse", false) == true then
        local rev = { CURPERCENT = "PERCENTCUR", PERCENTCUR = "CURPERCENT", CURMAX = "MAXCUR", MAXCUR = "CURMAX", CURMAXPERCENT = "PERCENTMAXCUR", PERCENTMAXCUR = "CURMAXPERCENT", MAXPERCENT = "PERCENTMAX", PERCENTMAX = "MAXPERCENT", PERCENTCURMAX = "CURMAXPERCENT" }
        hpLeftMode, hpRightMode = hpRightMode, hpLeftMode
        hpLeftMode = rev[hpLeftMode] or hpLeftMode
        hpCenterMode = rev[hpCenterMode] or hpCenterMode
        hpRightMode = rev[hpRightMode] or hpRightMode
    end
    local hpPctValue = floor(data.hp * 100 + 0.5)
    local hpSepRaw = TextScopeGet(key, "hpTextSeparator", "")
    mock.hpTextLeft:SetText(FormatMode(hpLeftMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextCenter:SetText(FormatMode(hpCenterMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpText:SetText(FormatMode(hpRightMode, hpCur, hpMax, hpPctValue, hpSepRaw, false))
    mock.hpTextPct:SetText("")
    local powerSlots = TextScopeHasSlots(key, "powerTextLeft", "powerTextCenter", "powerTextRight")
    local powerLeftMode, powerCenterMode, powerRightMode
    if powerSlots then
        powerLeftMode = TextScopeSlotGet(key, "powerTextLeft", "NONE", NormalizePowerMode)
        powerCenterMode = TextScopeSlotGet(key, "powerTextCenter", "NONE", NormalizePowerMode)
        powerRightMode = TextScopeSlotGet(key, "powerTextRight", "CURPERCENT", NormalizePowerMode)
    else
        powerLeftMode, powerCenterMode, powerRightMode = "NONE", "NONE", NormalizePowerMode(TextScopeGet(key, "powerTextMode", "CURPERCENT"))
    end
    local powerPctValue = floor(powerFrac * 100 + 0.5)
    local powerSepRaw = TextScopeGet(key, "powerTextSeparator", TextScopeGet(key, "hpTextSeparator", ""))
    mock.powerTextLeft:SetText(FormatMode(powerLeftMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextCenter:SetText(FormatMode(powerCenterMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerText:SetText(FormatMode(powerRightMode, pCur, pMax, powerPctValue, powerSepRaw, true))
    mock.powerTextPct:SetText("")
    mock.nameText:SetShown(conf.showName ~= false)
    local raidGroupAnchor = D.NormalizeRaidGroupNameAnchor(conf.raidGroupNameAnchor)
    if conf.showName == false and (raidGroupAnchor == "NAMERIGHT" or raidGroupAnchor == "NAMELEFT") then
        raidGroupAnchor = "CENTER"
    end
    local showRaidGroupName = conf.showRaidGroupInName == true and D.PreviewRaidGroupNameAllowed(key)
    mock.raidGroupNameText:SetShown(showRaidGroupName)
    mock.totInlineSep:Hide()
    mock.totInlineText:Hide()
    local hpTextOn = conf.showHP ~= false
    local powerTextOn = (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true
    mock.hpTextLeft:SetShown(hpTextOn and hpLeftMode ~= "NONE")
    mock.hpTextCenter:SetShown(hpTextOn and hpCenterMode ~= "NONE")
    mock.hpText:SetShown(hpTextOn and hpRightMode ~= "NONE")
    mock.hpTextPct:SetShown(false)
    mock.powerTextLeft:SetShown(powerTextOn and powerLeftMode ~= "NONE")
    mock.powerTextCenter:SetShown(powerTextOn and powerCenterMode ~= "NONE")
    mock.powerText:SetShown(powerTextOn and powerRightMode ~= "NONE")
    mock.powerTextPct:SetShown(false)
    mock.nameText:ClearAllPoints()
    local npt, nrel, nx, njust = ResolveNameAnchor(conf.nameTextAnchor or "LEFT", S(tonumber(conf.nameOffsetX) or 4))
    mock.nameText:SetPoint(npt, mock.textFrame, nrel, nx, S(tonumber(conf.nameOffsetY) or -4))
    mock.nameText:SetJustifyH(njust)
    mock.raidGroupNameText:ClearAllPoints()
    local raidGroupX = S(tonumber(conf.raidGroupNameOffsetX) or 3)
    local raidGroupY = S(tonumber(conf.raidGroupNameOffsetY) or 0)
    if raidGroupAnchor == "NAMERIGHT" then
        mock.raidGroupNameText:SetPoint("LEFT", mock.nameText, "RIGHT", raidGroupX, raidGroupY)
    elseif raidGroupAnchor == "NAMELEFT" then
        mock.raidGroupNameText:SetPoint("RIGHT", mock.nameText, "LEFT", raidGroupX, raidGroupY)
    else
        mock.raidGroupNameText:SetPoint(raidGroupAnchor, mock.textFrame, raidGroupAnchor, raidGroupX, raidGroupY)
    end
    mock.raidGroupNameText:SetJustifyH("LEFT")
    do
        local totConf = (_G.MSUF_DB and _G.MSUF_DB.targettarget) or {}
        local showInline = key == "target" and conf.showName ~= false and totConf.showToTInTargetName == true
        if showInline then
            local sep = ToTInlineSeparator(totConf.totInlineSeparator, totConf.totInlineCustomSeparator)
            local totData = UNIT_DATA.targettarget or { name = "Target" }
            local tr, tg, tb = PreviewNameColor("target", data, fr, fg, fb)
            local ir, ig, ib = PreviewToTInlineColor(totConf.totInlineColorMode, totData, tr, tg, tb, fr, fg, fb)
            mock.totInlineSep:SetText(sep ~= "" and sep or " ")
            mock.totInlineText:SetText(ShortenPreviewName(totData.name, "targettarget", conf))
            mock.totInlineText:SetTextColor(ir, ig, ib, 1)
            local inlineAnchor = (showRaidGroupName and raidGroupAnchor == "NAMERIGHT") and mock.raidGroupNameText or mock.nameText
            mock.totInlineSep:ClearAllPoints()
            mock.totInlineSep:SetPoint("LEFT", inlineAnchor, "RIGHT", S(4), 0)
            mock.totInlineText:ClearAllPoints()
            mock.totInlineText:SetPoint("LEFT", mock.totInlineSep, "RIGHT", S(4), 0)
            mock.totInlineSep:Show()
            mock.totInlineText:Show()
        end
    end
    local function PlacePreviewSlot(fs, parent, point, relPoint, x, y, justify)
        if not fs then return end
        fs:ClearAllPoints()
        fs:SetPoint(point, parent, relPoint, x, y)
        fs:SetJustifyH(justify)
    end
    local function NumField(primary, alias, generalPrimary, generalAlias, fallback)
        local v = conf[primary]
        if v == nil and alias then v = conf[alias] end
        if v == nil and generalPrimary then v = g[generalPrimary] end
        if v == nil and generalAlias then v = g[generalAlias] end
        return tonumber(v) or fallback or 0
    end
    local hpOX = NumField("hpOffsetX", "hpTextOffsetX", "hpOffsetX", "hpTextOffsetX", -4)
    local hpOY = NumField("hpOffsetY", "hpTextOffsetY", "hpOffsetY", "hpTextOffsetY", -4)
    local hpLeftX = hpOX + NumField("hpTextLeftOffsetX", "hpLeftOffsetX", "hpTextLeftOffsetX", "hpLeftOffsetX", 0)
    local hpLeftY = hpOY + NumField("hpTextLeftOffsetY", "hpLeftOffsetY", "hpTextLeftOffsetY", "hpLeftOffsetY", 0)
    local hpCenterX = hpOX + NumField("hpTextCenterOffsetX", "hpCenterOffsetX", "hpTextCenterOffsetX", "hpCenterOffsetX", 0)
    local hpCenterY = hpOY + NumField("hpTextCenterOffsetY", "hpCenterOffsetY", "hpTextCenterOffsetY", "hpCenterOffsetY", 0)
    local hpRightX = hpOX + NumField("hpTextRightOffsetX", "hpRightOffsetX", "hpTextRightOffsetX", "hpRightOffsetX", 0)
    local hpRightY = hpOY + NumField("hpTextRightOffsetY", "hpRightOffsetY", "hpTextRightOffsetY", "hpRightOffsetY", 0)
    PlacePreviewSlot(mock.hpTextLeft, mock.textFrame, "LEFT", "LEFT", S(4 + hpLeftX), S(hpLeftY), "LEFT")
    PlacePreviewSlot(mock.hpTextCenter, mock.textFrame, "CENTER", "CENTER", S(hpCenterX), S(hpCenterY), "CENTER")
    PlacePreviewSlot(mock.hpText, mock.textFrame, "RIGHT", "RIGHT", S(-4 + hpRightX), S(hpRightY), "RIGHT")
    PlacePreviewSlot(mock.hpTextPct, mock.textFrame, "RIGHT", "RIGHT", S(-4 + hpRightX), S(hpRightY), "RIGHT")
    local pOX = NumField("powerOffsetX", "powerTextOffsetX", "powerOffsetX", "powerTextOffsetX", -4)
    local pOY = NumField("powerOffsetY", "powerTextOffsetY", "powerOffsetY", "powerTextOffsetY", 4)
    local pLeftX = pOX + NumField("powerTextLeftOffsetX", "powerLeftOffsetX", "powerTextLeftOffsetX", "powerLeftOffsetX", 0)
    local pLeftY = pOY + NumField("powerTextLeftOffsetY", "powerLeftOffsetY", "powerTextLeftOffsetY", "powerLeftOffsetY", 0)
    local pCenterX = pOX + NumField("powerTextCenterOffsetX", "powerCenterOffsetX", "powerTextCenterOffsetX", "powerCenterOffsetX", 0)
    local pCenterY = pOY + NumField("powerTextCenterOffsetY", "powerCenterOffsetY", "powerTextCenterOffsetY", "powerCenterOffsetY", 0)
    local pRightX = pOX + NumField("powerTextRightOffsetX", "powerRightOffsetX", "powerTextRightOffsetX", "powerRightOffsetX", 0)
    local pRightY = pOY + NumField("powerTextRightOffsetY", "powerRightOffsetY", "powerTextRightOffsetY", "powerRightOffsetY", 0)
    if detachedPower and conf.detachedPowerBarTextOnBar == true and mock.detachedPower:IsShown() then
        PlacePreviewSlot(mock.powerTextLeft, mock.detachedPower, "LEFT", "LEFT", S(4 + pLeftX), S(pLeftY), "LEFT")
        PlacePreviewSlot(mock.powerTextCenter, mock.detachedPower, "CENTER", "CENTER", S(pCenterX), S(pCenterY), "CENTER")
        PlacePreviewSlot(mock.powerText, mock.detachedPower, "RIGHT", "RIGHT", S(-4 + pRightX), S(pRightY), "RIGHT")
        PlacePreviewSlot(mock.powerTextPct, mock.detachedPower, "RIGHT", "RIGHT", S(-4 + pRightX), S(pRightY), "RIGHT")
    else
        PlacePreviewSlot(mock.powerTextLeft, mock.textFrame, "BOTTOMLEFT", "BOTTOMLEFT", S(4 + pLeftX), S(1 + pLeftY), "LEFT")
        PlacePreviewSlot(mock.powerTextCenter, mock.textFrame, "BOTTOM", "BOTTOM", S(pCenterX), S(1 + pCenterY), "CENTER")
        PlacePreviewSlot(mock.powerText, mock.textFrame, "BOTTOMRIGHT", "BOTTOMRIGHT", S(-4 + pRightX), S(1 + pRightY), "RIGHT")
        PlacePreviewSlot(mock.powerTextPct, mock.textFrame, "BOTTOMRIGHT", "BOTTOMRIGHT", S(-4 + pRightX), S(1 + pRightY), "RIGHT")
    end
    if hasPortrait then
        mock.portrait:Show()
        mock.portrait:SetSize(sp, sp)
        mock.portrait:ClearAllPoints()
        local ox = S(tonumber(PortraitStyleGet(key, "portraitOffsetX", 0)) or 0)
        local oy = S(tonumber(PortraitStyleGet(key, "portraitOffsetY", 0)) or 0)
        if mode == "RIGHT" then mock.portrait:SetPoint("LEFT", mock, "RIGHT", S(4) + ox, oy)
        else mock.portrait:SetPoint("RIGHT", mock, "LEFT", -S(4) + ox, oy) end
        local cr, cg, cb = ClassColor(data.class)
        local renderMode = PortraitStyleGet(key, "portraitRender", "2D")
        if renderMode == "CLASS" then
            local visual = ClassPortraitVisual(data.class, PortraitStyleGet(key, "portraitClassStyle", "BLIZZARD"))
            if visual and visual.atlas and mock.portrait.tex.SetAtlas then
                mock.portrait.tex:SetAtlas(visual.atlas)
            else
                mock.portrait.tex:SetTexture(visual and visual.texture or "Interface\\ICONS\\INV_Misc_QuestionMark")
                if mock.portrait.tex.SetTexCoord then
                    mock.portrait.tex:SetTexCoord(
                        (visual and visual.left) or 0,
                        (visual and visual.right) or 1,
                        (visual and visual.top) or 0,
                        (visual and visual.bottom) or 1
                    )
                end
            end
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            mock.portrait.initial:Hide()
        else
            mock.portrait.tex:SetTexture(UnitPreviewPortraitTexture(key, data))
            if mock.portrait.tex.SetVertexColor then mock.portrait.tex:SetVertexColor(1, 1, 1, 1) end
            if mock.portrait.tex.SetTexCoord then
                mock.portrait.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            mock.portrait.initial:Hide()
        end
        if PortraitStyleGet(key, "portraitBgEnabled", false) == true then
            mock.portrait:SetBackdropColor(
                g.portraitBgColorR or 0.05,
                g.portraitBgColorG or 0.05,
                g.portraitBgColorB or 0.05,
                g.portraitBgColorA or 0.85
            )
        else
            mock.portrait:SetBackdropColor(0.03, 0.035, 0.05, 1)
        end
        local bStyle = PortraitStyleGet(key, "portraitBorderStyle", "NONE")
        if bStyle == "NONE" then
            mock.portrait:SetBackdropBorderColor(0, 0, 0, 0)
        elseif bStyle == "CUSTOM" or bStyle == "SOLID" then
            mock.portrait:SetBackdropBorderColor(
                g.portraitBorderColorR or 1,
                g.portraitBorderColorG or 1,
                g.portraitBorderColorB or 1,
                g.portraitBorderColorA or 1
            )
        elseif bStyle == "CLASS_COLOR" then
            mock.portrait:SetBackdropBorderColor(cr, cg, cb, 1)
        elseif bStyle == "REACTION" then
            local hostile = (key == "target" or key == "boss" or key == "focus" or key == "focustarget")
            mock.portrait:SetBackdropBorderColor(hostile and 1 or 0.1, hostile and 0.2 or 0.85, 0.1, 1)
        else
            mock.portrait:SetBackdropBorderColor(1, 1, 1, 1)
        end
        box.handlePortrait:SetSize(max(18, sp), max(18, sp))
        PlaceHandle(box.handlePortrait, mock.portrait)
    else
        mock.portrait:Hide()
        box.handlePortrait:Hide()
    end
    if castPreviewVisible then
        mock.cast:Show()
        if type(_G.MSUF_GetCastbarBackgroundColor) == "function" then
            local br, bg, bb, ba = _G.MSUF_GetCastbarBackgroundColor()
            mock.cast:SetBackdropColor(br or 0.10, bg or 0.10, bb or 0.10, ba or 0.85)
        end
        local scw, sch = max(20, S(castW)), max(6, S(castBarH))
        mock.cast:SetSize(scw, sch)
        if mock.cast.sizeTag then
            mock.cast.sizeTag:SetText(format("%d x %d", floor(castW + 0.5), floor(castBarH + 0.5)))
            mock.cast.sizeTag:Show()
        end
        mock.cast:ClearAllPoints()
        if castDetached then
            box._detachedCastPreview = true
            box._detachedCastBaseOffsetX, box._detachedCastBaseOffsetY = S(castOffsetX), S(castOffsetY)
            mock.cast:SetPoint("CENTER", canvas, "CENTER", box._detachedCastBaseOffsetX + panX, box._detachedCastBaseOffsetY + panY)
        elseif key == "player" then
            mock.cast:SetPoint("BOTTOM", mock, "TOP", S(castOffsetX), S(castOffsetY))
        else
            mock.cast:SetPoint("BOTTOMLEFT", mock, "TOPLEFT", S(castOffsetX), S(castOffsetY + ((key == "boss") and 2 or 0)))
        end
        local cr, cg, cb = 0.0, 0.9, 0.8
        if type(_G.MSUF_GetInterruptibleCastColor) == "function" then
            cr, cg, cb = _G.MSUF_GetInterruptibleCastColor()
        end
        mock.cast.fill:SetVertexColor(cr or 0.0, cg or 0.9, cb or 0.8, 1)
        local showIcon = CastbarShowIcon(key, g)
        mock.cast.icon:SetShown(showIcon)
        local iconX = ReadCastbarNum(g, key, "IconOffsetX", "bossCastIconOffsetX", 0)
        local iconY = ReadCastbarNum(g, key, "IconOffsetY", "bossCastIconOffsetY", 0)
        local iconSize = ReadCastbarNum(g, key, "IconSize", "bossCastIconSize", castBarH)
        if iconSize < 6 then iconSize = 6 elseif iconSize > 128 then iconSize = 128 end
        local sIcon = max(6, S(iconSize))
        local iconDetached = showIcon and (iconX ~= 0 or iconY ~= 0)
        if showIcon then
            mock.cast.icon:SetSize(sIcon, sIcon)
            mock.cast.icon:ClearAllPoints()
            mock.cast.icon:SetPoint("LEFT", mock.cast, "LEFT", S(iconX), S(iconY))
            box.handleCastbarIcon:SetSize(max(18, sIcon + 8), max(18, sIcon + 8))
            PlaceHandle(box.handleCastbarIcon, mock.cast.icon)
        else
            box.handleCastbarIcon:Hide()
        end
        mock.cast.fill:ClearAllPoints()
        if showIcon and not iconDetached then
            mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", sIcon + S(1), -S(1))
        else
            mock.cast.fill:SetPoint("TOPLEFT", mock.cast, "TOPLEFT", S(1), -S(1))
        end
        local timeReserve = max(S(2), min(S(60), floor(scw * 0.34 + 0.5)))
        mock.cast.fill:SetPoint("BOTTOMRIGHT", mock.cast, "BOTTOMRIGHT", -timeReserve, S(1))
        local showText = CastbarShowText(key, g)
        mock.cast.text:SetShown(showText)
        if showText then
            local tr, tg, tb = fr, fg, fb
            if type(_G.MSUF_GetCastbarTextColor) == "function" then
                tr, tg, tb = _G.MSUF_GetCastbarTextColor()
            end
            mock.cast.text:SetTextColor(tr, tg, tb, 1)
            local textSize = ReadCastbarNum(g, key, "SpellNameFontSize", "bossCastSpellNameFontSize", g.castbarSpellNameFontSize or g.fontSize or 14)
            if not textSize or textSize <= 0 then textSize = g.fontSize or 14 end
            mock.cast.text:SetFont(FONT, max(7, S(textSize)), "OUTLINE")
            mock.cast.text:ClearAllPoints()
            local textX = ReadCastbarNum(g, key, "TextOffsetX", "bossCastTextOffsetX", 0)
            local textY = ReadCastbarNum(g, key, "TextOffsetY", "bossCastTextOffsetY", 0)
            mock.cast.text:SetPoint("LEFT", mock.cast.fill, "LEFT", S(2 + textX), S(textY))
            mock.cast.text:SetPoint("RIGHT", mock.cast.time, "LEFT", -S(6), 0)
            mock.cast.text:SetText(TR(key == "boss" and "Celestial Ruin" or "Arcane Surge"))
            box.handleCastbarText:SetSize(max(34, mock.cast.text:GetStringWidth() + 10), max(18, mock.cast.text:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarText, canvas, { mock.cast.text }, 3) then
                PlaceHandle(box.handleCastbarText, mock.cast.text)
            end
        else
            box.handleCastbarText:Hide()
        end
        local showTime = key == "boss" and g.showBossCastTime ~= false
            or (key == "target" and g.showTargetCastTime ~= false)
            or (key == "focus" and g.showFocusCastTime ~= false)
            or (key == "player" and g.showPlayerCastTime ~= false)
        mock.cast.time:SetShown(showTime)
        mock.cast.time:SetText(FormatCastbarPreviewTime(g, key, 1.4, 2.0))
        if showTime then
            local timeX = ReadCastbarNum(g, key, "TimeOffsetX", "bossCastTimeOffsetX", g.castbarPlayerTimeOffsetX or -2)
            local timeY = ReadCastbarNum(g, key, "TimeOffsetY", "bossCastTimeOffsetY", g.castbarPlayerTimeOffsetY or 0)
            if key == "boss" then
                timeX = -2 + (tonumber(g.bossCastTimeOffsetX) or 0)
                timeY = tonumber(g.bossCastTimeOffsetY) or 0
            end
            local timeSize = ReadCastbarNum(g, key, "TimeFontSize", "bossCastTimeFontSize", g.castbarTimeFontSize or g.fontSize or 14)
            if not timeSize or timeSize <= 0 then timeSize = g.fontSize or 14 end
            mock.cast.time:SetFont(FONT, max(7, S(timeSize)), "OUTLINE")
            mock.cast.time:ClearAllPoints()
            mock.cast.time:SetPoint("RIGHT", mock.cast.fill, "RIGHT", S(timeX), S(timeY))
            box.handleCastbarTime:SetSize(max(28, mock.cast.time:GetStringWidth() + 10), max(18, mock.cast.time:GetStringHeight() + 6))
            if not UnitPreviewText.PlaceHandleAroundRegions(box.handleCastbarTime, canvas, { mock.cast.time }, 3) then
                PlaceHandle(box.handleCastbarTime, mock.cast.time)
            end
        else
            box.handleCastbarTime:Hide()
        end
        box.handleCastbar:SetSize(max(36, scw), max(18, sch + 8))
        PlaceHandle(box.handleCastbar, mock.cast)
    else
        mock.cast:Hide()
        if mock.cast.sizeTag then mock.cast.sizeTag:Hide() end
        box.handleCastbar:Hide()
        box.handleCastbarIcon:Hide()
        box.handleCastbarText:Hide()
        box.handleCastbarTime:Hide()
    end
    if Auras and Auras.Layout then
        Auras.Layout(box, mock, auraPreviewState, S, baseLevel)
    end
    local statusLayerAvailable = false
    for i = 1, #D.STATUS_PREVIEW do
        local spec = D.STATUS_PREVIEW[i]
        local icon = mock.icons[spec.id]
        local handle = box.statusHandles[spec.id]
        local showVal = conf[spec.show]
        if showVal == nil then showVal = g[spec.show] end
        local show = (showVal == nil) and (spec.defaultShow ~= false) or (showVal ~= false)
        if spec.allowed and not spec.allowed(key) then show = false end
        if spec.id == "elite" and not data.elite then show = false end
        if Preview.GetStatusPreviewMode() ~= "all" then
            local selected = NormalizeStatusPreviewId(Preview.selectedStatusId)
            if selected == "" then selected = "raidmarker" end
            show = show and (spec.id == selected)
        end
        icon:SetShown(show)
        if show then
            statusLayerAvailable = true
            local rawSize = tonumber(conf[spec.size]) or tonumber(g[spec.size]) or spec.defaultSize
            local sz = S(rawSize)
            if spec.id == "level" then
                if sz < 7 then sz = 7 end
            elseif sz < 10 then
                sz = 10
            end
            if icon.SetFrameLevel then
                local rawLayer = spec.layer and (tonumber(conf[spec.layer]) or tonumber(g[spec.layer])) or spec.defaultLayer
                icon:SetFrameLevel(textBase + ClampPreviewLayer(rawLayer, spec.defaultLayer or 7))
            end
            SetPreviewIconTexture(icon, spec, conf, g, key, data)
            if spec.id == "level" then
                local anchor = ResolveStatusPreviewAnchor(spec, conf, g)
                local x = S(tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0)
                local y = S(tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
                if icon.txt then
                    icon.txt:SetFont(FONT, max(7, sz), "OUTLINE")
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("LEFT", icon, "LEFT", 0, 0)
                    icon.txt:SetJustifyH("LEFT")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                PositionLevelPreview(icon, anchor, x, y, mock, S(6))
            elseif spec.id == "statusText" then
                local anchor = ResolveStatusPreviewAnchor(spec, conf, g)
                local x = S(tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0)
                local y = S(tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
                if icon.txt then
                    icon.txt:SetFont(FONT, max(7, sz), "OUTLINE")
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local textW = icon.txt and icon.txt.GetStringWidth and icon.txt:GetStringWidth() or sz
                local textH = icon.txt and icon.txt.GetStringHeight and icon.txt:GetStringHeight() or sz
                icon:SetSize(max(1, floor((tonumber(textW) or sz) + 0.5)), max(1, floor((tonumber(textH) or sz) + 0.5)))
                PositionSameAnchorPreview(icon, anchor, x, y, mock.hpBG or mock)
            else
                icon:SetSize(sz, sz)
                if icon.txt then
                    icon.txt:SetFont(FONT, max(7, floor(sz * 0.52 + 0.5)), "OUTLINE")
                    icon.txt:ClearAllPoints()
                    icon.txt:SetPoint("CENTER")
                    icon.txt:SetJustifyH("CENTER")
                end
                local anchor = ResolveStatusPreviewAnchor(spec, conf, g)
                local x = S(tonumber(conf[spec.x]) or tonumber(g[spec.x]) or spec.defaultX or 0)
                local y = S(tonumber(conf[spec.y]) or tonumber(g[spec.y]) or spec.defaultY or 0)
                if spec.id == "raidmarker" then
                    PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, true)
                elseif spec.id == "leader" or spec.id == "elite" then
                    PositionRuntimeLayoutIconPreview(icon, anchor, x, y, mock, false)
                elseif spec.id == "statusCombat" or spec.id == "statusResting" or spec.id == "statusIncomingRes" then
                    PositionStatusCornerPreview(icon, anchor, x, y, mock, S(2))
                else
                    PositionFromAnchor(icon, anchor, x, y, mock, sz)
                end
            end
            handle:SetSize(max(18, icon:GetWidth() + 8), max(18, icon:GetHeight() + 8))
            PlaceHandle(handle, icon)
        else
            handle:Hide()
        end
    end
    if showRaidGroupName then
        statusLayerAvailable = true
    end
    box.layerAvailable = {
        guides = true,
        body = true,
        nameText = conf.showName ~= false,
        hpText = conf.showHP ~= false,
        powerText = (key ~= "focustarget" and conf.showPower ~= false) or conf.showPower == true,
        portrait = hasPortrait,
        power = powerEnabled == true,
        classPower = classPowerOn,
        castbar = castEnabled,
        auras = auraPreviewState ~= nil,
        status = statusLayerAvailable,
        bounds = true,
    }
    for i = 1, #(box.layerButtons or {}) do
        if box.layerButtons[i].refresh then box.layerButtons[i]:refresh() end
    end
    local nameHandleW = mock.nameText:GetStringWidth() + 10
    if mock.totInlineSep and mock.totInlineSep:IsShown() then
        nameHandleW = nameHandleW + mock.totInlineSep:GetStringWidth() + mock.totInlineText:GetStringWidth() + S(8)
    end
    box.handleName:SetSize(max(46, nameHandleW), max(18, mock.nameText:GetStringHeight() + 6))
    if not UnitPreviewText.PlaceHandleAroundRegions(box.handleName, canvas, { mock.nameText, mock.totInlineSep, mock.totInlineText }, 3) then
        PlaceHandle(box.handleName, mock.nameText)
    end
    local function PlaceTextSlotHandle(handle, region)
        if not handle then return end
        if not (region and region.IsShown and region:IsShown()) then
            handle:Hide()
            return
        end
        local w = (region.GetStringWidth and region:GetStringWidth()) or region:GetWidth() or 36
        local h = (region.GetStringHeight and region:GetStringHeight()) or region:GetHeight() or 12
        handle:SetSize(max(26, w + 10), max(18, h + 6))
        if not UnitPreviewText.PlaceHandleAroundRegions(handle, canvas, { region }, 3) then
            PlaceHandle(handle, region)
        end
    end
    PlaceTextSlotHandle(box.handleRaidGroupName, mock.raidGroupNameText)
    if UnitPreviewTextMovesTogether(key, "hp") then
        SetShownSafe(box.handleHPLeft, false)
        SetShownSafe(box.handleHPCenter, false)
        SetShownSafe(box.handleHPRight, false)
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handleHP, canvas, { mock.hpTextLeft, mock.hpTextCenter, mock.hpText }, 3) then
            if not ((mock.hpTextLeft and mock.hpTextLeft:IsShown()) or (mock.hpTextCenter and mock.hpTextCenter:IsShown()) or (mock.hpText and mock.hpText:IsShown())) then
                box.handleHP:Hide()
            else
                box.handleHP:SetSize(max(46, mock.hpText:GetStringWidth() + 10), max(18, mock.hpText:GetStringHeight() + 6))
                PlaceHandle(box.handleHP, mock.hpText)
            end
        end
    else
        if box.handleHP then box.handleHP:Hide() end
        PlaceTextSlotHandle(box.handleHPLeft, mock.hpTextLeft)
        PlaceTextSlotHandle(box.handleHPCenter, mock.hpTextCenter)
        PlaceTextSlotHandle(box.handleHPRight, mock.hpText)
    end
    if UnitPreviewTextMovesTogether(key, "power") then
        SetShownSafe(box.handlePowerLeft, false)
        SetShownSafe(box.handlePowerCenter, false)
        SetShownSafe(box.handlePowerRight, false)
        if not UnitPreviewText.PlaceHandleAroundRegions(box.handlePower, canvas, { mock.powerTextLeft, mock.powerTextCenter, mock.powerText }, 3) then
            if not ((mock.powerTextLeft and mock.powerTextLeft:IsShown()) or (mock.powerTextCenter and mock.powerTextCenter:IsShown()) or (mock.powerText and mock.powerText:IsShown())) then
                box.handlePower:Hide()
            else
                box.handlePower:SetSize(max(46, mock.powerText:GetStringWidth() + 10), max(18, mock.powerText:GetStringHeight() + 6))
                PlaceHandle(box.handlePower, mock.powerText)
            end
        end
    else
        if box.handlePower then box.handlePower:Hide() end
        PlaceTextSlotHandle(box.handlePowerLeft, mock.powerTextLeft)
        PlaceTextSlotHandle(box.handlePowerCenter, mock.powerTextCenter)
        PlaceTextSlotHandle(box.handlePowerRight, mock.powerText)
    end
    ApplyPreviewLayerVisibility(box)
    ApplyPreviewTransparency(box, conf)
    RefreshHandleSelectionVisuals(box)
end
Preview._BuildPreview = BuildPreview
Preview._PreviewInCombat = PreviewInCombat
