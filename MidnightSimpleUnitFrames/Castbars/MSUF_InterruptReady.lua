local n,l=_G.C_Spell,_G.C_Timer
local d={DEATHKNIGHT={DEFAULT=47528},DEMONHUNTER={DEFAULT=183752},DRUID={DEFAULT=106839,BALANCE=78675},EVOKER={DEFAULT=351338},HUNTER={DEFAULT=147362,SURVIVAL=187707},MAGE={DEFAULT=2139},MONK={DEFAULT=116705},PALADIN={DEFAULT=96231},PRIEST={DEFAULT=15487},ROGUE={DEFAULT=1766},SHAMAN={DEFAULT=57994},WARLOCK={DEFAULT=19647,DEMONOLOGY=119914},WARRIOR={DEFAULT=6552},}local c={[102]="BALANCE",[255]="SURVIVAL",[266]="DEMONOLOGY"}local o,r,a={},nil,0
local function t()if type(_G.MSUF_EnsureDB)=="function"then _G.MSUF_EnsureDB()elseif type(t)=="function"then t()end
return(_G.MSUF_DB and _G.MSUF_DB.general)or{}end
local function u(e)if e==nil then return nil end
local n=_G.ToPlain
if type(n)=="function"then local e=tonumber(tostring(n(e)));if e~=nil then return e end end
local n=type(e)if n=="number"or n=="string"then return tonumber(tostring(e))end
return nil
end
local function i()local n,e=UnitClass and UnitClass("player")o.classToken=e
local e=e and d[e]local t=e and e.DEFAULT
if e and GetSpecialization and GetSpecializationInfo then
local r=select(1,GetSpecializationInfo(GetSpecialization()))local n=c[r]if n and e[n]then t=e[n]end
o.specID=r
end
o.spellID=t
return t
end
local function d()local e=o.spellID or i()if not(e and n and n.GetSpellCooldownDuration)then return nil end
return n.GetSpellCooldownDuration(e)end
local function c()local e=d()if not e then return false end
if e.IsZero then return e:IsZero()and true or false end
local e=e.GetRemainingDuration and e:GetRemainingDuration()or(e.GetRemaining and e:GetRemaining())return(u(e)or 0)<=0.05
end
local function h()local e=d()if not e then return nil end
return u(e.GetRemainingDuration and e:GetRemainingDuration()or(e.GetRemaining and e:GetRemaining()))end
local function d(e,n,o,r)local e=t()[e]if type(e)=="table"then
n,o,r=tonumber(e[1]or e["1"])or n,tonumber(e[2]or e["2"])or o,tonumber(e[3]or e["3"])or r
end
return n,o,r,1
end
local function u()local a,l,o,i=d("kickReadyColor",0,1,0)local t,e,n,r=d("kickNotReadyColor",1,0,0)if _G.CreateColor then return _G.CreateColor(a,l,o,i),_G.CreateColor(t,e,n,r)end
return{GetRGBA=function()return a,l,o,i end},{GetRGBA=function()return t,e,n,r end}end
local function s(t)local e,n=u()return t and e or n
end
local function R(n,e)if e=="target"then return n.kickReadyShowTarget==true end
if e=="focus"then return n.kickReadyShowFocus==true or n.enableFocusKickIcon==true end
if e=="boss"or(type(e)=="string"and e:match("^boss%d+$"))then return n.kickReadyShowBoss==true end
return false
end
local function k(e)return(e.kickReadyStyle=="border")and"border"or"box"end
local function d(n)local e=n.kickReadyBox
if e then return e end
e=CreateFrame("Frame",nil,n)e.fill=e:CreateTexture(nil,"OVERLAY")e.fill:SetAllPoints()e.fill:SetTexture("Interface\\Buttons\\WHITE8x8")e:Hide()n.kickReadyBox=e
return e
end
local function _(e)local t=t()local r=d(e)local n=e.statusBar and e.statusBar:GetHeight()or e:GetHeight()or 16
local o=t.kickReadyAutoSize==false and tonumber(t.kickReadySize)or n
o=math.max(8,math.min(o or 16,80))local n=t.kickReadyAnchor or"RIGHT"local a,l=tonumber(t.kickReadyOffsetX)or 4,tonumber(t.kickReadyOffsetY)or 0
local t=n=="RIGHT"and"LEFT"or n=="LEFT"and"RIGHT"or n=="TOP"and"BOTTOM"or n=="BOTTOM"and"TOP"or n
r:SetSize(o,o)r:ClearAllPoints()r:SetPoint(t,e.statusBar or e,n,a,l)return r
end
local function d(e)local e=e and e._msufOutline
return e and e.top,e and e.bottom,e and e.left,e and e.right
end
local function C(r,n,t,e,o)local a,d,l,i=d(r)if not a then return end
a:SetVertexColor(n,t,e,o);d:SetVertexColor(n,t,e,o);l:SetVertexColor(n,t,e,o);i:SetVertexColor(n,t,e,o)r._kickReadyBorderTinted=true
end
local function u(e)if not(e and e._kickReadyBorderTinted)then return end
e._kickReadyBorderTinted=nil
if type(_G.MSUF_ApplyCastbarOutline)=="function"then _G.MSUF_ApplyCastbarOutline(e,true)end
end
local function S(e,n)if n then local t=n.apiNotInterruptibleRaw
if t~=nil then return t end end
if e then local n=e._msufApiNotInterruptibleRaw
if n~=nil then return n end
return e.MSUF_apiNotInterruptibleRaw end
return nil
end
local function G(n,t)local e=s(n)if t~=nil and _G.CreateColor and _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorFromBoolean then
e=_G.C_CurveUtil.EvaluateColorFromBoolean(t,_G.CreateColor(0.6,0.6,0.6,1),e)end
if e and e.GetRGBA then return e:GetRGBA()end
return n and 0 or 1,n and 1 or 0,0,1
end
local function d(e)if not e then return end
if e.kickReadyBox then e.kickReadyBox:Hide();e.kickReadyBox._kickReadyShown=nil end
u(e)end
local function f(e,n)if not(e and e.statusBar)then return end
local t=t()if not R(t,e.unit)or not(e.MSUF_castActive or(n and n.active))then d(e);return end
if e.isNotInterruptible==true or e.MSUF_kickInterruptibleConfirmed==false or(n and n.isNotInterruptible==true)then d(e);return end
local o=c()local n=S(e,n)local r,a,o,l=G(o,n)if k(t)=="border"then
if e.kickReadyBox then e.kickReadyBox:Hide();e.kickReadyBox._kickReadyShown=nil end
C(e,r,a,o,l)else
u(e)local e=_(e)e.fill:SetVertexColor(r,a,o,l)if n~=nil and e.SetAlphaFromBoolean then e:SetAlphaFromBoolean(n,0,1)else e:SetAlpha(1)end
e:Show();e._kickReadyShown=true
end
end
local function d(e)e(_G.MSUF_TargetCastbar or _G.TargetCastBar)e(_G.MSUF_FocusCastbar or _G.FocusCastBar)local n=_G.MSUF_BossCastbars
if type(n)=="table"then for t=1,#n do e(n[t])end end
end
local function n()d(function(e)f(e)end)end
local function d()if r and r.Cancel then r:Cancel()end
r=nil
local e=h()if not(e and e>0.05 and l and l.NewTimer)then return end
a=a+1
local t=a
r=l.NewTimer(math.min(e+0.05,90),function()if t==a then n()end end)end
function _G.MSUF_KickReady_Init()i();return o.spellID end
function _G.MSUF_KickReady_IsReady()local e=c();d();return e end
function _G.MSUF_KickReady_EvaluateColor(e)return s(e)end
function _G.MSUF_KickReady_ApplyLayout(e)if e and R(t(),e.unit)then _(e)end end
function _G.MSUF_KickReady_RefreshFrame(e,n)f(e,n);d()end
local e=CreateFrame("Frame","MSUF_InterruptReady_EventFrame")e:RegisterEvent("PLAYER_LOGIN")e:RegisterEvent("PLAYER_ENTERING_WORLD")e:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")e:RegisterEvent("SPELL_UPDATE_COOLDOWN")e:SetScript("OnEvent",function()i()n()end)
