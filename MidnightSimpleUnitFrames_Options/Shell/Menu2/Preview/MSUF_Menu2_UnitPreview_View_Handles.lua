--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View_Handles.lua
--- Cold-path unitframe preview handle support.
---
--- Owns: runtime control registration for the preview surface, the
--- handle-to-settings navigation routes, the bars/castbar offset storage
--- backends, menu history bookkeeping and the text handle selection state.
--- Split from MSUF_Menu2_UnitPreview_View.lua, which keeps drag, nudge,
--- refresh and construction; it loads before the view and publishes through
--- MSUF.UFPreviewViewHandles (public routes stay on MSUF.UFPreview).
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
local PreviewCore = MSUF.UFPreviewCore or {}
local PreviewCastbar = MSUF.UFPreviewCastbar or {}
local PreviewZoomPan = MSUF.UFPreviewZoomPan or {}
local M2 = MSUF.MSUF2 or _G.MSUF2 or {}
local EnsureDB = M2.EnsureDB
local PreviewHelpers = M2.PreviewHelpers or {}

local PreviewModel = Preview.Model or {}
local CanonKey, CurrentPanelKey, UnitDB = PreviewModel.CanonKey, PreviewModel.CurrentPanelKey, PreviewModel.UnitDB
local ApplyPanelUnit, NormalizeStatusPreviewId = PreviewModel.ApplyPanelUnit, PreviewModel.NormalizeStatusPreviewId
local ResolveNameOffsetDelta = PreviewModel.ResolveNameOffsetDelta
local RoundOffset = PreviewCore.RoundOffset
local Handles = MSUF.UFPreviewViewHandles or {}
MSUF.UFPreviewViewHandles = Handles
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
local OpenPreviewHandleSettings
local function EnsureBarsDB()
    local db = EnsureDB()
    db.bars = db.bars or {}
    return db.bars
end
local function ReadBarsHandleOffsets(handle)
    local fields = handle and handle._fields or {}
    local bars = EnsureDB().bars or {}
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
    boss_target = "boss_target_highlight",
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
local function NameHandleOffsetDelta(handle, dx, dy)
    local box = handle and handle._preview
    local key = box and (box.key or (box._msufPanel and CurrentPanelKey(box._msufPanel))) or "player"
    local conf = UnitDB(key)
    return ResolveNameOffsetDelta(conf and conf.nameTextAnchor, dx, dy)
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
M2.AssignNamedValues(Handles, [[
    RegisterUnitPreviewControl UnitPreviewTextMovesTogether ApplyCastbarRuntimeForKey
    ReadBarsHandleOffsets WriteBarsHandleOffsets ReadCastbarSubOffsets WriteCastbarSubOffsets
    BeginMenuHistory CommitMenuHistory CheckpointMenuHistory OpenPreviewHandleSettings NameHandleOffsetDelta
    PreviewTextKindSlotForKey StorePreviewTextSelection HANDLE_BORDER_SPECS UnitPreviewLayerForHandle
]],
    RegisterUnitPreviewControl, UnitPreviewTextMovesTogether, ApplyCastbarRuntimeForKey,
    ReadBarsHandleOffsets, WriteBarsHandleOffsets, ReadCastbarSubOffsets, WriteCastbarSubOffsets,
    BeginMenuHistory, CommitMenuHistory, CheckpointMenuHistory, OpenPreviewHandleSettings, NameHandleOffsetDelta,
    PreviewTextKindSlotForKey, StorePreviewTextSelection, HANDLE_BORDER_SPECS, UnitPreviewLayerForHandle)
