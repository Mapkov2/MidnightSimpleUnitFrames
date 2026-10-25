--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View_Handles.lua
--- Cold-path unitframe preview handle support.
---
--- Owns: runtime control registration for the preview surface, the
--- handle-to-settings navigation routes, the bars/castbar offset storage
--- backends, menu history bookkeeping and the text handle selection state.
--- Split from MSUF_Menu2_UnitPreview_View.lua, which keeps drag, nudge,
--- refresh and construction; it loads before the view and publishes through
--- MSUF.UFPreviewViewHandles (public routes stay on MSUF.UFPreview).
local MSUF = _G.MSUF
local FILE = "Menu2/UnitPreview_View_Handles"
local ExportPublic = MSUF.ExportPublic
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
local PreviewCore = MSUF.UFPreviewCore or {}
local PreviewCastbar = MSUF.UFPreviewCastbar or {}
local PreviewZoomPan = MSUF.UFPreviewZoomPan or {}
local M2 = MSUF.MSUF2
local EnsureDB = M2.EnsureDB
local PreviewHelpers = M2.PreviewHelpers or {}

local PreviewModel = Preview.Model or {}
local CanonKey, CurrentPanelKey, UnitDB = PreviewModel.CanonKey, PreviewModel.CurrentPanelKey, PreviewModel.UnitDB
local ApplyPanelUnit, NormalizeStatusPreviewId = PreviewModel.ApplyPanelUnit, PreviewModel.NormalizeStatusPreviewId
local ResolveNameOffsetDelta = PreviewModel.ResolveNameOffsetDelta
local RoundOffset = PreviewCore.RoundOffset
local Handles = MSUF.UFPreviewViewHandles or {}
MSUF.UFPreviewViewHandles = Handles
-- Core runtime providers that every drag and nudge step calls. They are plain
-- core exports that load before this addon, so they are resolved once here.
local ApplyCastbarUnitAndSync = MSUF.Require("MSUF_ApplyCastbarUnitAndSync", FILE)
local ClassPowerApply = MSUF.Optional("MSUF_ClassPower_Apply")
local ClassPowerRefresh = MSUF.Require("MSUF_ClassPower_Refresh", FILE)
local ApplyPowerBarEmbedLayout = MSUF.Require("MSUF_ApplyPowerBarEmbedLayout_ForUnitKey", FILE)
--- A saved-state sub table (menu.unitX[unit] style bookkeeping) created on first use.
local function SubTable(parent, field)
    local child = parent[field]
    if not child then
        child = {}
        parent[field] = child
    end
    return child
end
local function RegisterUnitPreviewControl(widget, semanticPath, label, kind, classification, extra, pageKey)
    local page = M2.UnitPage
    if page and page.RegisterControl then
        page.RegisterControl(widget, { key = pageKey or M2.activeKey }, "preview." .. tostring(semanticPath), label, kind, classification, extra)
    end
    return widget
end
-- The highlighted gear is both a Search action (it opens the element's
-- settings) and, on other pages, plain navigation. The unit view registers the
-- selected handle's gear the same way, with its own translator.
local function GearOpenLabel(handle, translate)
    return M2.Format("Open %s settings", translate(tostring(handle._label or handle._key or "preview element")))
