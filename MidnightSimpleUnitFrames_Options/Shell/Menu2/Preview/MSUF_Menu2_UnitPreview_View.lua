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
local PreviewHelpers = M2.PreviewHelpers or {}
local function RegisterUnitPreviewControl(widget, semanticPath, label, kind, classification, extra, pageKey)
    local page = M2.UnitPage
    if page and type(page.RegisterControl) == "function" then
        page.RegisterControl(widget, { key = pageKey or M2.activeKey }, "preview." .. tostring(semanticPath), label, kind, classification, extra)
    end
    return widget
end
local UNIT_PREVIEW_ZOOM_CONTROLS = {
    { "zoomOutButton", "zoom.out", "Zoom out" },
    { "zoomFitButton", "zoom.fit", "Fit preview" },
    { "zoomOneButton", "zoom.one_to_one", "Pixel preview" },
    { "zoomInButton", "zoom.in", "Zoom in" },
    { "zoomHelpButton", "zoom.help", "Preview controls help" },
    { "zoomLockButton", "zoom.lock", "Lock preview zoom" },
}
function Preview.ResolveUnitHandleSection(handle, unitOrPageKey)
    local fields = handle and handle._fields or {}
    local unitKey = tostring(unitOrPageKey or "")
    unitKey = unitKey:match("^uf_(.+)$") or unitKey
    if unitKey == "" then
        local box = handle and handle._preview
        unitKey = (box and box.key) or tostring(M2.activeKey or ""):match("^uf_(.+)$") or "player"
    end
    if unitKey == "player" and fields.playerSection then return fields.playerSection end
    return fields.section
end
local function UnitPreviewHandleNavigationKey(handle, pageKey)
    if Preview.ResolveUnitHandleSection(handle, pageKey) == "classPower" then return "classpower" end
    return pageKey or M2.activeKey
end
local function RegisterUnitPreviewRuntimeControls(box, pageKey)
    if not box then return 0 end
    pageKey = pageKey or M2.activeKey
    local registrationSentinel = box.zoomBar or box.canvas
    if pageKey
        and box._msuf2RuntimeControlsPageKey == pageKey
        and registrationSentinel
        and type(M2.IsRuntimeControlRegisteredForWidget) == "function"
        and M2.IsRuntimeControlRegisteredForWidget(registrationSentinel, pageKey)
    then
        return 0
    end
    local count = 0
    local function Register(widget, semanticPath, label, kind, classification, extra)
        if not widget then return end
        RegisterUnitPreviewControl(widget, semanticPath, label, kind, classification, extra, pageKey)
        count = count + 1
    end
    box._msuf2ZoomCommand = box._msuf2ZoomCommand
        or (PreviewHelpers.BuildZoomCommand and PreviewHelpers.BuildZoomCommand(box, PreviewZoomPan, "UNIT_PREVIEW_ASSISTANT_ZOOM"))
    Register(box.zoomBar, "zoom.surface", "Unit Preview Zoom", "slider", "ephemeral", {
        help = "Sets the Unit preview zoom percentage; Fit and 1:1 remain available as exact actions.",
        command = box._msuf2ZoomCommand,
    })
    for i = 1, #UNIT_PREVIEW_ZOOM_CONTROLS do
        local info = UNIT_PREVIEW_ZOOM_CONTROLS[i]
        Register(box[info[1]], info[2], info[3], "button", "ephemeral")
    end
    local controlsHint = box._msuf2PreviewControlsHint
    Register(controlsHint and controlsHint._close, "hint.dismiss", "Dismiss preview tip", "button", "ephemeral")
    local previewUnitKey = tostring(pageKey or ""):match("^uf_(.+)$") or box.key
    box._msuf2PanCommand = box._msuf2PanCommand or (PreviewHelpers.BuildPanCommand and PreviewHelpers.BuildPanCommand(
        box, PreviewZoomPan,
        function(dx, dy)
            if type(Preview.Pan) ~= "function" then return false end
            local unit = (box._msuf2PanCommand and box._msuf2PanCommand.previewUnitKey) or box.key or previewUnitKey
            return Preview.Pan(unit, dx, dy)
        end,
        { previewSurface = "unit", previewUnitKey = previewUnitKey }
    ))
    if box._msuf2PanCommand then box._msuf2PanCommand.previewUnitKey = previewUnitKey end
    Register(box.canvas, "canvas", "Unit frame preview canvas", "canvas", "ephemeral", {
        help = "Pans this exact Unit preview canvas by an explicit X/Y delta.",
        command = box._msuf2PanCommand,
    })
    Register(box.animateCombatButton, "combat_animation", "Unit Preview Animation", "button", "ephemeral")
    for i = 1, #(box.layerButtons or {}) do
        local button = box.layerButtons[i]
        if button and (button.key ~= "classPower" or previewUnitKey == "player") then
            Register(button, "layer." .. tostring(button.key),
                tostring((button.fs and button.fs.GetText and button.fs:GetText()) or button.key or "Preview layer") .. " preview layer",
                "button", "ephemeral")
        end
    end
    for i = 1, #(box.handles or {}) do
        local handle = box.handles[i]
        local key = handle and handle._key
        local fields = handle and handle._fields or {}
        local exposeHandle = handle and not (fields.classPower == true and previewUnitKey ~= "player")
        if exposeHandle and handle._msuf2CommandAction then handle._msuf2CommandAction.previewUnitKey = previewUnitKey end
        -- Drag handles are direct-manipulation surfaces, not deterministic
        -- one-shot actions. Their underlying offsets remain Assistant-visible
        -- through the bound sliders; the adjacent gear is navigation.
        if exposeHandle then Register(handle, "handle." .. tostring(key), handle._label or key, "button", "ephemeral") end
        local gear = exposeHandle and handle._msuf2SettingsGear
        if gear and gear._msuf2UnitPreviewOpenCommand then
            Register(gear, "handle." .. tostring(key) .. ".open_settings",
                "Open " .. tostring((handle and handle._label) or key or "preview element") .. " settings",
                "button", "action", {
                    historyMode = "none",
                    help = "Click the highlighted preview button to jump directly to this element's settings below.",
                    command = gear._msuf2UnitPreviewOpenCommand,
                })
        else
            Register(gear, "handle." .. tostring(key) .. ".open_settings",
                "Open " .. tostring((handle and handle._label) or key or "preview element") .. " settings",
                "button", "navigation", { navigationKey = UnitPreviewHandleNavigationKey(handle, pageKey) })
        end
    end
    -- Selection chrome. Most X/Y edits remain ephemeral because they follow the
    -- current handle. The Player Dispel Symbol has no duplicate scalar sliders,
    -- so its two exact fields are reviewed dynamic setting surfaces.
    Register(box._msuf2ElementPicker, "element_picker", "Unit Preview Element Picker", "button", "ephemeral")
    local selectionBar = box._msuf2SelectionBar
    if selectionBar then
        if previewUnitKey == "player" and M2.PreviewSelectionBar then
            local selectionAPI = M2.PreviewSelectionBar
            selectionAPI.BindExactOffsetSearchTarget(selectionBar.editX, box, "dispelSymbol")
            selectionAPI.BindExactOffsetSearchTarget(selectionBar.editY, box, "dispelSymbol")
            Register(selectionBar.editX, "selection.dispel_symbol_offset_x", "UnitFrame Dispel Symbol Offset X",
                "textinput", "setting", {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "The shared Preview X field is pinned to the Player-owned Dispel Symbol handle for this exact Assistant route.",
                    assistantSettingKeys = { "player.unitDispelSymbolX" },
                    command = selectionAPI.BuildExactOffsetCommand(box, "dispelSymbol", "x", {
                        previewSurface = "unit", previewUnitKey = "player",
                    }),
                })
            Register(selectionBar.editY, "selection.dispel_symbol_offset_y", "UnitFrame Dispel Symbol Offset Y",
                "textinput", "setting", {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "The shared Preview Y field is pinned to the Player-owned Dispel Symbol handle for this exact Assistant route.",
                    assistantSettingKeys = { "player.unitDispelSymbolY" },
                    command = selectionAPI.BuildExactOffsetCommand(box, "dispelSymbol", "y", {
                        previewSurface = "unit", previewUnitKey = "player",
                    }),
                })
        end
        Register(selectionBar.resetButton, "selection.reset", "Reset selected preview element offset", "button", "ephemeral")
        Register(selectionBar.openButton, "selection.open_settings", "Open selected preview element settings", "button", "navigation", {
            navigationKey = UnitPreviewHandleNavigationKey(box._selectedHandle, pageKey),
        })
    end
    box._msuf2RuntimeControlsPageKey = pageKey
    return count
end
function Preview.RegisterRuntimeControlsForPage(box, pageKey)
    return RegisterUnitPreviewRuntimeControls(box, pageKey)
end
local Pick = M2.Pick
local AssignNamedValues = M2.AssignNamedValues
local F = M2.Fallbacks or {}
local PreviewModel = Preview.Model or {}
local UNIT_LABELS, UNIT_DATA, PreviewRaidGroupNameAllowed, PreviewRaidGroupNameText, NormalizePreviewRaidGroupNameAnchor, CanonKey, CurrentPanelKey, UnitDB, NormalizeHpMode, NormalizePowerMode, TextScopeGet, TextScopeHasSlots, TextScopeSlotGet, ToTInlineSeparator, ShortenPreviewName, ForceTextUnit, ApplyPanelUnit, EnsureUnitPortraitStyle, PortraitStyleGet, ApplyPortrait, NormalizeStatusPreviewId, ClassColor, HealthColor, DarkMatchHPColor, HealthBackgroundColor, PowerBackgroundColor, PowerColor, ClassPortraitVisual, UnitPreviewPortraitTexture, FontColor, PreviewNameColor, PreviewToTInlineColor, SetTex, PreviewHealPredictionEnabled, PreviewResolveHealPredAnchorMode, PreviewResolveAbsorbAnchorMode, PreviewAbsorbBarEnabled, LayoutUnitPreviewOverlay, MakeFS, ReadPowerBarEnabled, CanDetachPowerBarKey, ReadPowerBarHeight, ResolveNameAnchor, ResolveNameOffsetDelta, FormatMode, UnitPreviewText = Pick(PreviewModel, [[UNIT_LABELS UNIT_DATA PreviewRaidGroupNameAllowed PreviewRaidGroupNameText NormalizePreviewRaidGroupNameAnchor CanonKey CurrentPanelKey UnitDB NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet ToTInlineSeparator ShortenPreviewName ForceTextUnit ApplyPanelUnit EnsureUnitPortraitStyle PortraitStyleGet ApplyPortrait NormalizeStatusPreviewId ClassColor HealthColor DarkMatchHPColor HealthBackgroundColor PowerBackgroundColor PowerColor ClassPortraitVisual UnitPreviewPortraitTexture FontColor PreviewNameColor PreviewToTInlineColor SetTex PreviewHealPredictionEnabled PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewAbsorbBarEnabled LayoutUnitPreviewOverlay MakeFS ReadPowerBarEnabled CanDetachPowerBarKey ReadPowerBarHeight ResolveNameAnchor ResolveNameOffsetDelta FormatMode UnitPreviewText]])
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
local function ReadHandleOffsets(handle)
    if not handle then return 0, 0 end
    local preview = handle._preview
    local fields = handle._fields or {}
    if type(fields.readOffsets) == "function" then
        local x, y, xKey, yKey = fields.readOffsets(handle)
        if x ~= nil and y ~= nil then return x, y, xKey, yKey end
    end
    local xKey, yKey, defX, defY = ResolveHandleFields(preview, fields)
    local store, _, conf, general = HandleStore(preview, fields)
    local function ReadValue(key)
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
    local x = ReadValue(xKey)
    local y = ReadValue(yKey)
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
--- The hint line is a message surface, nothing else. The selected element, its
--- offsets and its actions live in the selection bar, and the full control list
--- lives behind the ? button, so this text no longer changes shape per
--- selection. Layer rows still borrow it for transient feedback and restore it
--- through UpdateHandleHint.
local function DefaultPreviewHint(box)
    local base
    if box and not PreviewGuidesVisible(box) then
        base = TR("guides hidden - arrows still nudge the selected element")
    else
        base = TR("drag to move - Tab picks the next element - ? lists every control")
    end
    -- Red, and only until the gesture has actually been used three times.
    local remaining = PreviewHelpers.PreviewMoveHintRemaining and PreviewHelpers.PreviewMoveHintRemaining() or 0
    if remaining > 0 then
        return format("|cffff4d3f%s|r   %s", format(TR("Drag background (%dx)"), remaining), base)
    end
    return base
