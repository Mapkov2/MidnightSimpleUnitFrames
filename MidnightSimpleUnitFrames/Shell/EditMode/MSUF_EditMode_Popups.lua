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

--- Popup router. All popups are Midnight-native (EM2).
local Popups = {}
EM2.Popups = Popups

function Popups.CloseAll()
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
        elseif key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" then
            pType = key
        end
    end

    Popups.CloseAll()

    if pType == "unit" then
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
    end
    if Popups.IsAnyOpen and Popups.IsAnyOpen() then
        if EM2.State then EM2.State.SetPopupOpen(true) end
        if EM2.Focus and EM2.Focus.SetPopupFocus then EM2.Focus.SetPopupFocus(key, anchorFrame) end
    end
end

function Popups.IsAnyOpen()
    return (EM2.UnitPopup and EM2.UnitPopup.IsOpen())
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
local function CanDetachPower(key) return key=="player" or key=="target" or key=="focus" end
local pf
local Sync
local UnitSectionForComponent = U.UnitSectionForComponent
local SyncMovers = U.SyncMovers or function() if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end end
local NotifyPositionChanged = U.NotifyPositionChanged or function(key, immediate) if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, immediate) end end

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
    conf.offsetX=San(pf.xBox and tonumber(pf.xBox:GetText()),0); conf.offsetY=San(pf.yBox and tonumber(pf.yBox:GetText()),0)
    local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then conf.width=floor(max(40,min(800,w))+0.5) end
    local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then conf.height=floor(max(8,min(200,h))+0.5) end
    if conf.powerBarDetached and CanDetachPower(key) then
        local dx=pf.dpbXBox and tonumber(pf.dpbXBox:GetText()); if dx then conf.detachedPowerBarOffsetX=San(dx,0) end
        local dy=pf.dpbYBox and tonumber(pf.dpbYBox:GetText()); if dy then conf.detachedPowerBarOffsetY=San(dy,-4) end
        local dw=pf.dpbWBox and tonumber(pf.dpbWBox:GetText()); if dw then conf.detachedPowerBarWidth=floor(max(20,min(800,dw))+0.5) end
        local dh=pf.dpbHBox and tonumber(pf.dpbHBox:GetText()); if dh then conf.detachedPowerBarHeight=floor(max(2,min(80,dh))+0.5) end
        local dl=pf.dpbLevelBox and tonumber(pf.dpbLevelBox:GetText()); if dl then conf.detachedPowerBarFrameLevelOffset=floor(max(0,min(20,dl))+0.5) end
        if pf.dpbTextBtn then conf.detachedPowerBarTextOnBar = pf.dpbTextBtn._checked and true or false end
        if key == "player" then
            if pf.dpbSyncBtn then conf.detachedPowerBarSyncClassPower = pf.dpbSyncBtn._checked and true or false end
            if pf.dpbAnchorBtn then conf.detachedPowerBarAnchorToClassPower = pf.dpbAnchorBtn._checked and true or false end
        end
    end
    --- Direct SetSize: MarkDirty/UpdateSimpleUnitFrame only handles health/power/text,
    --- not frame dimensions. Apply width/height immediately.
    if pf.parent and conf.width and conf.height then
        pf.parent:SetSize(conf.width, conf.height)
    end
    if pf.parent and pf.parent.ForceUpdate then pf.parent:ForceUpdate("EM2_UNIT_POPUP") end
    --- Full layout re-apply (power bar embed, text anchors, borders, etc.)
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
    if type(_G.MSUF_ForceTextLayoutForUnitKey)=="function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
    --- Clear PBEmbedLayout stamp so width/height changes are re-applied
    if pf.parent then
        local cs=_G.MSUF_NS and _G.MSUF_NS.Cache; if cs and cs.ClearStamp then cs.ClearStamp(pf.parent, "PBEmbedLayout") end
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
    if pf._titleFS then pf._titleFS:SetText(Tr(UnitLabel(key) .. " - Frame")) end
    Quick.SetBoxText(pf.xBox,San(conf.offsetX,0)); Quick.SetBoxText(pf.yBox,San(conf.offsetY,0))
    Quick.SetBoxText(pf.wBox,conf.width or (pf.parent and pf.parent:GetWidth()) or 250)
    Quick.SetBoxText(pf.hBox,conf.height or (pf.parent and pf.parent:GetHeight()) or 40)
    if pf.detachBtn and pf.detachBtn.SetCheckedVisual then
        local canDetach = CanDetachPower(key)
        local detachedOn = canDetach and conf.powerBarDetached == true
        pf.detachBtn:SetShown(canDetach)
        pf.detachBtn:SetCheckedVisual(detachedOn)
        if pf.dpbPanel then
            pf.dpbPanel:SetShown(detachedOn)
            --- +44 reserved at the bottom for the Undo/Redo/Reset footer row.
            pf:SetHeight(detachedOn and (key == "player" and 570 or 532) or (canDetach and 336 or 288))
            if detachedOn then pf.dpbPanel:SetHeight(key == "player" and 220 or 184) end
        end
        if detachedOn then
            Quick.SetBoxText(pf.dpbXBox, San(conf.detachedPowerBarOffsetX, 0))
            Quick.SetBoxText(pf.dpbYBox, San(conf.detachedPowerBarOffsetY, -4))
            Quick.SetBoxText(pf.dpbWBox, conf.detachedPowerBarWidth or conf.width or 250)
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
            local firstY = isPlayer and -92 or -62
            if pf.dpbXYRow then
                pf.dpbXYRow:ClearAllPoints()
                pf.dpbXYRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY)
            end
            if pf.dpbWHRow then
                pf.dpbWHRow:ClearAllPoints()
                pf.dpbWHRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY - 34)
            end
            if pf.dpbLayerRow then
                pf.dpbLayerRow:ClearAllPoints()
                pf.dpbLayerRow:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, firstY - 68)
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
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
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
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
    if pf.parent and pf.parent.ForceUpdate then pf.parent:ForceUpdate("EM2_UNIT_POPUP_RESETPOS") end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_RESETPOS", key)
    NotifyPositionChanged(key, true)
    if pf and pf:IsShown() then Sync() end
