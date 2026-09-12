--- Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View_Chrome.lua
--- Cold-path unitframe preview chrome.
---
--- Owns: the hint line and guides toggle, the pinned/compact presentation
--- switches, the text focus ring, and the Animate button with its preview
--- animation and live-state drivers. Split from MSUF_Menu2_UnitPreview_View.lua,
--- which keeps drag, nudge, refresh and construction; it loads before the view
--- and publishes through MSUF.UFPreviewViewChrome (public routes stay on
--- MSUF.UFPreview).
local addonName, addonNS = ...
local MSUF = addonNS or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic
MSUF.L = MSUF.L or (_G.MSUF_L) or {}
local L = MSUF.L
if not getmetatable(L) then setmetatable(L, { __index = function(_, k) return k end }) end
local isEn = (MSUF and MSUF.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end
local format = string.format
local TEX_W8 = "Interface\\Buttons\\WHITE8X8"
local Preview = MSUF.UFPreview or {}
MSUF.UFPreview = Preview
local PreviewCore = MSUF.UFPreviewCore or {}
local M2 = MSUF.MSUF2 or _G.MSUF2 or {}
local EnsureDB = M2.EnsureDB
local PreviewHelpers = M2.PreviewHelpers or {}

local PreviewModel = Preview.Model or {}
local CanonKey, TextScopeGet, UnitPreviewText = PreviewModel.CanonKey, PreviewModel.TextScopeGet, PreviewModel.UnitPreviewText
local MenuTheme = PreviewCore.MenuTheme
local ApplyPreviewBackdrop = PreviewCore.ApplyBackdrop
local Chrome = MSUF.UFPreviewViewChrome or {}
MSUF.UFPreviewViewChrome = Chrome
local function PreviewGuidesEnabled()
    local db = EnsureDB()
    local general = db and db.general
    if type(general) == "table" and general.unitPreviewGuidesEnabled ~= nil then return general.unitPreviewGuidesEnabled ~= false end
    return false
end
local function SetPreviewGuidesEnabled(enabled)
    local db = EnsureDB()
    db.general = db.general or {}
    db.general.unitPreviewGuidesEnabled = enabled ~= false
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
local NormalizePreviewTextFocusKind = PreviewHelpers.NormalizeTextFocusKind
local NormalizePreviewTextFocusSlot = PreviewHelpers.NormalizeTextFocusSlot
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
local UNIT_PREVIEW_ANIMATION_INTERVAL = 1 / 20
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
local StartPreviewAnimationDriver = PreviewHelpers.CreateAnimationStarter(PreviewAnimationInCombat, StopPreviewAnimationDriver, PreviewAnimationOnUpdate)
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
local SetUnitCanvasToolsShown = M2.PreviewHelpers.SetCanvasToolsShown
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
        SetUnitCanvasToolsShown(box, false, box and box.animateCombatButton)
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
            box._msuf2LayerPopoverWidth = popoverWidth
            sidebar:SetWidth(popoverWidth)
            if box._msuf2LayerRailHeader then box._msuf2LayerRailHeader:Hide() end
            if box.LayoutLayerRail then box:LayoutLayerRail(popoverWidth) end
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
        box._msuf2LayerPopoverWidth = nil
        if box.title then box.title:Show() end
        if box.hint then box.hint:Show() end
        SetUnitCanvasToolsShown(box, true, box and box.animateCombatButton)
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
M2.AssignNamedValues(Chrome, [[
    PreviewGuidesEnabled SetPreviewGuidesEnabled PreviewGuidesVisible DefaultPreviewHint UpdateHandleHint
    RequestPreviewLayoutRefresh ApplyPreviewTextFocus
    PreviewAnimationActive RefreshPreviewAnimationButton StopPreviewAnimationDriver KillPreviewAnimationForCombat
    SyncUnitPreviewLiveState ReleaseUnitPreviewLiveState StartPreviewAnimationDriver CreatePreviewAnimationButton
    ApplyUnitPinnedPresentation SetUnitCanvasToolsShown LayoutUnitHeaderControls ApplyUnitCompactPresentation
]],
    PreviewGuidesEnabled, SetPreviewGuidesEnabled, PreviewGuidesVisible, DefaultPreviewHint, UpdateHandleHint,
    RequestPreviewLayoutRefresh, ApplyPreviewTextFocus,
    PreviewAnimationActive, RefreshPreviewAnimationButton, StopPreviewAnimationDriver, KillPreviewAnimationForCombat,
    SyncUnitPreviewLiveState, ReleaseUnitPreviewLiveState, StartPreviewAnimationDriver, CreatePreviewAnimationButton,
    ApplyUnitPinnedPresentation, SetUnitCanvasToolsShown, LayoutUnitHeaderControls, ApplyUnitCompactPresentation)
