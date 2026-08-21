--- EditMode/MSUF_EditMode_Popups.lua - popup router and unit frame popup.
-- Owns popup composition only; protected frame edits route through EditMode apply helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local EM2 = _G.MSUF_EM2
if not EM2 then return end

if type(_G.MSUF_InstallEditPopupUI) == "function" then
    _G.MSUF_InstallEditPopupUI(addonName, MSUF)
end

local U = EM2.Util or {}
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe or function() return false end
local function ApplySettingsForKeySafe(key)
    local util = EM2 and EM2.Util or U
    local fn = util and util.ApplySettingsForKeySafe
    if type(fn) == "function" then return fn(key) end
    return false
end
local Menu2Style = _G.MSUF_EM2_Menu2Style or {}
local Factory = EM2.PopupFactory or {}
local Quick = EM2.QuickPopup or Menu2Style.QuickPopup or {}
local C = Factory.Colors or {}
local W8 = Factory.WhiteTexture or "Interface/Buttons/WHITE8X8"
local FS = Factory.FontString or Quick.FS
local Tr = Factory.Tr or Quick.Tr or U.Tr or function(text) return text end
local RefreshPalette = Factory.RefreshPalette or Quick.RefreshPalette or function() return C end
local BlockConfigCombatLocked = Factory.BlockConfigCombatLocked or Quick.BlockConfigCombatLocked or U.BlockConfigCombatLocked or function() return false end
local RefreshUFPreview = Factory.RefreshUFPreview or U.RefreshUFPreview or function() end
--- Shared legal unit-frame size range (State/MSUF_Defaults.lua). Every
--- width/height write below clamps against this table; the options unit
--- preview clamps its mock to the same table, so popup writes and preview
--- geometry cannot drift apart.
local SizeBounds = _G.MSUF_UnitFrameSizeBounds or { minW = 40, maxW = 800, minH = 8, maxH = 200 }

--- Popup router. All popups are Midnight-native (EM2).
local Popups = {}
EM2.Popups = Popups

local function NotifyGuidedPopupOpened(key)
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    if menu and type(menu.NotifyGuidedEditModePopupOpened) == "function" then
        return menu.NotifyGuidedEditModePopupOpened(key)
    end
    return false
end

function Popups.CloseAll()
    if EM2.ExternalPopup then EM2.ExternalPopup.Close() end
    if EM2.UnitPopup then EM2.UnitPopup.Close() end
    if EM2.CastPopup then EM2.CastPopup.Close() end
    if EM2.AuraPopup then EM2.AuraPopup.Close() end
    if _G.MSUF_EM2_HideGFPopup then
        _G.MSUF_EM2_HideGFPopup("party")
        _G.MSUF_EM2_HideGFPopup("raid")
        _G.MSUF_EM2_HideGFPopup("mythicraid")
    end
    if EM2.State then EM2.State.SetPopupOpen(false) end
    if EM2.Focus and EM2.Focus.ClearPopupFocus then EM2.Focus.ClearPopupFocus() end
end

