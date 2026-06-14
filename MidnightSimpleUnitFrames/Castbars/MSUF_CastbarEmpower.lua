-- Compact empower castbar support.
-- Computes empower stage timing and draws stage tick/blink visuals for castbars. It is kept
-- isolated from the main castbar runtime because empower APIs vary by client/build.
local ExportPublic = ((select(2, ...) or _G.MSUF_NS or _G.MSUF or {}).ExportPublic) or function(name, value)
_G[name] = value
return value
end

local s=_G.MSUF_EnsureDBLazy or function()if not MSUF_DB and type(EnsureDB)=="function"then EnsureDB()end
end local r=_G.MSUF_CastbarRuntime_PlainNumber or function(e)if e==nil then return nil end local t=_G.ToPlain
if type(t)=="function"then local e=t(e)local e=tonumber(tostring(e))if e~=nil then return e end
end local t=type(e)if t=="number"or t=="string"then return tonumber(tostring(e))end return nil
end local function d(e)e=r(e)if not e then return nil end
if e>20 then e=e/1000
end return e
end local function h(t)local a={}local e=0
local function n(e)if type(GetUnitEmpowerStageDuration)~="function"then return nil end
local e=GetUnitEmpowerStageDuration(t,e)local e=d(e)if not e or e<=0 then return nil end return e
end local l=nil
if type(GetUnitEmpowerStageCount)=="function"then local e=r(GetUnitEmpowerStageCount(t))if e and e>0 then l=e end end
local i=(n(0)~=nil)local o=i and 0 or 1
if l then for t=1,l do
local t=i and(t-1)or t local t=n(t)if not t then break end e=e+t
a[#a+1]=e end
else for t=o,o+9 do
local t=n(t)if not t then break end
e=e+t a[#a+1]=e
end end
local n=0 if type(GetUnitEmpowerHoldAtMaxTime)=="function"then
local e=GetUnitEmpowerHoldAtMaxTime(t)n=d(e)or 0
if n<0 then n=0 end end
local o,d,s=nil,nil,nil if type(UnitCastingInfo)=="function"then
local n,n,n,t,e=UnitCastingInfo(t)t=r(t)e=r(e)if t and e and e>t then
d=t/1000 s=e/1000
o=(e-t)/1000 end
end local t=e+n
if o and o>0 then if t<=0 then
t=o else
if o>t then t=o
end end
if e>0 then local e=o-e
if e<0 then e=0 end if n<=0 or math.abs((n or 0)-e)>0.15 then
n=e end
end end
if not t or t<=0 then t=3.0
end local c=0
local r=t if r<=0 then r=0.01 end
return{stageEnds=a,totalStage=e,maxHold=n,totalBase=t,totalWithGrace=r,grace=c,castStartSec=d,castEndSec=s,castTotal=o,zeroBased=i,stageCount=l,}end
local f=0.85 local e=1.00
local e=0.06 local e=0.14
local T=12 local e=0.90
local p=4 local t=0.14
local e={1.00,0.85,0.25}local function d()s()local e=MSUF_DB and MSUF_DB.general
local e=e and e.empowerStageBlinkTime if type(e)~="number"then
e=t or 0.14 end
if e<0.05 then e=0.05 end if e>1.00 then e=1.00 end
return e end
local function w()s()local e=MSUF_DB and MSUF_DB.general return(not e)or(e.empowerStageBlink~=false)end local function u(t,l)if not t or not t.statusBar then return end t.empowerTicks=t.empowerTicks or{}local a=t.statusBar:GetHeight()or 18 for n=1,l do
local e=t.empowerTicks[n]if not e then
e=t.statusBar:CreateTexture(nil,"OVERLAY")e:SetTexture("Interface/Buttons/WHITE8x8")e:SetVertexColor(1,1,1,f)e:SetWidth(2)e.MSUF_baseAlpha=f e.MSUF_baseWidth=2
t.empowerTicks[n]=e end
e:SetHeight(a)e:Show()if not e.MSUF_flash then local t=t.statusBar:CreateTexture(nil,"OVERLAY")t:SetTexture("Interface/Buttons/WHITE8x8")t:SetBlendMode("ADD")t:SetVertexColor(1.0,0.10,0.10,0.0)t:Hide()e.MSUF_flash=t local o=t:CreateAnimationGroup()local n=o:CreateAnimation("Alpha")n:SetFromAlpha(1.0)n:SetToAlpha(0.0)n:SetDuration(d())e.MSUF_flashAnim=n o:SetScript("OnFinished",function()if t then t:Hide()t:SetAlpha(0.0)end
end)e.MSUF_flashGroup=o
end if e.MSUF_flash then
e.MSUF_flash:SetHeight(a)end
if e.MSUF_glow then e.MSUF_glow:SetHeight(a)end end
for e=l+1,#t.empowerTicks do local e=t.empowerTicks[e]if e then e:Hide()if e.MSUF_glow then e.MSUF_glow:Hide()end if e.MSUF_flash then e.MSUF_flash:Hide()end
end end
end local s={{0.20,0.90,0.20,0.18},{0.95,0.80,0.20,0.18},{1.00,0.55,0.20,0.18},{1.00,0.25,0.25,0.18},}local function S(e,o)if not e or not e.statusBar then return end e.empowerSegments=e.empowerSegments or{}for n=1,o do local t=e.empowerSegments[n]if not t then t=e.statusBar:CreateTexture(nil,"ARTWORK")t:SetColorTexture(1,1,1,0.18)t:SetBlendMode("ADD")e.empowerSegments[n]=t end
t:Show()end
for t=o+1,#e.empowerSegments do e.empowerSegments[t]:Hide()end end
local t=nil local function m()local e=_G.MSUF_DB if e and e.general~=nil then
local e=(e.general.castbarUnifiedDirection and true or false)t=e
return e end
if t~=nil then return t
end if type(_G.MSUF_EnsureDB)=="function"then
_G.MSUF_EnsureDB()e=_G.MSUF_DB
end local e=(e and e.general and e.general.castbarUnifiedDirection)and true or false
t=e return e
end local function c(e)local t=m()if e then
e.MSUF_cachedUnifiedDirection=t end
return t end
local t=nil local function U()local e=_G.MSUF_DB if e and e.general~=nil then
local e=not(e.general.empowerColorStages==false)t=e
return e end
if t~=nil then return t
end if type(_G.MSUF_EnsureDB)=="function"then
_G.MSUF_EnsureDB()e=_G.MSUF_DB
end local e=not(e and e.general and e.general.empowerColorStages==false)t=e return e
end local function _(e)if not e or not e.isEmpower or not e.statusBar then return end if not e.empowerStageEnds or not e.empowerTotalWithGrace then return end
if not U()then if e.empowerSegments then
for t=1,#e.empowerSegments do local e=e.empowerSegments[t]if e then e:Hide()end end
end return
end local d=e.statusBar:GetWidth()or 0
if d<=1 then e.MSUF_empowerLayoutPending=true
return end
local r=e.empowerTotalWithGrace local i=e.empowerStageEnds
local u=e.statusBar:GetHeight()or 18 local m=(e.statusBar.GetReverseFill and e.statusBar:GetReverseFill())or false
local t=c(e)local h=not t
local t=#i local n=i[#i]or 0
local c=(r and n and r>n+0.001)if c then
t=t+1 end
S(e,t)local function f(t,o,n,i)if not r or r<=0 then return end local t=e.empowerSegments[t]if not t then return end local l=o/r
local n=n/r if l<0 then l=0 elseif l>1 then l=1 end
if n<0 then n=0 elseif n>1 then n=1 end if n<l then n=l end
local a=l local o=n
if h then a=1-n
o=1-l if a<0 then a=0 elseif a>1 then a=1 end
if o<0 then o=0 elseif o>1 then o=1 end if o<a then o=a end
end local n=d*a
local o=d*o local o=o-n
if o<0 then o=0 end local l,d,r,a=1,1,1,0.18
if i then l,d,r,a=i[1],i[2],i[3],i[4]end t:SetColorTexture(l,d,r,a)t:SetHeight(u)t:ClearAllPoints()if m then t:SetPoint("TOPRIGHT",e.statusBar,"TOPRIGHT",-n,0)t:SetPoint("BOTTOMRIGHT",e.statusBar,"BOTTOMRIGHT",-n,0)t:SetWidth(o)else t:SetPoint("TOPLEFT",e.statusBar,"TOPLEFT",n,0)t:SetPoint("BOTTOMLEFT",e.statusBar,"BOTTOMLEFT",n,0)t:SetWidth(o)end end
local t=0 for e=1,#i do
local n=i[e]or t local o=s[e]or s[#s]f(e,t,n,o)t=n
end if c then
f(#i+1,t,r,{1,1,1,0.10})end
e.MSUF_empowerLayoutPending=false end
local function i(e,t)if not e or not e.empowerTicks then return end
local e=e.empowerTicks[t]if not e then return end
local t=e.MSUF_flash local o=e.MSUF_flashGroup
local n=e.MSUF_baseAlpha or f or 0.85 local a=e.MSUF_baseWidth or 2
e.MSUF_baseWidth=a e.MSUF_blinkToken=(e.MSUF_blinkToken or 0)+1
local l=e.MSUF_blinkToken if t then
t:SetVertexColor(1.0,0.10,0.10,1.0)t:SetAlpha(1.0)t:Show()if o then
if e.MSUF_flashAnim then e.MSUF_flashAnim:SetDuration(d())end o:Stop()o:Play()end
end if e.SetWidth then e:SetWidth(p or 4)end
if e.SetVertexColor then e:SetVertexColor(1.0,0.10,0.10,1.0)elseif e.SetColorTexture then e:SetColorTexture(1.0,0.10,0.10,1.0)end if C_Timer and C_Timer.After then
local t=d()C_Timer.After(t,function()if not e or l~=e.MSUF_blinkToken then return end if e.SetWidth then e:SetWidth(a)end
if e.SetVertexColor then e:SetVertexColor(1.0,1.0,1.0,n)elseif e.SetColorTexture then e:SetColorTexture(1.0,1.0,1.0,n)elseif e.SetAlpha then e:SetAlpha(n)end end)end end
local function o(e)if not e or not e.isEmpower or not e.statusBar then return end
if not e.empowerStageEnds or not e.empowerTotalWithGrace then return end local n=e.statusBar:GetWidth()or 0
if n<=1 then e.MSUF_empowerLayoutPending=true
return end
local l=e.empowerTotalWithGrace local t=e.empowerStageEnds
local a=(e.statusBar.GetReverseFill and e.statusBar:GetReverseFill())or false local o=c(e)local o=not o _(e)u(e,#t)for o=1,#t do
local t=t[o]local t=t/l
if t<0 then t=0 elseif t>1 then t=1 end local t=t
local n=n*t local t=e.empowerTicks[o]t:ClearAllPoints()if a then
t:SetPoint("CENTER",e.statusBar,"RIGHT",-n,0)else
t:SetPoint("CENTER",e.statusBar,"LEFT",n,0)end
local n=t.MSUF_glow if n then
n:ClearAllPoints()n:SetPoint("CENTER",t,"CENTER",0,0)n:SetWidth(T or 12)n:SetHeight(e.statusBar:GetHeight()or 18)end local n=t.MSUF_flash
if n then n:ClearAllPoints()n:SetPoint("CENTER",t,"CENTER",0,0)local t=(p or 4)*3
if t<10 then t=10 end n:SetWidth(t)n:SetHeight(e.statusBar:GetHeight()or 18)end
end e.MSUF_empowerLayoutPending=false
end local function a(e,t)if not e or not e.statusBar then return
end e.isEmpower=true
e.interruptFeedbackEndTime=nil if e.latencyBar then e.latencyBar:Hide()end
local n,a,t=UnitCastingInfo("player")if not n then
n,a,t=UnitChannelInfo("player")end
if e.icon and t then e.icon:SetTexture(t)end if e.castText then
if type(_G.MSUF_CB_ApplyTexts)=="function"then _G.MSUF_CB_ApplyTexts(e,nil,n or"",nil)else MSUF_SetTextIfChanged(e.castText,n or"")end end
local t=h("player")local n=((GetTimePreciseSec and GetTimePreciseSec())or GetTime())e.empowerStartTime=t.castStartSec or n e.empowerStageEnds=t.stageEnds
e.empowerTotalBase=t.totalBase e.empowerTotalWithGrace=t.totalWithGrace
e.empowerNextStage=1 e._msufEmpowerStartNum=r(e.empowerStartTime)or n
e._msufEmpowerTotalNum=r(e.empowerTotalWithGrace)or 0 e._msufEmpowerBaseNum=r(e.empowerTotalBase)or e._msufEmpowerTotalNum
if t.stageEnds then local o={}for n=1,#t.stageEnds do o[n]=r(t.stageEnds[n])end e._msufEmpowerStageEndsNum=o
else e._msufEmpowerStageEndsNum=nil
end local a=_G.MSUF_GetReverseFillSafe(e,true)local t=nil if type(UnitCastingDuration)=="function"then
t=UnitCastingDuration("player")end
_G.MSUF_ApplyTimerAndFill(e.statusBar,t,a,false)e.statusBar:SetMinMaxValues(0,e.empowerTotalWithGrace)local t=n-(e.empowerStartTime or n)if t<0 then t=0 end
if t>e.empowerTotalWithGrace then t=e.empowerTotalWithGrace end e.statusBar:SetValue(t)e.MSUF_empowerLayoutPending=false o(e)if not e.MSUF_empowerSizeHooked and e.statusBar and e.statusBar.HookScript then e.MSUF_empowerSizeHooked=true
e.statusBar:HookScript("OnSizeChanged",function()if e.isEmpower and e.MSUF_empowerLayoutPending then
o(e)end
end)end
e:SetScript("OnUpdate",nil)if type(_G.MSUF_EnsureCastbarManager)=="function"then _G.MSUF_EnsureCastbarManager()end
if type(_G.MSUF_RegisterCastbar)=="function"then _G.MSUF_RegisterCastbar(e)end if type(_G.MSUF_UpdateCastbarFrame)=="function"then _G.MSUF_UpdateCastbarFrame(e,0)end
local t=_G.MSUF_PlayerCastbar_UpdateColorForInterruptible if type(t)=="function"then t(e)end
e:Show()end
local function n(e,t)if not e then return end
e.isEmpower=nil e.empowerStartTime=nil
e.empowerStageEnds=nil e.empowerTotalBase=nil
e.empowerTotalWithGrace=nil e.empowerNextStage=nil
e._msufEmpowerStartNum=nil e._msufEmpowerTotalNum=nil
e._msufEmpowerBaseNum=nil e._msufEmpowerStageEndsNum=nil
e.MSUF_empowerLayoutPending=false if e.empowerTicks then
for t=1,#e.empowerTicks do local e=e.empowerTicks[t]if e then if e.Hide then e:Hide()end
if e.MSUF_glow and e.MSUF_glow.Hide then e.MSUF_glow:Hide()end if e.MSUF_flash and e.MSUF_flash.Hide then e.MSUF_flash:Hide()end
end end
end if e.empowerSegments then
for t=1,#e.empowerSegments do local e=e.empowerSegments[t]if e and e.Hide then e:Hide()end end
end if t then
if e.SetScript then e:SetScript("OnUpdate",nil)end if type(_G.MSUF_UnregisterCastbar)=="function"then _G.MSUF_UnregisterCastbar(e)end
if e.timeText then MSUF_SetTextIfChanged(e.timeText,"")end if e.latencyBar and e.latencyBar.Hide then
e.latencyBar:Hide()end
if e.Hide then e:Hide()end end
end ExportPublic("MSUF_BuildEmpowerTimeline", h)
ExportPublic("MSUF_BlinkEmpowerTick", i)
ExportPublic("MSUF_LayoutEmpowerTicks", o)
ExportPublic("MSUF_EnsureEmpowerTicks", u)
ExportPublic("MSUF_EnsureEmpowerStageSegments", S)
ExportPublic("MSUF_LayoutEmpowerStageSegments", _)
ExportPublic("MSUF_GetUnifiedDirection", m)
ExportPublic("MSUF_GetUnifiedFillEnabled", c)
ExportPublic("MSUF_IsEmpowerColorStagesEnabled", U)
ExportPublic("MSUF_GetEmpowerStageBlinkTime", d)
ExportPublic("MSUF_IsEmpowerStageBlinkEnabled", w)
ExportPublic("MSUF_PlayerCastbar_EmpowerStart", a)
ExportPublic("MSUF_PlayerCastbar_ClearEmpower", n)