end
local function GearActionExtra(gear)
    return {
        historyMode = "none",
        help = "Click the highlighted preview button to jump directly to this element's settings below.",
        command = gear and gear._msuf2UnitPreviewOpenCommand,
    }
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
        and M2.IsRuntimeControlRegisteredForWidget
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
        or (PreviewHelpers.BuildZoomCommand and PreviewHelpers.BuildZoomCommand(box, PreviewZoomPan, "UNIT_PREVIEW_SEARCH_ZOOM"))
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
            if not Preview.Pan then return false end
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
        -- Class power belongs to the Player preview, the PvP trinket to Arena.
        if button and (button.key ~= "classPower" or previewUnitKey == "player")
            and (button.key ~= "trinket" or previewUnitKey == "arena") then
            Register(button, "layer." .. tostring(button.key),
                M2.Format("%s preview layer", tostring((button.fs and button.fs.GetText and button.fs:GetText()) or button.key or "Preview layer")),
                "button", "ephemeral")
        end
    end
    for i = 1, #(box.handles or {}) do
        local handle = box.handles[i]
        local key = handle and handle._key
        local fields = handle and handle._fields or {}
        local exposeHandle = handle and not (fields.classPower == true and previewUnitKey ~= "player")
            and not (key == "arenaTrinket" and previewUnitKey ~= "arena")
        if exposeHandle and handle._msuf2CommandAction then handle._msuf2CommandAction.previewUnitKey = previewUnitKey end
        -- Drag handles are direct-manipulation surfaces, not deterministic
        -- one-shot actions. Their underlying offsets remain Search-visible
        -- through the bound sliders; the adjacent gear is navigation.
        if exposeHandle then Register(handle, "handle." .. tostring(key), handle._label or key, "button", "ephemeral") end
        local gear = exposeHandle and handle._msuf2SettingsGear
        if gear then
            local path = "handle." .. tostring(key) .. ".open_settings"
            local label = GearOpenLabel(handle, M2.TranslateText)
            -- An action only on the preview's own unit page: a preview shown inside
            -- another page (each Colors category) keeps its gears as navigation,
            -- so search does not list every element's gear once per category.
            if gear._msuf2UnitPreviewOpenCommand and tostring(pageKey or ""):match("^uf_") then
                Register(gear, path, label, "button", "action", GearActionExtra(gear))
            else
                Register(gear, path, label, "button", "navigation", { navigationKey = UnitPreviewHandleNavigationKey(handle, pageKey) })
            end
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
            -- Exact rows on the Player page only; a preview inside another page
            -- (each Colors category) keeps the two fields ephemeral.
            local offsetClass = tostring(pageKey or ""):match("^uf_") and "setting" or "ephemeral"
            Register(selectionBar.editX, "selection.dispel_symbol_offset_x", "UnitFrame Dispel Symbol Offset X",
                "textinput", offsetClass, {
                    searchRouteDisposition = "dynamic",
                    searchRouteDispositionReason = "The shared Preview X field is pinned to the Player-owned Dispel Symbol handle for this exact Search route.",
                    searchSettingKeys = { "player.unitDispelSymbolX" },
                    command = selectionAPI.BuildExactOffsetCommand(box, "dispelSymbol", "x", {
                        previewSurface = "unit", previewUnitKey = "player",
                    }),
                })
            Register(selectionBar.editY, "selection.dispel_symbol_offset_y", "UnitFrame Dispel Symbol Offset Y",
                "textinput", offsetClass, {
                    searchRouteDisposition = "dynamic",
                    searchRouteDispositionReason = "The shared Preview Y field is pinned to the Player-owned Dispel Symbol handle for this exact Search route.",
                    searchSettingKeys = { "player.unitDispelSymbolY" },
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
    local byUnit = M2.unitTextMoveTogether and M2.unitTextMoveTogether[unitKey or "player"]
    local value = byUnit and byUnit[kind]
    if value == nil then return true end
    return value == true
end
local function UnitPreviewSetTextMoveTogether(unitKey, kind, value)
    SubTable(SubTable(M2, "unitTextMoveTogether"), unitKey or "player")[kind] = value ~= false
end
local function ApplyCastbarRuntimeForKey(key)
    ApplyCastbarUnitAndSync(key)
end
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
    if ClassPowerApply then
        ClassPowerApply({ anchor = true, cdm = true, playerHP = true, syncNow = false })
    else
        ClassPowerRefresh()
    end
    ApplyPowerBarEmbedLayout("player", true)
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
    -- Arena shares the boss-style flat key family; derive arenaCast* from the
    -- declared bossCast* field name instead of a per-unit prefix.
    if unitKey == "arena" and bossKey then return (bossKey:gsub("^bossCast", "arenaCast")) end
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
    local flatKey = CanonKey(key)
    if (flatKey == "boss" or flatKey == "arena") and fields.bossBaseX ~= nil then x = (tonumber(fields.bossBaseX) or 0) + (x or 0) end
    if (flatKey == "boss" or flatKey == "arena") and fields.bossBaseY ~= nil then y = (tonumber(fields.bossBaseY) or 0) + (y or 0) end
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
    local flatKey = CanonKey(key)
    if (flatKey == "boss" or flatKey == "arena") and fields.bossBaseX ~= nil then x = (tonumber(x) or 0) - (tonumber(fields.bossBaseX) or 0) end
    if (flatKey == "boss" or flatKey == "arena") and fields.bossBaseY ~= nil then y = (tonumber(y) or 0) - (tonumber(fields.bossBaseY) or 0) end
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
    if not M2.BeginHistoryTransaction then return false end
    return M2.BeginHistoryTransaction(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action))
end
local function CommitMenuHistory()
    if M2.CommitHistoryTransaction then return M2.CommitHistoryTransaction() end
    return false
end
local function CheckpointMenuHistory(handle, action)
    if M2.CheckpointHistory then return M2.CheckpointHistory(MenuHistoryLabel(handle, action), MenuHistorySource(handle, action)) end
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
    pvp_trinket = "pvp_trinket",
}
function Preview.PrepareUnitHandleSubmenu(menu, unit, handle)
    if not (menu and handle) then return end
    local key, section = handle._key, Preview.ResolveUnitHandleSection(handle, unit)
    local state, tab
    if section == "text" then state, tab = "unitTextTabSelection", key == "name" and "name" or (key:sub(1, 2) == "hp" and "hp" or "power")
    elseif section == "portrait" then state, tab = "unitPortraitTabSelection", "placement"
    elseif section == "castbar" then
        state = "unitCastbarTabSelection"
        tab = key == "castbarIcon" and "icon" or (key == "castbarTime" and "time" or ((key == "castbarText" or key == "castbarTarget")
            and "spell" or "general"))
    end
    if state then SubTable(menu, state)[unit] = tab end
    local textureSlot = section == "texture_layer" and (tonumber(key:match("^texLayer(%d)$")) or 1)
    local textureSlotChanged = false
    if textureSlot then
        local slots, tabs = SubTable(menu, "unitTexLayerSlot"), SubTable(menu, "unitTexLayerTab")
        textureSlotChanged = (tonumber(slots[unit]) or 1) ~= textureSlot
        slots[unit] = textureSlot
        tabs[unit] = "placement"
    end
    return textureSlotChanged
