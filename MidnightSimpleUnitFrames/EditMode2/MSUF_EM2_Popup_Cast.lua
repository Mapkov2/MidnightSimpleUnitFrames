local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local function G() local db=_G.MSUF_DB; return db and db.general or {} end
local function EG() local db=_G.MSUF_DB; if db then db.general=db.general or {} end; return db and db.general end
local function GP(u) local fn=_G.MSUF_GetCastbarPrefix; return type(fn)=="function" and fn(u) or nil end
local function GD(u) local fn=_G.MSUF_GetCastbarDefaultOffsets; if type(fn)=="function" then return fn(u) end; return 0,0 end
local function GST(u) local fn=_G.MSUF_GetCastbarShowTimeKey; return type(fn)=="function" and fn(u) or nil end
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local pf
local TF = { player="MSUF_SetPlayerCastbarTestMode", target="MSUF_SetTargetCastbarTestMode", focus="MSUF_SetFocusCastbarTestMode", boss="MSUF_SetBossCastbarTestMode" }
local function SetTest(u,on) for k,fn in pairs(TF) do local f=_G[fn]; if type(f)=="function" then f(k==u and on, true) end end end

local function Apply()
    if InCombatLockdown and InCombatLockdown() then return end
    if not pf or not pf.unit then return end; local g=EG(); if not g then return end; local u=pf.unit
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("castbar", u) end
    if u=="boss" then
        g.bossCastbarOffsetX=San(pf.xBox and tonumber(pf.xBox:GetText()),0); g.bossCastbarOffsetY=San(pf.yBox and tonumber(pf.yBox:GetText()),0)
        local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then g.bossCastbarWidth=floor(max(50,min(600,w))+0.5) end
        local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then g.bossCastbarHeight=floor(max(8,min(100,h))+0.5) end
        if pf.spellShowCB then g.showBossCastName=pf.spellShowCB:GetChecked() and true or false end
        if pf.iconShowCB then g.showBossCastIcon=pf.iconShowCB:GetChecked() and true or false end
        if pf.timeShowCB then g.showBossCastTime=pf.timeShowCB:GetChecked() and true or false end
        g.bossCastTextOffsetX=San(pf.spellXBox and tonumber(pf.spellXBox:GetText()),0); g.bossCastTextOffsetY=San(pf.spellYBox and tonumber(pf.spellYBox:GetText()),0)
        if pf.spellSizeBox then local sz=tonumber(pf.spellSizeBox:GetText()); if sz then g.bossCastSpellNameFontSize=floor(max(6,min(72,sz))+0.5) end end
        if pf.iconSizeBox then local sz=tonumber(pf.iconSizeBox:GetText()); if sz then g.bossCastIconSize=floor(max(6,min(128,sz))+0.5) end end
        if pf.timeSizeBox then local sz=tonumber(pf.timeSizeBox:GetText()); if sz then g.bossCastTimeFontSize=floor(max(6,min(72,sz))+0.5) end end
        if type(_G.MSUF_UpdateBossCastbarPreview)=="function" then _G.MSUF_UpdateBossCastbarPreview() end
    else
        local pre=GP(u); if not pre then return end; local dx,dy=GD(u)
        g[pre.."OffsetX"]=San(pf.xBox and tonumber(pf.xBox:GetText()),dx); g[pre.."OffsetY"]=San(pf.yBox and tonumber(pf.yBox:GetText()),dy)
        local w=pf.wBox and tonumber(pf.wBox:GetText()); if w then g[pre.."BarWidth"]=floor(max(50,min(600,w))+0.5) end
        local h=pf.hBox and tonumber(pf.hBox:GetText()); if h then g[pre.."BarHeight"]=floor(max(8,min(100,h))+0.5) end
        if pf.spellShowCB then g[pre.."ShowSpellName"]=pf.spellShowCB:GetChecked() and true or false end
        if pf.iconShowCB then g[pre.."ShowIcon"]=pf.iconShowCB:GetChecked() and true or false end
        local stk=GST(u); if stk and pf.timeShowCB then g[stk]=pf.timeShowCB:GetChecked() and true or false end
        g[pre.."TextOffsetX"]=San(pf.spellXBox and tonumber(pf.spellXBox:GetText()),0); g[pre.."TextOffsetY"]=San(pf.spellYBox and tonumber(pf.spellYBox:GetText()),0)
        if pf.spellSizeBox then local sz=tonumber(pf.spellSizeBox:GetText()); if sz then g[pre.."SpellNameFontSize"]=floor(max(6,min(48,sz))+0.5) end end
        if pf.iconSizeBox then local sz=tonumber(pf.iconSizeBox:GetText()); if sz then g[pre.."IconSize"]=floor(max(6,min(128,sz))+0.5) end end
        if pf.timeSizeBox then local sz=tonumber(pf.timeSizeBox:GetText()); if sz then g[pre.."TimeFontSize"]=floor(max(6,min(48,sz))+0.5) end end
        local ra=(u=="player" and "MSUF_ReanchorPlayerCastBar") or (u=="target" and "MSUF_ReanchorTargetCastBar") or (u=="focus" and "MSUF_ReanchorFocusCastBar")
        if type(_G[ra])=="function" then _G[ra]() end
    end
    if type(_G.MSUF_UpdateCastbarVisuals)=="function" then _G.MSUF_UpdateCastbarVisuals() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local BOSS_KEYS = {
    "bossCastbarOffsetX","bossCastbarOffsetY","bossCastbarWidth","bossCastbarHeight",
    "showBossCastName","showBossCastIcon","showBossCastTime",
    "bossCastTextOffsetX","bossCastTextOffsetY",
    "bossCastSpellNameFontSize","bossCastIconSize","bossCastTimeFontSize",
    "bossCastbarDetached",
}
local function SnapshotCast(u)
    local g=G(); if not g then return nil end; local snap={}
    if u=="boss" then
        for _,k in ipairs(BOSS_KEYS) do snap[k]=g[k] end
    else
        local pre=GP(u); if not pre then return nil end
        local stk=GST(u)
        local suffixes={"OffsetX","OffsetY","BarWidth","BarHeight","ShowSpellName","ShowIcon",
            "TextOffsetX","TextOffsetY","SpellNameFontSize","IconSize","TimeFontSize","Detached"}
        for _,s in ipairs(suffixes) do snap[pre..s]=g[pre..s] end
        if stk then snap[stk]=g[stk] end
    end
    return snap
