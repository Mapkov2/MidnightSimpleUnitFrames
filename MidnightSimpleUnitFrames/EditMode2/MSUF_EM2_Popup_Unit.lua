-- ============================================================================
-- MSUF_EM2_Popup_Unit.lua — v5
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local function DB() return _G.MSUF_DB end
local function Conf(k) local db=DB(); return db and db[k] end
local function CK(u) if not u then return nil end; if u=="targettarget" or u=="tot" then return "targettarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(u) then return "boss" end; return u end
local LABELS = { player="Player", target="Target", focus="Focus", targettarget="ToT", pet="Pet", boss="Boss" }
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local pf

local function Apply()
    if InCombatLockdown and InCombatLockdown() then return end
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("unit", key) end
    conf.offsetX=San(pf.xBox and tonumber(pf.xBox:GetText()),0); conf.offsetY=San(pf.yBox and tonumber(pf.yBox:GetText()),0)
    local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then conf.width=floor(max(40,min(800,w))+0.5) end
    local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then conf.height=floor(max(8,min(200,h))+0.5) end
    if pf.nameShowCB then conf.showName=pf.nameShowCB:GetChecked() and true or false end
    conf.nameOffsetX=San(pf.nameXBox and tonumber(pf.nameXBox:GetText()),0); conf.nameOffsetY=San(pf.nameYBox and tonumber(pf.nameYBox:GetText()),0)
    if pf._msufNameAnchorVal then conf.nameTextAnchor=pf._msufNameAnchorVal end
    if pf.nameSizeBox then local sz=tonumber(pf.nameSizeBox:GetText()); if sz then conf.nameFontSize=floor(max(6,min(48,sz))+0.5) end end
    if pf.hpShowCB then conf.showHP=pf.hpShowCB:GetChecked() and true or false end
    conf.hpOffsetX=San(pf.hpXBox and tonumber(pf.hpXBox:GetText()),0); conf.hpOffsetY=San(pf.hpYBox and tonumber(pf.hpYBox:GetText()),0)
    if pf._msufHPAnchorVal then conf.hpTextAnchor=pf._msufHPAnchorVal end
    if pf.hpSizeBox then local sz=tonumber(pf.hpSizeBox:GetText()); if sz then conf.hpFontSize=floor(max(6,min(48,sz))+0.5) end end
    if pf.powerShowCB then conf.showPower=pf.powerShowCB:GetChecked() and true or false end
    conf.powerOffsetX=San(pf.powerXBox and tonumber(pf.powerXBox:GetText()),0); conf.powerOffsetY=San(pf.powerYBox and tonumber(pf.powerYBox:GetText()),0)
    if pf._msufPowerAnchorVal then conf.powerTextAnchor=pf._msufPowerAnchorVal end
    if pf.powerSizeBox then local sz=tonumber(pf.powerSizeBox:GetText()); if sz then conf.powerFontSize=floor(max(6,min(48,sz))+0.5) end end
    if pf.detachCB and (pf.unit=="player" or pf.unit=="target" or pf.unit=="focus") then
        conf.powerBarDetached=pf.detachCB:GetChecked() and true or false
        if conf.powerBarDetached then
            local dw=pf.dpbWBox and tonumber(pf.dpbWBox:GetText()); if dw then conf.detachedPowerBarWidth=floor(max(20,min(800,dw))+0.5) end
            local dh=pf.dpbHBox and tonumber(pf.dpbHBox:GetText()); if dh then conf.detachedPowerBarHeight=floor(max(2,min(80,dh))+0.5) end
            local dx=pf.dpbXBox and tonumber(pf.dpbXBox:GetText()); if dx then conf.detachedPowerBarOffsetX=floor(dx+0.5) end
            local dy=pf.dpbYBox and tonumber(pf.dpbYBox:GetText()); if dy then conf.detachedPowerBarOffsetY=floor(dy+0.5) end
            if pf.syncCPCB and pf.unit=="player" then conf.detachedPowerBarSyncClassPower=pf.syncCPCB:GetChecked() and true or false end
            if pf.anchorCPCB and pf.unit=="player" then conf.detachedPowerBarAnchorToClassPower=pf.anchorCPCB:GetChecked() and true or false end
            if pf.textOnBarCB then conf.detachedPowerBarTextOnBar=pf.textOnBarCB:GetChecked() and true or false end
        end
    end
    if type(_G.MSUF_UpdateAllFonts)=="function" then _G.MSUF_UpdateAllFonts() end
    -- Direct SetSize: MarkDirty/UpdateSimpleUnitFrame only handles health/power/text,
    -- not frame dimensions. Apply width/height immediately.
    if pf.parent and conf.width and conf.height then
        pf.parent:SetSize(conf.width, conf.height)
    end
    local md=_G.MSUF_UFCore_MarkDirty; if type(md)=="function" and pf.parent then md(pf.parent, nil, true, "EM2:UnitPopup")
    elseif type(_G.UpdateSimpleUnitFrame)=="function" and pf.parent then _G.UpdateSimpleUnitFrame(pf.parent) end
    -- Full layout re-apply (power bar embed, text anchors, borders, etc.)
    if type(_G.MSUF_ApplyUnitFrameKey_Immediate)=="function" then _G.MSUF_ApplyUnitFrameKey_Immediate(key) end
    if type(_G.MSUF_ForceTextLayoutForUnitKey)=="function" then _G.MSUF_ForceTextLayoutForUnitKey(key) end
    -- Clear PBEmbedLayout stamp so width/height changes are re-applied
    if pf.parent then
        local cs=_G.MSUF_NS and _G.MSUF_NS.Cache; if cs and cs.ClearStamp then cs.ClearStamp(pf.parent, "PBEmbedLayout") end
    end
    if type(_G.MSUF_ApplyPowerBarEmbedLayout)=="function" and pf.parent then _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent) end
    if pf._refreshVisibility then pf._refreshVisibility() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function Sync()
    if not pf or not pf.unit then return end
    local key=CK(pf.unit); local conf=key and Conf(key); if not conf then return end
    local function S(b,v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
    local function SC(c,v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
    if pf._titleFS then pf._titleFS:SetText(LABELS[key] or key or "") end
    S(pf.xBox,San(conf.offsetX,0)); S(pf.yBox,San(conf.offsetY,0))
    S(pf.wBox,conf.width or (pf.parent and pf.parent:GetWidth()) or 250)
    S(pf.hBox,conf.height or (pf.parent and pf.parent:GetHeight()) or 40)
    SC(pf.nameShowCB, conf.showName~=false)
    S(pf.nameXBox,conf.nameOffsetX or 0); S(pf.nameYBox,conf.nameOffsetY or 0)
    local db=DB(); local g=db and db.general or {}
    S(pf.nameSizeBox,conf.nameFontSize or g.nameFontSize or g.fontSize or 14)
    pf._msufNameAnchorVal=conf.nameTextAnchor or "LEFT"
    if pf.nameAnchorDrop then pf.nameAnchorDrop:SetValue(pf._msufNameAnchorVal) end
    SC(pf.hpShowCB, conf.showHP~=false)
    S(pf.hpXBox,conf.hpOffsetX or 0); S(pf.hpYBox,conf.hpOffsetY or 0)
    S(pf.hpSizeBox,conf.hpFontSize or g.hpFontSize or g.fontSize or 14)
    pf._msufHPAnchorVal=conf.hpTextAnchor or "RIGHT"
    if pf.hpAnchorDrop then pf.hpAnchorDrop:SetValue(pf._msufHPAnchorVal) end
    SC(pf.powerShowCB, conf.showPower~=false)
    S(pf.powerXBox,conf.powerOffsetX or 0); S(pf.powerYBox,conf.powerOffsetY or 0)
    S(pf.powerSizeBox,conf.powerFontSize or g.powerFontSize or g.fontSize or 14)
    pf._msufPowerAnchorVal=conf.powerTextAnchor or "RIGHT"
    if pf.powerAnchorDrop then pf.powerAnchorDrop:SetValue(pf._msufPowerAnchorVal) end
    SC(pf.detachCB,conf.powerBarDetached); SC(pf.syncCPCB,conf.detachedPowerBarSyncClassPower)
    SC(pf.anchorCPCB,conf.detachedPowerBarAnchorToClassPower); SC(pf.textOnBarCB,conf.detachedPowerBarTextOnBar)
    S(pf.dpbWBox,conf.detachedPowerBarWidth or 150); S(pf.dpbHBox,conf.detachedPowerBarHeight or 6)
    S(pf.dpbXBox,conf.detachedPowerBarOffsetX or 0); S(pf.dpbYBox,conf.detachedPowerBarOffsetY or 0)
    pf.MSUF_prev = {}; for k,v in pairs(conf) do if type(v)~="table" then pf.MSUF_prev[k]=v end end; pf.MSUF_prev.key=key
    -- Refresh dependent gray-out state
    if pf.nameShowCB and pf.nameShowCB.UpdateDependents then pf.nameShowCB:UpdateDependents() end
    if pf.hpShowCB and pf.hpShowCB.UpdateDependents then pf.hpShowCB:UpdateDependents() end
    if pf.powerShowCB and pf.powerShowCB.UpdateDependents then pf.powerShowCB:UpdateDependents() end
    if pf._refreshVisibility then pf._refreshVisibility() end
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_UnitPopup", 380, 540, "Player")
    local ANCH = { {"LEFT","Left"}, {"RIGHT","Right"}, {"CENTER","Center"} }
    local top = pf._contentTop

    -- Frame
    local fC, fB = F.Card(pf, top, "Position & Size", -2, true)
    local fXY = F.PairRow(pf, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    local fWH = F.PairRow(pf, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox", anchorTo=fXY, onChanged=Apply })
    fC:RecalcHeight()

    -- Name
    local nC, nB = F.Card(pf, fC, "Name", -6, true)
    local nShow = F.CheckRow(pf, nB, nC, { label="Show Name", cbKey="nameShowCB", onChanged=function() Apply() end })
    local nXY = F.PairRow(pf, nB, nC, { label1="X:", label2="Y:", key1="nameXBox", key2="nameYBox", anchorTo=nShow, onChanged=Apply })
    local nSA = F.SizeAnchorRow(pf, nB, nC, { sizeKey="nameSizeBox", anchorKey="nameAnchorDrop", stateKey="_msufNameAnchorVal", options=ANCH, anchorTo=nXY, onChanged=Apply })
    nC:RecalcHeight()
    pf.nameShowCB:SetDependentRows(nXY, nSA)

    -- HP
    local hC, hB = F.Card(pf, nC, "HP", -6, true)
    local hShow = F.CheckRow(pf, hB, hC, { label="Show HP", cbKey="hpShowCB", onChanged=function() Apply() end })
    local hXY = F.PairRow(pf, hB, hC, { label1="X:", label2="Y:", key1="hpXBox", key2="hpYBox", anchorTo=hShow, onChanged=Apply })
    local hSA = F.SizeAnchorRow(pf, hB, hC, { sizeKey="hpSizeBox", anchorKey="hpAnchorDrop", stateKey="_msufHPAnchorVal", options=ANCH, anchorTo=hXY, onChanged=Apply })
    hC:RecalcHeight()
    pf.hpShowCB:SetDependentRows(hXY, hSA)

    -- Power
    local pC, pB = F.Card(pf, hC, "Power", -6, true)
    local pShow = F.CheckRow(pf, pB, pC, { label="Show Power", cbKey="powerShowCB", onChanged=function() Apply() end })
    local pXY = F.PairRow(pf, pB, pC, { label1="X:", label2="Y:", key1="powerXBox", key2="powerYBox", anchorTo=pShow, onChanged=Apply })
    local pSA = F.SizeAnchorRow(pf, pB, pC, { sizeKey="powerSizeBox", anchorKey="powerAnchorDrop", stateKey="_msufPowerAnchorVal", options=ANCH, anchorTo=pXY, onChanged=Apply })
    pC:RecalcHeight()
    pf.powerShowCB:SetDependentRows(pXY, pSA)

    -- Detach
    local dC, dB = F.Card(pf, pC, "Detached Power Bar", -6, false)
    pf._dpbCard = dC
    local dToggle = F.CheckRow(pf, dB, dC, { label="Detach from frame", cbKey="detachCB", onChanged=function() Apply() end })
    local dSync = F.CheckRow(pf, dB, dC, { label="Sync width to Resource Bar", cbKey="syncCPCB", anchorTo=dToggle, onChanged=function() Apply() end })
    local dAnch = F.CheckRow(pf, dB, dC, { label="Anchor to Resource Bar", cbKey="anchorCPCB", anchorTo=dSync, onChanged=function() Apply() end })
    local dText = F.CheckRow(pf, dB, dC, { label="Power text on bar", cbKey="textOnBarCB", anchorTo=dAnch, onChanged=function() Apply() end })
    local dWH = F.PairRow(pf, dB, dC, { label1="W:", label2="H:", key1="dpbWBox", key2="dpbHBox", anchorTo=dText, onChanged=Apply })
    local dXY = F.PairRow(pf, dB, dC, { label1="X:", label2="Y:", key1="dpbXBox", key2="dpbYBox", anchorTo=dWH, onChanged=Apply })
    dC:RecalcHeight()

    pf._allCards = { fC, nC, hC, pC, dC }

    -- Copy Settings dropdown
    local UNIT_SOURCES = {
        { key = "player", label = "Player" },
        { key = "target", label = "Target" },
        { key = "focus",  label = "Focus"  },
        { key = "targettarget", label = "ToT" },
        { key = "pet",    label = "Pet"    },
        { key = "boss",   label = "Boss"   },
    }
    local SKIP_COPY = { offsetX=true, offsetY=true }
    local copyRow = F.CopyDropdown(pf, pf._scrollChild, nil, {
        anchorTo = dC,
        sources = UNIT_SOURCES,
        onCopy = function(targetKey)
            local db = _G.MSUF_DB; if not db then return end
            local srcKey = pf.unit; if not srcKey then return end
            local src = db[srcKey]; if not src then return end
            if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("unit", targetKey) end
            local dst = db[targetKey]; if not dst then db[targetKey] = {}; dst = db[targetKey] end
            -- Copy all keys FROM current unit TO selected target (except position)
            for k, v in pairs(src) do
                if not SKIP_COPY[k] then
                    if type(v) == "table" then
                        dst[k] = _G.MSUF_DeepCopy and _G.MSUF_DeepCopy(v) or v
                    else
                        dst[k] = v
                    end
                end
            end
            -- Apply + resync
            if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
            if type(_G.MSUF_UpdateAllFonts) == "function" then _G.MSUF_UpdateAllFonts() end
            C_Timer.After(0.1, function() Sync() end)
        end,
    })

    -- Visibility refresh
    pf._refreshVisibility = function()
        local u = pf.unit
        local canDetach = (u == "player" or u == "target" or u == "focus")
        local isPlayer = (u == "player")
        dC:SetShown(canDetach)
        -- Sync/Anchor to Resource Bar: only meaningful for player
        if pf.syncCPCB then pf.syncCPCB:SetShown(isPlayer) end
        if pf.anchorCPCB then pf.anchorCPCB:SetShown(isPlayer) end
        -- Recalc scroll
        C_Timer.After(0, function()
            local t = pf._scrollChild and pf._scrollChild:GetTop()
            local last = copyRow or (canDetach and dC or pC)
            local b = last and last.GetBottom and last:GetBottom()
            if t and b then pf:UpdateScrollHeight(t - b + 30) else pf:UpdateScrollHeight(640) end
        end)
    end

    pf._recalcScroll = pf._refreshVisibility

    local ok, cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function()
        if pf.MSUF_prev and pf.MSUF_prev.key then
            local conf=Conf(pf.MSUF_prev.key)
            if conf then for k,v in pairs(pf.MSUF_prev) do if k~="key" then conf[k]=v end end
                if type(ApplyAllSettings)=="function" then ApplyAllSettings() end
                if type(_G.MSUF_UpdateAllFonts)=="function" then _G.MSUF_UpdateAllFonts() end end
        end; pf:Hide()
    end)
    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); cancel:Click() else s:SetPropagateKeyboardInput(true) end end)
    pf:UpdateScrollHeight(600)
    return pf
end

local UnitPopup = {}; EM2.UnitPopup = UnitPopup
function UnitPopup.Open(u, parent) if InCombatLockdown and InCombatLockdown() then return end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show() end
function UnitPopup.Close() if pf then pf:Hide() end end
function UnitPopup.IsOpen() return pf and pf:IsShown() or false end
function UnitPopup.Sync() if pf and pf:IsShown() then Sync() end end
