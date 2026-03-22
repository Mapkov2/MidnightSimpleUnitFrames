local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.PopupFactory then return end
local F = EM2.PopupFactory
local floor = math.floor
local max, min = math.max, math.min
local function A2() local db=_G.MSUF_DB; return db and db.auras2 end
local function Sh() local a=A2(); return a and a.shared or {} end
local function Lay(k) local a=A2(); if not a then return {} end; a.perUnit=a.perUnit or {}; a.perUnit[k]=a.perUnit[k] or {}; a.perUnit[k].layout=a.perUnit[k].layout or {}; return a.perUnit[k].layout end
local function San(v,d) v=tonumber(v) or d or 0; if v~=v or v>2000 or v<-2000 then v=d or 0 end; return floor(v+0.5) end
local function IsBoss(u) return type(u)=="string" and u:match("^boss%d+$") end
local pf

local function Apply()
    if InCombatLockdown and InCombatLockdown() then return end
    if not pf or not pf.unit then return end; local a2=A2(); if not a2 then return end
    a2.shared=a2.shared or {}; a2.perUnit=a2.perUnit or {}; local uk=pf.unit
    if type(_G.MSUF_EM_UndoBeforeChange)=="function" then _G.MSUF_EM_UndoBeforeChange("aura", uk) end
    local boss=IsBoss(uk)
    if boss and pf.bossTogetherCB then a2.shared.bossEditTogether=pf.bossTogetherCB:GetChecked() and true or false end
    local keys=(boss and a2.shared.bossEditTogether~=false) and {"boss1","boss2","boss3","boss4","boss5"} or {uk}
    local function R(b,fb) return San(b and tonumber(b:GetText()),fb) end
    local sp=max(0,min(30,R(pf.spacingBox,2)))
    local stSz=max(6,min(40,R(pf.stSzBox,14))); local stX=R(pf.stXBox,0); local stY=R(pf.stYBox,0)
    local cdSz=max(6,min(40,R(pf.cdSzBox,14))); local cdX=R(pf.cdXBox,0); local cdY=R(pf.cdYBox,0)
    local bX=R(pf.bXBox,0); local bY=R(pf.bYBox,0); local bSz=max(10,min(80,R(pf.bSzBox,26)))
    local dX=R(pf.dXBox,0); local dY=R(pf.dYBox,0); local dSz=max(10,min(80,R(pf.dSzBox,26)))
    local prX=R(pf.prXBox,0); local prY=R(pf.prYBox,0); local prSz=max(10,min(80,R(pf.prSzBox,26)))
    if pf.prPreviewCB then a2.shared.highlightPrivateAuras=pf.prPreviewCB:GetChecked() and true or false end
    for _,k in ipairs(keys) do
        a2.perUnit[k]=a2.perUnit[k] or {}; local uc=a2.perUnit[k]; uc.layout=uc.layout or {}; uc.overrideLayout=true; local l=uc.layout
        l.spacing=sp; l.stackTextSize=stSz; l.stackTextOffsetX=stX; l.stackTextOffsetY=stY
        l.cooldownTextSize=cdSz; l.cooldownTextOffsetX=cdX; l.cooldownTextOffsetY=cdY
        l.buffGroupOffsetX=bX; l.buffGroupOffsetY=bY; l.buffGroupIconSize=bSz
        l.debuffGroupOffsetX=dX; l.debuffGroupOffsetY=dY; l.debuffGroupIconSize=dSz
        l.privateOffsetX=prX; l.privateOffsetY=prY; l.privateSize=prSz; l.width=nil; l.height=nil
    end
    if type(_G.MSUF_Auras2_RefreshUnit)=="function" then for _,k in ipairs(keys) do _G.MSUF_Auras2_RefreshUnit(k) end
    elseif type(_G.MSUF_Auras2_RefreshAll)=="function" then _G.MSUF_Auras2_RefreshAll() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local SHARED_SNAP_KEYS = {"bossEditTogether","highlightPrivateAuras"}