end
local function UpdateHandleHint(box, handle)
    if not box then return end
    if M2.PreviewSelectionBar then M2.PreviewSelectionBar.Refresh(box) end
    if not box.hint then return end
    box.hint:SetText(DefaultPreviewHint(box))
end
local OpenPreviewHandleSettings
local MenuTheme
local function RefreshHandleSelectionVisuals(box)
    if not box then return end
    if not box._selectedHandle and Preview.RestoreQueuedHandle(box) then return end
    local guidesOn = PreviewGuidesVisible(box)
    local selected = box._selectedHandle
    if selected and selected.IsShown and not selected:IsShown() then selected = nil; box._selectedHandle = nil end
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
            openSettings = function(handle) return OpenPreviewHandleSettings(handle, "gear") end,
        })
        local previewPageKey = box._msuf2PinnedPreviewPageKey or M2.activeKey
        if gear and not gear._msuf2UnitPreviewOpenCommand then
            local targetHandle = selected
            gear._msuf2UnitPreviewOpenCommand = {
                kind = "button",
                historyMode = "none",
                canExecute = function() return targetHandle ~= nil end,
                set = function() return OpenPreviewHandleSettings(targetHandle, "assistant") end,
            }
        end
        RegisterUnitPreviewControl(gear, "handle." .. tostring(selected._key) .. ".open_settings",
            "Open " .. tostring(selected._label or selected._key or "preview element") .. " settings",
            "button", "action", {
                historyMode = "none",
                help = "Click the highlighted preview button to jump directly to this element's settings below.",
                command = gear and gear._msuf2UnitPreviewOpenCommand,
            }, previewPageKey)
    end
    UpdateHandleHint(box, selected)
end
local function ApplyCastbarRuntimeForKey(key)
    if type(_G.MSUF_ApplyCastbarUnitAndSync) == "function" then
        _G.MSUF_ApplyCastbarUnitAndSync(key)
        return
    elseif type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(key)
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals(key)
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
    local moveReason = reason or "UNIT_PREVIEW_MOVE"
    if fields.text then
        ForceTextUnit(key, moveReason)
    elseif fields.portrait then
        ApplyPortrait(box and box._msufPanel, key, reason or "UNIT_PREVIEW_PORTRAIT_MOVE")
    elseif fields.detachedPower then
        if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true) end
    elseif fields.castbar then
        ApplyCastbarRuntimeForKey(key)
    elseif fields.texLayer then
        local fn = _G.MSUF_RefreshUnitTextureLayers
        if type(fn) == "function" then fn(key) end
    elseif fields.statusRefresh then
        local fn = _G[fields.statusRefresh]
        if type(fn) == "function" then fn(key, moveReason) end
    end
    ApplyPanelUnit(box and box._msufPanel, key, moveReason)
    RequestPreviewLayoutRefresh(box, moveReason)
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
    if type(_G.MSUF_ClassPower_Apply) == "function" then _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, playerHP = true, syncNow = false }) elseif type(_G.MSUF_ClassPower_Refresh) == "function" then _G.MSUF_ClassPower_Refresh() end
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
local UNIT_SECTION_IDS = {
    text = "text",
    status = "status_icons",
    portrait = "portrait",
    power = "power_bar",
    castbar = "castbar",
    auras = "auras",
    auras3 = "auras",
    dispel_overlay = "unit_dispel_overlay",
    dispel_symbol = "unit_dispel_symbol",
    texture_layer = "texture_layer",
}
function Preview.PrepareUnitHandleSubmenu(menu, unit, handle)
    if not (menu and handle) then return end
    local key, section = handle._key, Preview.ResolveUnitHandleSection(handle, unit)
    local state, tab
    if section == "text" then state, tab = "unitTextTabSelection", key == "name" and "name" or (key:sub(1, 2) == "hp" and "hp" or "power")
    elseif section == "portrait" then state, tab = "unitPortraitTabSelection", "placement"
    elseif section == "castbar" then
        state = "unitCastbarTabSelection"
        tab = key == "castbarIcon" and "icon" or (key == "castbarTime" and "time" or ((key == "castbarText" or key == "castbarTarget") and "spell" or "general"))
    end
    if state then menu[state] = menu[state] or {}; menu[state][unit] = tab end
    local textureSlot = section == "texture_layer" and (tonumber(key:match("^texLayer(%d)$")) or 1)
    local textureSlotChanged = false
    if textureSlot then
        menu.unitTexLayerSlot = menu.unitTexLayerSlot or {}
        menu.unitTexLayerTab = menu.unitTexLayerTab or {}
        textureSlotChanged = (tonumber(menu.unitTexLayerSlot[unit]) or 1) ~= textureSlot
        menu.unitTexLayerSlot[unit] = textureSlot
        menu.unitTexLayerTab[unit] = "placement"
    end
    return textureSlotChanged
end
OpenPreviewHandleSettings = function(handle, source)
    if not handle then return false end
    local box = handle._preview or Preview.active
    local fields = handle._fields or {}
    local menu = _G.MSUF2 or M2
    local unit = box and box.key or "player"
    local section = Preview.ResolveUnitHandleSection(handle, unit)
    local textureSlotChanged = Preview.PrepareUnitHandleSubmenu(menu, unit, handle)
    if fields.statusRefresh then
        local selected = NormalizeStatusPreviewId(handle._key)
        Preview.selectedStatusId = selected
        if menu then
            menu.unitStatusSelection = menu.unitStatusSelection or {}
            menu.unitStatusSelection[unit] = selected
            menu.unitStatusTabSelection = menu.unitStatusTabSelection or {}
            menu.unitStatusTabSelection[unit] = "basic"
        end
    end
    if section == "auras3" then
        local lane = fields.auraPreviewKind
        if lane ~= "debuff" and lane ~= "custom1" and lane ~= "custom2" and lane ~= "custom3" and lane ~= "custom4" then lane = "buff" end
        local previousAuraLane
        local previousAuraTool
        if menu then
            menu.unitAuraTabSelection = menu.unitAuraTabSelection or {}
            previousAuraLane = menu.unitAuraTabSelection[unit] or "buff"
            menu.unitAuraTabSelection[unit] = lane
            menu.unitAuraToolSelection = menu.unitAuraToolSelection or {}
            local tools = menu.unitAuraToolSelection[unit]
            if type(tools) ~= "table" then tools = {}; menu.unitAuraToolSelection[unit] = tools end
            previousAuraTool = tools[lane]
            tools[lane] = "layout"
        end
        local pageKey = "uf_" .. tostring(unit)
        if menu and type(menu.SelectPage) == "function" then
            _G.MSUF_EM2_MenuFocusRequest = {
                key = unit,
                component = handle._key,
                lane = lane,
                pageKey = pageKey,
                sectionId = "auras",
                source = "unit-preview-" .. tostring(source or "settings"),
                explicit = true,
                -- A direct Preview click is navigation, not a temporary
                -- search/edit-mode reveal. Keep Auras open when its first
                -- control refresh rebuilds the Unit page.
                persistSection = true,
                changedAt = GetTime and GetTime() or 0,
            }
            -- The Aura workspace captures its selected container while the
            -- Unit page is built. Refreshers cannot replace that cached
            -- container, so rebuild only when this preview opens another one.
            if (lane ~= previousAuraLane or previousAuraTool ~= "layout")
                and type(menu.InvalidatePage) == "function"
            then
                Preview._restoreHandleUnit, Preview._restoreHandleKey, Preview._restoreSourceBox = unit, handle._key, box
                Preview._restoreSourceShowSerial = tonumber(box and box._msuf2PreviewShowSerial) or 0
                menu.InvalidatePage(pageKey)
            end
            local selected = menu.SelectPage(pageKey) ~= false
            if selected then Preview.RestoreQueuedHandle(Preview.active)
            else
                Preview._restoreHandleUnit, Preview._restoreHandleKey, Preview._restoreSourceBox, Preview._restoreSourceShowSerial = nil, nil, nil, nil
            end
            return selected
        end
        return false
    end
    if section == "classPower" then
        if menu and type(menu.SelectPage) == "function" then
            local sectionId = "classpower_display"
            if handle._key == "classPowerText" then
                sectionId = "classpower_visuals"
                if menu.SetMenuStateValue then menu.SetMenuStateValue("classPowerStyleTab", "text") else menu.classPowerStyleTab = "text" end
            elseif handle._key == "detachedPower" then
                sectionId = "classpower_detached_power"
                if menu.SetMenuStateValue then menu.SetMenuStateValue("classPowerDetachedPowerTab", "layout") else menu.classPowerDetachedPowerTab = "layout" end
            end
            ExportPublic("MSUF_EM2_MenuFocusRequest", {
                pageKey = "classpower",
                sectionId = sectionId,
                source = "unit-preview-" .. tostring(source or "settings"),
                explicit = true,
                changedAt = GetTime and GetTime() or 0,
            })
            return menu.SelectPage("classpower") ~= false
        end
        return false
    end
    local sectionId = UNIT_SECTION_IDS[section or ""] or UNIT_SECTION_IDS.text
    local pageKey = box and (box._msuf2PinnedPreviewPageKey or ("uf_" .. tostring(box.key or "player"))) or nil
    if menu and type(menu.SelectPage) == "function" and pageKey then
        -- Texture controls are intentionally bound to one slot for their whole
        -- lifetime. Opening another texture handle must therefore rebuild the
        -- cached Unit page before it is focused.
        if textureSlotChanged and type(menu.InvalidatePage) == "function" then
            menu.InvalidatePage(pageKey)
        end
        ExportPublic("MSUF_EM2_MenuFocusRequest", {
            key = box and box.key,
            component = handle._key,
            pageKey = pageKey,
            sectionId = sectionId,
            source = "unit-preview-" .. tostring(source or "settings"),
            explicit = true,
            changedAt = GetTime and GetTime() or 0,
        })
        return menu.SelectPage(pageKey) ~= false
    end
    return false