function Popups.Open(key, anchorFrame)
    if type(key) ~= "string" or key == "" then return end
    local cfg = EM2.Registry and EM2.Registry.Get(key)
    local pType = cfg and cfg.popupType

    if not pType then
        if key == "player" or key == "target" or key == "focus" or key == "focustarget" or key == "targettarget" or key == "pet" or key:match("^boss%d") then
            pType = "unit"
        elseif key:sub(1, 8) == "castbar_" then
            pType = "castbar"
        elseif key:sub(1, 5) == "aura_" then
            pType = "aura"
        elseif key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority" then
            pType = key
        end
    end

    Popups.CloseAll()

    if pType == "external" then
        local external = EM2.ExternalElements
        if external and type(external.Select) == "function" then
            external.Select(key, "mover", anchorFrame)
        end
        if EM2.ExternalPopup then EM2.ExternalPopup.Open(key, anchorFrame) end
    elseif pType == "unit" then
        ExportPublic("MSUF_EM2_ActiveAuraGroup", nil)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", nil)
        local unit = key
        if key:match("^boss%d") then unit = "boss" end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.UnitPopup then
            EM2.UnitPopup.Open(unit, frame or anchorFrame)
            if EM2.State then EM2.State.SetPopupOpen(true) end
        end
    elseif pType == "castbar" then
        ExportPublic("MSUF_EM2_ActiveAuraGroup", nil)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", nil)
        local unit = key
        if key:sub(1, 8) == "castbar_" then unit = key:sub(9) end
        if type(unit) == "string" and unit:match("^boss%d+$") then unit = "boss" end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.CastPopup then EM2.CastPopup.Open(unit, frame or anchorFrame) end
    elseif pType == "aura" then
        local unit = key
        if key:sub(1, 5) == "aura_" then unit = key:sub(6) end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.AuraPopup then EM2.AuraPopup.Open(unit, frame or anchorFrame) end
    elseif pType == "gf_party" or pType == "gf_raid" or pType == "gf_mythicraid" then
        ExportPublic("MSUF_EM2_ActiveAuraGroup", nil)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", nil)
        local mode = (pType == "gf_raid") and "raid" or ((pType == "gf_mythicraid") and "mythicraid" or "party")
        if _G.MSUF_EM2_ShowGFPopup then
            _G.MSUF_EM2_ShowGFPopup(mode)
            if EM2.State then EM2.State.SetPopupOpen(true) end
        end
    elseif pType == "gf_priority" then
        ExportPublic("MSUF_EM2_ActiveAuraGroup", nil)
        ExportPublic("MSUF_EM2_ActiveAuraUnit", nil)
        if EM2.Focus and EM2.Focus.SetSelection then
            EM2.Focus.SetSelection("gf_priority", "placement", nil, {
                source = "priority-mover",
                openSettings = true,
            })
        end
        if EM2.Focus and EM2.Focus.OpenFullSettings then
            EM2.Focus.OpenFullSettings("gf_priority")
        end
    end
    local opened = Popups.IsAnyOpen and Popups.IsAnyOpen() or false
    if opened then
        if EM2.State then EM2.State.SetPopupOpen(true) end
        if EM2.Focus and EM2.Focus.SetPopupFocus then EM2.Focus.SetPopupFocus(key, anchorFrame) end
        NotifyGuidedPopupOpened(key)
    end
    return opened
end

function Popups.IsAnyOpen()
    return (EM2.ExternalPopup and EM2.ExternalPopup.IsOpen())
        or (EM2.UnitPopup and EM2.UnitPopup.IsOpen())
        or (EM2.CastPopup and EM2.CastPopup.IsOpen())
        or (EM2.AuraPopup and EM2.AuraPopup.IsOpen())
        or (type(_G.MSUF_EM2_GFPopupIsOpen) == "function" and _G.MSUF_EM2_GFPopupIsOpen())
        or false
end

--- MSUF_EM2_Popup_Unit.lua - v5
local floor = math.floor
local max, min = math.max, math.min
local function DB() return _G.MSUF_DB end
local function Conf(k) local db=DB(); return db and db[k] end
local CK = U.NormalizeUnitKey or function(u) return u end
local UnitLabel = U.UnitLabel or function(u) return tostring(u or "") end
local UnitPageKey = U.UnitPageKey or function() return "uf_player" end
local UNIT_COPY_TARGETS = {
    { key="player", label="Player" },
    { key="target", label="Target" },
    { key="focus", label="Focus" },
    { key="focustarget", label="Focus Target" },
    { key="targettarget", label="ToT" },
    { key="pet", label="Pet" },
    { key="boss", label="Boss" },
}
local San = Quick.San
local CanDetachUnitPowerBar = _G.MSUF_CanDetachUnitPowerBar
local CanonPowerBarUnitKey = _G.MSUF_CanonPowerBarUnitKey
local function CanDetachPower(key)
    if type(CanDetachUnitPowerBar) == "function" then return CanDetachUnitPowerBar(key) == true end
    return type(CanonPowerBarUnitKey) == "function" and CanonPowerBarUnitKey(key) ~= nil
