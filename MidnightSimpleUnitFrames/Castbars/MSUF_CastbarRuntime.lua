local n,e=...e=e or{}local n=e.MSUF_CastbarRuntime or{}e.MSUF_CastbarRuntime=n
_G.MSUF_CastbarRuntime=n local t=_G.Enum and _G.Enum.StatusBarInterpolation
local e=_G.Enum and _G.Enum.StatusBarTimerDirection local l=(type(t)=="table"and type(t.Immediate)=="number")and t.Immediate or nil
local a=(type(e)=="table"and type(e.ElapsedTime)=="number")and e.ElapsedTime or nil local S=(type(e)=="table"and type(e.RemainingTime)=="number")and e.RemainingTime or nil
local p="SUCCEEDED"local m="FAILED"local h="INTERRUPTED"local c="STOPPED"local _="HARDHIDE"local s={}local f={"hideTimer","succeededTimer","timer"}local function o()return(GetTimePreciseSec and GetTimePreciseSec())or GetTime()end
local function d(e)if e==nil then return nil end
local n=_G.ToPlain if type(n)=="function"then
local e=n(e)local e=tonumber(tostring(e))if e~=nil then return e end end
local n=type(e)if n=="number"or n=="string"then
return tonumber(tostring(e))end
return nil end
local function r(e,n,i)local t=e and e[n]if not t then return end local r=_G.MSUF_CB_ApplyTexts
if type(r)=="function"then if n=="castText"then
r(e,nil,i or"",nil)elseif n=="timeText"then
r(e,nil,nil,i or"")end
elseif t.SetText then t:SetText(i or"")end end
local function u(e,n)if e and e.isEmpower==true then
return a end
if n==true then return S
end return a
end local function S(n,e,t)if e and e.reverseFill~=nil then return e.reverseFill==true
end if type(_G.MSUF_GetCastbarReverseFillForFrame)=="function"then
return _G.MSUF_GetCastbarReverseFillForFrame(n,t and true or false)==true end
if type(_G.MSUF_GetReverseFillSafe)=="function"then return _G.MSUF_GetReverseFillSafe(n,t and true or false)==true
end return false
end function n:ApplyTimer(e,n,t,i)if not e then return false end if e.SetReverseFill then
e:SetReverseFill(t and true or false)end
if not n or not e.SetTimerDuration then return false
end local t=e.GetParent and e:GetParent()or nil
local t=u(t,i)if l~=nil and t~=nil then
e:SetTimerDuration(n,l,t)else
e:SetTimerDuration(n)end
return true end
function n:ClearTimer(e)return false
end function n:SnapshotDuration(n,e)if not(n and e)then return nil,nil end local t
if e.GetRemainingDuration then t=e:GetRemainingDuration()elseif e.GetRemaining then t=e:GetRemaining()end local i
if e.GetTotalDuration then i=e:GetTotalDuration()end local e=d(t)local t=d(i)if e and e>0 then
n._msufPlainEndTime=o()+e n._msufRemaining=e
else n._msufPlainEndTime=nil
n._msufRemaining=nil end
n._msufPlainTotal=t return e,t
end function n:ApplyActive(e,n,i)if not(e and n and n.active==true)then return false end local a=n.durationObj
local l=n.spellName if not a or not l then return false end
i=i or s local o=n.castType or n.phase or"CAST"local t=(o=="CHANNEL")local u=e.unit or n.unit
e.interrupted=nil e.MSUF_castActive=true
e.MSUF_durationObj=a e.MSUF_isChanneled=t
if i.channelDirect~=nil then e.MSUF_channelDirect=i.channelDirect and true or nil
elseif t and(u=="target"or u=="focus")then e.MSUF_channelDirect=true
else e.MSUF_channelDirect=nil
end if i.resetRuntime~=false then
e.castDuration=nil e.castElapsed=nil
e.MSUF_timerDriven=nil e.MSUF_timerRangeSet=nil
e._msufLastSBValue=nil e._msufHardStopNoChannelSince=nil
e._msufHardStopNoCastSince=nil end
if e.icon and n.icon then e.icon:SetTexture(n.icon)end r(e,"castText",n.text or l or"")if i.skipSnapshot~=true then self:SnapshotDuration(e,a)end local r=S(e,n,t)e._msufStripeReverseFill=r and true or false e.MSUF_timerDriven=self:ApplyTimer(e.statusBar,a,r,t)and true or false
local t=e._msufCastState or n if i.skipCastState~=true then
e._msufCastState=t t.key=e._msufBarKey or t.key
t.unit=u t.active=true
t.phase=o t.castType=o
t.spellName=l t.text=n.text or l
t.icon=n.icon t.durationObj=a
t.holdUntil=nil end
if i.skipColor~=true and e.UpdateColorForInterruptible then e:UpdateColorForInterruptible()end if i.skipRegister~=true and type(_G.MSUF_RegisterCastbar)=="function"then
_G.MSUF_RegisterCastbar(e)end
if i.skipTimeText~=true and e.timeText and type(_G.MSUF_UpdateCastTimeText_FromStatusBar)=="function"then _G.MSUF_UpdateCastTimeText_FromStatusBar(e)end if i.skipShow~=true and e.Show then
e:Show()end
return true end
function n:ApplyInterrupt(t,n)if not t then return end
n=n or s local e=t.statusBar
if not e then return end if e.SetMinMaxValues then e:SetMinMaxValues(0,1)end
if e.SetValue then e:SetValue(n.barValue or 1)end if n.reverseFill~=nil and e.SetReverseFill then
e:SetReverseFill(n.reverseFill and true or false)end
local i=n.colorR or 0.8 local l=n.colorG or 0.1
local a=n.colorB or 0.1 if type(_G.MSUF_SetStatusBarColorIfChanged)=="function"then
_G.MSUF_SetStatusBarColorIfChanged(e,i,l,a,1)elseif e.SetStatusBarColor then
e:SetStatusBarColor(i,l,a,1)end
r(t,"castText",n.label or"Interrupted")r(t,"timeText","")if t.Show then t:Show()end if t.SetAlpha then t:SetAlpha(1)end
if n.skipShake~=true and type(_G.MSUF_PlayCastbarShake)=="function"then _G.MSUF_PlayCastbarShake(t)end end
function n:Stop(e,t,n)if not e then return end
n=n or s local n=t
if type(t)=="table"then n=t.reason or t.kind or t[1]end if type(n)~="string"then
n=c end
if e.SetScript then e:SetScript("OnUpdate",nil)end if type(_G.MSUF_UnregisterCastbar)=="function"then
_G.MSUF_UnregisterCastbar(e)end
e.MSUF_durationObj=nil e._msufPlainEndTime=nil
e._msufRemaining=nil e._msufFastText=nil
e._msufPlainTotal=nil e.MSUF_isChanneled=nil
e.MSUF_channelDirect=nil e.MSUF_timerDriven=nil
e.MSUF_timerRangeSet=nil e._msufLastSBValue=nil
e.castDuration=nil e.castElapsed=nil
e.MSUF_castActive=false local t=e._msufCastState
if t then t.unit=e.unit
t.key=e._msufBarKey or e.unit t.active=false
t.phase=(n==h)and"INTERRUPT"or"IDLE"t.durationObj=nil
t.holdUntil=nil end
if n==_ then r(e,"timeText","")if e.latencyBar then e.latencyBar:Hide()end if e.Hide then e:Hide()end
return end
if n==c then r(e,"timeText","")r(e,"castText","")if e.latencyBar then e.latencyBar:Hide()end
if not e.interrupted and e.Hide then e:Hide()end return
end for n=1,#f do
local t=f[n]local n=e[t]if n and n.Cancel then n:Cancel()end e[t]=nil
end if e.isEmpower and type(_G.MSUF_ClearEmpowerState)=="function"then
_G.MSUF_ClearEmpowerState(e)end
if n==p or n==m then r(e,"castText","")r(e,"timeText","")if e.Hide then e:Hide()end
return end
end function n:BuildState(t,n)local e=(_G.MSUF_GetCastbarEngine and _G.MSUF_GetCastbarEngine())or nil if e and e.BuildState then
return e:BuildState(t,n)end
return nil end
_G.MSUF_ApplyTimerAndFill=function(r,i,t,e)return n:ApplyTimer(r,i,t,e)end _G.MSUF_ApplyCastbarTimerDirection=function(i,e,r,t)return n:ApplyTimer(i,e,r,t)end
_G.MSUF_ClearCastbarTimerDuration=function(e)return n:ClearTimer(e)end _G.MSUF_Castbar_ApplyActiveDuration=function(t,i,e)return n:ApplyActive(t,i,e)end
_G.MSUF_ApplyInterruptBarVisuals=function(e,t)return n:ApplyInterrupt(e,t)end _G.MSUF_CB_ResetStateOnStop=function(e,i,t)return n:Stop(e,i,t)end
_G.MSUF_CastbarRuntime_PlainNumber=d