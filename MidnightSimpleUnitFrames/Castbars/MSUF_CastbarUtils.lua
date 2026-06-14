--- Castbars/MSUF_CastbarUtils.lua
--- Legacy/minified utility exports for castbar colors, preview sync, interrupt
--- tinting, shake/glow feedback, reverse fill, and spell-name shortening.
---
--- Many modules call these globals directly. Keep this file as a compatibility
--- surface; new code should prefer clearer helpers in Runtime/Style/Visuals and
--- leave these exports stable unless a migration is planned.

local ExportPublic = ((select(2, ...) or _G.MSUF_NS or _G.MSUF or {}).ExportPublic) or function(name, value)
_G[name] = value
return value
end

local e,e=...if type(_G.MSUF_HardSyncCastbarPreview)~="function"then
local function t(e)local n=_G.issecretvalue
if type(n)=="function"and n(e)==true then return nil end
e=tonumber(e)
if type(n)=="function"and n(e)==true then return nil end
if type(e)~="number"then return nil end
local n,r=pcall(function()return e>0 end)
return(n and r)and e or nil end
local function MSUF_HardSyncCastbarPreview(e,n)if not e or not n then return end
if n.GetScale and e.SetScale then local n=t(n:GetScale())if n then e:SetScale(n)end end
if e.statusBar and e.statusBar.SetSize then if n.statusBar and n.statusBar.GetSize then
local n,r=n.statusBar:GetSize()n=t(n)r=t(r)if n and r then
e.statusBar:SetSize(n,r)end
elseif e.GetSize then local n,r=e:GetSize()n=t(n)r=t(r)if n and r then e.statusBar:SetSize(n,r)end end
end if e.icon and e.icon.SetSize and n.icon and n.icon.GetSize then
local n,r=n.icon:GetSize()n=t(n)r=t(r)if n and r then
e.icon:SetSize(n,r)end
end if e.latencyBar and e.latencyBar.SetWidth and n.latencyBar and n.latencyBar.GetWidth then
local n=t(n.latencyBar:GetWidth())if n then
e.latencyBar:SetWidth(n)end
end end
ExportPublic("MSUF_HardSyncCastbarPreview", MSUF_HardSyncCastbarPreview)
end local function t()if not MSUF_DB and type(EnsureDB)=="function"then EnsureDB()end end
ExportPublic("MSUF_EnsureDBLazy", t) local function MSUF_GetAnchorFrame()t()local n=(MSUF_DB and MSUF_DB.general)or{}if n.anchorToCooldown then local e=_G["EssentialCooldownViewer"]if e and e.IsShown and e:IsShown()then return e
end return UIParent
end local e=n.anchorName
if e and e~=""and e~="EssentialCooldownViewer"then local e=_G[e]if e and e.IsShown and e:IsShown()then return e
end end
return UIParent end ExportPublic("MSUF_GetAnchorFrame", MSUF_GetAnchorFrame)
local function m(e,t,r,a,n)if not(e and e.SetStatusBarColor)then return end
n=n or 1 local i,d,l,o=e._msufLastColorR,e._msufLastColorG,e._msufLastColorB,e._msufLastColorA
if(i==t and d==r and l==a and o==n)or(e._msufLastR==t and e._msufLastG==r and e._msufLastB==a and e._msufLastA==n)then return
end e._msufLastColorR,e._msufLastColorG,e._msufLastColorB,e._msufLastColorA=t,r,a,n
e._msufLastR,e._msufLastG,e._msufLastB,e._msufLastA=t,r,a,n e:SetStatusBarColor(t,r,a,n)end if type(_G.MSUF_SetStatusBarColorIfChanged)~="function"then
local function MSUF_SetStatusBarColorIfChanged(a,n,e,t,r)m(a,n,e,t,r)end ExportPublic("MSUF_SetStatusBarColorIfChanged", MSUF_SetStatusBarColorIfChanged) end
local p={r=nil,g=nil,b=nil,a=nil,obj=nil}local F={r=nil,g=nil,b=nil,a=nil,obj=nil}local function h(e,t,r,a,n)if e.r==t and e.g==r and e.b==a and e.a==n and e.obj then
return e.obj end
e.r,e.g,e.b,e.a=t,r,a,n e.obj=CreateColor(t,r,a,n)return e.obj end
local function v(e)local n=_G.issecretvalue
if type(n)=="function"and n(e)==true then return true end
return e~=nil
end
local function MSUF_Castbar_ApplyNonInterruptibleTint(e,C,c,S,u,s,d,f,_,G,n)local e=e and e.statusBar if not e then return false end
local t=(n==true)local n=t and c or d
local r=t and S or f local a=t and u or _
local o=t and(s or 1)or(G or 1)local i=e.GetStatusBarTexture and e:GetStatusBarTexture()local l=false if i and i.SetVertexColorFromBoolean and CreateColor then
local r=h(p,c,S,u,s or 1)local n=h(F,d,f,_,G or 1)local e=C if not v(e)then
e=(t==true)end
i:SetVertexColorFromBoolean(e,r,n)l=true
end if not l then
m(e,n,r,a,o)else
e._msufLastColorR,e._msufLastColorG,e._msufLastColorB,e._msufLastColorA=n,r,a,o e._msufLastR,e._msufLastG,e._msufLastB,e._msufLastA=n,r,a,o
end if not e._msufGlowSkipBase then
local d,i,l,t=e._msufGlowBaseR,e._msufGlowBaseG,e._msufGlowBaseB,e._msufGlowBaseA if d~=n or i~=r or l~=a or t~=o then
e._msufGlowBaseR,e._msufGlowBaseG,e._msufGlowBaseB,e._msufGlowBaseA=n,r,a,o e._msufGlowLastP=nil
end end
return l end
ExportPublic("MSUF_Castbar_ApplyNonInterruptibleTint", MSUF_Castbar_ApplyNonInterruptibleTint)
local n=_G.MSUF_SetTextIfChanged local function i(e,t)if not(e and e.SetText)then return end if n then
n(e,t or"")else
e:SetText(t or"")end
end if _G.C_Timer and _G.C_Timer.After then
_G.C_Timer.After(0,function()n=_G.MSUF_SetTextIfChanged or n
end)end
local function n(n,e,t)if e and e.reverseFill~=nil then
return(e.reverseFill==true)end
local e=_G.MSUF_GetCastbarReverseFillForFrame if type(e)=="function"then
local e=e(n,t and true or false)if e~=nil then
return(e==true)end
end return false
end local function MSUF_GetReverseFillSafe(t,e)return n(t,nil,e)end ExportPublic("MSUF_GetReverseFillSafe", MSUF_GetReverseFillSafe)
local function r(e)if not e then return nil end
local n=e.unit or e.MSUF_unit or e._msufUnit or e.unitKey if type(n)=="string"and n~=""then
return n end
local n=e._msufBarKey or e.barKey or e.key if type(n)=="string"and n~=""then
if n=="player"or n=="target"or n=="focus"then return n end if n=="boss"or n:sub(1,4)=="boss"then return n end
end if e==_G.MSUF_PlayerCastbar or e==_G.MSUF_PlayerCastbarPreview then return"player"end
if e==_G.MSUF_TargetCastbar or e==_G.MSUF_TargetCastbarPreview then return"target"end if e==_G.MSUF_FocusCastbar or e==_G.MSUF_FocusCastbarPreview then return"focus"end
local e=e.GetName and e:GetName()or nil if type(e)=="string"then
if e:find("Target",1,true)then return"target"end if e:find("Focus",1,true)then return"focus"end
if e:find("Player",1,true)then return"player"end if e:find("boss",1,true)or e:find("Boss",1,true)then return"boss"end
end return nil
end local function MSUF_GetCastbarReverseFillForFrame(o,a)t()local n=(MSUF_DB and MSUF_DB.general)or{}local e=(n.castbarFillDirection=="RTL")and true or false if n.castbarOpositeDirectionTarget==true then
local n=r(o)if n=="target"then
e=not e end
end if a==true then
if n.castbarUnifiedDirection~=true then return not e
end end
return e end
ExportPublic("MSUF_GetCastbarReverseFillForFrame", MSUF_GetCastbarReverseFillForFrame)
local function MSUF_ResolveCastbarColors()t()local l=(MSUF_DB and MSUF_DB.general)or{}local n,r,o
if type(_G.MSUF_GetInterruptibleCastColor)=="function"then n,r,o=_G.MSUF_GetInterruptibleCastColor()end if not(n and r and o)then
local e=l.castbarInterruptibleColor or"teal"local e=(type(_G.MSUF_GetColorFromKey)=="function")and _G.MSUF_GetColorFromKey(e)or nil
if e and e.GetRGB then n,r,o=e:GetRGB()end end
if not(n and r and o)then n,r,o=0,0.85,0.85
end local a,e,t
if type(_G.MSUF_GetNonInterruptibleCastColor)=="function"then a,e,t=_G.MSUF_GetNonInterruptibleCastColor()end if not(a and e and t)then
local n=l.castbarNonInterruptibleColor or"red"local n=(type(_G.MSUF_GetColorFromKey)=="function")and _G.MSUF_GetColorFromKey(n)or nil
if n and n.GetRGB then a,e,t=n:GetRGB()end end
if not(a and e and t)then a,e,t=0.9,0.1,0.1
end return n,r,o,a,e,t
end ExportPublic("MSUF_ResolveCastbarColors", MSUF_ResolveCastbarColors) local function d(e)if not e or e.MSUF_ShakeGroup then return
end local n=e:CreateAnimationGroup("MSUF_ShakeGroup")n:SetLooping("NONE")local r=n:CreateAnimation("Translation")r:SetOffset(4,0)r:SetDuration(0.05)r:SetOrder(1)local a=n:CreateAnimation("Translation")a:SetOffset(-8,0)a:SetDuration(0.10)a:SetOrder(2)local t=n:CreateAnimation("Translation")t:SetOffset(4,0)t:SetDuration(0.05)t:SetOrder(3)e.MSUF_ShakeGroup=n
e.MSUF_ShakeA1=r e.MSUF_ShakeA2=a
e.MSUF_ShakeA3=t end
local function MSUF_PlayCastbarShake(e)if not e then
return end
t()local n=(MSUF_DB and MSUF_DB.general)or{}if n.castbarInterruptShake==false then return
end local n=tonumber(n.castbarShakeStrength)or 8
if n<0 then n=0 end if n>30 then n=30 end
if n<=0 then return
end local t=n/2
d(e)if e.MSUF_ShakeA1 and e.MSUF_ShakeA1.SetOffset then
e.MSUF_ShakeA1:SetOffset(t,0)end
if e.MSUF_ShakeA2 and e.MSUF_ShakeA2.SetOffset then e.MSUF_ShakeA2:SetOffset(-n,0)end if e.MSUF_ShakeA3 and e.MSUF_ShakeA3.SetOffset then
e.MSUF_ShakeA3:SetOffset(t,0)end
if e.MSUF_ShakeGroup then e.MSUF_ShakeGroup:Stop()e.MSUF_ShakeGroup:Play()end
end ExportPublic("MSUF_PlayCastbarShake", MSUF_PlayCastbarShake) local function MSUF_GetInterruptibleCastColor()t()local e=(MSUF_DB and MSUF_DB.general)or{}local t=tonumber(e.castbarInterruptibleR)local n=tonumber(e.castbarInterruptibleG)local e=tonumber(e.castbarInterruptibleB)if t and n and e then
return t,n,e,1 end
end ExportPublic("MSUF_GetInterruptibleCastColor", MSUF_GetInterruptibleCastColor) local function MSUF_GetNonInterruptibleCastColor()t()local e=(MSUF_DB and MSUF_DB.general)or{}local t=tonumber(e.castbarNonInterruptibleR)local n=tonumber(e.castbarNonInterruptibleG)local e=tonumber(e.castbarNonInterruptibleB)if t and n and e then
return t,n,e,1 end
end ExportPublic("MSUF_GetNonInterruptibleCastColor", MSUF_GetNonInterruptibleCastColor) local function o(e)if type(e)=="number"then return tonumber(tostring(e))end local n=_G.MSUF_ToPlainNumber
if type(n)=="function"then local e=n(e)if type(e)=="number"then return tonumber(tostring(e))end return e
end local n=type(e)if n=="number"or n=="string"then return tonumber(tostring(e))end return nil
end local e=nil
local r=-1 local function l()local n=_G.MSUF__castTimeGlobalRev or 1 if r==n and e~=nil then
return e end
t()local t=(MSUF_DB and MSUF_DB.general)or nil
if t and t.castbarShowGlow==false then e=false
else e=true
end r=n
return e end
local function MSUF_ResetCastbarGlowFade(e)if not e or not e.statusBar then return end
local e=e.statusBar if not e._msufGlowApplied then
return end
local t,r,a,n=e._msufGlowBaseR,e._msufGlowBaseG,e._msufGlowBaseB,e._msufGlowBaseA if type(t)~="number"or type(r)~="number"or type(a)~="number"then
e._msufGlowApplied=nil e._msufGlowLastP=nil
return end
if n==nil then n=1 end e._msufGlowSkipBase=true
if type(_G.MSUF_SetStatusBarColorIfChanged)=="function"then _G.MSUF_SetStatusBarColorIfChanged(e,t,r,a,n)else e:SetStatusBarColor(t,r,a,n)end e._msufGlowSkipBase=nil
e._msufGlowApplied=nil e._msufGlowLastP=nil
end ExportPublic("MSUF_ResetCastbarGlowFade", MSUF_ResetCastbarGlowFade) local function MSUF_ApplyCastbarGlowFade(e,r,t)if not e or not e.statusBar then return end if(e._msufIsPreview or e.MSUF_testMode)and not _G.MSUF_UnitEditModeActive then
return end
if e.interrupted then return
end if e.interruptFeedbackEndTime then
local n=(GetTimePreciseSec and GetTimePreciseSec())or GetTime()if n<e.interruptFeedbackEndTime then
return end
end if not l()then
_G.MSUF_ResetCastbarGlowFade(e)return
end local n=o(r)local t=o(t)if type(n)~="number"or type(t)~="number"or t<=0 then
return end
if n<0 then n=0 end if n>t then n=t end
local n=1-(n/t)if n<0 then n=0 elseif n>1 then n=1 end
n=n*n local e=e.statusBar
local t=e._msufGlowLastP if type(t)=="number"then
local e=n-t if e<0 then e=-e end
if e<0.02 then return
end end
e._msufGlowLastP=n local t,r,a,o=e._msufGlowBaseR,e._msufGlowBaseG,e._msufGlowBaseB,e._msufGlowBaseA
if type(t)~="number"or type(r)~="number"or type(a)~="number"then if e.GetStatusBarColor then
local l,n,i,d=e:GetStatusBarColor()t,r,a,o=l,n,i,d
e._msufGlowBaseR,e._msufGlowBaseG,e._msufGlowBaseB,e._msufGlowBaseA=t,r,a,o end
end if type(t)~="number"or type(r)~="number"or type(a)~="number"then
return end
if o==nil then o=1 end local l=t+(1-t)*n
local t=r+(1-r)*n local n=a+(1-a)*n
e._msufGlowSkipBase=true if type(_G.MSUF_SetStatusBarColorIfChanged)=="function"then
_G.MSUF_SetStatusBarColorIfChanged(e,l,t,n,o)else
e:SetStatusBarColor(l,t,n,o)end
e._msufGlowSkipBase=nil e._msufGlowApplied=true
end ExportPublic("MSUF_ApplyCastbarGlowFade", MSUF_ApplyCastbarGlowFade) local function MSUF_CB_ApplyColor(e,t)if e and e.UpdateColorForInterruptible then local n=e:UpdateColorForInterruptible()if _G.MSUF_KickReady_RefreshFrame then _G.MSUF_KickReady_RefreshFrame(e,t)end return n
end end
ExportPublic("MSUF_CB_ApplyColor", MSUF_CB_ApplyColor)
local function G(e,t)if not e or e==""then return e,false end
t=tonumber(t)or 0 if t<=0 then return"",e~=""end
local n,r,a=1,#e,0
while n<=r and a<t do local t=string.byte(e,n)if not t then break end
if t<128 then n=n+1 elseif t<224 then n=n+2 elseif t<240 then n=n+3 else n=n+4 end
a=a+1 end
if n>r then return e,false end
return string.sub(e,1,n-1),true end
local function K(e)if not e then return nil end
local n=e.unit or e.MSUF_unit or e._msufUnit or e.unitKey
if type(n)=="string"and n~=""then return n end
local n=e._msufBarKey or e.barKey or e.key
if type(n)=="string"and n~=""then if n=="player"or n=="target"or n=="focus"or n=="boss"or n:sub(1,4)=="boss"then return n end end
if e==_G.MSUF_PlayerCastbar or e==_G.MSUF_PlayerCastbarPreview then return"player"end
if e==_G.MSUF_TargetCastbar or e==_G.MSUF_TargetCastbarPreview then return"target"end
if e==_G.MSUF_FocusCastbar or e==_G.MSUF_FocusCastbarPreview then return"focus"end
local e=e.GetName and e:GetName()or nil
if type(e)=="string"then if e:find("Target",1,true)then return"target"end if e:find("Focus",1,true)then return"focus"end if e:find("Player",1,true)then return"player"end if e:find("boss",1,true)or e:find("Boss",1,true)then return"boss"end end
return nil end
local function C(e)if not e then return false end
t()local n=(MSUF_DB and MSUF_DB.general)or nil
if not n then return false end
local a=K(e)local t=tonumber(n.castbarSpellNameShortening)or 0
if a and tostring(a):match("^boss")and n.bossCastSpellNameShortening~=nil then t=tonumber(n.bossCastSpellNameShortening)or t end
if t<=0 then return false end
local r=tonumber(n.castbarSpellNameMaxLen)or 30
local t=tonumber(n.castbarSpellNameReservedSpace)or 8
if a and tostring(a):match("^boss")then
local e=tonumber(n.bossCastSpellNameMaxLen or n.bossCastSpellNameMaxChars or n.bossSpellNameMaxLen)
local a=tonumber(n.bossCastSpellNameReservedSpace or n.bossCastSpellNameReserved or n.bossSpellNameReservedSpace)
if e and e>0 then r=e end
if a and a>=0 then t=a end
end
r=math.floor((tonumber(r)or 30)+0.5)if r<1 then r=1 elseif r>80 then r=80 end
t=math.floor((tonumber(t)or 0)+0.5)if t<0 then t=0 elseif t>160 then t=160 end
local a=(_G.MSUF_CastbarStyleRevision or 1)..":"..r..":"..t
return true,r,t,a end
local function MSUF_GetCastbarSpellNameShorteningConfig(e)return C(e)end ExportPublic("MSUF_GetCastbarSpellNameShorteningConfig", MSUF_GetCastbarSpellNameShorteningConfig)
local function A(e,t)if t==nil then return t end
local n=_G.issecretvalue if type(n)=="function"and n(t)==true then return t end
local n=type(t)
if n~="string"and n~="number"and n~="boolean"then return t end
local n=tostring(t or"")if n==""then if e then e._msufRawCastText=n;e._msufShortCastText=n;e._msufShortCastTextKey=false end return n end
local r,a,t,S=C(e)
if not r then if e then e._msufRawCastText=n;e._msufShortCastText=n;e._msufShortCastTextKey=false end return n end
if e and e._msufRawCastText==n and e._msufShortCastTextKey==S and e._msufShortCastText~=nil then return e._msufShortCastText end
local r,o=G(n,a)local r=o and(r.."...")or n
if e then e._msufRawCastText=n;e._msufShortCastText=r;e._msufShortCastTextKey=S end
return r end
local function MSUF_ShortenCastbarSpellName(e,t)return A(e,t)end ExportPublic("MSUF_ShortenCastbarSpellName", MSUF_ShortenCastbarSpellName)
local function MSUF_RefreshCastbarSpellNameText(e)if not(e and e.castText)then return end
local t=e._msufRawCastText
if t==nil then return end
i(e.castText,A(e,t))end
ExportPublic("MSUF_RefreshCastbarSpellNameText", MSUF_RefreshCastbarSpellNameText)
local function MSUF_CB_ApplyTexts(e,r,n,t)if not e then return end
if r~=nil then if n==nil then n=r.castText end
if t==nil then t=r.timeText end end
if n~=nil and e.castText then i(e.castText,A(e,n))end if t~=nil and e.timeText then
i(e.timeText,t)end
end ExportPublic("MSUF_CB_ApplyTexts", MSUF_CB_ApplyTexts) local function MSUF_ClearEmpowerState(e)if not e then return end e.isEmpower=nil
e.empowerStartTime=nil e.empowerStageEnds=nil
e.empowerTotalBase=nil e.empowerTotalWithGrace=nil
e.empowerNextStage=nil e.MSUF_empowerLayoutPending=nil
e.MSUF_wantsEmpower=nil e.MSUF_empowerRetryCount=nil
e.MSUF_empowerRetryActive=nil e._msufEmpowerTotalNum=nil
e._msufEmpowerStartNum=nil e._msufEmpowerBaseNum=nil
e._msufEmpowerStageEndsNum=nil e._msufEmpowerMinMaxSet=nil
e._msufEmpowerElapsed=nil e._msufEmpowerTimerDriven=nil
if e.empowerTicks then for n=1,#e.empowerTicks do
local e=e.empowerTicks[n]if e then
e:Hide()if e.MSUF_glow then e.MSUF_glow:Hide()end
if e.MSUF_flash then e.MSUF_flash:Hide()end end
end end
if e.empowerSegments then for n=1,#e.empowerSegments do
local e=e.empowerSegments[n]if e then e:Hide()end
end end
end
ExportPublic("MSUF_ClearEmpowerState", MSUF_ClearEmpowerState)