end
local pf
local Sync
local UnitSectionForComponent = U.UnitSectionForComponent
local SyncMovers = U.SyncMovers or function() if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end end
local NotifyPositionChanged = U.NotifyPositionChanged or function(key, immediate) if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, immediate) end end
local FramePositionValues = U.FramePositionValues
local TranslateFramePosition = U.TranslateFramePosition

local function FrameForUnitKey(key)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(key)
        if frame then return frame end
    end
    local frames = uf and uf.frames or _G.MSUF_UnitFrames
    return key and frames and frames[key] or nil
end

local function ApplyPowerLayoutForUnitKey(key, detached)
    local M = (MSUF and MSUF.MSUF2) or _G.MSUF2
    local ApplyService = (M and M.ApplyService) or _G.MSUF_Menu2_ApplyService
    if ApplyService and type(ApplyService.ApplyPowerLayout) == "function" then
        return ApplyService.ApplyPowerLayout(key, detached == true, true)
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey) == "function" then
        return _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true)
    end
    local frame = FrameForUnitKey(key) or (pf and pf.parent)
    if type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" and frame then
        return _G.MSUF_ApplyPowerBarEmbedLayout(frame)
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
        return _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
    return false
end

local function Apply()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    local frame = FrameForUnitKey(key) or pf.parent
    local currentX, currentY = San(conf.offsetX, 0), San(conf.offsetY, 0)
    local displayX = pf.xBox and tonumber(pf.xBox:GetText())
    local displayY = pf.yBox and tonumber(pf.yBox:GetText())
    local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then conf.width=floor(max(SizeBounds.minW,min(SizeBounds.maxW,w))+0.5) end
    local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then conf.height=floor(max(SizeBounds.minH,min(SizeBounds.maxH,h))+0.5) end
    local sharedDetachedWidthSourceChanged = false
    if conf.powerBarDetached and CanDetachPower(key) then
        local manualDetachedWidthSelected = false
        local dx=pf.dpbXBox and tonumber(pf.dpbXBox:GetText()); if dx then conf.detachedPowerBarOffsetX=San(dx,0) end
        local dy=pf.dpbYBox and tonumber(pf.dpbYBox:GetText()); if dy then conf.detachedPowerBarOffsetY=San(dy,-4) end
        local dw=pf.dpbWBox and tonumber(pf.dpbWBox:GetText())
        if dw then
            dw = floor(max(20,min(800,dw))+0.5)
            local original = tonumber(pf._msufDetachedWidthOriginal)
            manualDetachedWidthSelected = original ~= nil and dw ~= original
            if manualDetachedWidthSelected then
                local bars = _G.MSUF_DB and _G.MSUF_DB.bars
                sharedDetachedWidthSourceChanged = bars and bars.detachedPowerBarWidthMode ~= nil or false
                if bars then bars.detachedPowerBarWidthMode = nil end
                conf.detachedPowerBarWidth = dw
                if key == "player" then conf.detachedPowerBarSyncClassPower = false end
                if pf.dpbSyncBtn and pf.dpbSyncBtn.SetCheckedVisual then pf.dpbSyncBtn:SetCheckedVisual(false) end
            else
                conf.detachedPowerBarWidth = dw
            end
            pf._msufDetachedWidthOriginal = dw
        end
        local dh=pf.dpbHBox and tonumber(pf.dpbHBox:GetText()); if dh then conf.detachedPowerBarHeight=floor(max(2,min(80,dh))+0.5) end
        local dl=pf.dpbLevelBox and tonumber(pf.dpbLevelBox:GetText()); if dl then conf.detachedPowerBarFrameLevelOffset=floor(max(0,min(30,dl))+0.5) end
        if pf.dpbTextBtn then conf.detachedPowerBarTextOnBar = pf.dpbTextBtn._checked and true or false end
        if key == "player" then
            if pf.dpbSyncBtn and not manualDetachedWidthSelected then
                conf.detachedPowerBarSyncClassPower = pf.dpbSyncBtn._checked and true or false
            end
            if pf.dpbAnchorBtn then conf.detachedPowerBarAnchorToClassPower = pf.dpbAnchorBtn._checked and true or false end
        end
    end
    --- Direct SetSize: MarkDirty/UpdateSimpleUnitFrame only handles health/power/text,
    --- not frame dimensions. Apply width/height immediately.
    if frame and conf.width and conf.height then
        frame:SetSize(conf.width, conf.height)
    end
    if type(TranslateFramePosition) == "function" then
        conf.offsetX, conf.offsetY = TranslateFramePosition(frame, currentX, currentY, displayX, displayY)
    else
        conf.offsetX, conf.offsetY = San(displayX, currentX), San(displayY, currentY)
    end
    if frame and frame.ForceUpdate then frame:ForceUpdate("EM2_UNIT_POPUP") end
    --- Full layout re-apply (power bar embed, text anchors, borders, etc.)
    if sharedDetachedWidthSourceChanged then
        ApplyAllSettingsSafe()
        if type(_G.MSUF_EnsureCooldownWidthObservers) == "function" then _G.MSUF_EnsureCooldownWidthObservers() end
    elseif not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
    if type(_G.MSUF_ForceTextLayoutForUnitKey)=="function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
    --- Clear PBEmbedLayout stamp so width/height changes are re-applied
    if frame then
        local cs=_G.MSUF_NS and _G.MSUF_NS.Cache; if cs and cs.ClearStamp then cs.ClearStamp(frame, "PBEmbedLayout") end
    end
    ApplyPowerLayoutForUnitKey(key, conf.powerBarDetached == true and CanDetachPower(key))
    if pf._refreshVisibility then pf._refreshVisibility() end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_APPLY", key)
    NotifyPositionChanged(key, true)
    if pf and pf:IsShown() then Sync() end