end
local AURA_PREVIEW_LANES = { debuff = true, custom1 = true, custom2 = true, custom3 = true, custom4 = true }
--- Every handle route posts the same EM2 focus request before it selects its page.
local function PostMenuFocusRequest(request, source)
    request.source = "unit-preview-" .. tostring(source or "settings")
    request.explicit = true
    request.changedAt = GetTime and GetTime() or 0
    ExportPublic("MSUF_EM2_MenuFocusRequest", request)
end
local function OpenAuraHandleSettings(handle, box, unit, fields, source)
    local lane = fields.auraPreviewKind
    if not AURA_PREVIEW_LANES[lane] then lane = "buff" end
    local laneSelection = SubTable(M2, "unitAuraTabSelection")
    local laneChanged = (laneSelection[unit] or "buff") ~= lane
    laneSelection[unit] = lane
    local toolSelection = SubTable(M2, "unitAuraToolSelection")
    local tools = toolSelection[unit]
    if type(tools) ~= "table" then
        tools = {}
        toolSelection[unit] = tools
    end
    local toolChanged = tools[lane] ~= "layout"
    tools[lane] = "layout"
    local pageKey = "uf_" .. tostring(unit)
    if not M2.SelectPage then return false end
    PostMenuFocusRequest({
        key = unit,
        component = handle._key,
        lane = lane,
        pageKey = pageKey,
        sectionId = "auras",
        -- A direct Preview click is navigation, not a temporary
        -- search/edit-mode reveal. Keep Auras open when its first
        -- control refresh rebuilds the Unit page.
        persistSection = true,
    }, source)
    -- SelectPage switches to the retained container/tool view. Only a view
    -- change needs restoration after its preview adopts the new page context.
    if laneChanged or toolChanged then
        Preview._restoreHandleUnit, Preview._restoreHandleKey, Preview._restoreSourceBox = unit, handle._key, box
        Preview._restoreSourceShowSerial = tonumber(box and box._msuf2PreviewShowSerial) or 0
    end
    local selected = M2.SelectPage(pageKey) ~= false
    if selected then
        -- A retained view can keep the same preview box and show generation.
        -- Selection has now committed, so that box may restore the new handle.
        if laneChanged or toolChanged then Preview._restoreSourceBox, Preview._restoreSourceShowSerial = nil, nil end
        Preview.RestoreQueuedHandle(Preview.active)
    else
        Preview._restoreHandleUnit, Preview._restoreHandleKey, Preview._restoreSourceBox, Preview._restoreSourceShowSerial = nil, nil, nil, nil
    end
    return selected