end
local function RestoreCast(snap)
    if not snap then return end; local g=EG(); if not g then return end
    for k,v in pairs(snap) do g[k]=v end
end

local function Sync()
    if not pf or not pf.unit then return end; local g=G(); local u=pf.unit
    pf._castSnap = SnapshotCast(u)
    local function S(b,v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
    local function SC(c,v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
    local lbl=(u=="player" and "Player") or (u=="target" and "Target") or (u=="focus" and "Focus") or (u=="boss" and "Boss") or u
    if pf._titleFS then pf._titleFS:SetText(lbl.." Castbar") end
    if u=="boss" then
        S(pf.xBox,g.bossCastbarOffsetX or 0); S(pf.yBox,g.bossCastbarOffsetY or 0)
        S(pf.wBox,g.bossCastbarWidth or 176); S(pf.hBox,g.bossCastbarHeight or 12)
        SC(pf.spellShowCB,g.showBossCastName~=false); SC(pf.iconShowCB,g.showBossCastIcon~=false); SC(pf.timeShowCB,g.showBossCastTime~=false)
        S(pf.spellXBox,g.bossCastTextOffsetX or 0); S(pf.spellYBox,g.bossCastTextOffsetY or 0)
        S(pf.spellSizeBox,g.bossCastSpellNameFontSize or g.fontSize or 14)
        S(pf.iconSizeBox,g.bossCastIconSize or g.bossCastbarHeight or 18)
        S(pf.timeSizeBox,g.bossCastTimeFontSize or g.fontSize or 14)
    else
        local pre=GP(u); if not pre then return end; local dx,dy=GD(u)
        S(pf.xBox,g[pre.."OffsetX"] or dx); S(pf.yBox,g[pre.."OffsetY"] or dy)
        S(pf.wBox,g[pre.."BarWidth"] or g.castbarGlobalWidth or 271); S(pf.hBox,g[pre.."BarHeight"] or g.castbarGlobalHeight or 18)
        SC(pf.spellShowCB,g[pre.."ShowSpellName"]~=false); SC(pf.iconShowCB,g[pre.."ShowIcon"]~=false)
        local stk=GST(u); SC(pf.timeShowCB,stk and g[stk]~=false)
        S(pf.spellXBox,g[pre.."TextOffsetX"] or 0); S(pf.spellYBox,g[pre.."TextOffsetY"] or 0)
        S(pf.spellSizeBox,g[pre.."SpellNameFontSize"] or g.fontSize or 14)
        S(pf.iconSizeBox,g[pre.."IconSize"] or g[pre.."BarHeight"] or 18)
        S(pf.timeSizeBox,g[pre.."TimeFontSize"] or g.fontSize or 14)
    end
    -- Anchor to unitframe checkbox
    if pf.anchorToUnitCB then
        local detachedKey
        if u == "boss" then
            detachedKey = "bossCastbarDetached"
        else
            local pre2 = GP(u)
            if pre2 then detachedKey = pre2 .. "Detached" end
        end
        local isDetached = detachedKey and g[detachedKey] == true
        SC(pf.anchorToUnitCB, not isDetached)
    end
    -- Refresh dependent gray-out state
    if pf.spellShowCB and pf.spellShowCB.UpdateDependents then pf.spellShowCB:UpdateDependents() end
    if pf.iconShowCB and pf.iconShowCB.UpdateDependents then pf.iconShowCB:UpdateDependents() end
    if pf.timeShowCB and pf.timeShowCB.UpdateDependents then pf.timeShowCB:UpdateDependents() end
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_CastPopup", 380, 460, "Castbar")
    local top=pf._contentTop

    local fC,fB = F.Card(pf, top, "Position & Size", -2, true)
    local fXY = F.PairRow(pf, fB, fC, { label1="X:", label2="Y:", key1="xBox", key2="yBox", onChanged=Apply })
    local fWH = F.PairRow(pf, fB, fC, { label1="W:", label2="H:", key1="wBox", key2="hBox", anchorTo=fXY, onChanged=Apply })
    fC:RecalcHeight()

    local sC,sB = F.Card(pf, fC, "Spell Name", -6, true)
    local sSh = F.CheckRow(pf, sB, sC, { label="Show", cbKey="spellShowCB", onChanged=function() Apply() end })
    local sXY = F.PairRow(pf, sB, sC, { label1="X:", label2="Y:", key1="spellXBox", key2="spellYBox", anchorTo=sSh, onChanged=Apply })
    local sSz = F.SingleRow(pf, sB, sC, { label="Size:", boxKey="spellSizeBox", anchorTo=sXY, onChanged=Apply })
    sC:RecalcHeight()
    pf.spellShowCB:SetDependentRows(sXY, sSz)

    local iC,iB = F.Card(pf, sC, "Icon", -6, true)
    local iSh = F.CheckRow(pf, iB, iC, { label="Show", cbKey="iconShowCB", onChanged=function() Apply() end })
    local iSz = F.SingleRow(pf, iB, iC, { label="Size:", boxKey="iconSizeBox", anchorTo=iSh, onChanged=Apply })
    iC:RecalcHeight()
    pf.iconShowCB:SetDependentRows(iSz)

    local tC,tB = F.Card(pf, iC, "Duration", -6, true)
    local tSh = F.CheckRow(pf, tB, tC, { label="Show", cbKey="timeShowCB", onChanged=function() Apply() end })
    local tSz = F.SingleRow(pf, tB, tC, { label="Size:", boxKey="timeSizeBox", anchorTo=tSh, onChanged=Apply })
    tC:RecalcHeight()
    pf.timeShowCB:SetDependentRows(tSz)

    -- Castbar anchor toggle
    local aC,aB = F.Card(pf, tC, "Anchor", -6, true)
    local aAnch = F.CheckRow(pf, aB, aC, { label="Anchor to unitframe", cbKey="anchorToUnitCB", onChanged=function()
        if not pf or not pf.unit then return end
        local anchored = pf.anchorToUnitCB and pf.anchorToUnitCB:GetChecked() and true or false
        local fn = _G.MSUF_EM_SetCastbarAnchoredToUnit
        if type(fn) == "function" then
            fn(pf.unit, anchored)
        end
        Apply()
    end })
    aC:RecalcHeight()

    pf._recalcScroll = function()
        C_Timer.After(0, function()
            local t=pf._scrollChild and pf._scrollChild:GetTop(); local b=pf._lastCard and pf._lastCard.GetBottom and pf._lastCard:GetBottom()
            if t and b then pf:UpdateScrollHeight(t-b+30) else pf:UpdateScrollHeight(540) end
        end)
    end

    -- Copy castbar settings (all except X/Y position)
    local CAST_SOURCES = {
        { key = "player", label = "Player" },
        { key = "target", label = "Target" },
        { key = "focus",  label = "Focus"  },
        { key = "boss",   label = "Boss"   },
    }
    -- Keys to copy (semantic) → per-unit reader/writer
    local function ReadCastbarSettings(u)
        local g = G(); if not g then return nil end
        local r = {}
        if u == "boss" then
            r.w = g.bossCastbarWidth; r.h = g.bossCastbarHeight
            r.showSpell = g.showBossCastName; r.showIcon = g.showBossCastIcon; r.showTime = g.showBossCastTime
            r.textX = g.bossCastTextOffsetX; r.textY = g.bossCastTextOffsetY
            r.spellSize = g.bossCastSpellNameFontSize; r.iconSize = g.bossCastIconSize; r.timeSize = g.bossCastTimeFontSize
        else
            local pre = GP(u); if not pre then return nil end
            r.w = g[pre.."BarWidth"]; r.h = g[pre.."BarHeight"]
            r.showSpell = g[pre.."ShowSpellName"]; r.showIcon = g[pre.."ShowIcon"]
            local stk = GST(u); r.showTime = stk and g[stk]
            r.textX = g[pre.."TextOffsetX"]; r.textY = g[pre.."TextOffsetY"]
            r.spellSize = g[pre.."SpellNameFontSize"]; r.iconSize = g[pre.."IconSize"]; r.timeSize = g[pre.."TimeFontSize"]
        end
        return r
    end
    local function WriteCastbarSettings(u, r)
        local g = EG(); if not g or not r then return end
        if u == "boss" then
            g.bossCastbarWidth = r.w; g.bossCastbarHeight = r.h
            g.showBossCastName = r.showSpell; g.showBossCastIcon = r.showIcon; g.showBossCastTime = r.showTime
            g.bossCastTextOffsetX = r.textX; g.bossCastTextOffsetY = r.textY
            g.bossCastSpellNameFontSize = r.spellSize; g.bossCastIconSize = r.iconSize; g.bossCastTimeFontSize = r.timeSize
        else
            local pre = GP(u); if not pre then return end
            g[pre.."BarWidth"] = r.w; g[pre.."BarHeight"] = r.h
            g[pre.."ShowSpellName"] = r.showSpell; g[pre.."ShowIcon"] = r.showIcon
            local stk = GST(u); if stk then g[stk] = r.showTime end
            g[pre.."TextOffsetX"] = r.textX; g[pre.."TextOffsetY"] = r.textY
            g[pre.."SpellNameFontSize"] = r.spellSize; g[pre.."IconSize"] = r.iconSize; g[pre.."TimeFontSize"] = r.timeSize
        end
    end

    local copyRow = F.CopyDropdown(pf, pf._scrollChild, nil, {
        anchorTo = aC,
        sources = CAST_SOURCES,
        onCopy = function(targetKey)
            local r = ReadCastbarSettings(pf.unit)
            if not r or not targetKey then return end
            if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("castbar", targetKey) end
            WriteCastbarSettings(targetKey, r)
            if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
            if type(ApplyAllSettings) == "function" then ApplyAllSettings() end
            C_Timer.After(0.1, function() Sync() end)
        end,
    })
    pf._lastCard = copyRow or aC

    local ok,cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function()
        RestoreCast(pf._castSnap)
        if type(_G.MSUF_UpdateCastbarVisuals)=="function" then _G.MSUF_UpdateCastbarVisuals() end
        if type(ApplyAllSettings)=="function" then ApplyAllSettings() end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        pf:Hide()
    end)
    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); cancel:Click() else s:SetPropagateKeyboardInput(true) end end)
    pf:UpdateScrollHeight(500)
    return pf
end

local CastPopup = {}; EM2.CastPopup = CastPopup
function CastPopup.Open(u, parent) if InCombatLockdown and InCombatLockdown() then return end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show(); SetTest(u, true)
    pf:SetScript("OnHide", function()
        if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
    end) end
function CastPopup.Close() if pf then
    if pf.unit and not _G.MSUF_UnitPreviewActive then SetTest(pf.unit, false) end
    pf:Hide() end end
function CastPopup.IsOpen() return pf and pf:IsShown() or false end
function CastPopup.Sync() if pf and pf:IsShown() then Sync() end end
