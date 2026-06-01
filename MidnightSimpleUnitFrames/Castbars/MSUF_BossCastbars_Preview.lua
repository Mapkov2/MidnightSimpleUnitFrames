local e,e=...local a=tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES)or 5
if a<1 or a>12 then a=5 end
local function s()if type(EnsureDB)=="function"then EnsureDB()end
MSUF_DB=MSUF_DB or{}MSUF_DB.general=MSUF_DB.general or{}return MSUF_DB.general
end
local function b()return _G.MSUF_InCombat==true
or((_G.InCombatLockdown and _G.InCombatLockdown())and true or false)or((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))and true or false)end
local function f()local e=s()if not e.castbarPlayerPreviewEnabled then return false end
if MSUF_DB.boss and MSUF_DB.boss.enabled==false then return false end
local t=_G.MSUF_ShouldUseMSUFCastbar
return type(t)=="function"and t("boss",e)==true or e.enableBossCastbar~=false
end
local function i(t)local e=_G.MSUF_UnitFrames
return(e and e["boss"..t])or _G["MSUF_boss"..t]end
local function u()if _G.MSUF_BossCastbarPreview then _G.MSUF_BossCastbarPreview:Hide()end
for e=2,a do local e=_G["MSUF_BossCastbarPreview"..e];if e then e:Hide()end end
end
local function l(t)local n=t==1 and"MSUF_BossCastbarPreview"or("MSUF_BossCastbarPreview"..t)local e=_G[n]if e then return e end
local s=s()local e,a=240,18
if type(_G.MSUF_GetCastbarDesiredSize)=="function"then e,a=_G.MSUF_GetCastbarDesiredSize("boss"..t,s,nil,e,a)else e,a=tonumber(s.bossCastbarWidth)or e,tonumber(s.bossCastbarHeight)or a end
local s=_G.MSUF_CreateCastbarPreviewFrame
if type(s)~="function"then return nil end
local e=s("boss",n,{parent=UIParent,strata="DIALOG",width=e,height=a,label="Celestial Ruin",showIcon=true,showTime=true,bgAlpha=0.8,initialValue=0,hideFillTexture=true,})if not e then return nil end
e.unit="boss"e._msufIsBossCastbar=true
e._msufIsPreview=true
e._msufBossIndex=t
if e.statusBar then
e.statusBar:SetValue(0)e.statusBar.MSUF_hideFillTexture=true
local e=e.statusBar.GetStatusBarTexture and e.statusBar:GetStatusBarTexture()if e then e:SetAlpha(0)end
end
if t==1 then _G.MSUF_BossCastbarPreview=e end
return e
end
local function _(e,n)if not(e and e.statusBar)then return end
local t=s()local a,s
if type(_G.MSUF_GetCastbarDesiredSize)=="function"then a,s=_G.MSUF_GetCastbarDesiredSize("boss"..n,t,e,240,18)else a,s=tonumber(t.bossCastbarWidth)or 240,tonumber(t.bossCastbarHeight)or 18 end
if type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout)=="function"then _G.MSUF_ApplyPlayerCastbarSizeAndLayout(e,t,a,s)else e:SetSize(a,s)end
if type(_G.MSUF_UpdateCastbarVisuals)=="function"then _G.MSUF_UpdateCastbarVisuals()end
if type(_G.MSUF_ApplyBossCastbarTextsLayout)=="function"then
_G.MSUF_ApplyBossCastbarTextsLayout(e,{baselineTimeX=-2,baselineTimeY=0,textOffsetX=tonumber(t.bossCastTextOffsetX)or 0,textOffsetY=tonumber(t.bossCastTextOffsetY)or 0,timeOffsetX=tonumber(t.bossCastTimeOffsetX)or-2,timeOffsetY=tonumber(t.bossCastTimeOffsetY)or 0,showName=t.showBossCastName~=false,showTime=t.showBossCastTime~=false,})end
if e.statusBar then
e.statusBar:SetValue(0)e.statusBar.MSUF_hideFillTexture=true
local e=e.statusBar.GetStatusBarTexture and e.statusBar:GetStatusBarTexture()if e then e:SetAlpha(0)end
end
end
local function o(t,a)if not t then return end
local e=s()local r,n=tonumber(e.bossCastbarOffsetX)or 0,tonumber(e.bossCastbarOffsetY)or 0
t:ClearAllPoints()if e.bossCastbarDetached==true then
local s,e=0,-((a-1)*34)if type(_G.MSUF_GetBossLayoutDelta)=="function"then
s,e=_G.MSUF_GetBossLayoutDelta(a,MSUF_DB.boss or{})s,e=tonumber(s)or 0,tonumber(e)or e
end
t:SetPoint("CENTER",UIParent,"CENTER",r+s,n+(tonumber(e)or 0))else
local e=i(a)if e then t:SetPoint("BOTTOMLEFT",e,"TOPLEFT",r,n+2)else t:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-420+r,(-220+n)-((a-1)*34))end
end
end
function _G.MSUF_UpdateBossCastbarPreview()if b()then return end
if not f()then u();return end
for t=1,a do
local a=i(t)local e=l(t)if e and a and(not a.IsShown or a:IsShown())then
local a=(_G.MSUF_BossCastbars and _G.MSUF_BossCastbars[t])or _G["MSUF_BossCastbar"..t]if type(_G.MSUF_HardSyncCastbarPreview)=="function"then _G.MSUF_HardSyncCastbarPreview(e,a)end
_(e,t)o(e,t)e:Show()elseif e then
e:Hide()end
end
end
_G.MSUF_HideAllBossCastbarPreviews=u
_G.MSUF_CreateBossCastbarPreview=l
_G.MSUF_ApplyBossCastbarPreviewLayout=_
_G.MSUF_PositionBossCastbarPreview=o