end
local function OpenClassPowerHandleSettings(handle, source)
    if not M2.SelectPage then return false end
    local sectionId = "classpower_display"
    if handle._key == "classPowerText" then
        sectionId = "classpower_visuals"
        if M2.SetMenuStateValue then M2.SetMenuStateValue("classPowerStyleTab", "text") else M2.classPowerStyleTab = "text" end
    elseif handle._key == "detachedPower" then
        sectionId = "classpower_detached_power"
        if M2.SetMenuStateValue then M2.SetMenuStateValue("classPowerDetachedPowerTab", "layout")
        else M2.classPowerDetachedPowerTab = "layout" end
    end
    PostMenuFocusRequest({ pageKey = "classpower", sectionId = sectionId }, source)
    return M2.SelectPage("classpower") ~= false
end
local function OpenPreviewHandleSettings(handle, source)
    if not handle then return false end
    local box = handle._preview or Preview.active
    local fields = handle._fields or {}
    local unit = box and box.key or "player"
    local section = Preview.ResolveUnitHandleSection(handle, unit)
    Preview.PrepareUnitHandleSubmenu(M2, unit, handle)
    if fields.statusRefresh then
        local selected = NormalizeStatusPreviewId(handle._key)
        Preview.selectedStatusId = selected
        SubTable(M2, "unitStatusSelection")[unit] = selected
        SubTable(M2, "unitStatusTabSelection")[unit] = "basic"
    end
    if section == "auras3" then return OpenAuraHandleSettings(handle, box, unit, fields, source) end
    if section == "classPower" then return OpenClassPowerHandleSettings(handle, source) end
    local sectionId = UNIT_SECTION_IDS[section or ""] or UNIT_SECTION_IDS.text
    local pageKey = box and (box._msuf2PinnedPreviewPageKey or ("uf_" .. tostring(box.key or "player"))) or nil
    if M2.SelectPage and pageKey then
        PostMenuFocusRequest({ key = box and box.key, component = handle._key, pageKey = pageKey, sectionId = sectionId }, source)
        return M2.SelectPage(pageKey) ~= false
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
    trinket = { key = "arenaTrinket", section = "pvp_trinket" },
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
    SubTable(menu, "unitTextTabSelection")[unitKey] = kind
    if slot then SubTable(SubTable(menu, "unitTextSlotSelection"), unitKey)[kind] = slot end
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
M2.Assign(Handles, {
    RegisterUnitPreviewControl = RegisterUnitPreviewControl,
    UnitPreviewTextMovesTogether = UnitPreviewTextMovesTogether,
    ApplyCastbarRuntimeForKey = ApplyCastbarRuntimeForKey, ReadBarsHandleOffsets = ReadBarsHandleOffsets,
    WriteBarsHandleOffsets = WriteBarsHandleOffsets, ReadCastbarSubOffsets = ReadCastbarSubOffsets,
    WriteCastbarSubOffsets = WriteCastbarSubOffsets, BeginMenuHistory = BeginMenuHistory,
    CommitMenuHistory = CommitMenuHistory, CheckpointMenuHistory = CheckpointMenuHistory,
    OpenPreviewHandleSettings = OpenPreviewHandleSettings, NameHandleOffsetDelta = NameHandleOffsetDelta,
    PreviewTextKindSlotForKey = PreviewTextKindSlotForKey, StorePreviewTextSelection = StorePreviewTextSelection,
    HANDLE_BORDER_SPECS = HANDLE_BORDER_SPECS, UnitPreviewLayerForHandle = UnitPreviewLayerForHandle,
})