end
Preview.DisabledLayerRoutes = Preview.DisabledLayerRoutes or {
    nameText = { key = "name", section = "text" },
    hpText = { key = "hpText", section = "text" },
    powerText = { key = "powerText", section = "text" },
    portrait = { key = "portrait", section = "portrait" },
    texLayer = { key = "texLayer1", section = "texture_layer" },
    power = { key = "power", section = "power" },
    classPower = { key = "classPower", section = "classPower" },
    castbar = { key = "castbar", section = "castbar" },
    buff = { key = "auraBuffs", section = "auras3", auraPreviewKind = "buff" },
    debuff = { key = "auraDebuffs", section = "auras3", auraPreviewKind = "debuff" },
    auras = { key = "auraCustom1", section = "auras3", auraPreviewKind = "custom1" },
    dispelOverlay = { key = "dispelOverlay", section = "dispel_overlay" },
    dispelSymbol = { key = "dispelSymbol", section = "dispel_symbol" },
    status = { key = "status", section = "status" },
}
function Preview.OpenUnavailableLayerSettings(box, layerKey)
    local route = Preview.DisabledLayerRoutes[layerKey]
    if not route then return false end
    return OpenPreviewHandleSettings({
        _key = route.key,
        _preview = box,
        _fields = { section = route.section, auraPreviewKind = route.auraPreviewKind },
    }, "disabled-layer")
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
    local beforeX, beforeY = ReadHandleOffsets(handle)
    local nextX, nextY = RoundOffset(x), RoundOffset(y)
    store[xKey], store[yKey] = nextX, nextY
    local directPrefixes = fields.text and Preview.ActiveDirectTextMovePrefixes(handle, store)
    if directPrefixes then
        if reason == "PREVIEW_RESET_OFFSET" and type(M2.SyncDirectTextOffsets) == "function" then
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
    elseif fields.text and type(M2.SyncDirectTextOffsets) == "function" then
        M2.SyncDirectTextOffsets(store, xKey)
        M2.SyncDirectTextOffsets(store, yKey)
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
    if fields and type(fields.resolveOffsetDelta) == "function" then
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
local function NameHandleOffsetDelta(handle, dx, dy)
    local box = handle and handle._preview
    local key = box and (box.key or (box._msufPanel and CurrentPanelKey(box._msufPanel))) or "player"
    local conf = UnitDB(key)
    return ResolveNameOffsetDelta(conf and conf.nameTextAnchor, dx, dy)
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
    if selection and type(selection.ReadRenderedCoordinates) == "function" then
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
function Preview.ResetSelectionOffsets(_, handle, reason)
    local fields = handle and handle._fields or {}
    return WriteHandleOffsets(handle, tonumber(fields.defaultX) or 0, tonumber(fields.defaultY) or 0, reason)
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

