local e,e=...local i=UIParent
local l=C_Timer and C_Timer.After
local r=C_Timer and C_Timer.NewTicker
local e,t
local c,F=false,false
local o
local function n()local e=_G.MSUF_EnsureDB
if type(e)=="function"then e()end
MSUF_DB=MSUF_DB or{}MSUF_DB.general=MSUF_DB.general or{}local e=MSUF_DB.general
if e.enableFocusKickIcon==nil then e.enableFocusKickIcon=false end
if e.focusKickIconOffsetX==nil then e.focusKickIconOffsetX=300 end
if e.focusKickIconOffsetY==nil then e.focusKickIconOffsetY=0 end
if e.focusKickIconWidth==nil then e.focusKickIconWidth=40 end
if e.focusKickIconHeight==nil then e.focusKickIconHeight=40 end
return e
end
local function u()local t=n()if MSUF_DB.focus and MSUF_DB.focus.enabled==false then return false end
local e=_G.MSUF_ShouldUseMSUFCastbar
if type(e)=="function"and not e("focus",t)then return false end
return t.enableFocusKickIcon==true
end
local function a(e,t,n)e=tonumber(e)or 0
if e<t then return t end
if e>n then return n end
return e
end
local function d(e)e=tonumber(e)or 0
if e>=0 then return math.floor(e+0.5)end
return math.ceil(e-0.5)end
local function f(t)local e=tonumber(t.focusKickTextSize)if e then return a(e,8,24)end
return((tonumber(t.focusKickIconHeight)or 40)>=48)and 14 or 12
end
local function T(e)if not e then return end
if e.MSUF_timeTicker and e.MSUF_timeTicker.Cancel then e.MSUF_timeTicker:Cancel()end
e.MSUF_timeTicker,e.MSUF_timeUpdater,e.MSUF_timeAccum=nil,nil,nil
e:SetScript("OnUpdate",nil)end
local function _()if not(e and e:IsShown()and e.timeText)then return T(e)end
local t=e.MSUF_sourceCastBar or _G.FocusCastBar or _G.MSUF_FocusCastBar
if not(t and t.timeText)then
e.timeText:SetText("")e.timeText:SetAlpha(0)return
end
e.timeText:SetText(t.timeText:GetText()or"")e.timeText:SetAlpha(t.timeText:GetAlpha()or 1)end
local function m()if not e or e.MSUF_timeUpdater then return end
e.MSUF_timeUpdater,e.MSUF_timeAccum=true,0
if r then
e.MSUF_timeTicker=r(0.05,_)else
e:SetScript("OnUpdate",function(e,t)if not e:IsShown()then return T(e)end
e.MSUF_timeAccum=(e.MSUF_timeAccum or 0)+(t or 0)if e.MSUF_timeAccum>=0.05 then e.MSUF_timeAccum=0;_()end
end)end
end
local function s()local n=n()local i=(type(_G.MSUF_GetFontPath)=="function"and _G.MSUF_GetFontPath())or STANDARD_TEXT_FONT or"Fonts\\FRIZQT__.TTF"local o=(type(_G.MSUF_GetFontFlags)=="function"and _G.MSUF_GetFontFlags())or"OUTLINE"local n=f(n)if e and e.timeText then e.timeText:SetFont(i,n,o)end
if t and t.timeText then t.timeText:SetFont(i,n,o)end
if type(_G.MSUF_GetConfiguredFontColor)=="function"then
local i,o,n=_G.MSUF_GetConfiguredFontColor()if i and o and n then
if e and e.timeText then e.timeText:SetTextColor(i,o,n,1)end
if t and t.timeText then t.timeText:SetTextColor(i,o,n,1)end
end
end
end
local function f(r,n,o,t)if not(e and e.edges)then return end
t=t or 1
for i=1,#e.edges do e.edges[i]:SetVertexColor(r,n,o,t)end
end
local function h(n,t)if not e then return end
if type(_G.MSUF_KickReady_Init)=="function"then _G.MSUF_KickReady_Init()end
if e.icon and e.icon.SetDesaturated then e.icon:SetDesaturated(n==true)end
if n==true then f(0.6,0.6,0.6,1);return end
local e
if type(_G.MSUF_KickReady_IsReady)=="function"and type(_G.MSUF_KickReady_EvaluateColor)=="function"then
e=_G.MSUF_KickReady_EvaluateColor(_G.MSUF_KickReady_IsReady())end
if t~=nil and e and _G.CreateColor and _G.C_CurveUtil and _G.C_CurveUtil.EvaluateColorFromBoolean then
e=_G.C_CurveUtil.EvaluateColorFromBoolean(t,_G.CreateColor(0.6,0.6,0.6,1),e)end
if e and e.GetRGBA then f(e:GetRGBA())else f(1,0.2,0.2,1)end
end
local function S()if not(e and e.edges)then return end
local t,i,o,n=e.edges[1],e.edges[2],e.edges[3],e.edges[4]t:ClearAllPoints();t:SetPoint("TOPLEFT",e,"TOPLEFT");t:SetPoint("TOPRIGHT",e,"TOPRIGHT");t:SetHeight(2)i:ClearAllPoints();i:SetPoint("BOTTOMLEFT",e,"BOTTOMLEFT");i:SetPoint("BOTTOMRIGHT",e,"BOTTOMRIGHT");i:SetHeight(2)o:ClearAllPoints();o:SetPoint("TOPLEFT",e,"TOPLEFT");o:SetPoint("BOTTOMLEFT",e,"BOTTOMLEFT");o:SetWidth(2)n:ClearAllPoints();n:SetPoint("TOPRIGHT",e,"TOPRIGHT");n:SetPoint("BOTTOMRIGHT",e,"BOTTOMRIGHT");n:SetWidth(2)end
local function r()if not e then return end
local t=n()local n=a(t.focusKickIconWidth,16,128)local o=a(t.focusKickIconHeight,16,128)e:SetParent(i)e:ClearAllPoints()e:SetPoint("CENTER",i,"CENTER",t.focusKickIconOffsetX or 300,t.focusKickIconOffsetY or 0)e:SetSize(n,o)S()s()end
local function S()if e then return e end
e=CreateFrame("Frame","MSUF_FocusKickIcon",i,"BackdropTemplate")e:SetFrameStrata("HIGH")e:SetFrameLevel(50)e:Hide()e:HookScript("OnHide",T)e.bg=e:CreateTexture(nil,"BACKGROUND")e.bg:SetAllPoints()e.bg:SetColorTexture(0,0,0,0.9)e.icon=e:CreateTexture(nil,"ARTWORK")e.icon:SetPoint("TOPLEFT",1,-1)e.icon:SetPoint("BOTTOMRIGHT",-1,1)e.icon:SetTexCoord(0.07,0.93,0.07,0.93)e.edges={}for n=1,4 do
local t=e:CreateTexture(nil,"OVERLAY",nil,7)t:SetTexture("Interface\\Buttons\\WHITE8x8")e.edges[n]=t
end
e.timeText=e:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")e.timeText:SetPoint("BOTTOM",e,"BOTTOM",0,2)e.timeText:SetJustifyH("CENTER")e.timeText:SetText("")e.timeText:SetAlpha(0)e:EnableMouse(true)e:SetMovable(true)e:RegisterForDrag("LeftButton")e:SetScript("OnDragStart",function(e)e:StartMoving()end)e:SetScript("OnDragStop",function(e)e:StopMovingOrSizing()local c=n()local t,a=e:GetCenter()local e,n=i:GetCenter()if t and a and e and n then
c.focusKickIconOffsetX=d(t-e)c.focusKickIconOffsetY=d(a-n)end
r()if o then o()end
end)r()return e
end
local function p()if not e then return end
f(1,0.2,0.2,1)if e.bg then e.bg:SetColorTexture(0,0,0,0.9)end
if l then
l(0.18,function()if not e then return end
local e=_G.FocusCastBar or _G.MSUF_FocusCastBar
h(e and e.isNotInterruptible==true,e and e._msufApiNotInterruptibleRaw)end)end
local n=n()local d,t,a=6,0,6
local function o()if not(e and e:IsShown())then return end
t=t+1
local c=(t%2==0)and-1 or 1
e:ClearAllPoints()e:SetPoint("CENTER",i,"CENTER",(n.focusKickIconOffsetX or 300)+c*d,n.focusKickIconOffsetY or 0)if t<a and l then l(0.02,o)else r()end
end
o()end
local function f(e)if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(e,1,0.2,0.2,1)elseif DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then DEFAULT_CHAT_FRAME:AddMessage(e)else print(e)end
end
local function l(e)F=e and true or false
if t and t._selBorder then t._selBorder:SetShown(F)end
end
local function I(u,i)if not(c and F)then return false end
if InCombatLockdown and InCombatLockdown()then return false end
local e=n()local t=(IsControlKeyDown and IsControlKeyDown())and 10 or((IsShiftKeyDown and IsShiftKeyDown())and 5 or 1)e.focusKickIconOffsetX=a(d((e.focusKickIconOffsetX or 0)+(u or 0)*t),-500,500)e.focusKickIconOffsetY=a(d((e.focusKickIconOffsetY or 0)+(i or 0)*t),-500,500)r()if o then o()end
l(true)return true
end
local function T()if t then return t end
t=CreateFrame("Frame","MSUF_FocusKickPreviewFrame",i,"BackdropTemplate")t:SetFrameStrata("HIGH")t:SetFrameLevel(70)t:SetMovable(true)t:EnableMouse(true)t:EnableKeyboard(true)if t.SetPropagateKeyboardInput then t:SetPropagateKeyboardInput(true)end
t:RegisterForDrag("LeftButton")t.icon=t:CreateTexture(nil,"ARTWORK")t.icon:SetAllPoints()t._selBorder=t:CreateTexture(nil,"OVERLAY")t._selBorder:SetPoint("TOPLEFT",t,"TOPLEFT",-3,3)t._selBorder:SetPoint("BOTTOMRIGHT",t,"BOTTOMRIGHT",3,-3)t._selBorder:SetColorTexture(0.27,0.53,0.80,0.45)t._selBorder:Hide()t.timeText=t:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")t.timeText:SetPoint("BOTTOM",t,"BOTTOM",0,2)t.timeText:SetJustifyH("CENTER")t.timeText:SetText("5.0")local e=t:CreateAnimationGroup()e:SetLooping("REPEAT")local u=e:CreateAnimation("Animation")u:SetDuration(0.08)u:SetScript("OnUpdate",function()if t and t:IsShown()and t.timeText then
local e=8.0-(((GetTime and GetTime())or 0)%8.0)t.timeText:SetText(string.format("%.1f",e))end
end)t._msufFakeTimerAG=e
t:SetScript("OnMouseDown",function(t,e)if e=="LeftButton"then l(true)end end)t:SetScript("OnKeyDown",function(e,t)local o,n=0,0
if t=="LEFT"then o=-1 elseif t=="RIGHT"then o=1 elseif t=="UP"then n=1 elseif t=="DOWN"then n=-1 else
if e.SetPropagateKeyboardInput then e:SetPropagateKeyboardInput(true)end
return
end
local t=_G.GetCurrentKeyBoardFocus and _G.GetCurrentKeyBoardFocus()if t and t.IsObjectType and t:IsObjectType("EditBox")then return end
if e.SetPropagateKeyboardInput then e:SetPropagateKeyboardInput(false)end
if not I(o,n)and e.SetPropagateKeyboardInput then e:SetPropagateKeyboardInput(true)end
end)t:SetScript("OnHide",function(e)l(false);if e.SetPropagateKeyboardInput then e:SetPropagateKeyboardInput(true)end end)t:SetScript("OnDragStart",function(e)if not c then return end
if InCombatLockdown and InCombatLockdown()then f("In combat - cannot move Focus Interrupt Tracker preview.");return end
l(true)e:StartMoving()end)t:SetScript("OnDragStop",function(e)e:StopMovingOrSizing()if not c then return end
local t=n()local u,c=e:GetCenter()local e,n=i:GetCenter()if u and c and e and n then
t.focusKickIconOffsetX=a(d(u-e),-500,500)t.focusKickIconOffsetY=a(d(c-n),-500,500)r()if o then o()end
l(true)end
end)t:Hide()s()return t
end
o=function()if not c then if t then t:Hide()end;return end
local n=n()T()local r=a(n.focusKickIconWidth,16,128)local o=a(n.focusKickIconHeight,16,128)t:SetParent(i)t:ClearAllPoints()t:SetPoint("CENTER",i,"CENTER",n.focusKickIconOffsetX or 0,n.focusKickIconOffsetY or 0)t:SetSize(r,o)if t.icon then
local e=(e and e.icon and e.icon.GetTexture and e.icon:GetTexture())or"Interface\\Icons\\INV_Misc_QuestionMark"t.icon:SetTexture(e)end
s()t:Show()end
local function a(e)c=e and true or false
T()if not c then
if t._msufFakeTimerAG and t._msufFakeTimerAG.Stop then t._msufFakeTimerAG:Stop()end
l(false)t:Hide()return
end
if not u()then
c=false
if t._msufFakeTimerAG and t._msufFakeTimerAG.Stop then t._msufFakeTimerAG:Stop()end
l(false)t:Hide()f("Enable Focus Interrupt Tracker first to use the on-screen preview.")return
end
if t._msufFakeTimerAG and t._msufFakeTimerAG.Play then t._msufFakeTimerAG:Play()end
o()end
local i=false
local function t(e)n()i=true
if e then S();r()end
end
_G.MSUF_FocusKick_EnsureInitialized=t
function MSUF_InitFocusKickIcon()t(u())if type(_G.MSUF_FocusKickDriver_ForceUpdate)=="function"then _G.MSUF_FocusKickDriver_ForceUpdate()end
end
function MSUF_UpdateFocusKickIconOptions()t(u())if e then r()end
if type(_G.MSUF_FocusKickDriver_ForceUpdate)=="function"then _G.MSUF_FocusKickDriver_ForceUpdate()end
if o then o()end
end
_G.MSUF_FocusKick_SetPreviewEnabled=a
_G.MSUF_FocusKick_IsPreviewEnabled=function()return c end
_G.MSUF_FocusKick_UpdateAppearance=r
_G.MSUF_FocusKick_ApplyTimeTextFont=s
function _G.MSUF_FocusKick_ApplyCastState(t)n()if not u()then
if e then
if e.timeText then e.timeText:SetText("");e.timeText:SetAlpha(0)end
e:Hide()end
return
end
S()if not(t and t.active==true)then
if e.timeText then e.timeText:SetText("");e.timeText:SetAlpha(0)end
e:Hide()return
end
if e.icon and t.icon then
if type(_G.MSUF_SetIconTexture)=="function"then _G.MSUF_SetIconTexture(e.icon,t.icon,"")else e.icon:SetTexture(t.icon)end
end
e.MSUF_sourceCastBar=_G.FocusCastBar or _G.MSUF_FocusCastBar
h(t.isNotInterruptible==true,t.apiNotInterruptibleRaw)e._msufLastCastState=t
e:Show()r()m()_()end
function _G.MSUF_FocusKick_PlayInterruptFeedback()if not u()then return end
S()p()end
