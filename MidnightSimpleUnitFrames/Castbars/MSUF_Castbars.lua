--- Castbars/MSUF_Castbars.lua
--- Legacy/minified player castbar creation, backend application, castbar manager,
--- and timer text update loop.
---
--- This file still owns some historical globals used by the newer readable
--- Castbar modules. Prefer adding shared behavior to Engine, Runtime, Frames,
--- Style, or Visuals; when this file must change, keep edits tiny and validate
--- with `luac -p` because formatting does not make control flow obvious.

local d=_G.MSUF_PlayerCastbar_Cast
local a=_G.MSUF_PlayerCastbar_OnEvent local f=_G.MSUF_PlayerCastbar_UpdateLatencyZone
local F=_G.MSUF_LayoutEmpowerTicks local C=_G.MSUF_BlinkEmpowerTick
local b=_G.MSUF_IsEmpowerStageBlinkEnabled local p=_G.MSUF_PlayerChannelHasteMarkers_Update
local n={"UNIT_SPELLCAST_EMPOWER_START","UNIT_SPELLCAST_EMPOWER_STOP","UNIT_SPELLCAST_EMPOWER_UPDATE",}local t={"UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_CHANNEL_UPDATE","UNIT_SPELLCAST_DELAYED","UNIT_SPELLCAST_INTERRUPTIBLE","UNIT_SPELLCAST_NOT_INTERRUPTIBLE","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED",}local function i(e,r)if not e then return end if r then
if e._msufPlayerEventsRegistered then return end for t=1,#n do
e:RegisterUnitEvent(n[t],"player")end
for n=1,#t do e:RegisterUnitEvent(t[n],"player","vehicle")end e:RegisterEvent("PLAYER_ENTERING_WORLD")e:SetScript("OnEvent",a)e._msufPlayerEventsRegistered=true
return end
if not e._msufPlayerEventsRegistered then return end for t=1,#n do
e:UnregisterEvent(n[t])end
for n=1,#t do e:UnregisterEvent(t[n])end e:UnregisterEvent("PLAYER_ENTERING_WORLD")e:SetScript("OnEvent",nil)e._msufPlayerEventsRegistered=nil
end local function t(e)if not e then return end if e.hideTimer and e.hideTimer.Cancel then
e.hideTimer:Cancel()end
e.hideTimer=nil e:SetScript("OnUpdate",nil)e.interruptFeedbackEndTime=nil e.MSUF_castActive=false
e.MSUF_wantsEmpower=nil if e.timeText then e.timeText:SetText("")end
if e.latencyBar then e.latencyBar:Hide()end if MSUF_PlayerChannelHasteMarkers_Hide then MSUF_PlayerChannelHasteMarkers_Hide(e)end
if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end e:Hide()end function _G.MSUF_PlayerCastbar_ApplyBackendState()local e=true local n=_G.MSUF_IsCastbarEnabledForUnit
if type(n)=="function"then e=n("player")==true
end if e then
MSUF_InitSafePlayerCastbar()if MSUF_PlayerCastbar then
i(MSUF_PlayerCastbar,true)end
return MSUF_PlayerCastbar end
if MSUF_PlayerCastbar then i(MSUF_PlayerCastbar,false)t(MSUF_PlayerCastbar)end
return nil end
function MSUF_InitSafePlayerCastbar()if not MSUF_PlayerCastbar then
local e=CreateFrame("Frame","MSUF_PlayerCastBar",UIParent)e:SetClampedToScreen(true)MSUF_PlayerCastbar=e e.unit="player"local r=18 e:SetSize(200,r)local n=e:CreateTexture(nil,"BACKGROUND")n:SetAllPoints(e)n:SetColorTexture(0,0,0,1)e.background=n
local t=e:CreateTexture(nil,"OVERLAY",nil,7)t:SetSize(r,r)t:SetPoint("LEFT",e,"LEFT",0,0)e.icon=t
local n=CreateFrame("StatusBar",nil,e)n:SetPoint("LEFT",t,"RIGHT",0,0)n:SetPoint("RIGHT",e,"RIGHT",0,0)n:SetPoint("TOP",e,"TOP",0,0)n:SetPoint("BOTTOM",e,"BOTTOM",0,0)local a=MSUF_GetCastbarTexture()n:SetStatusBarTexture(a)n:GetStatusBarTexture():SetHorizTile(true)e.statusBar=n local t=e:CreateTexture(nil,"ARTWORK")t:SetPoint("TOPLEFT",n,"TOPLEFT",0,0)t:SetPoint("BOTTOMRIGHT",n,"BOTTOMRIGHT",0,0)local a=a if type(_G.MSUF_GetCastbarBackgroundTexture)=="function"then
local e=_G.MSUF_GetCastbarBackgroundTexture()if e and e~=""then
a=e end
end t:SetTexture(a)do local n,e,a,r=0.176,0.176,0.176,1
if type(_G.MSUF_GetCastbarBackgroundColor)=="function"then n,e,a,r=_G.MSUF_GetCastbarBackgroundColor()end t:SetVertexColor(n,e,a,r)end e.backgroundBar=t
local t=n:CreateFontString(nil,"OVERLAY")local s,o,l=GameFontHighlight:GetFont()t:SetFont(s,o,l)t:SetPoint("LEFT",n,"LEFT",2,0)e.castText=t EnsureDB()local t=MSUF_DB.general local d=t.castbarPlayerTimeOffsetX or-2
local _=t.castbarPlayerTimeOffsetY or 0 local a=n:CreateFontString(nil,"OVERLAY")local t=n:CreateTexture(nil,"OVERLAY")t:SetColorTexture(1,0,0,0.25)t:SetPoint("TOPRIGHT",n,"TOPRIGHT",0,0)t:SetPoint("BOTTOMRIGHT",n,"BOTTOMRIGHT",0,0)t:SetWidth(0)t:Hide()e.latencyBar=t if not e.MSUF_latencyHooked and e.HookScript then
e:HookScript("OnSizeChanged",function(e)if e and e.latencyBar and e.MSUF_latencyLastDurSec and e.MSUF_latencyLastDurSec>0 then
f(e,e.MSUF_latencyLastIsChanneled,e.MSUF_latencyLastDurSec)end
end)e.MSUF_latencyHooked=true
end a:SetFont(s,o,l)a:SetPoint("RIGHT",n,"RIGHT",d,_)a:SetJustifyH("RIGHT")a:SetText("")e.timeText=a
if _G.MSUF_ApplyCastbarOutline then _G.MSUF_ApplyCastbarOutline(e,true)end e.empowerStageTicks=e.empowerStageTicks or{}local t=5 local r=r
for a=1,t-1 do local t=e.empowerStageTicks[a]if not t then t=n:CreateTexture(nil,"OVERLAY")t:SetColorTexture(1,1,1,0.8)e.empowerStageTicks[a]=t
end t:SetSize(3,r)t:Hide()end
i(e,true)e:Hide()end C_Timer.After(0,function()if not(MSUF_PlayerCastbar and MSUF_PlayerCastbar._msufPlayerEventsRegistered)then return end if not MSUF_PlayerCastbar or not d then return end
local e=UnitCastingInfo("player")local n=UnitChannelInfo("player")if not(e or n)and type(UnitHasVehicleUI)=="function"and UnitHasVehicleUI("player")and type(UnitExists)=="function"and UnitExists("vehicle")then e=UnitCastingInfo("vehicle")n=UnitChannelInfo("vehicle")end
if e or n then d(MSUF_PlayerCastbar)end end)end do
local t=MSUF_ToPlainNumber if type(t)~="function"then
t=function(e)if e==nil then return nil end
local n=type(e)if n=="number"then
local e=tostring(e)return tonumber(e)end if n=="string"then
return tonumber(e)end
local e=tostring(e)return tonumber(e)end end
local S=math.floor local function T(e,t,n)if not e or not e.timeText then return end local i=S((t or 0)*10)local a=n and S((n or 0)*10)or-1 local r=e._msufCastTimeFormat or"CURRENT"if i==e._msufLastTimeDecimal and a==e._msufLastTimeTotalDecimal
and r==e._msufLastTimeFormat then
return end
e._msufLastTimeDecimal=i e._msufLastTimeTotalDecimal=a
e._msufLastTimeFormat=r MSUF_SetCastTimeText(e,t,n)end _G.MSUF__castbarStyleGlobalRev=_G.MSUF__castbarStyleGlobalRev or 1
_G.MSUF_CastbarStyleRev=_G.MSUF__castbarStyleGlobalRev local h=_G.MSUF__castbarStyleGlobalRev
local G=_G.MSUF__castTimeGlobalRev or 1 local f=GetTimePreciseSec or GetTime
local r=_G.MSUF_ApplyCastbarGlowFade local m=_G.MSUF_ResetCastbarGlowFade
local c=_G.MSUF_RefreshCastbarStyleCache if C_Timer and C_Timer.After then
C_Timer.After(0,function()r=_G.MSUF_ApplyCastbarGlowFade or r
m=_G.MSUF_ResetCastbarGlowFade or m c=_G.MSUF_RefreshCastbarStyleCache or c
end)end
function _G.MSUF_BumpCastbarStyleRev()_G.MSUF__castbarStyleGlobalRev=(_G.MSUF__castbarStyleGlobalRev or 1)+1
_G.MSUF_CastbarStyleRev=_G.MSUF__castbarStyleGlobalRev h=_G.MSUF__castbarStyleGlobalRev
end local function e()if _G.MSUF__castbarStyleHooked then return end local n=_G.MSUF_UpdateCastbarVisuals
if type(n)~="function"then return end _G.MSUF__castbarStyleHooked=true
_G.MSUF_UpdateCastbarVisuals=function(...)_G.MSUF_BumpCastbarStyleRev()return n(...)end
end e()if C_Timer and C_Timer.After then C_Timer.After(0,e)end local function e(e,a)if not e then return end local t=_G.MSUF_RefreshCastbarStyleCache
if type(t)~="function"then return end local n=_G.MSUF__castbarStyleGlobalRev or 1
if a or e._msufCastbarStyleRev~=n then t(e)e._msufCastbarStyleRev=n end
end _G.MSUF__castTimeGlobalRev=_G.MSUF__castTimeGlobalRev or 1
function _G.MSUF_BumpCastTimeRev()_G.MSUF__castTimeGlobalRev=(_G.MSUF__castTimeGlobalRev or 1)+1
G=_G.MSUF__castTimeGlobalRev end
local function l(n,e)e=tostring(e or""):lower()if n and n._msufIsBossCastbar then return"boss"end if e:match("^boss%d+$")then return"boss"end
return e end
local function s(e)if not e or not e.unit then
return true end
local n=MSUF_DB and MSUF_DB.general if not n then
e._msufCastTimeEnabled=true return true
end local a=e.unit
local t=true if a=="player"then
t=(n.showPlayerCastTime~=false)elseif a=="target"then
t=(n.showTargetCastTime~=false)elseif a=="focus"then
t=(n.showFocusCastTime~=false)elseif e._msufIsBossCastbar or tostring(a or""):match("^boss%d+$")then
t=(n.showBossCastTime~=false)end
local o=e._msufCastTimeFormat local r="CURRENT"local i=_G.MSUF_GetCastbarTimeFormat if type(i)=="function"then
r=i(l(e,a),n)end
e._msufCastTimeFormat=r or"CURRENT"if o~=e._msufCastTimeFormat then
e._msufLastTimeDecimal=nil e._msufLastTimeTotalDecimal=nil
e._msufLastTimeFormat=nil end
e._msufCastTimeEnabled=t and true or false return e._msufCastTimeEnabled
end local function U(e,t)if not e or not e.unit then return true
end local n=_G.MSUF__castTimeGlobalRev or 1
if t or e._msufCastTimeRev~=n or e._msufCastTimeEnabled==nil then s(e)e._msufCastTimeRev=n end
return e._msufCastTimeEnabled~=false end
_G.MSUF_IsCastTimeEnabled=function(e)return U(e,false)end if _G.MSUF_UpdateCastbarVisuals and not _G.__MSUF_CastTimeRevHooked then
_G.__MSUF_CastTimeRevHooked=true local e=_G.MSUF_UpdateCastbarVisuals
_G.MSUF_UpdateCastbarVisuals=function(...)_G.MSUF_BumpCastTimeRev()local e=e(...)if type(_G.MSUF_ReanchorPlayerCastBar)=="function"then
_G.MSUF_ReanchorPlayerCastBar()end
if _G.MSUF_ApplyCastbarOutlineToAll then _G.MSUF_ApplyCastbarOutlineToAll(false)end return e
end end
local e=MSUF_CastbarManager if e then
if e.SetScript then e:SetScript("OnUpdate",nil)end if e.Hide then e:Hide()end
if e.active then wipe(e.active)end end
local l=CreateFrame("Frame")l.active={}l.low={}l.high={}l:Hide()local d=nil
C_Timer.After(0,function()d=_G.MSUF_UpdateCastbarFrame
end)local a=0
local n=0 local u=0.10
local o local _
local i=0 local function s(n,a)local e=next(n)while e do
local o=next(n,e)local t=false
if e._msufIsBossCastbar then local n=e._msufBossExistNext
if(not n)or(i>=n)then e._msufBossExistNext=i+0.25
local n=e.unit if n and((type(UnitExists)=="function"and not UnitExists(n))or(type(UnitIsDeadOrGhost)=="function"and UnitIsDeadOrGhost(n)))then if type(_G.MSUF_BossCastbar_Stop)=="function"then
_G.MSUF_BossCastbar_Stop(e)else
if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end if e.Hide then e:Hide()end
end t=true
end end
end if not t then
local n=e._msufRemaining if e._msufFastText and n then
n=n-a if n<0 then n=0 end
e._msufRemaining=n if n<=0.001 then
if e.SetSucceeded then e:SetSucceeded()else e:Hide()end else
local l=S(n*10)local t=e._msufCastTimeFormat or"CURRENT"if t=="CURRENT"then if l~=e._msufLastTimeDecimal then
e._msufLastTimeDecimal=l e._msufLastTimeTotalDecimal=-1
e._msufLastTimeFormat=t e.timeText._msufLastText=nil
e.timeText:SetFormattedText("%.1f",n)end
else T(e,n,e._msufPlainTotal)end if e.MSUF_isChanneled then
if n<1.0 then local n=e._msufHeavyIn
if n then n=n-a
else n=0
end if n<=0 then
n=e._msufTickInterval or 0.10 local n=d or _G.MSUF_UpdateCastbarFrame
if n then n(e,a,nil,i)end end
e._msufHeavyIn=n end
elseif r then local i=e._msufPlainTotal
if i and i>0 then local t=e._msufGlowIn
if t then t=t-a
else t=0
end if t<=0 then
e._msufGlowIn=0.04 r(e,n,i)else e._msufGlowIn=t
end end
end end
else local n=e._msufHeavyIn
if n then n=n-a
else n=0
end if n<=0 then
n=e._msufTickInterval or 0.10 local n=d or _G.MSUF_UpdateCastbarFrame
if n then n(e,a,nil,i)end end
e._msufHeavyIn=n end
end e=o
end end
local function S(e,t)if a<=0 then
e._msufLowTickAccum=0 e:Hide()return end
t=t or 0 i=i+t
if n>0 then s(e.high,t)end local n=a-n
if n>0 then local n=(e._msufLowTickAccum or 0)+t
if n>=u then e._msufLowTickAccum=0
s(e.low,n)else
e._msufLowTickAccum=n end
else e._msufLowTickAccum=0
end end
local function d()if o then
o:Cancel()o=nil
end _=nil
end local function g()if a<=0 then d()MSUF_CastbarManager:Hide()return
end if n>0 then
d()MSUF_CastbarManager:SetScript("OnUpdate",S)return end
local n=(f or GetTimePreciseSec)()local e=_ and(n-_)or u
_=n if e<=0 or e>0.5 then
e=u end
i=i+e s(MSUF_CastbarManager.low,e)end local function M()if a<=0 then d()MSUF_CastbarManager:SetScript("OnUpdate",nil)MSUF_CastbarManager:Hide()return end
MSUF_CastbarManager:Show()if n>0 then
d()MSUF_CastbarManager:SetScript("OnUpdate",S)else MSUF_CastbarManager:SetScript("OnUpdate",nil)if not o and C_Timer and C_Timer.NewTicker then _=(f or GetTimePreciseSec)()o=C_Timer.NewTicker(u,g)s(MSUF_CastbarManager.low,0)return true elseif not o then
MSUF_CastbarManager:SetScript("OnUpdate",S)end
end return false
end l:SetScript("OnHide",function(e)d()e:SetScript("OnUpdate",nil)end)MSUF_CastbarManager=l
function MSUF_RegisterCastbar(e)if not e or not e.statusBar then return end
if not MSUF_CastbarManager or not MSUF_CastbarManager.active then return end local t=e.MSUF_castActive==true
or e.isEmpower==true or e.MSUF_timerDriven==true
or e._msufPlainEndTime~=nil or e._msufPlainTotal~=nil
or e.MSUF_durationObj~=nil or e.MSUF_castDuration~=nil
or e.MSUF_channelDuration~=nil or e.castDuration~=nil
or e.channelDuration~=nil if not t then
if MSUF_CastbarManager.active[e]==true and MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end return
end U(e,true)e._msufFastText=(e.timeText and e._msufCastTimeEnabled~=false and e.MSUF_timerDriven==true
and not e.isEmpower)or false if e.isEmpower then
e._msufTickInterval=0.03 elseif e._msufFastText~=true and e.MSUF_timerDriven~=true then
if e._msufTickInterval==nil or e._msufTickInterval>0.05 then e._msufTickInterval=0.05
end elseif e._msufTickInterval==nil or e._msufTickInterval<0.10 then
e._msufTickInterval=0.10 end
e._msufHeavyIn=0 local t=e._msufPlainEndTime
if t then local n=t-(f or GetTimePreciseSec)()e._msufRemaining=(n>0)and n or 0 end
local t=e._msufTickInterval and e._msufTickInterval<0.10 or false local i=MSUF_CastbarManager.active[e]==true
local r=e._msufManagerHighFreq==true if i and r~=t then
n=n+(t and 1 or-1)if n<0 then n=0 end
end e._msufManagerHighFreq=t or nil
local l=e._msufManagerBucket local r=t and MSUF_CastbarManager.high or MSUF_CastbarManager.low
if i and l~=r then if l then l[e]=nil end
r[e]=true e._msufManagerBucket=r
end if not i then
a=a+1 if t then n=n+1 end
MSUF_CastbarManager.active[e]=true r[e]=true
e._msufManagerBucket=r end
if not e._msufOnHideHooked then e._msufOnHideHooked=true
e:HookScript("OnHide",function(e)if e._msufInUnregister then return end
if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end end)end local e=M()if not e and not i and not t and n<=0 then s(MSUF_CastbarManager.low,0)end end
function MSUF_UnregisterCastbar(e)if not e then return end
if not MSUF_CastbarManager or not MSUF_CastbarManager.active then return end e._msufInUnregister=true
if m then m(e)end if MSUF_CastbarManager.active[e]then
MSUF_CastbarManager.active[e]=nil if MSUF_CastbarManager.low then MSUF_CastbarManager.low[e]=nil end
if MSUF_CastbarManager.high then MSUF_CastbarManager.high[e]=nil end a=a-1
if a<0 then a=0 end if e._msufManagerHighFreq then
n=n-1 if n<0 then n=0 end
end end
e._msufNextTick=nil e._msufHeavyIn=nil
e._msufHardStopNext=nil e._msufZeroCount=nil
e._msufLastTimeDecimal=nil e._msufLastTimeTotalDecimal=nil
e._msufLastTimeFormat=nil e._msufFastText=nil
e._msufRemaining=nil e._msufGlowIn=nil
e._msufCastTimeWasEnabled=nil e._msufManagerHighFreq=nil
e._msufManagerBucket=nil e._msufInUnregister=nil
M()end
function MSUF_UpdateCastbarFrame(e,a,i,n)if not e or not e.statusBar then
return end
local l=e._msufCastTimeEnabled if l==nil or e._msufCastTimeRev~=G then
l=U(e,false)end
if e.timeText and not l and e._msufCastTimeWasEnabled then MSUF_SetTextIfChanged(e.timeText,"")end if e._msufCastTimeWasEnabled~=l then
e._msufCastTimeWasEnabled=l end
if e._msufCastbarStyleRev~=h then if c then
c(e)end
e._msufCastbarStyleRev=h end
local o=n or 0 if e.isEmpower and e.empowerStartTime and e.empowerTotalWithGrace then
local n=e._msufEmpowerTotalNum if not n then
n=t(e.empowerTotalWithGrace)or 0 if n>0 then e._msufEmpowerTotalNum=n end
end if n<=0 then n=0.01 end
if not i then i=(f or GetTimePreciseSec)()end local a=e._msufEmpowerStartNum
if not a then a=t(e.empowerStartTime)or i
e._msufEmpowerStartNum=a end
local i=i-a if i<0 then i=0 end
if i>n then i=n end e._msufEmpowerElapsed=i
if not e._msufEmpowerMinMaxSet then e._msufEmpowerMinMaxSet=true
if e.statusBar.SetMinMaxValues then e.statusBar:SetMinMaxValues(0,n)end end
if e.statusBar.SetValue then e.statusBar:SetValue(i)end local a=e._msufEmpowerBaseNum
if not a then a=t(e.empowerTotalBase)or n
if a>0 then e._msufEmpowerBaseNum=a end end
if a<=0 then a=n end if e.timeText and l then
local n=a-i if n<0 then n=0 end
T(e,n,a)end
if e.MSUF_empowerLayoutPending and F then F(e)end if e.empowerStageEnds and e.empowerTicks and C then
if not e.empowerNextStage then e.empowerNextStage=1 end local r=e._msufEmpowerStageEndsNum
while e.empowerNextStage<=#e.empowerStageEnds do local a=e.empowerNextStage
local n=r and r[a]if not n then
local e=e.empowerStageEnds[a]if type(e)~="number"then e=t(e)end
n=e if n and r then r[a]=n end
end if not n then break end
if i>=n then if b and b()then
C(e,a)end
e.empowerNextStage=a+1 else
break end
end end
if r and a>0 then local n=a-i
if n<0 then n=0 end r(e,n,a)end return
end if e.MSUF_isChanneled then
local n=e._msufHardStopNext if(not n)or(o>=n)then
e._msufHardStopNext=o+0.15 local n=e.unit
if e.unit=="player"and type(_G.MSUF_PlayerCastbar_GetEffectiveUnit)=="function"then n=_G.MSUF_PlayerCastbar_GetEffectiveUnit(e)end if n and n~=""then
if UnitChannelInfo(n)then e._msufHardStopNoChannelSince=nil
e._msufHardStopChanThresh=nil else
local a=e._msufHardStopNoChannelSince if not a then
e._msufHardStopNoChannelSince=o local t=0
if GetCVar then t=tonumber(GetCVar("SpellQueueWindow")or"0")or 0 end if t<0 then t=0 end
local n=0.45 local t=(t/1000)+0.10
if t>n then n=t end if n>0.80 then n=0.80 end
e._msufHardStopChanThresh=n else
local n=e._msufHardStopChanThresh or 0.45 if(o-a)>=n then
if e.SetSucceeded then e:SetSucceeded()else e:Hide()end return
end end
end end
end end
if e.unit=="player"and e.MSUF_isChanneled and e._msufPlayerChannelHasteMarkers then if o>=(e._msufHasteMarkersNext or 0)then
e._msufHasteMarkersNext=o+0.15 p(e,false)end end
if not i then i=(f or GetTimePreciseSec)()end local a=e.MSUF_durationObj
if a and(a.GetRemainingDuration or a.GetRemaining)then if e._msufLastDurationObj~=a then
e._msufLastDurationObj=a e._msufTimerAssumeCountdown=nil
end local n=e._msufPlainEndTime
local o=n and(n-i)or nil local d=(not o)or(o<1.0)local n local s=nil
if d then local r
if a.GetRemainingDuration then r=a:GetRemainingDuration()else r=a:GetRemaining()end n=t(r)if(not n)and e.statusBar and e.MSUF_timerDriven then local r=e.statusBar
if r.GetMinMaxValues and r.GetValue then local i,a=r:GetMinMaxValues()local r=r:GetValue()i=t(i)or 0
a=t(a)r=t(r)if a and r and a>i then local l=a-i
s=l local t=e._msufTimerAssumeCountdown
if t==nil then local n=math.abs(r-i)local a=math.abs(a-r)t=(a<n)e._msufTimerAssumeCountdown=t end
if t then n=r-i
else n=a-r
end if n<0 then n=0 end
if n>l then n=l end end
end end
if not n and not o then if e.timeText and l and r~=nil then
local n if type(r)=="number"then
n=string.format("%.1f",r)else
n=tostring(r or"")end
MSUF_SetTextIfChanged(e.timeText,n)e._msufZeroCount=nil
end return
end else
n=o end
if n then if n<0 then n=0 end
if d then e._msufPlainEndTime=i+n
e._msufRemaining=n end
if r then local i=e._msufPlainTotal
if not i then if a.GetTotalDuration then
i=t(a:GetTotalDuration())end
end if(not i)and s then
i=s end
if(not i)and e.statusBar then local e=e.statusBar
if e.GetMinMaxValues then local n,e=e:GetMinMaxValues()n=t(n)or 0 e=t(e)if e and e>n then i=e-n
end end
end if i and i>0 then
r(e,n,i)end
end if n<=0.001 then
e._msufZeroCount=(e._msufZeroCount or 0)+1 if e._msufZeroCount>=2 then
e._msufZeroCount=nil if e.SetSucceeded then
e:SetSucceeded()else
MSUF_UnregisterCastbar(e)if e.Hide then e:Hide()end
end end
else e._msufZeroCount=nil
end end
return end
if e.endTime then local n=t(e.endTime)or 0
local a=n-i if a<0 then a=0 end
local i=e._msufPlainTotal if i and i>0 and e.statusBar and e.statusBar.SetValue then
local n if e._msufStripeReverseFill then
n=a else
n=i-a end
if n<0 then n=0 end if n>i then n=i end
e.statusBar:SetValue(n)end
if e.timeText and l then T(e,a,i)end if r and e.statusBar then
local n=e.statusBar if n.GetMinMaxValues then
local i,n=n:GetMinMaxValues()i=t(i)or 0
n=t(n)if n and n>i then
local n=n-i if n and n>0 then
r(e,a,n)end
end end
end if a<=0.001 then
if e.SetSucceeded then e:SetSucceeded()else MSUF_UnregisterCastbar(e)if e.Hide then e:Hide()end end
end end
end end