local function ExactPreviewDelta(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
local function ExactUnitPreviewKey(value)
    if type(value) ~= "string" or value == "" then return nil end
    value = value:lower()
    if UNIT_DATA[value] then return value end
    if value == "tot" then return "targettarget" end
    if value == "focus_target" or value == "focustargettarget" then return "focustarget" end
    if value:match("^boss%d+$") then return "boss" end
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
--- This is the deterministic Assistant/Edit Mode entry point. It deliberately
--- does not consult the shared Edit Mode nudge target or the currently selected
--- mover. The write is accepted only after exact DB readback; a failed readback
--- is rolled back before returning false.
function Preview.NudgeHandle(unitKey, handleKey, dx, dy)
    if type(M2.IsConfigCombatLocked) == "function" and M2.IsConfigCombatLocked() then return false, "combat-locked" end
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
    if type(M2.IsConfigCombatLocked) == "function" and M2.IsConfigCombatLocked() then return false, "combat-locked" end
    unitKey = ExactUnitPreviewKey(unitKey)
    if not unitKey then return false, "unknown-unit" end
    dx, dy = ExactPreviewDelta(dx), ExactPreviewDelta(dy)
    if dx == nil or dy == nil then return false, "invalid-delta" end
    local box = Preview.active
    if not (box and box.IsShown and box:IsShown() and (not box.IsVisible or box:IsVisible())) then return false, "preview-not-visible" end
    if unitKey ~= ExactUnitPreviewKey(box.key) then return false, "unit-preview-mismatch" end
    if (box.canvas and box.canvas._msufPreviewPanning) or (box.dragFrame and box.dragFrame._handle) then return false, "preview-busy" end
    if type(PreviewZoomPan.NudgePan) ~= "function" then return false, "pan-api-unavailable" end
    return PreviewZoomPan.NudgePan(box, dx, dy)
end
ExportPublic("MSUF_UFPreview_NudgeHandle", function(unitKey, handleKey, dx, dy)
    return Preview.NudgeHandle(unitKey, handleKey, dx, dy)
end)
ExportPublic("MSUF_UFPreview_Pan", function(unitKey, dx, dy)
    return Preview.Pan(unitKey, dx, dy)
end)
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
        -- Under reverse order the configured left slot renders on the physical
        -- right FontString (and vice versa); ring the visible text.
        local box = Preview.active
        if box and TextScopeGet(box.key, "hpTextReverse", false) == true then
            if slot == "left" then slot = "right" elseif slot == "right" then slot = "left" end
        end
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
        Place = function(frame, parent, regions, pad)
            local renderScale = tonumber(box and (box._mockEffectiveScale or box._mockScale or box._mockAutoScale)) or 1
            return UnitPreviewText.PlaceHandleAroundRegions(frame, parent, regions, pad, {
                coordinateScale = renderScale,
                fitText = true,
                useScaledRect = true,
            })
        end,
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
    -- Tab steps through the placed handles. Overlapping elements in dense
    -- corners cannot all be reached by clicking, so keyboard traversal is the
    -- only way to select what sits underneath.
    if keyName == "TAB" then
        local box = (self and self.handles and self) or Preview.active
        if box and M2.PreviewSelectionBar
            and M2.PreviewSelectionBar.CycleHandle(box, IsShiftKeyDown and IsShiftKeyDown()) then
            if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
            return
        end
    end
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
local function UnitPreviewLayerForHandle(key, fields)
    fields = fields or {}
    if fields.previewLayer then return fields.previewLayer end
    if fields.texLayer or tostring(key or ""):match("^texLayer") then return "texLayer" end
    if fields.auraPreviewKind == "buff" or fields.auraPreviewKind == "debuff" then return fields.auraPreviewKind end
    if fields.auraPreviewKind then return "auras" end
    if fields.portrait then return "portrait" end
    if fields.detachedPower then return "power" end
    if fields.classPower then return "classPower" end
    if fields.castbar or fields.section == "castbar" then return "castbar" end
    if fields.statusRefresh or fields.section == "status" then return "status" end
    if key == "name" then return "nameText" end
    if tostring(key or ""):match("^hp") then return "hpText" end
    if tostring(key or ""):match("^power") then return "powerText" end
end
local function MakeHandle(preview, key, fields, label, color)
    local h = CreateFrame("Button", nil, preview.canvas)
    -- Composite elements need a deterministic mouse-hit hierarchy. The broad
    -- container handle stays on the base interaction plane while its smaller
    -- icon/text/time handles sit above it; creation/show order must not decide
    -- which element receives the click.
    local interactionPriority = tonumber(fields and fields.interactionPriority) or 0
    h:SetFrameLevel((PreviewCore.InteractionFrameLevel and PreviewCore.InteractionFrameLevel(preview.canvas, interactionPriority))
        or ((preview.canvas:GetFrameLevel() or 0) + 30 + interactionPriority))
    h:SetSize(20, 20)
    h:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    if h.RegisterForDrag then h:RegisterForDrag("LeftButton") end
    h:EnableMouse(true)
    if PreviewHelpers.BindPreviewWheel then PreviewHelpers.BindPreviewWheel(h, preview) end
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
    h._previewLayerKey = UnitPreviewLayerForHandle(key, fields)
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
        local showTooltip = GameTooltip and (not PreviewHelpers.ShouldShowPreviewHandleTooltip
            or PreviewHelpers.ShouldShowPreviewHandleTooltip(preview))
        if showTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- `_label` can be rebound per unit on the shared box (custom
            -- container 4 is Defensive Buffs on player, Dots on target
            -- elsewhere); the creation-time closure label is only the fallback.
            GameTooltip:SetText(TR(self._label or label), 1, 1, 1)
            GameTooltip:AddLine(TR("Drag to move. Arrow keys nudge."), 0.82, 0.82, 0.82, true)
            GameTooltip:AddLine(TR("Right-click opens quick actions."), 0.50, 0.78, 0.92, true)
            GameTooltip:Show()
        end
    end)
    h:SetScript("OnLeave", function(self)
        self._hovering = nil
        RefreshHandleSelectionVisuals(preview)
        if GameTooltip then GameTooltip:Hide() end
    end)
    h:SetScript("OnClick", function(self, button)
        if self._suppressNextClick then
            self._suppressNextClick = nil
            return
        end
        if button == "RightButton" then
            SelectPreviewHandle(self, true)
            if PreviewHelpers.ShowPreviewHandleContext then
                PreviewHelpers.ShowPreviewHandleContext(self, {
                    M = M2,
                    T = MenuTheme and MenuTheme(),
                    Tr = TR,
                    title = self._label or self._key,
                    openSettings = OpenPreviewHandleSettings,
                })
            end
            return
        end
        SelectPreviewHandle(self)
    end)
    local function StartHandleDrag(self, button)
        if button and button ~= "LeftButton" then return end
        if self._dragging == true or preview.dragFrame._handle == self or (preview.canvas and preview.canvas._msufPreviewPanning) then return true end
        self._didDragMove = nil
        if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() and StartPreviewPan and StartPreviewPan(preview.canvas, preview, button) then
            self._suppressNextClick = true
            return
        end
        SelectPreviewHandle(self, true)
        if PreviewHelpers.ShowPreviewMoveCue then PreviewHelpers.ShowPreviewMoveCue(preview, self) end
        local x, y = ReadHandleOffsets(self)
        self._startX = x
        self._startY = y
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragging = true
        preview._dragFrozenScale = tonumber(preview._mockScale) or tonumber(preview._mockAutoScale) or 1
        preview._dragFrozenBaseOffsetX = tonumber(preview._mockBaseOffsetX) or 0
        preview._dragFrozenBaseOffsetY = tonumber(preview._mockBaseOffsetY) or 0
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
    local function StopHandleDrag(self, button, allowOpenSettings)
        if StopPreviewPan and preview.canvas and preview.canvas._msufPreviewPanning then StopPreviewPan(preview.canvas) end
        if button and button ~= "LeftButton" then return end
        local wasDragging = self._dragging == true or preview.dragFrame._handle == self
        if not wasDragging then return end
        local didMove = self._didDragMove == true
        if didMove and PreviewHelpers.NotePreviewElementMoved then PreviewHelpers.NotePreviewElementMoved() end
        local openSettingsOnRelease = allowOpenSettings == true
            and button == "LeftButton"
            and not didMove
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
        preview._dragFrozenBaseOffsetX = nil
        preview._dragFrozenBaseOffsetY = nil
        if type(fields.clearDragOffsets) == "function" then fields.clearDragOffsets(self) end
        self._dragging = nil
        self._lastDragX = nil
        self._lastDragY = nil
        self._dragPoint = nil
        self._dragRelTo = nil
        self._dragRelPoint = nil
        self._dragOffsetX = nil
        self._dragOffsetY = nil
        self._didDragMove = nil
        RefreshHandleSelectionVisuals(preview)
        if hadFrozenScale and not preview._manualZoom then RequestPreviewLayoutRefresh(preview, "UNIT_PREVIEW_DRAG_END") end
        if openSettingsOnRelease then OpenPreviewHandleSettings(self, "click") end
    end
    h:SetScript("OnMouseDown", StartHandleDrag)
    h:SetScript("OnMouseUp", function(self, button) StopHandleDrag(self, button, true) end)
    h:SetScript("OnDragStart", StartHandleDrag)
    h:SetScript("OnDragStop", function(self, button) StopHandleDrag(self, button, false) end)
    h:SetScript("OnHide", function(self) StopHandleDrag(self, nil, false) end)
    h:SetScript("OnKeyDown", PreviewArrowKeyDown)
    h._msuf2CommandAction = {
        kind = "button",
        historyMode = "none",
        interaction = "preview.handle.select",
        previewSurface = "unit",
        previewHandleKey = key,
        previewUnitKey = preview.key or tostring(M2._msuf2SearchBuildKey or M2.activeKey or ""):match("^uf_(.+)$"),
        set = function()
            if h._msufPlaced == false then return false end
            if h.IsShown and not h:IsShown() then return false end
            SelectPreviewHandle(h, true)
            return preview._selectedHandle == h
        end,
    }
    if PreviewHelpers.EnsurePreviewHandleGear then
        local gear = PreviewHelpers.EnsurePreviewHandleGear(h, {
            T = MenuTheme and MenuTheme(),
            Tr = TR,
            shown = false,
            openSettings = function(handle) return OpenPreviewHandleSettings(handle, "gear") end,
        })
        if gear and not gear._msuf2UnitPreviewOpenCommand then
            gear._msuf2UnitPreviewOpenCommand = {
                kind = "button",
                historyMode = "none",
                set = function() return OpenPreviewHandleSettings(h, "assistant") end,
            }
        end
    end
    h:Hide()
    preview.handles[#preview.handles + 1] = h
    return h
end
local CreateIcon = PreviewStatus.CreateIcon
local SetPreviewIconTexture = PreviewStatus.SetIconTexture
local ResolveStatusPreviewAnchor = PreviewStatus.ResolveAnchor
MenuTheme = PreviewCore.MenuTheme
local ApplyPreviewBackdrop = PreviewCore.ApplyBackdrop
local STATUS_PREVIEW = (MSUF.UFPreviewSpecs and MSUF.UFPreviewSpecs.StatusPreview) or {}
local PREVIEW_LAYERS = (MSUF.UFPreviewSpecs and MSUF.UFPreviewSpecs.PreviewLayers) or {}
local ZOOM_MIN = tonumber(PreviewZoomPan.MIN) or 0.35
local UNIT_PREVIEW_ANIMATION_INTERVAL = 1 / 20
if PreviewZoomPan.Configure then PreviewZoomPan.Configure({ Preview = Preview, T = M2.Theme, TR = TR, TEX_W8 = TEX_W8, UpdateHandleHint = UpdateHandleHint }) end
local function ZoomOrOne(v) return tonumber(v) or 1 end
local ClampPreviewZoom = PreviewZoomPan.Clamp or ZoomOrOne
local UpdatePreviewZoomControls = PreviewZoomPan.UpdateControls or F.Noop
local SetPreviewZoom = PreviewZoomPan.SetZoom or F.Noop
local StepPreviewZoom = PreviewZoomPan.Step or F.Noop
StartPreviewPan = PreviewZoomPan.Start or StartPreviewPan
StopPreviewPan = PreviewZoomPan.Stop or StopPreviewPan
local SetPreviewAnimationEnabled
local function PreviewAnimationInCombat()
    local fn = PreviewCore.InCombat
    if type(fn) == "function" then return fn() == true end
    return InCombatLockdown and InCombatLockdown() or false
end
local function PreviewAnimationActive(box)
    return box and box._animationEnabled == true
end
local function RefreshPreviewAnimationButton(box)
    local btn = box and box.animateCombatButton
    if not btn then return end
    local active = PreviewAnimationActive(box)
    if btn.fs then
        -- The button plays an animation loop; it does not switch the preview
        -- into a combat state. Label it after what it does.
        btn.fs:SetText(active and TR("Stop") or TR("Animate"))
        btn.fs:SetTextColor(active and 0.06 or 0.78, active and 0.95 or 0.84, active and 1.00 or 0.96, 1)
    end
    if btn.MSUF2RefreshPreviewPill then btn:MSUF2RefreshPreviewPill(active) end
    if btn.SetBackdropColor and not btn._msuf2PreviewPillFill then
        if active then
            btn:SetBackdropColor(0.020, 0.125, 0.155, 0.96)
            btn:SetBackdropBorderColor(0.10, 0.82, 0.95, 1)
        else
            btn:SetBackdropColor(0.015, 0.018, 0.030, 0.86)
            btn:SetBackdropBorderColor(0.10, 0.14, 0.22, 0.92)
        end
    end
end
local function StopPreviewAnimationDriver(box)
    if not (box and box.SetScript) then return end
    box:SetScript("OnUpdate", nil)
    if box.UnregisterEvent then box:UnregisterEvent("PLAYER_REGEN_DISABLED") end
end
local function KillPreviewAnimationForCombat(box)
    if not box then return end
    StopPreviewAnimationDriver(box)
    box._animationEnabled = nil
    box._animationElapsed = 0
    box._animationAccum = 0
    box._previewAnimationState = nil
    box._previewAnimationData = nil
    RefreshPreviewAnimationButton(box)
end
--- Live-state driver: keeps the preview mirroring the real unit (target
--- swaps, health/power ticks, roster changes) while the menu is open.
--- Zero combat overhead by construction: PLAYER_REGEN_DISABLED drops every
--- listener for the whole fight (only the single re-arm signal stays), and
--- the driver exists only while a preview box is in use.
local LIVE_STATE_UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION" }
local LIVE_STATE_UNIT_TOKENS = { player = "player", target = "target", targettarget = "targettarget", focustarget = "focustarget", focus = "focus", boss = "boss1", pet = "pet" }
local SyncUnitPreviewLiveState
local function UnitPreviewLiveStateEvent(driver, event)
    local box = driver._msufLiveStateBox
    if not box then
        driver:UnregisterAllEvents()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if not (box.IsShown and box:IsShown()) then
        driver:UnregisterAllEvents()
        driver._msufLiveArmed = false
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        SyncUnitPreviewLiveState(box, box.key, "PLAYER_REGEN_ENABLED")
        return
    end
    if PreviewAnimationInCombat() then return end
    if box.RequestRefresh then box:RequestRefresh("UNIT_PREVIEW_LIVE_STATE") end
end
SyncUnitPreviewLiveState = function(box, key, reason)
    if not (box and CreateFrame) then return end
    local driver = box._msufLiveStateDriver
    if not driver then
        driver = CreateFrame("Frame")
        driver._msufLiveStateBox = box
        driver:SetScript("OnEvent", UnitPreviewLiveStateEvent)
        box._msufLiveStateDriver = driver
    end
    local unit = LIVE_STATE_UNIT_TOKENS[CanonKey(key or box.key)] or "player"
    if PreviewAnimationInCombat() then
        driver:UnregisterAllEvents()
        driver._msufLiveUnit = unit
        driver._msufLiveArmed = false
        driver:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if driver._msufLiveArmed == true and driver._msufLiveUnit == unit then return end
    driver:UnregisterAllEvents()
    driver._msufLiveUnit = unit
    driver._msufLiveArmed = true
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("PLAYER_FOCUS_CHANGED")
    driver:RegisterEvent("GROUP_ROSTER_UPDATE")
    if driver.RegisterUnitEvent then
        for i = 1, #LIVE_STATE_UNIT_EVENTS do
            driver:RegisterUnitEvent(LIVE_STATE_UNIT_EVENTS[i], unit)
        end
        driver:RegisterUnitEvent("UNIT_PET", "player")
    end
    if reason == "PLAYER_REGEN_ENABLED" and box.RequestRefresh then box:RequestRefresh("UNIT_PREVIEW_LIVE_STATE") end
end
local function ReleaseUnitPreviewLiveState(box)
    local driver = box and box._msufLiveStateDriver
    if not driver then return end
    driver:UnregisterAllEvents()
    driver._msufLiveArmed = false
end
local function RefreshPreviewAnimationFrame(box)
    local refresh = Preview and Preview.Refresh
    if type(refresh) == "function" then
        refresh(box, "UNIT_PREVIEW_ANIMATE")
    else
        RequestPreviewLayoutRefresh(box, "UNIT_PREVIEW_ANIMATE")
    end
    -- The large menu preview owns this clock.  Feed the exact same elapsed
    -- value into already-built Edit Mode aura dummies so their timers/swipes
    -- stay in phase without starting a second OnUpdate or doing full layouts.
    local a3 = MSUF and MSUF.MSUF_Auras3
    local refreshEditAnimation = a3 and a3.RefreshEditPreviewAnimation
    if type(refreshEditAnimation) == "function" then
        refreshEditAnimation(box and box.key, box and box._animationElapsed)
    end
end

Preview.RestoreStaticEditModeAuraPreview = function(box)
    local a3 = MSUF and MSUF.MSUF_Auras3
    local refresh = a3 and a3.RefreshEditPreview
    if type(refresh) == "function" then refresh(box and box.key) end
end
local function PreviewAnimationOnUpdate(box, elapsed)
    if not (box and box._animationEnabled == true and box.IsShown and box:IsShown()) then
        StopPreviewAnimationDriver(box)
        return
    end
    if PreviewAnimationInCombat() then
        KillPreviewAnimationForCombat(box)
        if box.hint then box.hint:SetText(TR("Preview animation pauses during combat.")) end
        return
    end
    elapsed = tonumber(elapsed) or 0
    box._animationElapsed = (tonumber(box._animationElapsed) or 0) + elapsed
    box._animationAccum = (tonumber(box._animationAccum) or 0) + elapsed
    if box._animationAccum < UNIT_PREVIEW_ANIMATION_INTERVAL then return end
    box._animationAccum = 0
    RefreshPreviewAnimationFrame(box)
end
local function StartPreviewAnimationDriver(box)
    if not (box and box._animationEnabled == true) then return end
    if PreviewAnimationInCombat() then
        StopPreviewAnimationDriver(box)
        return
    end
    if box.RegisterEvent then box:RegisterEvent("PLAYER_REGEN_DISABLED") end
    box:SetScript("OnUpdate", PreviewAnimationOnUpdate)
end
SetPreviewAnimationEnabled = function(box, enabled, reason)
    if not box then return end
    enabled = enabled == true
    if enabled and PreviewAnimationInCombat() then
        KillPreviewAnimationForCombat(box)
        if box.hint then box.hint:SetText(TR("Preview animation pauses during combat.")) end
        RefreshPreviewAnimationButton(box)
        return
    end
    if enabled and box._animationEnabled ~= true then
        box._animationElapsed = 0
        box._animationAccum = 0
    end
    box._animationEnabled = enabled
    if enabled then
        StartPreviewAnimationDriver(box)
    else
        StopPreviewAnimationDriver(box)
        box._previewAnimationState = nil
        box._previewAnimationData = nil
        Preview.RestoreStaticEditModeAuraPreview(box)
    end
    RefreshPreviewAnimationButton(box)
    RequestPreviewLayoutRefresh(box, reason or "UNIT_PREVIEW_ANIMATE_TOGGLE")
end
local function TogglePreviewAnimation(box)
    SetPreviewAnimationEnabled(box, not PreviewAnimationActive(box), "UNIT_PREVIEW_COMBAT_ANIMATE")
end
local function CreatePreviewAnimationButton(box)
    if not (box and box.canvas) or box.animateCombatButton then return end
    local T = MenuTheme()
    local btn = CreateFrame("Button", nil, box.canvas, "BackdropTemplate")
    btn:SetSize(74, 22)
    btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    if box.zoomBar then
        btn:SetPoint("RIGHT", box.zoomBar, "LEFT", -6, 0)
    else
        btn:SetPoint("TOPRIGHT", box.canvas, "TOPRIGHT", -174, -6)
    end
    if btn.SetFrameLevel and box.canvas.GetFrameLevel then btn:SetFrameLevel((box.canvas:GetFrameLevel() or 0) + 82) end
    btn.fs = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.fs:SetPoint("CENTER")
    if T and T.StyleFontString then T.StyleFontString(btn.fs, T.colors and T.colors.text or { 1, 1, 1, 1 }, 0) end
    btn._preview = box
    if PreviewHelpers.StylePreviewPillButton then PreviewHelpers.StylePreviewPillButton(btn, T, { fontField = "fs" }) end
    btn:SetScript("OnClick", function(self) TogglePreviewAnimation(self._preview) end)
    btn._msuf2CommandAction = {
        kind = "toggle",
        historyMode = "none",
        get = function() return PreviewAnimationActive(box) end,
        set = function(enabled)
            if enabled == true and PreviewAnimationInCombat() then return false end
            SetPreviewAnimationEnabled(box, enabled == true, "UNIT_PREVIEW_ASSISTANT_ANIMATION")
            return PreviewAnimationActive(box) == (enabled == true)
        end,
    }
    if M2.AddTooltip then
        M2.AddTooltip(btn, "Animate Preview", "Animates health, power, absorbs, cast progress, aura timers, and the target-DoT Pandemic window. Matching Edit Mode aura dummies use the same clock. Pauses during combat.", { hook = true })
    end
    box.animateCombatButton = btn
    box.RefreshAnimationButton = RefreshPreviewAnimationButton
    RefreshPreviewAnimationButton(box)
end
local function ApplyUnitPinnedPresentation(box, pinned, opts, sideW)
    if not box then return end
    local T = MenuTheme()
    local colors = (T and T.colors) or {}
    local shade = box._msuf2PinnedHeaderShade
    if not shade and box.CreateTexture then
        shade = box:CreateTexture(nil, "BORDER", nil, -1)
        shade:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
        shade:SetPoint("TOPRIGHT", box, "TOPRIGHT", -1, -1)
        shade:SetHeight(29)
        shade:SetTexture(TEX_W8)
        box._msuf2PinnedHeaderShade = shade
    end
    local line = box._msuf2PinnedHeaderLine
    if not line and box.CreateTexture then
        line = box:CreateTexture(nil, "BORDER", nil, 0)
        line:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -29)
        line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -10, -29)
        line:SetHeight(1)
        line:SetTexture(TEX_W8)
        box._msuf2PinnedHeaderLine = line
    end
    if M2.PreviewSelectionBar then M2.PreviewSelectionBar.SetShown(box, true) end
    if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
    if box.footer then box.footer:SetShown(not pinned) end
    if shade then
        local bg = colors.coreShadow or { 0.006, 0.016, 0.032, 1 }
        shade:SetColorTexture(bg[1], bg[2], bg[3], pinned and 0.92 or 0)
        shade:SetShown(pinned)
    end
    if line then
        local border = colors.borderSoft or colors.border or { 0.070, 0.260, 0.390, 1 }
        line:SetColorTexture(border[1], border[2], border[3], pinned and 0.52 or 0)
        line:SetShown(pinned)
    end
    UpdateHandleHint(box, box._selectedHandle)