local LAYOUT_KEYS = {
    "spacing","stackTextSize","stackTextOffsetX","stackTextOffsetY",
    "cooldownTextSize","cooldownTextOffsetX","cooldownTextOffsetY",
    "buffGroupOffsetX","buffGroupOffsetY","buffGroupIconSize",
    "debuffGroupOffsetX","debuffGroupOffsetY","debuffGroupIconSize",
    "privateOffsetX","privateOffsetY","privateSize",
}
local function SnapshotAura(uk)
    local a2=A2(); if not a2 then return nil end; local snap={shared={},units={}}
    local sh=a2.shared or {}
    for _,k in ipairs(SHARED_SNAP_KEYS) do snap.shared[k]=sh[k] end
    local boss=IsBoss(uk)
    local keys=(boss and sh.bossEditTogether~=false) and {"boss1","boss2","boss3","boss4","boss5"} or {uk}
    for _,k in ipairs(keys) do
        snap.units[k]={}
        local pu=a2.perUnit and a2.perUnit[k]; local l=pu and pu.layout or {}
        for _,lk in ipairs(LAYOUT_KEYS) do snap.units[k][lk]=l[lk] end
        snap.units[k]._overrideLayout=pu and pu.overrideLayout
    end
    return snap
end
local function RestoreAura(snap)
    if not snap then return end; local a2=A2(); if not a2 then return end
    a2.shared=a2.shared or {}
    for k,v in pairs(snap.shared) do a2.shared[k]=v end
    a2.perUnit=a2.perUnit or {}
    for uk,vals in pairs(snap.units) do
        a2.perUnit[uk]=a2.perUnit[uk] or {}; local pu=a2.perUnit[uk]
        pu.overrideLayout=vals._overrideLayout; pu.layout=pu.layout or {}
        for _,lk in ipairs(LAYOUT_KEYS) do pu.layout[lk]=vals[lk] end
    end
end

