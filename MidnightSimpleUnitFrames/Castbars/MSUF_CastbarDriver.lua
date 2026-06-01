local e,e=...local n=GetTime
local e=math.floor local i=_G.C_Timer and _G.C_Timer.NewTicker
local r local function a(e,t)if not e or not e.unit then return end if not e:IsShown()then
if r then r(e,false)else e:SetScript("OnUpdate",nil)end return
end if e.interrupted then return end
local n=n()local t=e._msufSafetyNext or 0
if n<t then return end e._msufSafetyNext=n+0.25
local t=e.unit if not UnitExists(t)or(UnitIsDeadOrGhost and UnitIsDeadOrGhost(t))then
if r then r(e,false)else e:SetScript("OnUpdate",nil)end _G.MSUF_CB_ResetStateOnStop(e,"STOPPED")return end
local t=e._msufPlainEndTime if t then
local n=t-n if n<=0 then
e._msufZeroCount=(e._msufZeroCount or 0)+1 if e._msufZeroCount>=2 then
e._msufZeroCount=nil if r then r(e,false)else e:SetScript("OnUpdate",nil)end
if e.SetSucceeded then e:SetSucceeded()else _G.MSUF_CB_ResetStateOnStop(e,"STOPPED")end end
else e._msufZeroCount=nil
end end
end r=function(e,n)if not e then return end if n then
e:SetScript("OnUpdate",nil)if e._msufSafetyTicker then return end
e._msufSafetyNext=0 if i then
e._msufSafetyTicker=i(0.25,function()a(e,0.25)end)else
e:SetScript("OnUpdate",a)end
else if e._msufSafetyTicker and e._msufSafetyTicker.Cancel then
e._msufSafetyTicker:Cancel()end
e._msufSafetyTicker=nil e._msufSafetyNext=nil
e:SetScript("OnUpdate",nil)end
end _G.MSUF_INTERRUPT_FEEDBACK_DURATION=_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5
local function S(e)e=e or""local n=_G.MSUF_IsCastbarEnabledForUnit if type(n)=="function"then
local e=n(e)if e~=nil then
return e end
end if type(_G.MSUF_EnsureDBLazy)=="function"then
_G.MSUF_EnsureDBLazy()elseif type(_G.MSUF_EnsureDB)=="function"then
_G.MSUF_EnsureDB()end
local n=(_G.MSUF_DB and _G.MSUF_DB.general)or nil if not n then
return true end
local t=_G.MSUF_ShouldUseMSUFCastbar if type(t)=="function"then
return t(e,n)==true end
if e=="player"then return n.enablePlayerCastbar~=false
elseif e=="target"then return n.enableTargetCastbar~=false
elseif e=="focus"then return n.enableFocusCastbar~=false
else return true
end end
local t={"UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_DELAYED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_CHANNEL_UPDATE","UNIT_SPELLCAST_EMPOWER_START","UNIT_SPELLCAST_EMPOWER_STOP","UNIT_SPELLCAST_EMPOWER_UPDATE","UNIT_SPELLCAST_INTERRUPTIBLE","UNIT_SPELLCAST_NOT_INTERRUPTIBLE","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_INTERRUPTED",}local function d(e,n,r)if not e then return end
if r then if e._msufDriverEventsRegistered then return end
for r=1,#t do e:RegisterUnitEvent(t[r],n)end if n=="target"or n=="focus"then
e:RegisterEvent("PLAYER_"..n:upper().."_CHANGED")end
e._msufDriverEventsRegistered=true return
end if not e._msufDriverEventsRegistered then return end
for n=1,#t do e:UnregisterEvent(t[n])end if n=="target"or n=="focus"then
e:UnregisterEvent("PLAYER_"..n:upper().."_CHANGED")end
e._msufDriverEventsRegistered=nil end
local function o(n)local e=_G.MSUF_PlayerChannelHasteMarkers_Hide if type(e)=="function"then e(n)end
end local function h(n,t)local e=_G.MSUF_PlayerChannelHasteMarkers_Update if type(e)=="function"then e(n,t)end
end local t=_G.ToPlain
local function n(e)if e==nil then return nil end
if t then local e=t(e)local e=tonumber(tostring(e))if e~=nil then
return e end
end local n=type(e)if n=="number"or n=="string"then return tonumber(tostring(e))end return nil
end local function a(i)local t=i and i.statusBar if not(t and t.GetValue and t.GetMinMaxValues)then return nil end
local e=t:GetValue()local r,t=t:GetMinMaxValues()e=n(e)r=n(r)t=n(t)if not(e and r and t)then return nil end
local n=t-r if not(type(n)=="number"and n>0)then return nil end
local n=i._msufLastSBValue i._msufLastSBValue=e
local n=(n~=nil and e<(n-0.0001))local e=n and(e-r)or(t-e)if type(e)~="number"then return nil end if e<0 then e=0 end
return e end
function _G.MSUF_UpdateCastTimeText_FromStatusBar(e)if not(e and e.timeText)then return end
if not(type(MSUF_IsCastTimeEnabled)=="function"and MSUF_IsCastTimeEnabled(e))then MSUF_SetTextIfChanged(e.timeText,"")return end
local i=a(e)if type(i)=="number"then
local r if e._msufPlainTotal then
r=e._msufPlainTotal elseif e.statusBar and e.statusBar.GetMinMaxValues then
local t,e=e.statusBar:GetMinMaxValues()t=n(t)or 0
e=n(e)if e and e>t then r=e-t end
end MSUF_SetCastTimeText(e,i,r)else MSUF_SetTextIfChanged(e.timeText,"")end end
local C=_G.MSUF_ClearEmpowerState local function T(e,a)local t=CreateFrame("Frame",e,UIParent)t:SetClampedToScreen(true)t.unit=a t.reverseFill=false
function t:UpdateColorForInterruptible()if not self or not self.statusBar or not self.statusBar.SetStatusBarColor then
return end
if not MSUF_DB then EnsureDB()end local e=(self.isNotInterruptible==true)local _,n,l,t,r,i=_G.MSUF_ResolveCastbarColors()local a=self._msufApiNotInterruptibleRaw
if e then a=true
end if type(_G.MSUF_Castbar_ApplyNonInterruptibleTint)=="function"then
_G.MSUF_Castbar_ApplyNonInterruptibleTint(self,a,t,r,i,1,_,n,l,1,e)else
if e then _G.MSUF_SetStatusBarColorIfChanged(self.statusBar,t,r,i,1)else _G.MSUF_SetStatusBarColorIfChanged(self.statusBar,_,n,l,1)end end
end local function i(n)local e=(_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine())or nil if e and e.BuildState then
return e:BuildState(n.unit,n)end
return nil end
local function s(e,n)if not e then return end
if n and n.active then e._msufActiveSeq=n.spellSequenceID
e._msufActiveCastType=n.castType else
e._msufActiveSeq=nil e._msufActiveCastType=nil
end end
local function f(e,n)if not e then return false end
if n==nil then return false end local e=e._msufActiveSeq
if e==nil then return false end if type(n)~='number'or type(e)~='number'then return false end
return e~=n end
local function _(e)if e.interrupted then
return end
local n=i(e)s(e,n)e:Cast(n)end
local function l(n)if not n then return end
local e e=n._msufStopTimer1;if e and e.Cancel then e:Cancel()end;n._msufStopTimer1=nil
e=n._msufStopTimer2;if e and e.Cancel then e:Cancel()end;n._msufStopTimer2=nil e=n._msufStopTimer3;if e and e.Cancel then e:Cancel()end;n._msufStopTimer3=nil
end local function u(e)if not e then return end local n=e._msufStartRetryTimer
if n and n.Cancel then n:Cancel()end e._msufStartRetryTimer=nil
e._msufStartRetryPending=nil end
local function c(e)if e._msufDriverCBReady then return end
e._msufDriverCBReady=true local function t()if not e or e.interrupted then return true end return(e._msufCastToken or 0)~=(e._msufStopExpToken or 0)end e._msufStopCB_chanT1=function()if t()then return end local n=i(e)if n and n.active then s(e,n);e:Cast(n);return end if f(e,e._msufStopExpSeq)then
_(e);return end
e._msufStopTimer2=C_Timer.NewTimer(e._msufStopT2 or 0.08,e._msufStopCB_chanT2)end
e._msufStopCB_chanT2=function()if t()then return end
local n=i(e)if n and n.active then s(e,n);e:Cast(n);return end
if f(e,e._msufStopExpSeq)then _(e);return
end e:SetSucceeded()end e._msufStopCB_failsafe=function()if t()then return end local n=i(e)if n and n.active then s(e,n);e:Cast(n);return
end if f(e,e._msufStopExpSeq)then
_(e);return end
e:SetSucceeded()end
e._msufStopCB_castT1=function()if t()then return end
local n=i(e)if n and n.active then
s(e,n);e:Cast(n)else
if f(e,e._msufStopExpSeq)then _(e);return
end e:SetSucceeded()end end
e._msufStartRetryCB=function()e._msufStartRetryPending=nil
e._msufStartRetryTimer=nil if not e or e.interrupted then return end
if(e._msufCastToken or 0)~=(e._msufStartRetryToken or 0)then return end local n=i(e)if n and n.active then s(e,n);e:Cast(n)end end
e._msufDeathRecheckCB=function()e._msufDeathRecheckPending=nil
if not e:IsShown()or e.interrupted then return end local n=e.unit
if n and(not UnitExists(n)or(UnitIsDeadOrGhost and UnitIsDeadOrGhost(n)))then r(e,false)l(e)u(e)o(e)_G.MSUF_CB_ResetStateOnStop(e,"STOPPED")end end
end local function f(e)e._msufCastToken=(e._msufCastToken or 0)+1 return e._msufCastToken
end local function T(e,i)if not e or e.interrupted then return end local r=e._msufCastToken or 0
local n=e._msufActiveSeq l(e)c(e)e._msufStopExpToken=r
e._msufStopExpSeq=n if i=="CHANNEL"then
local n=0 if GetCVar then n=tonumber(GetCVar("SpellQueueWindow")or"0")or 0 end
if n<0 then n=0 end local n=(n/1000)+0.08
if n<0.20 then n=0.20 end if n>0.70 then n=0.70 end
local t=0.12 if t>n then t=n end
local r=n-t if r<0.08 then r=0.08 end
local n=n+0.55 if n<0.70 then n=0.70 end
if n>1.20 then n=1.20 end e._msufStopT2=r
e._msufStopTimer1=C_Timer.NewTimer(t,e._msufStopCB_chanT1)e._msufStopTimer3=C_Timer.NewTimer(n,e._msufStopCB_failsafe)return end
e._msufStopTimer1=C_Timer.NewTimer(0.12,e._msufStopCB_castT1)e._msufStopTimer3=C_Timer.NewTimer(0.40,e._msufStopCB_failsafe)end t:SetScript("OnEvent",function(e,n,t,...)local a,a=...if not S(e.unit or"")then
if e.unit=="target"or e.unit=="focus"then d(e,e.unit,false)end r(e,false)l(e)u(e)o(e)_G.MSUF_CB_ResetStateOnStop(e,"HARDHIDE")if _G.MSUF_UnregisterCastbar then _G.MSUF_UnregisterCastbar(e)end return
end if n=="UNIT_HEALTH"then
if e:IsShown()and not e.interrupted then local n=e.unit
if n and(not UnitExists(n)or(UnitIsDeadOrGhost and UnitIsDeadOrGhost(n)))then r(e,false)l(e)u(e)o(e)_G.MSUF_CB_ResetStateOnStop(e,"STOPPED")return end
if not e._msufDeathRecheckPending then c(e)e._msufDeathRecheckPending=true C_Timer.After(0.1,e._msufDeathRecheckCB)end end
return end
if e.unit=="player"then if n=="UNIT_SPELLCAST_EMPOWER_START"or n=="UNIT_SPELLCAST_EMPOWER_UPDATE"then
e.MSUF_wantsEmpower=true elseif n=="UNIT_SPELLCAST_EMPOWER_STOP"then
e.MSUF_wantsEmpower=nil elseif n=="UNIT_SPELLCAST_START"or n=="UNIT_SPELLCAST_CHANNEL_START"then
e.MSUF_wantsEmpower=nil end
else e.MSUF_wantsEmpower=nil
if n=="UNIT_SPELLCAST_EMPOWER_START"then n="UNIT_SPELLCAST_START"elseif n=="UNIT_SPELLCAST_EMPOWER_UPDATE"then n="UNIT_SPELLCAST_DELAYED"elseif n=="UNIT_SPELLCAST_EMPOWER_STOP"then n="UNIT_SPELLCAST_STOP"end end
if n=="UNIT_SPELLCAST_START"or n=="UNIT_SPELLCAST_CHANNEL_START"or n=="UNIT_SPELLCAST_EMPOWER_START"then l(e)u(e)local t=f(e)e.isNotInterruptible=false e.MSUF_kickInterruptibleConfirmed=nil
_(e)local n=i(e)if not(n and n.active and n.spellName)then c(e)e._msufStartRetryToken=t if not e._msufStartRetryPending then
e._msufStartRetryPending=true e._msufStartRetryTimer=C_Timer.NewTimer(0.05,e._msufStartRetryCB)end end
elseif n=="UNIT_SPELLCAST_DELAYED"or n=="UNIT_SPELLCAST_CHANNEL_UPDATE"or n=="UNIT_SPELLCAST_EMPOWER_UPDATE"then if n=="UNIT_SPELLCAST_CHANNEL_UPDATE"and(e._msufStopTimer1 or e._msufStopTimer2 or e._msufStopTimer3)then
l(e)f(e)end _(e)elseif n=="UNIT_SPELLCAST_STOP"or n=="UNIT_SPELLCAST_EMPOWER_STOP"then e.MSUF_kickInterruptibleConfirmed=nil
T(e,"CAST")elseif n=="UNIT_SPELLCAST_CHANNEL_STOP"then
e.MSUF_kickInterruptibleConfirmed=nil T(e,"CHANNEL")elseif n=="UNIT_SPELLCAST_FAILED"then e.MSUF_kickInterruptibleConfirmed=nil
T(e,"CAST")elseif n=="UNIT_SPELLCAST_SUCCEEDED"then
if e.unit~="player"then _(e)else local n=i(e)if n and n.active then s(e,n)e:Cast(n)end
end elseif n=="UNIT_SPELLCAST_INTERRUPTIBLE"then
if t~=e.unit then return end e.isNotInterruptible=false
e.MSUF_kickInterruptibleConfirmed=true e._msufApiNotInterruptibleRaw=false
if e.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(e)end if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(e,nil)end
elseif n=="UNIT_SPELLCAST_NOT_INTERRUPTIBLE"then if t~=e.unit then return end
e.isNotInterruptible=true e.MSUF_kickInterruptibleConfirmed=false
e._msufApiNotInterruptibleRaw=true if e.UpdateColorForInterruptible then _G.MSUF_CB_ApplyColor(e)end
if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(e,nil)end elseif n=="UNIT_SPELLCAST_INTERRUPTED"then
if t~=e.unit then return end l(e)e.MSUF_kickInterruptibleConfirmed=nil e:SetInterrupted()elseif(n=="PLAYER_TARGET_CHANGED"and e.unit=="target")or(n=="PLAYER_FOCUS_CHANGED"and e.unit=="focus")then l(e)u(e)f(e)if e.timer then e.timer:Cancel()e.timer=nil end
e.interrupted=nil e.MSUF_kickInterruptibleConfirmed=nil
_(e)end
end)local function u(e)if type(_G.MSUF_BuildCastbarFrameElements)=="function"then return _G.MSUF_BuildCastbarFrameElements(e)end if MSUF_DevPrint then MSUF_DevPrint("MSUF: MSUF_BuildCastbarFrameElements missing")end
end function t:Cast(e)local e=e if not(e and e.active and e.unit==self.unit and e.spellName)then
local n=_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine()if n and n.BuildState then
e=n:BuildState(self.unit,self)else
e=nil end
end local n=nil
if e~=nil then n=e.apiNotInterruptibleRaw
end self._msufApiNotInterruptibleRaw=n
local t,l,a,n,s local _=false
if e and e.active and e.spellName then t=e.spellName
l=e.text or e.spellName a=e.icon
n=e.startTimeMS s=e.endTimeMS
_=(e.castType=="CHANNEL")end
if e and e.active then self._msufCastSpellID=e.spellId
self._msufCastSpellSeq=e.spellSequenceID end
if self.hideTimer and self.hideTimer.Cancel then self.hideTimer:Cancel()self.hideTimer=nil end
if self.succeededTimer and self.succeededTimer.Cancel then self.succeededTimer:Cancel()self.succeededTimer=nil end
local n=(e and e.durationObj~=nil)and e.durationObj or nil if(n==nil)and e and e.active then
local t=e.spellSequenceID if type(t)=="number"and self._msufLastDurationSeq==t and self._msufLastDurationObj~=nil then
n=self._msufLastDurationObj e.durationObj=n
end end
if e and e.active and n~=nil then local e=e.spellSequenceID
if type(e)=="number"then self._msufLastDurationSeq=e
self._msufLastDurationObj=n end
elseif not(e and e.active)then self._msufApiNotInterruptibleRaw=nil
self._msufLastDurationSeq=nil self._msufLastDurationObj=nil
end if self.isEmpower then
C(self)end
if t and n then e.durationObj=n
e.text=l or t e.icon=a
_G.MSUF_Castbar_ApplyActiveDuration(self,e,{skipColor=true,skipRegister=true,skipTimeText=true,skipShow=true,})local n=_G.MSUF_GetReverseFillSafe(self,_)self._msufStripeReverseFill=n
h(self,true)if self.UpdateColorForInterruptible then
_G.MSUF_CB_ApplyColor(self)end
if MSUF_RegisterCastbar then MSUF_RegisterCastbar(self)end if self.timeText then
_G.MSUF_UpdateCastTimeText_FromStatusBar(self)end
self:Show()self.MSUF_castActive=true
if _G.MSUF_KickReady_RefreshFrame then if _G.C_Timer and _G.C_Timer.After then
if not self._msufKickReadyDeferredCB then self._msufKickReadyDeferredCB=function()if self and self.MSUF_castActive==true and _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(self,nil)end end
end _G.C_Timer.After(0,self._msufKickReadyDeferredCB)else _G.MSUF_KickReady_RefreshFrame(self,e)end end
if self.unit~="player"then self._msufZeroCount=nil
r(self,true)end
else r(self,false)self.MSUF_castActive=false self.MSUF_kickInterruptibleConfirmed=nil
if self.kickReadyBox then self.kickReadyBox:Hide()end if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(self,nil)end
if self.hideTimer and self.hideTimer.Cancel then self.hideTimer:Cancel()end self.hideTimer=C_Timer.NewTimer(0,function()if not self or not self.unit then return end local e=i(self)if e and e.active then self:Cast(e)return end
_G.MSUF_CB_ResetStateOnStop(self,"STOPPED")end)end if self.timer then
self.timer:Cancel()self.timer=nil
end local e=(_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)if type(e)~="number"then e=0.5 end if e<0 then e=0 end
self.timer=C_Timer.NewTimer(e,function()if self.interrupted then
self.interrupted=nil self:Hide()end end)end function t:SetInterrupted()o(self)r(self,false)_G.MSUF_CB_ResetStateOnStop(self,"INTERRUPTED")self.interrupted=true
self._msufApiNotInterruptibleRaw=nil self.MSUF_castActive=false
self.MSUF_kickInterruptibleConfirmed=nil if self.kickReadyBox then self.kickReadyBox:Hide()end
if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(self,nil)end if type(_G.MSUF_EnsureDBLazy)=="function"then _G.MSUF_EnsureDBLazy()end
local e=(self.unit and MSUF_DB and MSUF_DB[self.unit])or nil if e and e.showInterrupt==false then
self.interrupted=nil if self.castText then
_G.MSUF_CB_ApplyTexts(self,nil,"",nil)end
if self.timeText then _G.MSUF_CB_ApplyTexts(self,nil,nil,"")end self:Hide()return end
local e=_G.MSUF_GetReverseFillSafe(self,false)_G.MSUF_ApplyInterruptBarVisuals(self,{barValue=1,colorR=1,colorG=0,colorB=0,reverseFill=e,label="Interrupted",})local n=(_G.MSUF_INTERRUPT_FEEDBACK_DURATION or 0.5)if type(n)~="number"then n=0.5 end if n<0 then n=0 end
if self._msufCastState then local t=(type(GetTime)=="function")and GetTime()or 0
local e=self._msufCastState e.unit=self.unit
e.key=self._msufBarKey or self.unit e.active=false
e.phase="INTERRUPT"e.durationObj=nil
e.holdUntil=t+n end
self.hideTimer=C_Timer.NewTimer(n,function()if not self or not self.unit then return end
local e=i(self)if e and e.active then
self.interrupted=nil self:Cast(e)return end
if self.interrupted then self.interrupted=nil
self:Hide()end
end)end
function t:SetSucceeded()o(self)if self.interrupted then return
end r(self,false)_G.MSUF_CB_ResetStateOnStop(self,"SUCCEEDED")end
d(t,a,true)local e=_G["MSUF_"..a]if e then t:ClearAllPoints()if a=="target"then t:SetPoint("BOTTOMLEFT",e,"TOPLEFT",0,5)elseif a=="focus"then t:SetPoint("TOPLEFT",e,"BOTTOMLEFT",0,-5)elseif a=="player"then t:SetPoint("BOTTOM",e,"TOP",0,5)else t:SetPoint("CENTER",UIParent,"CENTER",0,-300)end local e=e:GetWidth()if e and e>0 then t:SetWidth(e)end end
u(t)t:Hide()if a=="target"then MSUF_TargetCastbar=t
_G.MSUF_TargetCastBar=t elseif a=="focus"then
MSUF_FocusCastbar=t _G.MSUF_FocusCastBar=t
elseif a=="player"then MSUF_PlayerCastbar=t
_G.MSUF_PlayerCastBar=t end
return t end
function MSUF_EnsureCastbarManager()if MSUF_CastbarManager and MSUF_RegisterCastbar and MSUF_UnregisterCastbar and MSUF_UpdateCastbarFrame then
return end
end MSUF_PlayerCastbar=MSUF_PlayerCastbar or nil
local function i(e)if not S(e)then
return nil end
if e=="target"then if not _G["TargetCastBar"]then
return T("TargetCastBar","target")end
return _G["TargetCastBar"]elseif e=="focus"then
if not _G["FocusCastBar"]then return T("FocusCastBar","focus")end return _G["FocusCastBar"]end return nil
end local function n(e,t)local n=e and e[t]if n and n.Cancel then
n:Cancel()end
if e then e[t]=nil
end end
local function a(e)if not e then return end
r(e,false)n(e,"timer")n(e,"hideTimer")n(e,"_msufStopTimer1")n(e,"_msufStopTimer2")n(e,"_msufStopTimer3")n(e,"_msufStartRetryTimer")e._msufStartRetryPending=nil
e._msufDeathRecheckPending=nil e.MSUF_castActive=false
e.interrupted=nil e.MSUF_kickInterruptibleConfirmed=nil
o(e)if _G.MSUF_CB_ResetStateOnStop then
_G.MSUF_CB_ResetStateOnStop(e,"HARDHIDE")elseif e.Hide then
e:Hide()end
if _G.MSUF_UnregisterCastbar then _G.MSUF_UnregisterCastbar(e)end if e.SetScript then
e:SetScript("OnUpdate",nil)end
if e.Hide then e:Hide()end end
local function r(e)if e=="target"then
return _G.TargetCastBar or _G.MSUF_TargetCastBar or _G.MSUF_TargetCastbar elseif e=="focus"then
return _G.FocusCastBar or _G.MSUF_FocusCastBar or _G.MSUF_FocusCastbar end
return nil end
local function t(n)if n~="target"and n~="focus"then return nil end
local t=S(n)local e=r(n)if t then e=e or i(n)if e then d(e,n,true)end return e
end if e then
d(e,n,false)a(e)end return nil
end function MSUF_CastbarDriver_OnLogin(e)t("target")t("focus")if MSUF_ReanchorTargetCastBar then MSUF_ReanchorTargetCastBar()end if MSUF_ReanchorFocusCastBar then MSUF_ReanchorFocusCastBar()end
if MSUF_ReanchorPlayerCastBar then MSUF_ReanchorPlayerCastBar()end if MSUF_UpdateCastbarVisuals then MSUF_UpdateCastbarVisuals()end
if MSUF_UpdateCastbarTextures then MSUF_UpdateCastbarTextures()end end
function MSUF_CastbarDriver_OnEnteringWorld(e)t("target")t("focus")if PetCastingBarFrame then
PetCastingBarFrame:UnregisterAllEvents()PetCastingBarFrame:Hide()PetCastingBarFrame:HookScript("OnShow",function(e)e:Hide()end)end
if MSUF_EventBus_Unregister then MSUF_EventBus_Unregister("PLAYER_ENTERING_WORLD","MSUF_CASTBAR_DRIVER_WORLD")end end
MSUF_EventBus_Register("PLAYER_LOGIN","MSUF_CASTBAR_DRIVER_LOGIN",MSUF_CastbarDriver_OnLogin,nil,true)MSUF_EventBus_Register("PLAYER_ENTERING_WORLD","MSUF_CASTBAR_DRIVER_WORLD",MSUF_CastbarDriver_OnEnteringWorld)_G.MSUF_CreateCastBar=T _G.MSUF_CastbarDriver_EnsureUnit=i
_G.MSUF_CastbarDriver_ApplyBackendState=t