end
--- Compact inline presentation: the preview shrinks to a reference strip, the
--- canvas takes the full box width, and the docked layer sidebar becomes a
--- popover behind a "Layers" button. The docked sidebar has a fixed content
--- height, so simply shrinking the box would spill its rows past the section.
local function EnsureUnitLayersButton(box)
    if box._msuf2LayersButton then return box._msuf2LayersButton end
    local T = MenuTheme()
    local btn
    if T and T.Button then
        btn = T.Button(box, TR("Layers"), 76, 20)
    else
        btn = CreateFrame("Button", nil, box, "BackdropTemplate")
        btn:SetSize(76, 20)
    end
    btn:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -5)
    btn:SetScript("OnClick", function()
        local sidebar = box.sidebar
        if sidebar then sidebar:SetShown(not sidebar:IsShown()) end
    end)
    if M2 and M2.AddTooltip then
        M2.AddTooltip(btn, "Layers", "Toggle the preview layer list.", { hook = true })
    end
    box._msuf2LayersButton = btn
    return btn
end
local function SetUnitCanvasToolsShown(box, shown)
    if not box then return end
    local controlsHint = box._msuf2PreviewControlsHint
    if not shown then
        if box._msuf2CompactToolsHidden ~= true then
            box._msuf2CompactControlsHintWasShown = controlsHint and controlsHint.IsShown and controlsHint:IsShown() or false
        end
        box._msuf2CompactToolsHidden = true
        if box.zoomBar then box.zoomBar:Hide() end
        if box.animateCombatButton then box.animateCombatButton:Hide() end
        if controlsHint then controlsHint:Hide() end
        return
    end
    box._msuf2CompactToolsHidden = nil
    if box.zoomBar then box.zoomBar:Show() end
    if box.animateCombatButton then box.animateCombatButton:Show() end
    if controlsHint and box._msuf2CompactControlsHintWasShown then controlsHint:Show() end
end
local function LayoutUnitHeaderControls(box, compact)
    if not box then return end
    local header = box._msuf2CompactHeader
    local expandBtn = box._msuf2CompactExpandButton
    local layersBtn = box._msuf2LayersButton
    if compact and header then
        if layersBtn then
            if layersBtn.SetText then layersBtn:SetText(TR("Layers") .. " v") end
            layersBtn:SetParent(header)
            layersBtn:ClearAllPoints()
            if expandBtn then layersBtn:SetPoint("RIGHT", expandBtn, "LEFT", -8, 0)
            else layersBtn:SetPoint("RIGHT", header, "RIGHT", -108, 0) end
            if layersBtn.SetFrameLevel and header.GetFrameLevel then
                layersBtn:SetFrameLevel((header:GetFrameLevel() or 1) + 3)
            end
        end
        return
    end
    if layersBtn then
        if layersBtn.SetText then layersBtn:SetText(TR("Layers")) end
        layersBtn:SetParent(box)
        layersBtn:ClearAllPoints()
        layersBtn:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -5)
    end
end
local function ApplyUnitCompactPresentation(box, compact, sideW)
    if not box then return end
    compact = compact and true or false
    box._msuf2CompactPreview = compact
    if box._msuf2PinnedFloating == true then compact = false end
    if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(box, compact, 1.50) end
    local canvas, sidebar = box.canvas, box.sidebar
    local T = MenuTheme()
    if compact then
        if box.title then box.title:Hide() end
        if box.hint then box.hint:Hide() end
        SetUnitCanvasToolsShown(box, false)
        if canvas then
            canvas:ClearAllPoints()
            canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
            canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
        end
        if M2.PreviewSelectionBar then M2.PreviewSelectionBar.SetShown(box, false) end
        if sidebar and canvas then
            sidebar:ClearAllPoints()
            local layersBtn = EnsureUnitLayersButton(box)
            if layersBtn and box._msuf2CompactHeader then
                sidebar:SetPoint("TOPRIGHT", layersBtn, "BOTTOMRIGHT", 0, -6)
            else
                sidebar:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -28)
            end
            -- The chips keep their flow inside the popover; it is sized to a
            -- readable column rather than the full box width, and the rail
            -- caption is redundant behind a button already labelled "Layers".
            local popoverWidth = 268
            sidebar:SetWidth(popoverWidth)
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Hide() end
            if box.LayoutLayerRail then box:LayoutLayerRail(popoverWidth + 24) end
            if sidebar.SetFrameLevel and canvas.GetFrameLevel then
                sidebar:SetFrameLevel((canvas:GetFrameLevel() or 1) + 90)
            end
            if sidebar.SetBackdropColor then sidebar:SetBackdropColor(0.012, 0.026, 0.050, 0.98) end
            if sidebar.SetBackdropBorderColor then
                local border = (T and T.colors and T.colors.borderSoft) or { 0.086, 0.149, 0.227, 1 }
                sidebar:SetBackdropBorderColor(border[1], border[2], border[3], 0.9)
            end
            sidebar:Hide()
        end
        EnsureUnitLayersButton(box):Show()
        LayoutUnitHeaderControls(box, true)
    else
        if box.title then box.title:Show() end
        if box.hint then box.hint:Show() end
        SetUnitCanvasToolsShown(box, true)
        LayoutUnitHeaderControls(box, false)
        if sidebar then
            if sidebar.SetFrameLevel and canvas and canvas.GetFrameLevel then
                sidebar:SetFrameLevel((canvas:GetFrameLevel() or 1) + 1)
            end
            if PreviewHelpers.ApplyPreviewChrome then
                PreviewHelpers.ApplyPreviewChrome(sidebar, "sidebar", T, ApplyPreviewBackdrop)
            end
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Show() end
        end
        if M2.PreviewSelectionBar then M2.PreviewSelectionBar.SetShown(box, true) end
        if box.ApplyDockedPreviewLayout then box:ApplyDockedPreviewLayout(12) end
        if box._msuf2LayersButton then box._msuf2LayersButton:Hide() end
    end