end

function Sync()
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    if pf._titleFS then pf._titleFS:SetText(Tr(UnitLabel(key)) .. " " .. Tr("Frame")) end
    local frame = FrameForUnitKey(key) or pf.parent
    local x, y, width, height
    if type(FramePositionValues) == "function" then
        x, y, width, height = FramePositionValues(frame)
    end
    Quick.SetBoxText(pf.xBox,x ~= nil and x or San(conf.offsetX,0)); Quick.SetBoxText(pf.yBox,y ~= nil and y or San(conf.offsetY,0))
    Quick.SetBoxText(pf.wBox,conf.width or width or (frame and frame:GetWidth()) or 250)
    Quick.SetBoxText(pf.hBox,conf.height or height or (frame and frame:GetHeight()) or 40)
    if pf.detachBtn and pf.detachBtn.SetCheckedVisual then
        local canDetach = CanDetachPower(key)
        local detachedOn = canDetach and conf.powerBarDetached == true
        pf.detachBtn:SetShown(canDetach)
        pf.detachBtn:SetCheckedVisual(detachedOn)
        if pf.dpbPanel then
            pf.dpbPanel:SetShown(detachedOn)
            --- Keep the detail panel between the quiet detach action and the pinned footer.
            pf:SetHeight(detachedOn and (key == "player" and 620 or 584) or (canDetach and 410 or 370))
            if detachedOn then pf.dpbPanel:SetHeight(key == "player" and 220 or 184) end
        end
        if detachedOn then
            Quick.SetBoxText(pf.dpbXBox, San(conf.detachedPowerBarOffsetX, 0))
            Quick.SetBoxText(pf.dpbYBox, San(conf.detachedPowerBarOffsetY, -4))
            local detachedWidth = floor(max(20, min(800, tonumber(conf.detachedPowerBarWidth or conf.width) or 250)) + 0.5)
            Quick.SetBoxText(pf.dpbWBox, detachedWidth)
            pf._msufDetachedWidthOriginal = detachedWidth
            Quick.SetBoxText(pf.dpbHBox, conf.detachedPowerBarHeight or 6)
            Quick.SetBoxText(pf.dpbLevelBox, conf.detachedPowerBarFrameLevelOffset or 6)
            if pf.dpbTextBtn and pf.dpbTextBtn.SetCheckedVisual then
                pf.dpbTextBtn:SetCheckedVisual(conf.detachedPowerBarTextOnBar == true)
            end
            local isPlayer = key == "player"
            if pf.dpbSyncBtn then
                pf.dpbSyncBtn:SetShown(isPlayer)
                if pf.dpbSyncBtn.SetCheckedVisual then pf.dpbSyncBtn:SetCheckedVisual(isPlayer and conf.detachedPowerBarSyncClassPower ~= false) end
            end
            if pf.dpbAnchorBtn then
                pf.dpbAnchorBtn:SetShown(isPlayer)
                if pf.dpbAnchorBtn.SetCheckedVisual then pf.dpbAnchorBtn:SetCheckedVisual(isPlayer and conf.detachedPowerBarAnchorToClassPower == true) end
            end
            local firstY = isPlayer and -92 or -72
            if pf.dpbXYRow then
                pf.dpbXYRow:ClearAllPoints()
                pf.dpbXYRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY)
            end
            if pf.dpbWHRow then
                pf.dpbWHRow:ClearAllPoints()
                pf.dpbWHRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY - 36)
            end
            if pf.dpbLayerRow then
                pf.dpbLayerRow:ClearAllPoints()
                pf.dpbLayerRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY - 72)
            end
        end
    end
