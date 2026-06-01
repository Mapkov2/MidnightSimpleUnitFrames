local t,n=...n=n or{}local e=n.MSUF_CastbarRegistry local t=n.MSUF_CastbarStyle
local u=_G.MSUF_CastbarRuntime_PlainNumber or function(t)if t==nil then return nil end
local e=_G.ToPlain if type(e)=="function"then
local n=e(t)local n=tonumber(tostring(n))if n~=nil then return n end end
local e=type(t)if e=="number"or e=="string"then
return tonumber(tostring(t))end
return nil end
n.MSUF_CastbarEngine=n.MSUF_CastbarEngine or{}local t=n.MSUF_CastbarEngine
local l={}t.VERSION=3
t._subs=t._subs or{}t._state=t._state or{}local function i(e)if not e then return nil end
local n=t._subs[e]if not n then
n={}t._subs[e]=n
end return n
end function t:RegisterBar(n,t,r,i)if e and e.Register then e:Register(n,t,r,i)end end
function t:UnregisterBar(n)if e and e.Unregister then
e:Unregister(n)end
end function t:Subscribe(n,t)if not n or type(t)~="function"then return end local n=i(n)n[#n+1]=t end
function t:Notify(n,e)local n=t._subs and t._subs[n]if not n then return end for t=1,#n do
local n=n[t]if type(n)=="function"then
n(e)end
end end
function t:ForceRefresh(n)end
function t:GetState(n)return t._state and t._state[n]end local n=_G.MSUF_EnsureDBLazy or function()if not MSUF_DB and type(EnsureDB)=="function"then EnsureDB()end end
local function r(e,i)n()local t=(MSUF_DB and MSUF_DB.general)or{}local n=(t.castbarFillDirection=="RTL")and true or false
if i=="target"and t.castbarOpositeDirectionTarget==true then n=not n
end local t=(t.castbarUnifiedDirection==true)if e=="CHANNEL"or e=="EMPOWER"then if t then
return n end
return not n end
return n end
local function a(t,n)if n and n.isNotInterruptible~=nil then
return(n.isNotInterruptible==true)end
return false end
local function o(n)if n~="player"then return false end
if type(GetUnitEmpowerStageCount)~="function"then return false end local n=GetUnitEmpowerStageCount(n)local n=u(n)if type(n)=="number"and n>0 then
return true end
return false end
function t:BuildState(e,i)if not e then return{active=false}end
local n=GetTime()if l[e]==n and t._state[e]then
return t._state[e]end
l[e]=n local n=t._state[e]if not n then n={}t._state[e]=n end
n.active=false n.unit=e
n.castType="NONE"n.spellName=nil
n.text=nil n.icon=nil
n.spellId=nil n.startTimeMS=nil
n.endTimeMS=nil n.durationObj=nil
n.isNotInterruptible=false n.apiNotInterruptible=nil
n.apiNotInterruptibleRaw=nil n.reverseFill=nil
local t,u,s,c,f,p,p,l,d,p=UnitCastingInfo(e)if t then
local o=o(e)n.castType=o and"EMPOWER"or"CAST"n.spellName=t n.text=u or t
n.icon=s n.spellId=d
n.startTimeMS=c n.endTimeMS=f
n.active=true n.apiNotInterruptible=l
n.apiNotInterruptibleRaw=l n.isNotInterruptible=a(e,i)if type(UnitCastingDuration)=="function"then n.durationObj=UnitCastingDuration(e)end n.reverseFill=r(n.castType,n.unit)return n end
local t,s,o,c,d,f,l,u,f=UnitChannelInfo(e)if t then
n.castType="CHANNEL"n.apiNotInterruptible=l
n.apiNotInterruptibleRaw=l n.spellName=t
n.text=s or t n.icon=o
n.spellId=u n.startTimeMS=c
n.endTimeMS=d n.active=true
n.isNotInterruptible=a(e,i)if type(UnitChannelDuration)=="function"then
n.durationObj=UnitChannelDuration(e)end
n.reverseFill=r(n.castType,n.unit)return n
end return n
end if not _G.MSUF_BuildCastState then
function _G.MSUF_BuildCastState(e,n)return t:BuildState(e,n)end end
if not _G.MSUF_GetCastbarEngine then _G.MSUF_GetCastbarEngine=function()return t end
end