end
local function BuildPreview(parent, panel, width, height)
    local sideW = 104
    local T = MenuTheme()
    local colors = (T and T.colors) or {}
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(width or 632, height or 228)
    local chrome = PreviewHelpers.ApplyPreviewChrome and PreviewHelpers.ApplyPreviewChrome(box, "outer", T, ApplyPreviewBackdrop)
    if not chrome then
        ApplyPreviewBackdrop(box, colors.panel or { 0.035, 0.067, 0.114, 0.54 }, colors.borderSoft or { 0.086, 0.149, 0.227, 0.46 })
        chrome = { title = colors.title or colors.text, layerHeader = colors.muted }
    end
    box._msufStaticH = height or 228
    box._msufPanel = panel
    box.ApplyPinnedPreviewPresentation = function(self, pinned, opts)
        if pinned then
            if PreviewHelpers.SwitchCompactZoomMode then PreviewHelpers.SwitchCompactZoomMode(self, false, 1.50) end
            -- The pinned header reuses title/hint; compact mode may have
            -- hidden them and must never leave the floating header empty.
            if self.title then self.title:Show() end
            if self.hint then self.hint:Show() end
            SetUnitCanvasToolsShown(self, true)
            LayoutUnitHeaderControls(self, false)
            if self._msuf2LayersButton then self._msuf2LayersButton:Hide() end
        end
        ApplyUnitPinnedPresentation(self, pinned, opts, sideW)
        if not pinned and self._msuf2CompactPreview then
            ApplyUnitCompactPresentation(self, true, sideW)
        end
    end
    box.ApplyCompactPreviewPresentation = function(self, compact)
        ApplyUnitCompactPresentation(self, compact, sideW)
    end
    function box:RequestRefresh(reason)
        local preview = MSUF.UFPreview or Preview
        if type(preview) == "table" then
            if self:IsShown() then preview.active = self end
            if type(preview.RequestRefreshForBox) == "function" then
                preview.RequestRefreshForBox(self, reason)
                return
            end
            if type(preview.Refresh) == "function" and self:IsShown() and (not self.IsVisible or self:IsVisible()) then
                preview.Refresh(self, reason)
            end
        end
    end
    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    title:SetText(TR("Unit Frame Preview"))
    if T and T.StyleFontString then T.StyleFontString(title, chrome.title or colors.title or colors.text or { 1, 1, 1, 1 }, 1) end
    box.title = title
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 12, 0)
    hint:SetText(DefaultPreviewHint())
    if T and T.StyleFontString then T.StyleFontString(hint, colors.muted or { 0.55, 0.60, 0.70, 0.90 }, 0) end
    box.hint = hint
    -- The canvas is anchored against the selection bar rather than the box, so
    -- whatever the chip rail does not need stays with the preview surface.
    local canvas = CreateFrame("Frame", nil, box, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)
    canvas:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    canvas._msuf2PreviewCanvasUnderlay = box
    if PreviewHelpers.ApplyPreviewChrome then
        PreviewHelpers.ApplyPreviewChrome(canvas, "canvas", T, ApplyPreviewBackdrop)
    else
        ApplyPreviewBackdrop(canvas, { 0.020, 0.039, 0.071, 0.92 }, colors.borderSoft or { 0.086, 0.149, 0.227, 0.38 })
    end
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    if canvas.SetPropagateMouseWheel then canvas:SetPropagateMouseWheel(false) end
    box.canvas = canvas
    PreviewHelpers.BuildZoomBar(box, canvas, {
        texture = TEX_W8,
        T = T,
        themeReadout = true,
        CreateZoomButton = PreviewZoomPan.CreateButton,
        Tr = TR,
        StepZoom = StepPreviewZoom,
        SetZoom = SetPreviewZoom,
        StartPan = StartPreviewPan,
        StopPan = StopPreviewPan,
        fitReason = "UNIT_PREVIEW_ZOOM_FIT",
        oneReason = "UNIT_PREVIEW_ZOOM_1TO1",
        lockButton = true,
        defaultLocked = true,
        lockReason = "UNIT_PREVIEW_ZOOM_LOCK",
        unlockReason = "UNIT_PREVIEW_ZOOM_UNLOCK",
    })
    -- Full Unit previews are 1:1 editors on first use. The page is constructed
    -- in Compact mode before the fresh-session auto-expand runs; seed the Full
    -- slot here so that technical restore cannot lock its first Fit scale
    -- (often about 50%) as though it were a prior user zoom. The shared box is
    -- built only once, so later manual/Fit choices remain untouched.
    if box._msuf2CompactZoomMode == nil and box._manualZoom == nil then
        box._manualZoom = 1.00
        box._msuf2ZoomLockDefaultPending = nil
    end
    if PreviewHelpers.EnsurePreviewControlsHint then
        PreviewHelpers.EnsurePreviewControlsHint(box, canvas, { M = M2, T = T, Tr = TR })
    end
    CreatePreviewAnimationButton(box)
    -- Layer chips flow along the bottom instead of holding a fixed column: the
    -- canvas keeps the full box width, and the rail only claims the rows it
    -- actually fills. `box.sidebar` stays the field name because the compact
    -- popover and the colour page already address the layer surface by it.
    local sidebar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    sidebar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    sidebar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 12)
    sidebar:SetHeight(30)
    if PreviewHelpers.ApplyPreviewChrome then
        PreviewHelpers.ApplyPreviewChrome(sidebar, "sidebar", T, ApplyPreviewBackdrop)
    else
        ApplyPreviewBackdrop(sidebar, colors.coreShadow or colors.panel or { 0.020, 0.039, 0.071, 0.56 }, colors.borderSoft or { 0.086, 0.149, 0.227, 0.32 })
    end
    box.sidebar = sidebar
    local sHdr = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sHdr:SetPoint("LEFT", sidebar, "LEFT", 10, 0)
    sHdr:SetText(TR("LAYERS"))
    local layerHeaderColor = chrome.layerHeader or colors.muted or { 0.62, 0.70, 0.82, 0.82 }
    sHdr:SetTextColor(layerHeaderColor[1], layerHeaderColor[2], layerHeaderColor[3], layerHeaderColor[4] or 0.82)
    if T and T.StyleFontString then T.StyleFontString(sHdr, layerHeaderColor, 0) end
    box._msuf2LayerRailHeader = sHdr
    box.layerVisibility = {}
    box.layerButtons = {}
    local function UnitLayerAvailable(owner, key)
        return not (owner and owner.layerAvailable and owner.layerAvailable[key] == false)
    end
    local activeLayerText = colors.pillTextActive or colors.text or { 0.92, 0.96, 1.00, 1.00 }
    local mutedLayerText = colors.muted or { 0.62, 0.70, 0.82, 0.90 }
    local disabledLayerText = colors.dim or { 0.36, 0.46, 0.60, 0.82 }
    local unitLayerButtonOpts = {
        Tr = TR,
        layout = "chip",
        height = 20,
        rowHeight = 20,
        topOffset = 23,
        showOffText = false,
        quiet = true,
        quietBase = chrome.rowBase,
        quietHover = chrome.rowHover,
        textOn = { activeLayerText[1], activeLayerText[2], activeLayerText[3], 1.00 },
        textOff = { mutedLayerText[1], mutedLayerText[2], mutedLayerText[3], 0.72 },
        textDisabled = { disabledLayerText[1], disabledLayerText[2], disabledLayerText[3], 0.64 },
        IsAvailable = UnitLayerAvailable,
        IsOn = function(owner, key) return UnitLayerAvailable(owner, key) and owner.layerVisibility[key] ~= false end,
        IsSelected = function(owner, key) return owner and owner._msuf2SelectedPreviewLayerKey == key end,
        OnClick = function(self, owner)
            if owner.layerAvailable and owner.layerAvailable[self.key] == false then
                if GameTooltip then GameTooltip:Hide() end
                Preview.OpenUnavailableLayerSettings(owner, self.key)
                return
            end
            owner.layerVisibility[self.key] = owner.layerVisibility[self.key] == false
            if self.key == "guides" then SetPreviewGuidesEnabled(owner.layerVisibility[self.key] ~= false) end
            -- Hiding a layer changes the footprint, so auto-fit has to recenter.
            -- A zoom the user dialled in by hand is a deliberate viewport and
            -- must survive the toggle; _manualZoom is exactly that marker.
            if self.key ~= "guides" and owner._manualZoom == nil then
                owner._zoomPanX, owner._zoomPanY = 0, 0
            end
            for j = 1, #owner.layerButtons do owner.layerButtons[j]:refresh() end
            -- Visibility is local preview state and does not need a full render.
            -- Apply it immediately; the queued refresh only recomputes footprint
            -- and fit geometry for layers such as Auras, Cast and Class Power.
            if PreviewCore.ApplyLayerVisibility then PreviewCore.ApplyLayerVisibility(owner) end
            RequestPreviewLayoutRefresh(owner, "UNIT_PREVIEW_LAYER")
            RefreshHandleSelectionVisuals(owner)
        end,
        OnEnter = function(self, owner, available, on, tr)
            if not available then
                self.bg:SetColorTexture(0.014, 0.038, 0.072, 0.62)
                self.fs:SetTextColor(disabledLayerText[1], disabledLayerText[2], disabledLayerText[3], 0.78)
                owner.hint:SetText(TR("This layer is off in settings. Click to open its options."))
                return
            end
            local label = tr(self.fs and self.fs:GetText() or self.key)
            if owner.hint then owner.hint:SetText(label .. " - " .. TR(on and "click to hide this preview layer" or "click to show this preview layer")) end
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(label, 1, 1, 1)
                if self.tooltip then GameTooltip:AddLine(tr(self.tooltip), 0.82, 0.82, 0.82, true) end
                GameTooltip:AddLine(TR(on and "Click to hide this preview layer." or "Click to show this preview layer."), 0.55, 0.68, 0.86, true)
                if self.key == "guides" then GameTooltip:AddLine(tr(on and "Turn off to inspect the frame without mover outlines. The selected element can still be nudged with arrow keys." or "Guides are hidden. Turn this back on to see drag handles and selected borders."), 0.55, 0.68, 0.86, true) end
                GameTooltip:Show()
            end
        end,
        OnLeave = function(_, owner) UpdateHandleHint(owner, owner._selectedHandle) end,
    }
    for i = 1, #PREVIEW_LAYERS do
        local def = PREVIEW_LAYERS[i]
        -- Bounds are an optional measurement overlay, not part of the frame's
        -- configured visual. Keep the real frame outline visible and start the
        -- separate cyan measurement guide hidden.
        if def.key == "guides" then
            box.layerVisibility[def.key] = PreviewGuidesEnabled()
        elseif def.key == "bounds" then
            box.layerVisibility[def.key] = false
        else
            box.layerVisibility[def.key] = true
        end
        local btn = PreviewHelpers.CreateLayerButton(sidebar, box, def, i, sideW, unitLayerButtonOpts)
        if M2.AddTooltip then
            M2.AddTooltip(btn, "Layer disabled", "Click to open the setting that enables this layer.", {
                hook = true,
                enabled = function(self) return UnitLayerAvailable(box, self.key) == false end,
            })
        end
        box.layerButtons[#box.layerButtons + 1] = btn
    end
    box.LayoutLayerRail = function(self, railWidth)
        if not PreviewHelpers.FlowLayerChips then return 30 end
        railWidth = tonumber(railWidth) or (self.sidebar and self.sidebar.GetWidth and self.sidebar:GetWidth()) or 0
        local headerWidth = 0
        local header = self._msuf2LayerRailHeader
        if header and header:IsShown() then
            headerWidth = (header.GetStringWidth and header:GetStringWidth()) or 44
            headerWidth = headerWidth + 18
        end
        return PreviewHelpers.FlowLayerChips(self.sidebar, self.layerButtons, {
            width = railWidth - headerWidth,
            padX = 10 + headerWidth,
            rowHeight = 20,
        })
    end
    if M2.PreviewSelectionBar then
        M2.PreviewSelectionBar.Create(box, {
            Tr = TR,
            Theme = MenuTheme,
            ApplyBackdrop = ApplyPreviewBackdrop,
            Round = RoundOffset,
            HandleList = function(owner) return owner.handles end,
            HandleLabel = function(handle) return handle._label or handle._key end,
            ReadOffsets = Preview.ReadSelectionCoordinates,
            WriteOffsets = Preview.WriteSelectionCoordinates,
            ResetOffsets = Preview.ResetSelectionOffsets,
            NudgeDelta = function(owner, dx, dy) return NudgeSelectedHandleDelta(owner, dx, dy) end,
            DefaultOffsets = function(_, handle)
                local fields = handle._fields or {}
                return tonumber(fields.defaultX) or 0, tonumber(fields.defaultY) or 0
            end,
            OpenSettings = function(_, handle, source) return OpenPreviewHandleSettings(handle, source) end,
            SelectHandle = function(_, handle) return SelectPreviewHandle(handle, true) end,
            UpdateHint = function(owner, handle) return UpdateHandleHint(owner, handle) end,
        })
        M2.PreviewSelectionBar.CreatePicker(box, canvas)
    end
    -- One layout path for the docked (inline expanded) and floating states: the
    -- rail sits on the bottom edge, the selection bar rides above it, and the
    -- canvas takes whatever is left instead of a fixed-width column.
    box.ApplyDockedPreviewLayout = function(self, bottomInset)
        bottomInset = tonumber(bottomInset) or 12
        local rail, selection, surface = self.sidebar, self._msuf2SelectionBar, self.canvas
        if not surface then return end
        if rail then
            rail:ClearAllPoints()
            rail:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 12, bottomInset)
            rail:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -12, bottomInset)
            rail:Show()
            if self.LayoutLayerRail then
                self:LayoutLayerRail((self.GetWidth and self:GetWidth() or 0) - 24)
            end
        end
        surface:ClearAllPoints()
        surface:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -30)
        if selection and rail then
            selection:ClearAllPoints()
            selection:SetPoint("BOTTOMLEFT", rail, "TOPLEFT", 0, 6)
            selection:SetPoint("BOTTOMRIGHT", rail, "TOPRIGHT", 0, 6)
            selection:Show()
            surface:SetPoint("BOTTOMRIGHT", selection, "TOPRIGHT", 0, 6)
        else
            surface:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -12, bottomInset)
        end
        if self._msuf2ElementPicker then self._msuf2ElementPicker:Show() end
    end
    -- A plain root owns no synthetic Center texture. Only the real health
    -- background media below may cover the unit-frame rectangle; outlines are
    -- drawn by the dedicated four-edge overlay in PreviewCore.
    local mock = CreateFrame("Frame", nil, canvas)
    if mock.SetBackdropColor then mock:SetBackdropColor(0, 0, 0, 0) end
    box.mock = mock
    local function MockTexture(field, layer, texture, color, mode, owner)
        local tex = (owner or mock):CreateTexture(nil, layer)
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
    -- Bounds is guide-line ownership only; it must not create another full-frame
    -- backdrop Center behind the real bar media.
    mock.bounds = CreateFrame("Frame", nil, mock)
    mock.bounds:SetFrameLevel((mock:GetFrameLevel() or 0) + 28)
    mock.bounds:SetAllPoints(mock)
    mock.sizeTag = mock.bounds:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.sizeTag:SetPoint("BOTTOM", mock.bounds, "TOP", 0, 2)
    mock.sizeTag:SetTextColor(0.62, 0.84, 0.94, 0.95)
    if T and T.StyleFontString then T.StyleFontString(mock.sizeTag, { 0.62, 0.84, 0.94, 0.95 }, 0) end
    -- Use the same native StatusBar ownership as the live frame and Group
    -- Preview. The old unit preview stretched a free-standing Texture as its
    -- fill; that left a separate full-frame surface which could render black
    -- instead of showing the selected statusbar/background media.
    mock.healthBar = CreateFrame("StatusBar", nil, mock)
    mock.healthBar:SetAllPoints(mock)
    mock.healthBar:SetMinMaxValues(0, 1)
    mock.healthBar:SetValue(0.72)
    mock.healthBar:SetStatusBarTexture(type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8)
    mock.hp = mock.healthBar:GetStatusBarTexture()
    mock.hpBar, mock.Health, mock.health = mock.healthBar, mock.healthBar, mock.healthBar
    mock.healthFill = mock.hp
    if mock.hp and mock.hp.SetDrawLayer then mock.hp:SetDrawLayer("ARTWORK", 0) end
    if mock.hp then mock.hp:SetAlpha(0) end
    -- Live Health.Create owns the background on the root frame and insets only
    -- the StatusBar fill for embedded power. Keep that exact separation here.
    mock.hpBG = mock:CreateTexture(nil, "BACKGROUND", nil, -7)
    mock.hpBG:SetAllPoints(mock)
    mock.hpBG:SetTexture(TEX_W8)
    mock.hpBG:SetVertexColor(0, 0, 0, 0)
    mock.bg, mock.hpBarBG, mock.healthBg = mock.hpBG, mock.hpBG, mock.hpBG
    MockTexture("tempMaxHealthBg", "ARTWORK", TEX_W8, { 0, 0, 0, 0.65 }, "color", mock.healthBar)
    MockTexture("tempMaxHealth", "ARTWORK", TEX_W8, { 0.70, 0.10, 0.10, 1 }, nil, mock.healthBar)
    MockTexture("healPred", "ARTWORK", TEX_W8, { 0, 1, 0.4, 0.55 }, nil, mock.healthBar)
    MockTexture("absorb", "ARTWORK", TEX_W8, { 0.55, 0.70, 1, 0.58 }, nil, mock.healthBar)
    MockTexture("healAbsorb", "ARTWORK", TEX_W8, { 0.70, 0, 0, 1 }, nil, mock.healthBar)
    MockTexture("powerBG", "BACKGROUND", TEX_W8, { 0, 0, 0, 0 }, "color")
    local initialPower = MockTexture("power", "ARTWORK", type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or TEX_W8, nil, "settex")
    initialPower:SetAlpha(0)
    -- Decorative texture layer preview regions (3 slots): child frames so the
    -- render pass can mirror the runtime's per-slot frame-level offsets (see
    -- RenderTextureLayerPreview).
    mock.texLayers = {}
    for i = 1, 3 do
        local texLayerHolder = CreateFrame("Frame", nil, mock)
        texLayerHolder.tex = texLayerHolder:CreateTexture(nil, "ARTWORK")
        texLayerHolder.tex:SetAllPoints(texLayerHolder)
        texLayerHolder:Hide()
        mock.texLayers[i] = texLayerHolder
    end
    mock.classPower = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.classPower:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
    mock.classPower:SetBackdropColor(0, 0, 0, 0.55)
    mock.classPower:SetBackdropBorderColor(0, 0, 0, 1)
    mock.classPower.segments = {}
    mock.classPower.segmentBgs = {}
    mock.classPower.segmentEdges = {}
    mock.classPower.runeTexts = {}
    mock.classPower.textOwner = CreateFrame("Frame", nil, mock.classPower)
    mock.classPower.textOwner:SetAllPoints(mock.classPower)
    if mock.classPower.textOwner.EnableMouse then mock.classPower.textOwner:EnableMouse(false) end
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
        local rfs = MakeFS(mock.classPower.textOwner, "OVERLAY", 8)
        rfs:SetJustifyH("CENTER")
        if rfs.SetJustifyV then rfs:SetJustifyV("MIDDLE") end
        if rfs.SetShadowColor then rfs:SetShadowColor(0, 0, 0, 1) end
        if rfs.SetShadowOffset then rfs:SetShadowOffset(1, -1) end
        rfs:Hide()
        mock.classPower.runeTexts[i] = rfs
    end
    mock.classPower.text = MakeFS(mock.classPower.textOwner, "OVERLAY", 12)
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
    mock.raidGroupLayer = FillFrame(mock.textFrame)
    mock.hpLayer = FillFrame(mock.textFrame)
    mock.powerLayer = FillFrame(mock.textFrame)
    MakeTextSet(mock.nameLayer, "nameText", "totInlineSep", "totInlineText")
    MakeTextSet(mock.raidGroupLayer, "raidGroupNameText")
    MakeTextSet(mock.hpLayer, "hpTextLeft", "hpTextCenter", "hpText", "hpTextPct")
    MakeTextSet(mock.powerLayer, "powerTextLeft", "powerTextCenter", "powerText", "powerTextPct")
    mock.cast = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    mock.cast:SetBackdrop({ bgFile = TEX_W8 })
    mock.cast:SetBackdropColor(0, 0, 0, 0.92)
    mock.cast:SetBackdropBorderColor(0, 0, 0, 0)
    mock.cast:EnableMouse(false)
    mock.cast:SetScript("OnMouseUp", function(self, button)
        if canvas._msufPreviewPanning then
            StopPreviewPan(canvas)
            return
        end
        if button and button ~= "LeftButton" then return end
        -- Whole-bar movement is owned by handleCastbar on the interaction
        -- layer. This plain Frame keeps a one-click fallback route to the same
        -- settings when that handle is not the active mouse target.
        OpenPreviewHandleSettings(box.handleCastbar, "click")
    end)
    mock.cast:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TR("Castbar"), 1, 1, 1)
            GameTooltip:AddLine(TR("Preview follows the current castbar visibility, whole-bar layer, icon, text, and global color settings."), 0.82, 0.82, 0.82, true)
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
    mock.cast.icon.texture = mock.cast.icon:CreateTexture(nil, "ARTWORK", nil, 7)
    mock.cast.icon.texture:SetTexture(136235)
    mock.cast.icon.texture:SetPoint("TOPLEFT", mock.cast.icon, "TOPLEFT", 1, -1)
    mock.cast.icon.texture:SetPoint("BOTTOMRIGHT", mock.cast.icon, "BOTTOMRIGHT", -1, 1)
    mock.cast.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mock.cast.text = MakeFS(mock.cast, "OVERLAY", 11)
    mock.cast.text:SetPoint("LEFT", mock.cast, "LEFT", 24, 0)
    mock.cast.time = MakeFS(mock.cast, "OVERLAY", 11)
    mock.cast.time:SetPoint("RIGHT", mock.cast, "RIGHT", -6, 0)
    mock.cast.target = MakeFS(mock.cast, "OVERLAY", 10)
    mock.cast.target:SetPoint("TOP", mock.cast, "BOTTOM", 0, -1)
    mock.cast.sizeTag = mock.cast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mock.cast.sizeTag:SetPoint("BOTTOM", mock.cast, "TOP", 0, 2)
    mock.cast.sizeTag:SetTextColor(0.20, 0.90, 0.85, 0.95)
    if T and T.StyleFontString then T.StyleFontString(mock.cast.sizeTag, { 0.20, 0.90, 0.85, 0.95 }, 0) end
    mock.icons = {}
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        mock.icons[spec.id] = CreateIcon(canvas, spec.color, spec.text)
    end
    box.handles = {}
    box.dragFrame = CreateFrame("Frame", nil, canvas)
    box.dragFrame:EnableMouse(true)
    if PreviewHelpers.BindPreviewWheel then PreviewHelpers.BindPreviewWheel(box.dragFrame, box) end
    if box.dragFrame.SetFrameLevel then
        box.dragFrame:SetFrameLevel((PreviewCore.InteractionFrameLevel and PreviewCore.InteractionFrameLevel(canvas, 2))
            or ((canvas:GetFrameLevel() or 0) + 32))
    end
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
        dx, dy = Preview.ActiveHandleDelta(h, dx, dy)
        local nextX = RoundOffset((h._startX or 0) + dx)
        local nextY = RoundOffset((h._startY or 0) + dy)
        if nextX ~= h._startX or nextY ~= h._startY then h._didDragMove = true end
        if h._lastDragX == nextX and h._lastDragY == nextY then return end
        h._lastDragX = nextX
        h._lastDragY = nextY
        WriteHandleOffsets(h, nextX, nextY, "UNIT_PREVIEW_DRAG")
    end
    box.handleName = MakeHandle(box, "name", { x = "nameOffsetX", y = "nameOffsetY", defaultX = 4, defaultY = -4, text = true, resolveOffsetDelta = NameHandleOffsetDelta, section = "text" }, "Name text", { 0.30, 0.66, 1.0 })
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
    box.handleDetachedPower = MakeHandle(box, "detachedPower", { x = "detachedPowerBarOffsetX", y = "detachedPowerBarOffsetY", defaultX = 0, defaultY = -4, detachedPower = true, section = "power", playerSection = "classPower" }, "Detached power bar", { 0.95, 0.72, 0.18 })
    box.texLayerHandles = {
        MakeHandle(box, "texLayer", { x = "texLayerOffsetX", y = "texLayerOffsetY", defaultX = 0, defaultY = 0, texLayer = true, section = "texture_layer" }, "Texture layer 1", { 0.80, 0.55, 0.25 }),
        MakeHandle(box, "texLayer2", { x = "texLayer2OffsetX", y = "texLayer2OffsetY", defaultX = 0, defaultY = 0, texLayer = true, section = "texture_layer" }, "Texture layer 2", { 0.80, 0.55, 0.25 }),
        MakeHandle(box, "texLayer3", { x = "texLayer3OffsetX", y = "texLayer3OffsetY", defaultX = 0, defaultY = 0, texLayer = true, section = "texture_layer" }, "Texture layer 3", { 0.80, 0.55, 0.25 }),
    }
    box.handleClassPower = MakeHandle(box, "classPower", { barsX = "classPowerOffsetX", barsY = "classPowerOffsetY", defaultX = 0, defaultY = 0, classPower = true, readOffsets = ReadBarsHandleOffsets, writeOffsets = WriteBarsHandleOffsets, section = "classPower" }, "Class power", { 0.30, 0.78, 0.55 })
    box.handleClassPowerText = MakeHandle(box, "classPowerText", { barsX = "classPowerTextOffsetX", barsY = "classPowerTextOffsetY", defaultX = 0, defaultY = 0, classPower = true, readOffsets = ReadBarsHandleOffsets, writeOffsets = WriteBarsHandleOffsets, section = "classPower" }, "Class power text", { 0.30, 0.78, 0.55 })
    box.handleCastbar = MakeHandle(box, "castbar", { castbar = true, global = true, section = "castbar" }, "Castbar", { 0.20, 0.90, 0.85 })
    box.handleCastbarIcon = MakeHandle(box, "castbarIcon", { suffixX = "IconOffsetX", suffixY = "IconOffsetY", bossX = "bossCastIconOffsetX", bossY = "bossCastIconOffsetY", defaultX = 0, defaultY = 0, iconFallback = true, readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar", interactionPriority = 1 }, "Castbar icon", { 0.20, 0.90, 0.85 })
    box.handleCastbarText = MakeHandle(box, "castbarText", { suffixX = "TextOffsetX", suffixY = "TextOffsetY", bossX = "bossCastTextOffsetX", bossY = "bossCastTextOffsetY", defaultX = 0, defaultY = 0, readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar", interactionPriority = 1 }, "Castbar text", { 0.20, 0.90, 0.85 })
    box.handleCastbarTarget = MakeHandle(box, "castbarTarget", { suffixX = "TargetNameOffsetX", suffixY = "TargetNameOffsetY", bossX = "bossCastTargetNameOffsetX", bossY = "bossCastTargetNameOffsetY", defaultX = 0, defaultY = 1, readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar", interactionPriority = 1 }, "Cast target text", { 0.95, 0.78, 0.22 })
    box.handleCastbarTime = MakeHandle(box, "castbarTime", { suffixX = "TimeOffsetX", suffixY = "TimeOffsetY", bossX = "bossCastTimeOffsetX", bossY = "bossCastTimeOffsetY", bossBaseX = -2, defaultX = -2, defaultY = 0, defaultXFromG = "castbarPlayerTimeOffsetX", defaultYFromG = "castbarPlayerTimeOffsetY", readOffsets = ReadCastbarSubOffsets, writeOffsets = WriteCastbarSubOffsets, section = "castbar", interactionPriority = 1 }, "Castbar time", { 0.20, 0.90, 0.85 })
    if type(PreviewAuras.CreateHandles) == "function" then PreviewAuras.CreateHandles(box, MakeHandle) end
    box.statusHandles = { raidgroupname = box.handleRaidGroupName }
    for i = 1, #STATUS_PREVIEW do
        local spec = STATUS_PREVIEW[i]
        box.statusHandles[spec.id] = MakeHandle(box, spec.id, { x = spec.x, y = spec.y, defaultX = spec.defaultX or 0, defaultY = spec.defaultY or 0, statusRefresh = spec.refresh, section = "status" }, spec.label, spec.color)
    end
    box:EnableKeyboard(true)
    if box.SetPropagateKeyboardInput then box:SetPropagateKeyboardInput(true) end
    box:SetScript("OnKeyDown", PreviewArrowKeyDown)
    function box:ReleasePreviewInteraction()
        self._selectedHandle = nil
        Preview.SetArrowBindings(self, false)
        RefreshHandleSelectionVisuals(self)
        if self.dragFrame then
            self.dragFrame:SetScript("OnUpdate", nil)
            self.dragFrame:SetScript("OnMouseUp", nil)
            self.dragFrame._handle = nil
            self.dragFrame:Hide()
        end
        if self._msufPreviewNudgeTarget
            and rawget(_G, "MSUF_EM2_ActivePreviewNudgeTarget") == self._msufPreviewNudgeTarget
            and type(_G.MSUF_EM2_SetPreviewNudgeTarget) == "function"
        then
            _G.MSUF_EM2_SetPreviewNudgeTarget(nil)
        end
        if PreviewHelpers.ReleaseKeyboardCapture then
            PreviewHelpers.ReleaseKeyboardCapture(self)
        elseif self.SetPropagateKeyboardInput then
            self:SetPropagateKeyboardInput(true)
        end
    end
    box:SetScript("OnShow", function(self)
        self._msuf2PreviewShowSerial = (tonumber(self._msuf2PreviewShowSerial) or 0) + 1
        Preview.active = self
        if PreviewAnimationActive(self) then StartPreviewAnimationDriver(self) end
        RefreshPreviewAnimationButton(self)
        self:RequestRefresh("SHOW")
    end)
    box:SetScript("OnHide", function(self)
        StopPreviewAnimationDriver(self)
        if PreviewAnimationActive(self) then Preview.RestoreStaticEditModeAuraPreview(self) end
        ReleaseUnitPreviewLiveState(self)
        self._refreshSerial = (tonumber(self._refreshSerial) or 0) + 1
        self._refreshQueued = nil
        self._refreshReason = nil
        if self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
        end
        self:ReleasePreviewInteraction()
        if Preview.active == self then Preview.active = nil end
        if type(Preview.UninstallRefreshHooks) == "function" then Preview.UninstallRefreshHooks() end
    end)
    box:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            KillPreviewAnimationForCombat(self)
            self._refreshReason = nil
            self._refreshQueued = nil
            self._selectedHandle = nil
            Preview.SetArrowBindings(self, false)
            if PreviewHelpers.ReleaseKeyboardCapture then
                PreviewHelpers.ReleaseKeyboardCapture(self)
            elseif self.SetPropagateKeyboardInput then
                self:SetPropagateKeyboardInput(true)
            end
            RefreshHandleSelectionVisuals(self)
        end
    end)
    box:HookScript("OnSizeChanged", function(self, changedWidth, changedHeight)
        if not self:IsShown() then return end
        changedWidth = floor((tonumber(changedWidth) or self:GetWidth() or 0) + 0.5)
        changedHeight = floor((tonumber(changedHeight) or self:GetHeight() or 0) + 0.5)
        if self._msufUFPreviewRefreshWidth == changedWidth and self._msufUFPreviewRefreshHeight == changedHeight then return end
        self._msufUFPreviewRefreshWidth = changedWidth
        self._msufUFPreviewRefreshHeight = changedHeight
        -- The chip rail wraps on width, and the canvas hangs off its top edge,
        -- so a resize has to reflow the rail before the render measures the
        -- canvas.
        if self._msuf2CompactPreview ~= true and self.ApplyDockedPreviewLayout then
            self:ApplyDockedPreviewLayout(12)
        end
        self:RequestRefresh("UNIT_PREVIEW_SIZE")
    end)
    box.OnPreviewCanvasMoved = function(_, button)
        if PreviewHelpers.NotePreviewCanvasMoved then PreviewHelpers.NotePreviewCanvasMoved(button) end
    end
    box:ApplyDockedPreviewLayout(12)
    RegisterUnitPreviewRuntimeControls(box, M2.activeKey)
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
        PreviewInCombat TR PortraitStyleGet RuntimeSpecForPreviewKey RuntimeAppliedPortraitSizeForPreviewKey RuntimeVisualScaleForPreviewKey RuntimeCastbarVisualScaleForPreviewKey ClampPreviewZoom ResolveDefaultPreviewZoomLock UpdatePreviewZoomControls ZOOM_MIN
        max min abs floor format TEX_W8 FONT STATUS_PREVIEW CurrentPanelKey UnitDB UNIT_DATA UNIT_LABELS ReadPowerBarEnabled ReadPowerBarHeight LiveUnitData SyncLiveStateDriver
    ]],
        PreviewInCombat, TR, PortraitStyleGet, RuntimeSpecForPreviewKey, PreviewRuntime.AppliedPortraitSizeForPreviewKey or F.Nil, RuntimeVisualScaleForPreviewKey, PreviewRuntime.CastbarVisualScaleForPreviewKey or RuntimeVisualScaleForPreviewKey, ClampPreviewZoom, PreviewZoomPan.ResolveDefaultLock or F.Noop, UpdatePreviewZoomControls, ZOOM_MIN,
        max, min, abs, floor, format, TEX_W8, FONT, STATUS_PREVIEW, CurrentPanelKey, UnitDB, UNIT_DATA, UNIT_LABELS, ReadPowerBarEnabled, ReadPowerBarHeight, PreviewModel.LiveUnitData, SyncUnitPreviewLiveState)
    AssignNamedValues(deps, [[
        PreviewRaidGroupNameAllowed PreviewRaidGroupNameText NormalizeRaidGroupNameAnchor CastbarEnabled CastbarShowIcon CastbarShowText ReadCastbarSize ReadCastbarNum FormatCastbarPreviewTime
        CastbarOffsetFields CastbarDetached CanDetachPowerBarKey ClampPreviewLayer SetTex PlaceHandle PlaceHandleAroundRegions UnitPreviewText UnitPreviewTextMovesTogether
        NormalizeHpMode NormalizePowerMode TextScopeGet TextScopeHasSlots TextScopeSlotGet FormatMode ShortenPreviewName ToTInlineSeparator ResolveNameAnchor ClassColor HealthColor
    ]],
        PreviewRaidGroupNameAllowed, PreviewRaidGroupNameText, NormalizePreviewRaidGroupNameAnchor, CastbarEnabled, CastbarShowIcon, CastbarShowText, ReadCastbarSize, ReadCastbarNum, FormatCastbarPreviewTime,
        CastbarOffsetFields, CastbarDetached, CanDetachPowerBarKey, ClampPreviewLayer, SetTex, PlaceHandle, UnitPreviewText.PlaceHandleAroundRegions, UnitPreviewText, UnitPreviewTextMovesTogether,
        NormalizeHpMode, NormalizePowerMode, TextScopeGet, TextScopeHasSlots, TextScopeSlotGet, FormatMode, ShortenPreviewName, ToTInlineSeparator, ResolveNameAnchor, ClassColor, HealthColor)
    AssignNamedValues(deps, [[
        DarkMatchHPColor HealthBackgroundColor PowerBackgroundColor PowerColor FontColor PreviewResolveHealPredAnchorMode PreviewResolveAbsorbAnchorMode PreviewHealPredictionEnabled PreviewAbsorbBarEnabled
        UnitPreviewPortraitTexture ClassPortraitVisual PreviewNameColor PreviewToTInlineColor LayoutUnitPreviewOverlay PositionFromAnchor PositionRuntimeLayoutIconPreview
        PositionStatusCornerPreview PositionSameAnchorPreview PositionLevelPreview ResolveStatusPreviewAnchor SetPreviewIconTexture NormalizeStatusPreviewId
        ApplyPreviewTextFocus ApplyPreviewRounded ApplyPreviewFrameBorder PreviewRoundedOutlineThickness ApplyPreviewBoundsGuide SetShownSafe ApplyPreviewLayerVisibility
        ApplyPreviewTransparency RefreshHandleSelectionVisuals Auras
    ]],
        DarkMatchHPColor, HealthBackgroundColor, PowerBackgroundColor, PowerColor, FontColor, PreviewResolveHealPredAnchorMode, PreviewResolveAbsorbAnchorMode, PreviewHealPredictionEnabled, PreviewAbsorbBarEnabled,
        UnitPreviewPortraitTexture, ClassPortraitVisual, PreviewNameColor, PreviewToTInlineColor, LayoutUnitPreviewOverlay, PositionFromAnchor, PositionRuntimeLayoutIconPreview,
        PositionStatusCornerPreview, PositionSameAnchorPreview, PositionLevelPreview, ResolveStatusPreviewAnchor, SetPreviewIconTexture, NormalizeStatusPreviewId,
        ApplyPreviewTextFocus, ApplyPreviewRounded, ApplyPreviewFrameBorder, PreviewRoundedOutlineThickness, ApplyPreviewBoundsGuide, SetShownSafe, ApplyPreviewLayerVisibility,
        Preview.ApplyPreviewTransparency, RefreshHandleSelectionVisuals, PreviewAuras)
end
if MSUF.UFPreviewRender and MSUF.UFPreviewRender.Install then MSUF.UFPreviewRender.Install(Preview, Preview.RefreshDeps) end
Preview._BuildPreview = BuildPreview
Preview._PreviewInCombat = PreviewInCombat