end

local function SetHUDStatus(text, kind)
    if type(_G.MSUF_EM2_SetHUDStatus) == "function" then
        _G.MSUF_EM2_SetHUDStatus(Tr(text), kind)
    end
end

local function ApplyMenu2UnitSelection(component, slot)
    if not pf or not pf.unit then return nil end
    local key = CK(pf.unit)
    if not key then return nil end
    local pageKey = UnitPageKey(key)
    local sectionId = UnitSectionForComponent(component)

    if EM2.Focus and EM2.Focus.SetSelection then
        EM2.Focus.SetSelection(key, component, slot, { source = "unit-popup", menu = false })
    end

    if U.SetMenuFocusRequest then U.SetMenuFocusRequest({
        key = key,
        component = component,
        slot = slot,
        pageKey = pageKey,
        sectionId = sectionId,
        source = "unit-popup",
    }) end

    local M = _G.MSUF2 or (MSUF and MSUF.MSUF2)
    if M and (component == "name" or component == "hp" or component == "power") then
        U.SyncUnitTextMenuState(M, key, component, slot)
    end

    return key
end

local function OpenMenu2Page(pageKey, component, slot)
    if not pf or not pf.unit then return end
    Apply()
    local key = ApplyMenu2UnitSelection(component, slot)
    pageKey = pageKey or UnitPageKey(key or CK(pf.unit))
    Quick.OpenPage(pageKey, pf)
end

local function OpenMenu2Settings()
    OpenMenu2Page(nil, "frame")
end

local function ApplyDetachPower(checked)
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local key = CK(pf.unit)
    if not CanDetachPower(key) then return end
    local conf = key and Conf(key)
    if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    conf.powerBarDetached = checked and true or false
    if conf.powerBarDetached then
        conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
        conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
        conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or 250
        conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
        conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
        if key == "player" and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
    end
    if not ApplySettingsForKeySafe(key) then ApplyAllSettingsSafe() end
    ApplyPowerLayoutForUnitKey(key, conf.powerBarDetached == true)
    if pf.parent and pf.parent.ForceUpdate then pf.parent:ForceUpdate("EM2_UNIT_POPUP_DETACH") end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_DETACH", key)
    SetHUDStatus(checked and "Detached powerbar" or "Embedded powerbar", "ok")
    Sync()
end

local function ResetPosition()
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit then return end
    local key = CK(pf.unit)
    local conf = key and Conf(key)
    if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    local dx, dy = 0, 0
    if type(_G.MSUF_GetDefaultUnitOffsets) == "function" then dx, dy = _G.MSUF_GetDefaultUnitOffsets(key) end
    conf.offsetX, conf.offsetY = dx, dy
    if not ApplySettingsForKeySafe(key) then ApplyAllSettingsSafe() end
    if pf.parent and pf.parent.ForceUpdate then pf.parent:ForceUpdate("EM2_UNIT_POPUP_RESETPOS") end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_RESETPOS", key)
    NotifyPositionChanged(key, true)
    if pf and pf:IsShown() then Sync() end
end

