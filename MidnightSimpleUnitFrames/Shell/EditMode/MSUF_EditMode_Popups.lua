--- EditMode/MSUF_EditMode_Popups.lua - popup router and unit frame popup.
local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

if type(_G.MSUF_InstallEditPopupUI) == "function" then
    _G.MSUF_InstallEditPopupUI(addonName, MSUF)
end

local U = EM2.Util or {}
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe or function() return false end
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
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
        local unit = key
        if key:match("^boss%d") then unit = "boss" end
        local frame = cfg and cfg.getFrame and cfg.getFrame()
        if EM2.UnitPopup then
            EM2.UnitPopup.Open(unit, frame or anchorFrame)
            if EM2.State then EM2.State.SetPopupOpen(true) end
        end
    elseif pType == "castbar" then
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
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
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil
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
local function CK(u) if not u then return nil end; if u=="targettarget" or u=="tot" then return "targettarget" end
    if u=="focustarget" or u=="focus_target" or u=="focustargettarget" then return "focustarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(u) then return "boss" end; return u end
local LABELS = { player="Player", target="Target", focus="Focus", focustarget="Focus Target", targettarget="ToT", pet="Pet", boss="Boss" }
local UNIT_PAGE_KEYS = { player="uf_player", target="uf_target", focus="uf_focus", focustarget="uf_focustarget", targettarget="uf_targettarget", pet="uf_pet", boss="uf_boss" }
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
    if type(_G.MSUF_UpdateAllFonts)=="function" then _G.MSUF_UpdateAllFonts() end
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
    if type(_G.MSUF_ApplyPowerBarEmbedLayout)=="function" and pf.parent then _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent) end
    if pf._refreshVisibility then pf._refreshVisibility() end
    SyncMovers()
    RefreshUFPreview("EM2_UNIT_POPUP_APPLY", key)
    NotifyPositionChanged(key, true)
    if pf and pf:IsShown() then Sync() end
end