end

local function CopyBoundsTo(targetKey)
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
    dst.offsetX = San(src.offsetX, 0)
    dst.offsetY = San(src.offsetY, 0)
    if src.width ~= nil then dst.width = floor(max(40, min(800, tonumber(src.width) or 250)) + 0.5) end
    if src.height ~= nil then dst.height = floor(max(8, min(200, tonumber(src.height) or 40)) + 0.5) end
    local applied = false
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then
        _G.MSUF_ApplyUnitFrameKey_Immediate(targetKey)
        applied = true
    elseif ApplySettingsForKeySafe(targetKey) then
        applied = true
    end
    ApplyPowerLayoutForUnitKey(targetKey, dst.powerBarDetached == true and CanDetachPower(targetKey))
    if not applied and not ApplyAllSettingsSafe() and type(_G.MSUF_UpdateAllFrames)=="function" then _G.MSUF_UpdateAllFrames() end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_COPY_BOUNDS", targetKey)
    if EM2.Focus and EM2.Focus.Pulse then EM2.Focus.Pulse(targetKey, "frame", nil, { source = "unit-copy", duration = 0.32 }) end
    SetHUDStatus("Copied frame bounds", "ok")
    Sync()
end

local function Build()
    if pf then return pf end
    RefreshPalette()
    local toggleOpts = {
        palette = C,
        sync = function() if pf and pf:IsShown() then Sync() end end,
    }

    pf = Quick.CreateShell("MSUF_EM2_UnitPopup", {
        height = 336,
        title = "Frame",
        subtitle = "Frame bounds",
        hoverSource = "unit-popup",
        blocker = BlockConfigCombatLocked,
    })

    local function WirePopupFocus(btn, component, slot)
        return U.WirePopupFocus and U.WirePopupFocus(btn, function() return pf and pf.unit and CK(pf.unit) end, component, "unit-popup", slot) or btn
    end

    local function CopyMenuEntries()
        local entries = { { key = "__all__", label = "All units", highlight = true } }
        for _, target in ipairs(UNIT_COPY_TARGETS) do entries[#entries + 1] = target end
        return entries
    end

    local function CopyMenuSelect(entry)
        if entry.key == "__all__" then
            local srcKey = pf and pf.unit and CK(pf.unit)
            for _, target in ipairs(UNIT_COPY_TARGETS) do
                if target.key ~= srcKey then CopyBoundsTo(target.key) end
            end
        else
            CopyBoundsTo(entry.key)
        end
    end

    Quick.ValuePairAt(pf, pf, 20, -72, "X", "xBox", Apply, "Y", "yBox", Apply)
    Quick.ValuePairAt(pf, pf, 20, -102, "Width", "wBox", Apply, "Height", "hBox", Apply)

    WirePopupFocus(Quick.ButtonAt(pf, "Name", 20, -140, 58, 30, function() OpenMenu2Page(nil, "name") end), "name")
    WirePopupFocus(Quick.ButtonAt(pf, "HP", 90, -140, 58, 30, function() OpenMenu2Page(nil, "hp") end), "hp")
    WirePopupFocus(Quick.ButtonAt(pf, "Power", 160, -140, 72, 30, function() OpenMenu2Page(nil, "power") end), "power")
    WirePopupFocus(Quick.ButtonAt(pf, "Auras", 244, -140, 68, 30, function() OpenMenu2Page(nil, "auras") end), "auras")
    WirePopupFocus(Quick.ButtonAt(pf, "Cast", 324, -140, 58, 30, function() OpenMenu2Page(nil, "castbar") end), "castbar")

    Quick.ButtonAt(pf, "Open settings", 20, -190, 190, 30, OpenMenu2Settings)
    Quick.MenuButtonAt(pf, "Copy to", 224, -190, 190, 30, CopyMenuEntries, CopyMenuSelect, { palette = C })
    pf.detachBtn = Quick.ToggleAt(pf, "Detach powerbar", 20, -238, 394, 30, ApplyDetachPower, toggleOpts)

    pf.dpbPanel = CreateFrame("Frame", nil, pf, "BackdropTemplate")
    pf.dpbPanel:SetPoint("TOPLEFT", pf, "TOPLEFT", 20, -282)
    pf.dpbPanel:SetSize(394, 220)
    pf.dpbPanel:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1, insets={left=1,right=1,top=1,bottom=1} })
    pf.dpbPanel:SetBackdropColor(C.cardBg[1], C.cardBg[2], C.cardBg[3], 0.58)
    pf.dpbPanel:SetBackdropBorderColor(C.cardEdge[1], C.cardEdge[2], C.cardEdge[3], 0.72)
    Menu2Style.Card(pf.dpbPanel)
    local dpbTitle = FS(pf.dpbPanel, 12, C.white)
    dpbTitle:SetPoint("TOPLEFT", pf.dpbPanel, "TOPLEFT", 16, -12)
    dpbTitle:SetText(Tr("Detached power bar"))
    local dpbHint = FS(pf.dpbPanel, 10, C.muted)
    dpbHint:SetPoint("LEFT", dpbTitle, "RIGHT", 10, 0)
    dpbHint:SetText(Tr("position, size, and layer"))
    pf.dpbTextBtn = Quick.ToggleAt(pf.dpbPanel, "Text on bar", 16, -36, 112, 30, Apply, toggleOpts)
    pf.dpbSyncBtn = Quick.ToggleAt(pf.dpbPanel, "Sync class", 140, -36, 112, 30, Apply, toggleOpts)
    pf.dpbAnchorBtn = Quick.ToggleAt(pf.dpbPanel, "Anchor class", 264, -36, 114, 30, Apply, toggleOpts)
    pf.dpbXYRow = Quick.ValuePairAt(pf, pf.dpbPanel, 16, -92, "X", "dpbXBox", Apply, "Y", "dpbYBox", Apply)
    pf.dpbWHRow = Quick.ValuePairAt(pf, pf.dpbPanel, 16, -126, "Width", "dpbWBox", Apply, "Height", "dpbHBox", Apply)
    pf.dpbLayerRow = Quick.SingleValueAt(pf, pf.dpbPanel, 16, -160, "Layer", "dpbLevelBox", Apply)
    pf.dpbPanel:Hide()

    if Quick.AddFooterControls then
        Quick.AddFooterControls(pf, { anchor = "BOTTOM", bottomGap = 12, onResetPosition = ResetPosition })
    end

    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(pf) end
    return pf
end

local UnitPopup = {}; EM2.UnitPopup = UnitPopup
function UnitPopup.Open(u, parent) if BlockConfigCombatLocked() then return false end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show(); if Menu2Style.FadeIn then Menu2Style.FadeIn(pf, 0.12, 0.86, 1) end; return true end
function UnitPopup.Close() if pf then pf:Hide() end end
function UnitPopup.IsOpen() return pf and pf:IsShown() or false end
function UnitPopup.Sync() if pf and pf:IsShown() then Sync() end end
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