--- Copies the source frame's size only. Position is deliberately excluded so a
--- size copy cannot unexpectedly move another frame. The unit page copy dialog
--- ("Frame Size") holds the same contract -- placement stays independently editable.
local function CopySizeTo(targetKey)
    if BlockConfigCombatLocked() then return end
    if not pf or not pf.unit or not targetKey then return end
    local db = DB()
    if not db then return end
    Apply()
    local srcKey = CK(pf.unit)
    local src = srcKey and db[srcKey]
    if not src or targetKey == srcKey then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", targetKey) end
    local dst = db[targetKey]
    if not dst then db[targetKey] = {}; dst = db[targetKey] end
    if src.width ~= nil then dst.width = floor(max(SizeBounds.minW, min(SizeBounds.maxW, tonumber(src.width) or 250)) + 0.5) end
    if src.height ~= nil then dst.height = floor(max(SizeBounds.minH, min(SizeBounds.maxH, tonumber(src.height) or 40)) + 0.5) end
    local applied = ApplySettingsForKeySafe(targetKey)
    ApplyPowerLayoutForUnitKey(targetKey, dst.powerBarDetached == true and CanDetachPower(targetKey))
    if not applied and not ApplyAllSettingsSafe() and type(_G.MSUF_UpdateAllFrames)=="function" then _G.MSUF_UpdateAllFrames() end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_COPY_SIZE", targetKey)
    if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(targetKey, "frame", nil, { source = "unit-copy", duration = 0.32 }) end
    SetHUDStatus("Copied frame size", "ok")
    Sync()
end

local function CaptureSizeRatio()
    local w = pf and pf.wBox and tonumber(pf.wBox:GetText())
    local h = pf and pf.hBox and tonumber(pf.hBox:GetText())
    if w and h and h > 0 then pf._sizeRatio = w / h end
end

local function ApplySize(changed)
    if pf and pf._lockRatio then
        local ratio = tonumber(pf._sizeRatio)
        local w = pf.wBox and tonumber(pf.wBox:GetText())
        local h = pf.hBox and tonumber(pf.hBox:GetText())
        if ratio and ratio > 0 then
            if changed == "width" and w then
                Quick.SetBoxText(pf.hBox, floor(max(SizeBounds.minH, min(SizeBounds.maxH, w / ratio)) + 0.5))
            elseif changed == "height" and h then
                Quick.SetBoxText(pf.wBox, floor(max(SizeBounds.minW, min(SizeBounds.maxW, h * ratio)) + 0.5))
            end
        end
    end
    Apply()
end

local function ToggleSizeRatio(checked)
    if not pf then return end
    pf._lockRatio = checked and true or false
    if pf._lockRatio then CaptureSizeRatio() end
end

