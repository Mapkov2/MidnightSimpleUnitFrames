local s=_G.MSUF_EnsureDBLazy or function()if not MSUF_DB and type(EnsureDB)=="function"then EnsureDB()end
end local l=_G.MSUF_CastbarRuntime_PlainNumber or function(e)if e==nil then return nil end local n=_G.ToPlain
if type(n)=="function"then local e=n(e)local e=tonumber(tostring(e))if e~=nil then return e end
end local n=type(e)if n=="number"or n=="string"then return tonumber(tostring(e))end return nil
end local m=function(t,n)local e=_G.MSUF_PlayerCastbar_EmpowerStart;if e then e(t,n)end end
local f=function(t,n)local e=_G.MSUF_PlayerCastbar_ClearEmpower;if e then e(t,n)end end local M=function(t,n)local e=_G.MSUF_PlayerChannelHasteMarkers_Update;if e then e(t,n)end end
local S=function(n)local e=_G.MSUF_PlayerChannelHasteMarkers_Hide;if e then e(n)end end local function r(e,r,t)if not e or not e.latencyBar or not e.statusBar then return
end local n=e.statusBar:GetWidth()or 0
local n=n*(r or 0)local t=_G.MSUF_GetReverseFillSafe(e,t and true or false)local t=t and true or false e.latencyBar:ClearAllPoints()if t then e.latencyBar:SetPoint("TOPLEFT",e.statusBar,"TOPLEFT",0,0)e.latencyBar:SetPoint("BOTTOMLEFT",e.statusBar,"BOTTOMLEFT",0,0)else
e.latencyBar:SetPoint("TOPRIGHT",e.statusBar,"TOPRIGHT",0,0)e.latencyBar:SetPoint("BOTTOMRIGHT",e.statusBar,"BOTTOMRIGHT",0,0)end e.latencyBar:SetWidth(n)if n and n>0 then e.latencyBar:Show()else e.latencyBar:Hide()end end
local function o(n,t)if not n then
return end
local e=n._msufLatencyPending if not e then
return end
if t and e.generation~=t then return
end r(n,e.pct or 0,e.isChanneled and true or false)end local a={}local function u()local n=a
local t=#n if t<=0 then
return end
local e=1 while e<=t do
local t=n[e]local r=n[e+1]o(t,r)n[e]=nil
n[e+1]=nil e=e+2
end end
local function U(e,i,n)if not e or not e.latencyBar or not e.statusBar then
return end
n=l(n)s()local t=(MSUF_DB and MSUF_DB.general)or{}if t.castbarShowLatency==false then
e.latencyBar:Hide()return
end if(e.MSUF_testMode or e._msufIsPreview)and not MSUF_UnitEditModeActive then
e.latencyBar:Hide()return
end if not n or type(n)~="number"or n<=0 then
e.latencyBar:Hide()return
end local l,l,r,t=GetNetStats()local t=math.max(r or 0,t or 0)local r=tonumber(GetCVar("SpellQueueWindow")or"0")or 0
local l=math.max(t,r)local r=n*1000
local t=0 if r>0 then
t=l/r end
if t>1 then t=1 end if t<0 then t=0 end
e.MSUF_latencyLastPct=t e.MSUF_latencyLastIsChanneled=i and true or false
e.MSUF_latencyLastDurSec=n local r=e.statusBar:GetWidth()or 0
local n=e._msufLatencyPending if not n then
n={}e._msufLatencyPending=n
end n.pct=t
n.isChanneled=i and true or false n.generation=(n.generation or 0)+1
local t=n.generation if(not r or r<=1)and C_Timer and C_Timer.After then
local n=a n[#n+1]=e
n[#n+1]=t C_Timer.After(0,u)return end
o(e,t)end
local function o(r)if not r or not r.statusBar then
return end
s()local i=MSUF_DB and MSUF_DB.general or{}if i.playerCastbarOverrideEnabled then if not(r.interruptFeedbackEndTime and GetTime()<r.interruptFeedbackEndTime)then
local a=i.playerCastbarOverrideMode local e,n,t
if a=="CUSTOM"then e=tonumber(i.playerCastbarOverrideR)n=tonumber(i.playerCastbarOverrideG)t=tonumber(i.playerCastbarOverrideB)else local a,r=UnitClass("player")if r then if type(MSUF_GetClassBarColor)=="function"then
e,n,t=MSUF_GetClassBarColor(r)end
if(not e)and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r]then local r=RAID_CLASS_COLORS[r]e,n,t=r.r,r.g,r.b end
end end
if e and n and t then if type(_G.MSUF_SetStatusBarColorIfChanged)=="function"then
_G.MSUF_SetStatusBarColorIfChanged(r.statusBar,e,n,t,1)else
r.statusBar:SetStatusBarColor(e,n,t,1)end
return end
end end
local e=i.castbarNonInterruptibleColor or"red"local l=false
local e=r.unit or"player"local e=C_NamePlate
and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(e,issecure())if e then local e=(e.UnitFrame and e.UnitFrame.castBar)or e.castBar or e.CastBar
local e=e and e.barType if e=="uninterruptable"or e=="uninterruptible"or e=="uninterruptibleSpell"or e=="shield"then
l=true end
end if r.isNotInterruptible then
l=true end
local n,t,e,a if l then
if MSUF_GetNonInterruptibleCastColor then n,t,e=MSUF_GetNonInterruptibleCastColor()a=1 end
if not n or not t or not e then local r=i.castbarNonInterruptibleColor or"red"if MSUF_GetColorFromKey then local r=MSUF_GetColorFromKey(r)if r then n,t,e,a=r:GetRGBA()end end
end if not n or not t or not e then
n,t,e,a=0.4,0.01,0.01,1 end
else if MSUF_GetInterruptibleCastColor then
n,t,e=MSUF_GetInterruptibleCastColor()a=1
end if not n or not t or not e then
local r=i.castbarInterruptibleColor or"turquoise"if MSUF_GetColorFromKey then
local r=MSUF_GetColorFromKey(r)if r then
n,t,e,a=r:GetRGBA()end
end end
if not n or not t or not e then n,t,e,a=0,1,0.9,1
end end
if type(_G.MSUF_SetStatusBarColorIfChanged)=="function"then _G.MSUF_SetStatusBarColorIfChanged(r.statusBar,n,t,e,a or 1)else r.statusBar:SetStatusBarColor(n,t,e,a or 1)end end
local function I()s()local e=MSUF_DB and MSUF_DB.general or{}local r=tonumber(e.castbarInterruptR)local n=tonumber(e.castbarInterruptG)local t=tonumber(e.castbarInterruptB)if r and n and t then return r,n,t,1
end local e=e.castbarInterruptColor or"red"if MSUF_GetColorFromKey then local e=MSUF_GetColorFromKey(e)if e then return e:GetRGBA()end end
return 0.8,0.1,0.1,1 end
local t=(_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)local function T(e)local e=e and e.msuCastbarFrame if not e or not e.unit then
return end
if e.MSUF_testMode then return
end local n=e.unit or"player"if n=="player"and type(UnitHasVehicleUI)=="function"and UnitHasVehicleUI("player")then if type(UnitExists)=="function"and UnitExists("vehicle")then
if(type(UnitCastingInfo)=="function"and UnitCastingInfo("vehicle"))or(type(UnitChannelInfo)=="function"and UnitChannelInfo("vehicle"))then
n="vehicle"end
end end
local t=UnitCastingInfo(n)local n=UnitChannelInfo(n)if t or n then if MSUF_PlayerCastbar_Cast then
MSUF_PlayerCastbar_Cast(e)end
return end
e:SetScript("OnUpdate",nil)if e.timeText then
MSUF_SetTextIfChanged(e.timeText,"")end
if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end e._msufActiveCastGUID=nil
e._msufActiveSpellID=nil e._msufActiveCastBarID=nil
e._msufActiveCastUnit=nil e:Hide()end local function C(e,n)if not e or not e.statusBar then return
end s()local r=(MSUF_DB and MSUF_DB.player)or{}if r.showInterrupt==false then
e:SetScript("OnUpdate",nil)e.interruptFeedbackEndTime=nil
if e.timeText then MSUF_SetTextIfChanged(e.timeText,"")end if e.statusBar and e.statusBar.SetValue then e.statusBar:SetValue(0)end
e:Hide()return
end if e.hideTimer then
e.hideTimer:Cancel()e.hideTimer=nil
end e:SetScript("OnUpdate",nil)if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end e.MSUF_durationObj=nil
e.MSUF_channelDirect=nil e.MSUF_timerDriven=nil
e.MSUF_timerRangeSet=nil if _G.MSUF_ClearCastbarTimerDuration and e.statusBar then
_G.MSUF_ClearCastbarTimerDuration(e.statusBar)end
e._msufActiveCastUnit=nil e._msufActiveCastGUID=nil
e._msufActiveSpellID=nil e._msufActiveCastBarID=nil
e._msufChanNilSince=nil e.interruptFeedbackEndTime=GetTime()+t
local r=_G.MSUF_GetReverseFillSafe and _G.MSUF_GetReverseFillSafe(e,false)or false _G.MSUF_ApplyInterruptBarVisuals(e,{barValue=1,colorR=0.8,colorG=0.1,colorB=0.1,reverseFill=r,label=n or INTERRUPTED,})local n=t
if type(n)~='number'then n=0.5 end if n<0 then n=0 end
e.hideTimer=C_Timer.NewTimer(n,T)e.hideTimer.msuCastbarFrame=e
end local function d(e)local e=(e and e.unit)or"player"if e=="player"and type(UnitHasVehicleUI)=="function"and UnitHasVehicleUI("player")then
if type(UnitExists)=="function"and UnitExists("vehicle")then if(type(UnitCastingInfo)=="function"and UnitCastingInfo("vehicle"))or(type(UnitChannelInfo)=="function"and UnitChannelInfo("vehicle"))then return"vehicle"end end
end return e
end local function s(e)if not e then return end e._msufActiveCastGUID=nil
e._msufActiveSpellID=nil e._msufActiveCastBarID=nil
end local function i(e,n,r,t)if not e then return end e._msufActiveCastGUID=n
e._msufActiveSpellID=r e._msufActiveCastBarID=t
end local function a(e,n)if not e then return false end if not n then return true end
if not e._msufActiveCastUnit then return true end return n==e._msufActiveCastUnit
end local function u(e,n)if not e then return false end if not n then return true end
if not e._msufActiveCastBarID then return true end return n==e._msufActiveCastBarID
end local function c(e,n,r,t)if not e then return false end if t and e._msufActiveCastBarID and t~=e._msufActiveCastBarID then
return true end
if n and e._msufActiveCastGUID and n~=e._msufActiveCastGUID then return true
end if r and e._msufActiveSpellID and r~=e._msufActiveSpellID then
return true end
return false end
local function h(e)if not e then return end
e.endTime=nil e._msufPlainEndTime=nil
e._msufPlainTotal=nil e._msufRemaining=nil
e._msufLastTimeDecimal=nil e._msufZeroCount=nil
e._msufLastDurationObj=nil e._msufTimerAssumeCountdown=nil
end local function p(e,t,n)if not e then return end h(e)t=l(t)n=l(n)local r=GetTime()if type(n)=="number"then
local n=n/1000 local t=n-r
e.endTime=n if type(t)=="number"and t>0 then
e._msufPlainEndTime=n e._msufRemaining=t
end end
if type(t)=="number"and type(n)=="number"then local n=(n-t)/1000
if type(n)=="number"and n>0 then e._msufPlainTotal=n
end end
end local function F(e,t,n,r)if not(e and e.statusBar and e.statusBar.SetMinMaxValues and e.statusBar.SetValue)then return end local t=l(t)or 0
local n=l(n)or t if t<0 then t=0 end
if n<0 then n=0 end if n>t then n=t end
local t=t if t<=0 then t=0.001 end
e.statusBar:SetMinMaxValues(0,t)if r then
e.statusBar:SetValue(n)else
e.statusBar:SetValue(t-n)end
end local function B(e)local n=_G.issecretvalue if type(n)=="function"and n(e)==true then
local t=_G.ToPlain if type(t)~="function"then return false end
local r=t(e)if type(n)=="function"and n(r)==true then return false end
e=r
end
if e==nil then return false end
return e==true
end local function _(e,c,_,s,T,h,d,u,C,f,a,n,t)local r=(_=="CHANNEL")e.interruptFeedbackEndTime=nil
e.interrupted=nil e.MSUF_castActive=true
e._msufActiveCastUnit=c e._msufChanNilSince=nil
e._msufCastNilSince=nil e._msufHardStopNilSince=nil
i(e,r and nil or a,f,n)e.MSUF_castDuration=r and nil or t
e.MSUF_channelDuration=r and t or nil e.MSUF_channelTotal=nil
local i=_G.MSUF_GetReverseFillSafe(e,r)local a=false
if t then local n=e._msufPlayerState or{}e._msufPlayerState=n n.active=true
n.unit=c n.castType=_
n.spellName=s n.text=T or s
n.icon=h n.spellId=f
n.startTimeMS=d n.endTimeMS=u
n.durationObj=t n.reverseFill=i
a=_G.MSUF_Castbar_ApplyActiveDuration(e,n,{skipColor=true,skipRegister=true,skipTimeText=true,skipShow=true,})and true or false
else e.MSUF_durationObj=nil
e.MSUF_isChanneled=r e.MSUF_timerDriven=nil
if e.icon then e.icon:SetTexture(h or nil)end if e.castText then if type(_G.MSUF_CB_ApplyTexts)=="function"then _G.MSUF_CB_ApplyTexts(e,nil,s or"",nil)else MSUF_SetTextIfChanged(e.castText,s or"")end end
end e._msufStripeReverseFill=(i and true or false)if r then e.MSUF_channelDirect=nil
else S(e)end local n=(e.isNotInterruptible==true)if B(C)then n=true end e.isNotInterruptible=n
p(e,d,u)if(not a)and e._msufPlainTotal and e._msufRemaining then
F(e,e._msufPlainTotal,e._msufRemaining,i)end
o(e)local n=nil
if t and t.GetTotalDuration then n=l(t:GetTotalDuration())end if(not r)and n==nil and t and t.GetRemainingDuration then
n=l(t:GetRemainingDuration())end
if n==nil then n=e._msufPlainTotal end if r then
e.MSUF_channelTotal=n end
U(e,r,n)e:SetScript("OnUpdate",nil)e.MSUF_durationObj=t e.MSUF_timerDriven=a and true or nil
MSUF_EnsureCastbarManager()if MSUF_RegisterCastbar then
MSUF_RegisterCastbar(e)end
if _G.MSUF_UpdateCastbarFrame then local n=(GetTimePreciseSec and GetTimePreciseSec())or GetTime()_G.MSUF_UpdateCastbarFrame(e,0,n)end
e:Show()if r then
M(e,true)end
end local n={UNIT_SPELLCAST_START=true,UNIT_SPELLCAST_INTERRUPTIBLE=true,UNIT_SPELLCAST_NOT_INTERRUPTIBLE=true,UNIT_SPELLCAST_SENT=true,}local i={UNIT_SPELLCAST_STOP=true,UNIT_SPELLCAST_CHANNEL_STOP=true,}local l={UNIT_SPELLCAST_CHANNEL_START=true,}local function t(e,r)if not e or not e.unit or not e.statusBar then return end
if e.isEmpower then return end local a=n
local i=i local u=l
local n=d(e)if r=="UNIT_SPELLCAST_INTERRUPTIBLE"then e.isNotInterruptible=false elseif r=="UNIT_SPELLCAST_NOT_INTERRUPTIBLE"then e.isNotInterruptible=true elseif r=="UNIT_SPELLCAST_START"or r=="UNIT_SPELLCAST_SENT"or r=="UNIT_SPELLCAST_CHANNEL_START"then e.isNotInterruptible=false end if a[r]then
local r,d,u,f,s,c,o,l,i,a=UnitCastingInfo(n)if not r then
if UnitChannelInfo(n)then return t(e,"UNIT_SPELLCAST_CHANNEL_START")end return t(e,"UNIT_SPELLCAST_STOP")end local t=nil
if type(UnitCastingDuration)=="function"then t=UnitCastingDuration(n)end _(e,n,"CAST",r,d,u,f,s,l,i,o,a,t)return end
if u[r]then local r,s,o,u,a,f,d,l,f,f,i=UnitChannelInfo(n)if not r then if UnitCastingInfo(n)then
return t(e,"UNIT_SPELLCAST_START")end
return t(e,"UNIT_SPELLCAST_STOP")end
local t=nil if type(UnitChannelDuration)=="function"then
t=UnitChannelDuration(n)end
_(e,n,"CHANNEL",r,s,o,u,a,d,l,nil,i,t)return
end if i[r]then
e._msufChanNilSince=nil e._msufCastNilSince=nil
e._msufHardStopNilSince=nil e.MSUF_channelDuration=nil
e.MSUF_castDuration=nil e.MSUF_channelTotal=nil
h(e)s(e)e._msufActiveCastUnit=nil S(e)if _G.MSUF_CB_ResetStateOnStop then _G.MSUF_CB_ResetStateOnStop(e,"STOPPED")else e:SetScript("OnUpdate",nil)if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end if e.latencyBar then e.latencyBar:Hide()end
if e.timeText then MSUF_SetTextIfChanged(e.timeText,"")end e:Hide()end if e.statusBar and e.statusBar.SetValue then e.statusBar:SetValue(0)end
return end
end local function i(e)if not e or not e.unit or not e.statusBar then return end if e.isEmpower then return end
if e.MSUF_testMode then return end local n=d(e)if UnitCastingInfo(n)then t(e,"UNIT_SPELLCAST_START")elseif UnitChannelInfo(n)then t(e,"UNIT_SPELLCAST_CHANNEL_START")else t(e,"UNIT_SPELLCAST_STOP")end end
local function l(e)if not e then return end
local n=(e._msufSoftResyncToken or 0)+1 e._msufSoftResyncToken=n
if C_Timer and C_Timer.After then C_Timer.After(0,function()if not e or e._msufSoftResyncToken~=n then return end if e.isEmpower or e.MSUF_testMode then return end
i(e)end)else i(e)end end
local function _(e,n,...)if not MSUF_IsCastbarEnabledForUnit("player")then
e:SetScript("OnUpdate",nil)if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(e)end
e.interruptFeedbackEndTime=nil s(e)e._msufActiveCastUnit=nil if e.timeText then
MSUF_SetTextIfChanged(e.timeText,"")end
if e.latencyBar then e.latencyBar:Hide()end e:Hide()return end
if e.MSUF_testMode then return
end local r=select(1,...)if n=="UNIT_SPELLCAST_EMPOWER_START"or n=="UNIT_SPELLCAST_EMPOWER_UPDATE"then m(e,select(3,...))return elseif n=="UNIT_SPELLCAST_EMPOWER_STOP"then
f(e,true)return
end if e.isEmpower then
if n=="UNIT_SPELLCAST_INTERRUPTED"then if type(_G.MSUF_PlayerCastbar_ShowInterruptFeedback)=="function"then
_G.MSUF_PlayerCastbar_ShowInterruptFeedback(e,"Interrupted")else
f(e,true)end
return elseif n=="UNIT_SPELLCAST_STOP"or n=="UNIT_SPELLCAST_FAILED"or n=="UNIT_SPELLCAST_SUCCEEDED"then
f(e,true)return
end end
if n=="UNIT_SPELLCAST_INTERRUPTED"then if not a(e,r)then
return end
local t=select(2,...)local n=select(3,...)local r=select(5,...)if c(e,t,n,r)then
return end
s(e)C(e,INTERRUPTED)return end
if not e.isEmpower then if n=="UNIT_SPELLCAST_START"or n=="UNIT_SPELLCAST_SENT"or n=="UNIT_SPELLCAST_CHANNEL_START"or n=="UNIT_SPELLCAST_INTERRUPTIBLE"or n=="UNIT_SPELLCAST_NOT_INTERRUPTIBLE"then
t(e,n)return
elseif n=="UNIT_SPELLCAST_CHANNEL_UPDATE"or n=="UNIT_SPELLCAST_DELAYED"then if not a(e,r)then
return end
local n=select(4,...)if not u(e,n)then return end
i(e)return
elseif n=="UNIT_SPELLCAST_STOP"then if not a(e,r)then
return end
local r=select(4,...)if not u(e,r)then return end
t(e,n)return
elseif n=="UNIT_SPELLCAST_CHANNEL_STOP"then if not a(e,r)then
return end
local n=select(5,...)if not u(e,n)then return end
l(e)return
elseif n=="UNIT_SPELLCAST_FAILED"then if not a(e,r)then
return end
local n=select(2,...)local t=select(3,...)local r=select(4,...)if c(e,n,t,r)then
return end
l(e)return
end end
if n=="UNIT_SPELLCAST_INTERRUPTIBLE"then e.isNotInterruptible=false
o(e)return
elseif n=="UNIT_SPELLCAST_NOT_INTERRUPTIBLE"then e.isNotInterruptible=true
o(e)return
end end
_G.MSUF_PlayerCastbar_UpdateLatencyZone=U _G.MSUF_PlayerCastbar_UpdateColorForInterruptible=o
_G.MSUF_GetInterruptFeedbackColor=I _G.MSUF_PlayerCastbar_HideIfNoLongerCasting=T
_G.MSUF_PlayerCastbar_ShowInterruptFeedback=C _G.MSUF_PlayerCastbar_GetEffectiveUnit=d
_G.MSUF_PlayerCastbar_UnhaltedUpdate=t _G.MSUF_PlayerCastbar_Cast=i
_G.MSUF_PlayerCastbar_OnEvent=_