function Sync()
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    if pf._titleFS then pf._titleFS:SetText(Tr((LABELS[key] or key or "") .. " - Frame")) end
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
    local pageKey = UNIT_PAGE_KEYS[key] or "uf_player"
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
    pageKey = pageKey or UNIT_PAGE_KEYS[key or CK(pf.unit)] or "uf_player"
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
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey)=="function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey(key, true)
    elseif type(_G.MSUF_ApplyPowerBarEmbedLayout_All)=="function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    elseif type(_G.MSUF_ApplyPowerBarEmbedLayout)=="function" and pf.parent then
        _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent)
    end
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
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(targetKey) end
    if not ApplyAllSettingsSafe() and type(_G.MSUF_UpdateAllFrames)=="function" then _G.MSUF_UpdateAllFrames() end
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

    local function MakeButtonIn(parent, text, x, y, w, onClick)
        local b = Quick.Button(parent, text, w or 66, 30, onClick)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return b
    end

    local function MakeTinyButton(text, x, y, w, onClick)
        return MakeButtonIn(pf, text, x, y, w, onClick)
    end

    local function WirePopupFocus(btn, component, slot)
        return U.WirePopupFocus and U.WirePopupFocus(btn, function() return pf and pf.unit and CK(pf.unit) end, component, "unit-popup", slot) or btn
    end

    local function MakeToggleButtonIn(parent, text, x, y, w, onClick)
        local b = Quick.ToggleButton(parent, text, w, 30, onClick, toggleOpts)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return b
    end

    local function MakeToggleButton(text, x, y, w, onClick)
        return MakeToggleButtonIn(pf, text, x, y, w, onClick)
    end

    local function MakeCopyButton(x, y, w)
        local b = MakeTinyButton("Copy to", x, y, w, nil)
        local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("TOOLTIP")
        menu:SetFrameLevel(960)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetBackdrop({ bgFile=W8, edgeFile=W8, edgeSize=1 })
        menu:SetBackdropColor(C.panelBg[1], C.panelBg[2], C.panelBg[3], 0.98)
        menu:SetBackdropBorderColor(C.panelEdge[1], C.panelEdge[2], C.panelEdge[3], 0.95)
        Menu2Style.Shell(menu)
        menu:Hide()

        --- "All units" first, then each individual target.
        local entries = { { key = "__all__", label = "All units" } }
        for _, t in ipairs(UNIT_COPY_TARGETS) do entries[#entries + 1] = t end

        local itemH = 22
        menu:SetSize(w, #entries * itemH + 6)
        for i, src in ipairs(entries) do
            local item = CreateFrame("Button", nil, menu)
            item:SetSize(w - 4, itemH)
            item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(3 + (i - 1) * itemH))
            local bg = item:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0, 0, 0, 0)
            --- Subtle divider under the "All units" entry.
            if src.key == "__all__" then
                bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.08)
            end
            local fs = FS(item, 10, src.key == "__all__" and C.title or C.white)
            fs:SetPoint("LEFT", 8, 0)
            fs:SetText(Tr(src.label))
            item:SetScript("OnEnter", function()
                bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.22)
            end)
            item:SetScript("OnLeave", function()
                bg:SetColorTexture(src.key == "__all__" and C.btnHover[1] or 0, src.key == "__all__" and C.btnHover[2] or 0, src.key == "__all__" and C.btnHover[3] or 0, src.key == "__all__" and 0.08 or 0)
            end)
            item:SetScript("OnClick", function()
                menu:Hide()
                if src.key == "__all__" then
                    local srcKey = pf and pf.unit and CK(pf.unit)
                    for _, t in ipairs(UNIT_COPY_TARGETS) do
                        if t.key ~= srcKey then CopyBoundsTo(t.key) end
                    end
                else
                    CopyBoundsTo(src.key)
                end
                if b then
                    Menu2Style.SetButtonText(b, src.label)
                    C_Timer.After(1.2, function() Menu2Style.SetButtonText(b, "Copy to") end)
                end
            end)
        end
        b:SetScript("OnClick", function()
            if menu:IsShown() then menu:Hide(); return end
            menu:ClearAllPoints()
            menu:SetPoint("TOP", b, "BOTTOM", 0, -3)
            menu:Show()
        end)
        menu:SetScript("OnUpdate", function(self)
            if not self:IsShown() then return end
            if b:IsMouseOver() or self:IsMouseOver() then
                self._closeTimer = nil
            else
                if not self._closeTimer then self._closeTimer = GetTime() + 0.35
                elseif GetTime() >= self._closeTimer then self:Hide() end
            end
        end)
        pf:HookScript("OnHide", function() menu:Hide() end)
        return b
    end

    local function MakeValuePairIn(parent, x, y, label1, key1, label2, key2)
        return Quick.ValuePair(pf, parent, y, label1, key1, Apply, label2, key2, Apply, { x = x or 0 })
    end

    local function MakeValuePair(y, label1, key1, label2, key2)
        return MakeValuePairIn(pf, 20, y, label1, key1, label2, key2)
    end

    local function MakeSingleValueIn(parent, x, y, label, key)
        return Quick.SingleValue(pf, parent, y, label, key, Apply, { x = x or 0 })
    end

    MakeValuePair(-72, "X", "xBox", "Y", "yBox")
    MakeValuePair(-102, "Width", "wBox", "Height", "hBox")

    WirePopupFocus(MakeTinyButton("Name", 20, -140, 58, function() OpenMenu2Page(nil, "name") end), "name")
    WirePopupFocus(MakeTinyButton("HP", 90, -140, 58, function() OpenMenu2Page(nil, "hp") end), "hp")
    WirePopupFocus(MakeTinyButton("Power", 160, -140, 72, function() OpenMenu2Page(nil, "power") end), "power")
    WirePopupFocus(MakeTinyButton("Auras", 244, -140, 68, function() OpenMenu2Page(nil, "auras") end), "auras")
    WirePopupFocus(MakeTinyButton("Cast", 324, -140, 58, function() OpenMenu2Page(nil, "castbar") end), "castbar")

    MakeTinyButton("Open settings", 20, -190, 190, OpenMenu2Settings)
    MakeCopyButton(224, -190, 190)
    pf.detachBtn = MakeToggleButton("Detach powerbar", 20, -238, 394, ApplyDetachPower)

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
    pf.dpbTextBtn = MakeToggleButtonIn(pf.dpbPanel, "Text on bar", 16, -36, 112, Apply)
    pf.dpbSyncBtn = MakeToggleButtonIn(pf.dpbPanel, "Sync class", 140, -36, 112, Apply)
    pf.dpbAnchorBtn = MakeToggleButtonIn(pf.dpbPanel, "Anchor class", 264, -36, 114, Apply)
    pf.dpbXYRow = MakeValuePairIn(pf.dpbPanel, 16, -92, "X", "dpbXBox", "Y", "dpbYBox")
    pf.dpbWHRow = MakeValuePairIn(pf.dpbPanel, 16, -126, "Width", "dpbWBox", "Height", "dpbHBox")
    pf.dpbLayerRow = MakeSingleValueIn(pf.dpbPanel, 16, -160, "Layer", "dpbLevelBox")
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