local function Build()
    if pf then return pf end
    RefreshPalette()
    local toggleOpts = {
        palette = C,
        sync = function() if pf and pf:IsShown() then Sync() end end,
    }

    pf = Quick.CreateShell("MSUF_EM2_UnitPopup", {
        width = 560,
        height = 410,
        title = "Frame",
        liveStatus = true,
        hoverSource = "unit-popup",
        blocker = BlockConfigCombatLocked,
    })

    local function WirePopupFocus(btn, component, slot)
        return U.WirePopupFocus and U.WirePopupFocus(btn, function() return pf and pf.unit and CK(pf.unit) end, component, "unit-popup", slot) or btn
    end

    local function CopyMenuEntries()
        local entries = { { key = "__all__", label = "All units", highlight = true } }
        local srcKey = pf and pf.unit and CK(pf.unit)
        for _, target in ipairs(UNIT_COPY_TARGETS) do
            if target.key ~= srcKey then entries[#entries + 1] = target end
        end
        return entries
    end

    local function CopyMenuSelect(entry)
        if entry.key == "__all__" then
            local srcKey = pf and pf.unit and CK(pf.unit)
            for _, target in ipairs(UNIT_COPY_TARGETS) do
                if target.key ~= srcKey then CopySizeTo(target.key) end
            end
        else
            CopySizeTo(entry.key)
        end
    end

    Quick.ValueCard(pf, pf, 20, -58, 208, "Position", {
        { label = "X", key = "xBox", onChanged = Apply },
        { label = "Y", key = "yBox", onChanged = Apply },
    }, { height = 132, boxWidth = 64 })
    local sizeCard = Quick.ValueCard(pf, pf, 240, -58, 300, "Size", {
        { label = "Width", key = "wBox", onChanged = function() ApplySize("width") end },
        { label = "Height", key = "hBox", onChanged = function() ApplySize("height") end },
    }, { height = 132, boxWidth = 64, controlsRightInset = 88 })
    pf.ratioBtn = Quick.ToggleAt(sizeCard, "Lock ratio", 208, -80, 80, 32, ToggleSizeRatio, toggleOpts)

    WirePopupFocus(Quick.ButtonAt(pf, "Frame", 20, -204, 96, 34, OpenMenu2Settings, { active = true }), "frame")
    WirePopupFocus(Quick.ButtonAt(pf, "Bars", 124, -204, 96, 34, function() OpenMenu2Page(nil, "powerbar") end), "powerbar")
    WirePopupFocus(Quick.ButtonAt(pf, "Text", 228, -204, 96, 34, function() OpenMenu2Page(nil, "name") end), "name")
    WirePopupFocus(Quick.ButtonAt(pf, "Auras", 332, -204, 96, 34, function() OpenMenu2Page(nil, "auras") end), "auras")
    WirePopupFocus(Quick.ButtonAt(pf, "Cast", 436, -204, 104, 34, function() OpenMenu2Page(nil, "castbar") end), "castbar")

    Quick.ButtonAt(pf, "Open detailed settings", 20, -250, 334, 36, OpenMenu2Settings, { variant = "primary" })
    Quick.MenuButtonAt(pf, "Copy size to...", 366, -250, 174, 36, CopyMenuEntries, CopyMenuSelect, { palette = C })
    pf.detachBtn = Quick.ToggleAt(pf, "Detach power bar", 174, -300, 212, 30, ApplyDetachPower, toggleOpts)

    pf.dpbPanel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    pf.dpbPanel:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -340)
    pf.dpbPanel:SetSize(520, 220)
    pf.dpbPanel:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    pf.dpbPanel:SetBackdropColor(C.cardBg[1], C.cardBg[2], C.cardBg[3], 0.58)
    pf.dpbPanel:SetBackdropBorderColor(C.cardEdge[1], C.cardEdge[2], C.cardEdge[3], 0.72)
    Menu2Style.Card(pf.dpbPanel)
    local dpbTitle = FS(pf.dpbPanel, "body", C.white)
    dpbTitle:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, -12)
    dpbTitle:SetText(Tr("Detached power bar"))
    local dpbHint = FS(pf.dpbPanel, "caption", C.muted)
    dpbHint:SetPoint("LEFT", dpbTitle, "RIGHT", 12, 0)
    dpbHint:SetText(Tr("offset, size, and layer"))
    pf.dpbTextBtn = Quick.ToggleAt(pf.dpbPanel, "Text on bar", 16, -36, 112, 30, Apply, toggleOpts)
    pf.dpbSyncBtn = Quick.ToggleAt(pf.dpbPanel, "Sync class", 140, -36, 112, 30, Apply, toggleOpts)
    pf.dpbAnchorBtn = Quick.ToggleAt(pf.dpbPanel, "Anchor class", 264, -36, 114, 30, Apply, toggleOpts)
    pf.dpbXYRow = Quick.ValuePairAt(pf, pf.dpbPanel, 16, -92, "X offset", "dpbXBox", Apply, "Y offset", "dpbYBox", Apply)
    pf.dpbWHRow = Quick.ValuePairAt(pf, pf.dpbPanel, 16, -126, "Width", "dpbWBox", Apply, "Height", "dpbHBox", Apply)
    pf.dpbLayerRow = Quick.SingleValueAt(pf, pf.dpbPanel, 16, -160, "Layer", "dpbLevelBox", Apply)
    do
        local ui = (MSUF and MSUF.UI) or _G.MSUF_UI
        local info
        if ui and type(ui.Button) == "function" then
            info = ui.Button(pf.dpbLayerRow, "I", 20, 20, {
                variant = "success",
                skipHistory = true,
                align = "CENTER",
                onClick = function(self)
                    local show = _G.MSUF_ShowLayerOverview
                    if type(show) == "function" then show(self) end
                end,
            })
        elseif type(Quick.Button) == "function" then
            info = Quick.Button(pf.dpbLayerRow, "I", 20, 20, function(self)
                local show = _G.MSUF_ShowLayerOverview
                if type(show) == "function" then show(self) end
            end)
        end
        if info then
            info:SetPoint("RIGHT", pf.dpbLayerRow, "RIGHT", 0, 0)
            info._msuf2SkipHistoryCheckpoint = true
            info._msuf2LayerOverviewButton = true
            if info.HookScript then
                info:HookScript("OnEnter", function(self)
                    if not _G.GameTooltip then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(Tr("Layer overview"), 0.35, 1.00, 0.62)
                    GameTooltip:AddLine(Tr("Shows all configurable MSUF layers on the unified 0-30 scale."), 0.78, 0.86, 0.96, true)
                    GameTooltip:Show()
                end)
                info:HookScript("OnLeave", function() if _G.GameTooltip then GameTooltip:Hide() end end)
                info:HookScript("OnHide", function(self)
                    local hide = _G.MSUF_HideLayerOverviewForAnchor
                    if type(hide) == "function" then hide(self) end
                end)
            end
            pf.dpbLayerInfoButton = info
        end
    end
    pf.dpbPanel:Hide()

    if Quick.AddFooterControls then
        Quick.AddFooterControls(pf, { anchor = "BOTTOM", bottomGap = 12, onResetPosition = ResetPosition })
    end

    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end
    return pf