local function Sync()
    if not pf or not pf.unit then return end; local sh=Sh(); local uk=pf.unit; local ek=uk
    pf._auraSnap = SnapshotAura(uk)
    if IsBoss(uk) and sh.bossEditTogether~=false then ek="boss1" end; local l=Lay(ek)
    local function V(lk,sk,d) return (l[lk]~=nil and l[lk]) or (sh[sk]~=nil and sh[sk]) or d end
    local function S(b,v) if b and b.SetText then b:SetText(tostring(v or 0)) end end
    local function SC(c,v) if c and c.SetChecked then c:SetChecked(v and true or false) end end
    local lbl=uk; if IsBoss(uk) then lbl="Boss "..(uk:match("%d+") or "1") end
    if pf._titleFS then pf._titleFS:SetText(lbl.." Auras") end
    S(pf.spacingBox,V("spacing","spacing",2))
    S(pf.stSzBox,V("stackTextSize","stackTextSize",14)); S(pf.stXBox,V("stackTextOffsetX","stackTextOffsetX",0)); S(pf.stYBox,V("stackTextOffsetY","stackTextOffsetY",0))
    S(pf.cdSzBox,V("cooldownTextSize","cooldownTextSize",14)); S(pf.cdXBox,V("cooldownTextOffsetX","cooldownTextOffsetX",0)); S(pf.cdYBox,V("cooldownTextOffsetY","cooldownTextOffsetY",0))
    S(pf.bXBox,V("buffGroupOffsetX","buffGroupOffsetX",0)); S(pf.bYBox,V("buffGroupOffsetY","buffGroupOffsetY",0)); S(pf.bSzBox,V("buffGroupIconSize","buffGroupIconSize",26))
    S(pf.dXBox,V("debuffGroupOffsetX","debuffGroupOffsetX",0)); S(pf.dYBox,V("debuffGroupOffsetY","debuffGroupOffsetY",0)); S(pf.dSzBox,V("debuffGroupIconSize","debuffGroupIconSize",26))
    S(pf.prXBox,V("privateOffsetX","privateOffsetX",0)); S(pf.prYBox,V("privateOffsetY","privateOffsetY",0)); S(pf.prSzBox,V("privateSize","privateSize",26))
    SC(pf.prPreviewCB,sh.highlightPrivateAuras); SC(pf.bossTogetherCB,sh.bossEditTogether~=false)
    if pf._bossRow then pf._bossRow:SetShown(IsBoss(uk)) end
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_AuraPopup", 380, 520, "Auras")
    local top=pf._contentTop

    local fC,fB = F.Card(pf, top, "Layout", -2, true)
    local fSp = F.SingleRow(pf, fB, fC, { label="Spacing:", boxKey="spacingBox", onChanged=Apply })
    local fBoss = F.CheckRow(pf, fB, fC, { label="Boss 1-5 edit together", cbKey="bossTogetherCB", anchorTo=fSp, onChanged=function() Apply() end })
    pf._bossRow = fBoss; fC:RecalcHeight()

    local tC,tB = F.Card(pf, fC, "Text Overlays", -6, true)
    local tStSz = F.SingleRow(pf, tB, tC, { label="Stack size:", boxKey="stSzBox", onChanged=Apply })
    local tStXY = F.PairRow(pf, tB, tC, { label1="St X:", label2="St Y:", key1="stXBox", key2="stYBox", anchorTo=tStSz, onChanged=Apply })
    local tCdSz = F.SingleRow(pf, tB, tC, { label="CD size:", boxKey="cdSzBox", anchorTo=tStXY, yOff=-8, onChanged=Apply })
    local tCdXY = F.PairRow(pf, tB, tC, { label1="CD X:", label2="CD Y:", key1="cdXBox", key2="cdYBox", anchorTo=tCdSz, onChanged=Apply })
    tC:RecalcHeight()

    local bC,bB = F.Card(pf, tC, "Buffs", -6, true)
    local bXY = F.PairRow(pf, bB, bC, { label1="X:", label2="Y:", key1="bXBox", key2="bYBox", onChanged=Apply })
    local bSz = F.SingleRow(pf, bB, bC, { label="Icon size:", boxKey="bSzBox", anchorTo=bXY, onChanged=Apply })
    bC:RecalcHeight()

    local dC,dB = F.Card(pf, bC, "Debuffs", -6, true)
    local dXY = F.PairRow(pf, dB, dC, { label1="X:", label2="Y:", key1="dXBox", key2="dYBox", onChanged=Apply })
    local dSz = F.SingleRow(pf, dB, dC, { label="Icon size:", boxKey="dSzBox", anchorTo=dXY, onChanged=Apply })
    dC:RecalcHeight()

    local prC,prB = F.Card(pf, dC, "Private Auras", -6, true)
    local prPv = F.CheckRow(pf, prB, prC, { label="Preview (highlight)", cbKey="prPreviewCB", onChanged=function() Apply() end })
    local prXY = F.PairRow(pf, prB, prC, { label1="X:", label2="Y:", key1="prXBox", key2="prYBox", anchorTo=prPv, onChanged=Apply })
    local prSz = F.SingleRow(pf, prB, prC, { label="Icon size:", boxKey="prSzBox", anchorTo=prXY, onChanged=Apply })
    prC:RecalcHeight()

    pf._recalcScroll = function()
        C_Timer.After(0, function()
            local t=pf._scrollChild and pf._scrollChild:GetTop(); local b=prC and prC.GetBottom and prC:GetBottom()
            if t and b then pf:UpdateScrollHeight(t-b+20) else pf:UpdateScrollHeight(700) end
        end)
    end

    local ok,cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function()
        RestoreAura(pf._auraSnap)
        if type(_G.MSUF_Auras2_RefreshAll)=="function" then _G.MSUF_Auras2_RefreshAll() end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        pf:Hide()
    end)
    pf:EnableKeyboard(true)
    pf:SetScript("OnKeyDown", function(s,k) if k=="ESCAPE" then s:SetPropagateKeyboardInput(false); cancel:Click() else s:SetPropagateKeyboardInput(true) end end)
    pf:UpdateScrollHeight(700)
    return pf
end

local AuraPopup = {}; EM2.AuraPopup = AuraPopup
function AuraPopup.Open(u, parent) if InCombatLockdown and InCombatLockdown() then return end; Build(); pf.unit=u; pf.parent=parent; Sync(); pf:Show() end
function AuraPopup.Close() if pf then pf:Hide() end end
function AuraPopup.IsOpen() return pf and pf:IsShown() or false end
function AuraPopup.Sync() if pf and pf:IsShown() then Sync() end end
