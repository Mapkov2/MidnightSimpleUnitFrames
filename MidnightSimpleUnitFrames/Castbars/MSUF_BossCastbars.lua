local e,e=...local a=tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES)or 5
if a<1 or a>12 then a=5 end
local f={"UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_DELAYED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_CHANNEL_UPDATE","UNIT_SPELLCAST_EMPOWER_START","UNIT_SPELLCAST_EMPOWER_STOP","UNIT_SPELLCAST_EMPOWER_UPDATE","UNIT_SPELLCAST_INTERRUPTIBLE","UNIT_SPELLCAST_NOT_INTERRUPTIBLE","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_INTERRUPTED",}local e={"UNIT_HEALTH","INSTANCE_ENCOUNTER_ENGAGE_UNIT","ENCOUNTER_START","ENCOUNTER_END","PLAYER_ENTERING_WORLD",}local function o()if type(_G.EnsureDB)=="function"then _G.EnsureDB()end
end
local function u()return _G.MSUF_InCombat==true
or((_G.InCombatLockdown and _G.InCombatLockdown())and true or false)or((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))and true or false)end
local function s()o()local e=_G.MSUF_DB and _G.MSUF_DB.general
local t=_G.MSUF_ShouldUseMSUFCastbar
if type(t)=="function"then return t("boss",e)==true end
return(not e)or(e.enableBossCastbar~=false)end
local function l(t,s,a,o,n,e)if not t then return false end
n=math.floor((tonumber(n)or 0)+0.5)e=math.floor((tonumber(e)or 0)+0.5)local l,r,i,_,d=t:GetPoint(1)if l==s and r==a and i==o
and math.abs((tonumber(_)or 0)-n)<=0.01
and math.abs((tonumber(d)or 0)-e)<=0.01 then
return false
end
t:ClearAllPoints()t:SetPoint(s,a,o,n,e)return true
end
local function _(t,e)e=tonumber(e)if not(t and e and e>0)then return false end
if t.GetWidth and math.abs((t:GetWidth()or 0)-e)<=0.01 then return false end
t:SetWidth(e)return true
end
local function r(t,e)e=tonumber(e)if not(t and e and e>0)then return false end
if t.GetHeight and math.abs((t:GetHeight()or 0)-e)<=0.01 then return false end
t:SetHeight(e)return true
end
local function S(e)if not(e and e.statusBar)then return end
o()local t=(_G.MSUF_DB and _G.MSUF_DB.general)or{}local n=e:GetHeight()or 18
if n<12 then n=12 end
local a=(t.showBossCastIcon==nil)and(t.castbarShowIcon~=false)or(t.showBossCastIcon~=false)local s=tonumber(t.bossCastIconOffsetX)or tonumber(t.castbarIconOffsetX)or 0
local o=tonumber(t.bossCastIconOffsetY)or tonumber(t.castbarIconOffsetY)or 0
local n=tonumber(t.bossCastIconSize)or tonumber(t.castbarIconSize)or n
if n<6 then n=6 elseif n>128 then n=128 end
if e.icon then
local t=((s~=0 or o~=0)and e.statusBar)or e
if e.icon.SetParent and e.icon:GetParent()~=t then e.icon:SetParent(t)end
e.icon:ClearAllPoints()e.icon:SetPoint("LEFT",e,"LEFT",s,o)e.icon:SetSize(n,n)e.icon:SetShown(a)end
e.statusBar:ClearAllPoints()if a and e.icon and s==0 and o==0 then
e.statusBar:SetPoint("LEFT",e,"LEFT",n+1,0)else
e.statusBar:SetPoint("LEFT",e,"LEFT",0,0)end
e.statusBar:SetPoint("TOP",e,"TOP",0,-1)e.statusBar:SetPoint("BOTTOM",e,"BOTTOM",0,1)e.statusBar:SetPoint("RIGHT",e,"RIGHT",-1,0)if e.backgroundBar then
e.backgroundBar:ClearAllPoints()e.backgroundBar:SetAllPoints(e.statusBar)end
if type(_G.MSUF_ApplyBossCastbarTextsLayout)=="function"then
local n=tonumber(t.bossCastSpellNameFontSize)or tonumber(t.castbarSpellNameFontSize)or tonumber(t.fontSize)or 14
local o=tonumber(t.bossCastTimeFontSize)or n
_G.MSUF_ApplyBossCastbarTextsLayout(e,{baselineTimeX=-2,baselineTimeY=0,textOffsetX=tonumber(t.bossCastTextOffsetX)or 0,textOffsetY=tonumber(t.bossCastTextOffsetY)or 0,timeOffsetX=tonumber(t.bossCastTimeOffsetX)or-2,timeOffsetY=tonumber(t.bossCastTimeOffsetY)or 0,showName=t.showBossCastName~=false,showTime=t.showBossCastTime~=false,nameFontSize=n,timeFontSize=o,})end
if type(_G.MSUF_ApplyCastbarOutline)=="function"then _G.MSUF_ApplyCastbarOutline(e,true)end
end
local function E(t,f)if not t then return false end
o()local n=(_G.MSUF_DB and _G.MSUF_DB.general)or{}local d=t.unit or"boss1"local i=tonumber(tostring(d):match("boss(%d+)"))or 1
local o,s
if type(_G.MSUF_GetCastbarDesiredSize)=="function"then
o,s=_G.MSUF_GetCastbarDesiredSize(d,n,t,240,12)else
o,s=tonumber(n.bossCastbarWidth),tonumber(n.bossCastbarHeight)end
local e=false
e=r(t,s or t:GetHeight()or 18)or e
local a=tonumber(n.bossCastbarOffsetX)or 0
local r=tonumber(n.bossCastbarOffsetY)or 0
if n.bossCastbarDetached==true then
local s,n=0,-((i-1)*34)if type(_G.MSUF_GetBossLayoutDelta)=="function"then
local e=(_G.MSUF_DB and _G.MSUF_DB.boss)or{}s,n=_G.MSUF_GetBossLayoutDelta(i,e)s,n=tonumber(s)or 0,tonumber(n)or n
end
e=l(t,"CENTER",UIParent,"CENTER",a+s,r+(tonumber(n)or 0))or e
e=_(t,o or t:GetWidth()or 240)or e
else
local n=_G["MSUF_"..d]if n and n.GetWidth then
e=l(t,"BOTTOMLEFT",n,"TOPLEFT",a,r+2)or e
e=_(t,o or n:GetWidth()or 240)or e
else
e=l(t,"TOPRIGHT",UIParent,"TOPRIGHT",-420+a,(-220+r)-((i-1)*34))or e
e=_(t,o or t:GetWidth()or 240)or e
end
end
if e or f then S(t)end
return e
end
local function n(e)if not e then return end
if type(_G.MSUF_CB_ResetStateOnStop)=="function"then
_G.MSUF_CB_ResetStateOnStop(e,"STOPPED")elseif e.Hide then
e:Hide()end
end
local function i(e,t)if not e then return end
if t then
if e._msufBossEventsRegistered then return end
for t=1,#f do e:RegisterUnitEvent(f[t],e.unit)end
e:RegisterUnitEvent("UNIT_HEALTH",e.unit)e:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")e:RegisterEvent("ENCOUNTER_START")e:RegisterEvent("ENCOUNTER_END")e:RegisterEvent("PLAYER_ENTERING_WORLD")e._msufDriverEventsRegistered=true
e._msufBossEventsRegistered=true
return
end
e:UnregisterAllEvents()e._msufDriverEventsRegistered=nil
e._msufBossEventsRegistered=nil
end
local function l(o)local t="boss"..o
local a="MSUF_BossCastbar"..o
local e=_G[a]if not e then
local n=_G.MSUF_CreateCastBar
if type(n)~="function"then return nil end
e=n(a,t)end
if not e then return nil end
e.unit=t
e._msufBarKey=t
e._msufIsBossCastbar=true
e:SetFrameStrata("HIGH")e:SetFrameLevel(50+o)e.ApplyLayout=S
e.UpdateAnchor=E
if not e._msufBossHooked then
e._msufBossHooked=true
e:HookScript("OnEvent",function(e,t)if t=="ENCOUNTER_END"then n(e);return end
if t=="INSTANCE_ENCOUNTER_ENGAGE_UNIT"or t=="ENCOUNTER_START"or t=="PLAYER_ENTERING_WORLD"then
if s()then
e:UpdateAnchor(true)if e.Cast then e:Cast()end
end
elseif t=="UNIT_HEALTH"and e:IsShown()and(not UnitExists(e.unit)or(UnitIsDeadOrGhost and UnitIsDeadOrGhost(e.unit)))then
n(e)end
end)end
i(e,s())e:UpdateAnchor(true)e:Hide()return e
end
local function r()if _G.MSUF_BossCastbars then return _G.MSUF_BossCastbars end
if not s()then return nil end
local t={}_G.MSUF_BossCastbars=t
for n=1,a do
local e=l(n)t[n]=e
if e and UnitExists(e.unit)and e.Cast then e:Cast()end
end
return t
end
local function a()if not u()and type(_G.MSUF_UpdateBossCastbarPreview)=="function"then
_G.MSUF_UpdateBossCastbarPreview()end
end
function _G.MSUF_ApplyBossCastbarTimeSetting()o()local e=_G.MSUF_DB and _G.MSUF_DB.general
local t=(not e)or(e.showBossCastTime~=false)local e=_G.MSUF_BossCastbars
if e then
for n=1,#e do
local e=e[n]if e and e.timeText then
e.timeText:Show()e.timeText:SetAlpha(t and 1 or 0)if not t and e.timeText.SetText then e.timeText:SetText("")end
end
end
end
a()end
function _G.MSUF_ApplyBossCastbarPositionSetting(n)local e=_G.MSUF_BossCastbars or r()if not e then return end
for t=1,#e do
local e=e[t]if e then e:UpdateAnchor(n~=false)end
end
a()end
function _G.MSUF_SetBossCastbarsEnabled(e)o()e=e and true or false
local t=_G.MSUF_DB and _G.MSUF_DB.general
if t then
local n=_G.MSUF_SetCastbarBackend
if type(n)=="function"then n("boss",e and"MSUF"or"HIDE",t)else t.enableBossCastbar=e end
end
local t=e and(_G.MSUF_BossCastbars or r())or _G.MSUF_BossCastbars
if not t then return end
for o=1,#t do
local t=t[o]if t then
i(t,e)if e then
t:UpdateAnchor(true)if UnitExists(t.unit)and t.Cast then t:Cast()end
else
n(t)end
end
end
if type(_G.MSUF_UpdateCastbarVisuals)=="function"then _G.MSUF_UpdateCastbarVisuals()end
a()end
function _G.MSUF_ApplyBossCastbarsEnabled()_G.MSUF_SetBossCastbarsEnabled(s())end
local function t()r()if type(_G.MSUF_ApplyBossCastbarPositionSetting)=="function"then _G.MSUF_ApplyBossCastbarPositionSetting(true)end
end
if type(_G.MSUF_EventBus_Register)=="function"then
_G.MSUF_EventBus_Register("PLAYER_LOGIN","MSUF_BOSS_CASTBARS",t,nil,true)_G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD","MSUF_BOSS_CASTBARS_WORLD",t)else
local e=CreateFrame("Frame")e:RegisterEvent("PLAYER_LOGIN")e:RegisterEvent("PLAYER_ENTERING_WORLD")e:SetScript("OnEvent",t)end
_G.MSUF_BossCastbar_Stop=n