end

local UnitPopup = {}; EM2.UnitPopup = UnitPopup
function UnitPopup.Open(u, parent) if BlockConfigCombatLocked() then return false end; Build(); pf.unit=u; pf.parent=parent; Sync(); if pf._lockRatio then CaptureSizeRatio() end; pf:Show(); if Menu2Style.FadeIn then Menu2Style.FadeIn(pf, 0.12, 0.86, 1) end; return true end
function UnitPopup.Close() if pf then pf:Hide() end end
function UnitPopup.IsOpen() return pf and pf:IsShown() or false end
function UnitPopup.Sync() if pf and pf:IsShown() then Sync() end end
function UnitPopup.RefreshHistory() if pf and pf:IsShown() and pf._refreshUndoRedo then pf._refreshUndoRedo() end end
local ASSISTANT_UNIT_FIELDS = {
    x = { "xBox" }, y = { "yBox" }, width = { "wBox" }, height = { "hBox" },
    detachedX = { "dpbXBox" }, detachedY = { "dpbYBox" }, detachedWidth = { "dpbWBox" },
    detachedHeight = { "dpbHBox" }, detachedLayer = { "dpbLevelBox" },
    detached = { "detachBtn", true }, textOnBar = { "dpbTextBtn", true },
    syncClass = { "dpbSyncBtn", true }, anchorClass = { "dpbAnchorBtn", true },
}
function UnitPopup.GetAssistantField(field)
    if not (pf and pf.unit and pf:IsShown()) then return nil end
    local spec = ASSISTANT_UNIT_FIELDS[field]
    local widget = spec and pf[spec[1]]
    if not widget then return nil end
    if spec[2] then return widget._checked == true end
    return tonumber(widget.GetText and widget:GetText())
end
function UnitPopup.SetAssistantField(field, value)
    if BlockConfigCombatLocked() or not (pf and pf.unit and pf:IsShown()) then return false end
    local spec = ASSISTANT_UNIT_FIELDS[field]
    local widget = spec and pf[spec[1]]
    if not widget then return false end
    if spec[2] then
        local checked = value == true
        if widget.SetCheckedVisual then widget:SetCheckedVisual(checked) end
        widget._checked = checked
        if field == "detached" then ApplyDetachPower(checked) else Apply() end
    else
        Quick.SetBoxText(widget, tonumber(value))
        Apply()
    end
    return UnitPopup.GetAssistantField(field) == (spec[2] and (value == true) or tonumber(value))
end
