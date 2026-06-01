local r={player={w="castbarPlayerBarWidth",h="castbarPlayerBarHeight",x="castbarPlayerOffsetX",y="castbarPlayerOffsetY",dx=0,dy=5,reanchor="MSUF_ReanchorPlayerCastBar",test="MSUF_SetPlayerCastbarTestMode"},target={w="castbarTargetBarWidth",h="castbarTargetBarHeight",x="castbarTargetOffsetX",y="castbarTargetOffsetY",dx=65,dy=-15,reanchor="MSUF_ReanchorTargetCastBar",test="MSUF_SetTargetCastbarTestMode"},focus={w="castbarFocusBarWidth",h="castbarFocusBarHeight",x="castbarFocusOffsetX",y="castbarFocusOffsetY",fallbackX="castbarTargetOffsetX",fallbackY="castbarTargetOffsetY",dx=65,dy=-15,reanchor="MSUF_ReanchorFocusCastBar",test="MSUF_SetFocusCastbarTestMode"},boss={w="bossCastbarWidth",h="bossCastbarHeight",x="bossCastbarOffsetX",y="bossCastbarOffsetY",dx=0,dy=0,reanchor="MSUF_ReanchorBossCastBar",test="MSUF_SetBossCastbarTestMode"},}local function s()if type(EnsureDB)=="function"then EnsureDB()end
MSUF_DB=MSUF_DB or{}MSUF_DB.general=MSUF_DB.general or{}return MSUF_DB.general
end
local function d()return InCombatLockdown and InCombatLockdown()end
local function o(t)t=tonumber(t)or 0;return t>=0 and math.floor(t+0.5)or math.ceil(t-0.5)end
local function i(e,t)return tonumber(e[t.x])or(t.fallbackX and tonumber(e[t.fallbackX]))or t.dx or 0 end
local function c(e,t)return tonumber(e[t.y])or(t.fallbackY and tonumber(e[t.fallbackY]))or t.dy or 0 end
local function l(t)if type(_G.MSUF_ApplyCastbarUnitAndSync)=="function"then _G.MSUF_ApplyCastbarUnitAndSync(t)else
local e=r[t]local e=e and e.reanchor and _G[e.reanchor]if type(e)=="function"then e()end
if type(MSUF_UpdateCastbarVisuals)=="function"then MSUF_UpdateCastbarVisuals()end
if t=="boss"and not d()and type(_G.MSUF_UpdateBossCastbarPreview)=="function"then _G.MSUF_UpdateBossCastbarPreview()end
end
if type(_G.MSUF_PositionCastbarPreviewUnit)=="function"then _G.MSUF_PositionCastbarPreviewUnit(t)end
if type(MSUF_UpdateCastbarEditInfo)=="function"then MSUF_UpdateCastbarEditInfo(t)end
if type(MSUF_SyncCastbarPositionPopup)=="function"then MSUF_SyncCastbarPositionPopup(t)end
end
local function f(e,t)if type(MSUF_ClampToSlider)~="function"then return end
local n,a=_G.MSUF_CastbarBossXOffsetSlider,_G.MSUF_CastbarBossYOffsetSlider
if n then e[t.x]=MSUF_ClampToSlider(n,tonumber(e[t.x])or 0)end
if a then e[t.y]=MSUF_ClampToSlider(a,tonumber(e[t.y])or 0)end
end
local function u(t)if not(_G.MSUF_UnitEditModeActive and C_Timer and C_Timer.After)then return end
local e=r[t]local a=e and _G[e.test]if type(a)~="function"then return end
a(true,true)_G.MSUF_CastbarPreviewPulseTimers=_G.MSUF_CastbarPreviewPulseTimers or{}local e=_G.MSUF_CastbarPreviewPulseTimers
if type(e[t])=="table"then e[t].cancelled=true end
local n={}e[t]=n
C_Timer.After(8,function()if n.cancelled or e[t]~=n or not _G.MSUF_UnitEditModeActive or d()then return end
local n=s()if n[(t=="player"and"playerCastbarTestMode")or(t=="target"and"targetCastbarTestMode")or(t=="focus"and"focusCastbarTestMode")or"bossCastbarTestMode"]then return end
local n=_G.MSUF_EM2 and _G.MSUF_EM2.CastPopup
if n and n.IsOpen and n:IsOpen()then return end
e[t]=nil
a(false,true)end)end
local function S(e,a,t)local n=_G.MSUF_EM2_SetPreviewNudgeTarget
if type(n)~="function"then return end
n({frame=e,IsActive=function()return _G.MSUF_UnitEditModeActive and e.IsShown and e:IsShown()end,Nudge=function(e,r,n)if not _G.MSUF_UnitEditModeActive or d()then return end
local e=s()if type(_G.MSUF_EM_UndoBeforeChange)=="function"then _G.MSUF_EM_UndoBeforeChange("castbar",a,true)end
e[t.x]=o(i(e,t)+(r or 0))e[t.y]=o(c(e,t)+(n or 0))if a=="boss"then f(e,t)end
l(a)end,})end
local function _(a,t)local t=_G.MSUF_GetCastbarWidthSourceKey and _G.MSUF_GetCastbarWidthSourceKey(t)local e=_G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
local t=t and a[t]if type(e)=="function"then return e(t)~=nil end
return t=="unitframe"or t=="essential"or t=="utility"end
function _G.MSUF_SetupCastbarPreviewEditHandlers(n,a)if not n or n.MSUF_PreviewEditHandlersSetup then return end
local e=r[a]or r.player
n.MSUF_PreviewEditHandlersSetup=true
n:SetClampedToScreen(true)n:SetFrameStrata("DIALOG")n:EnableMouse(true)n:SetScript("OnMouseDown",function(t,n)if _G.MSUF_UnitEditModeActive then S(t,a,e)end
if n=="RightButton"then
if _G.MSUF_UnitEditModeActive and not MSUF_EditModeSizing and not d()and type(MSUF_OpenCastbarPositionPopup)=="function"then MSUF_OpenCastbarPositionPopup(a,t)end
return
end
if n~="LeftButton"or not _G.MSUF_UnitEditModeActive or d()then return end
local n=s()if not n.castbarPlayerPreviewEnabled then return end
t.isDragging,t.dragMoved,t._msufUndoFired=true,false,false
local r=UIParent:GetEffectiveScale()or 1
local S,d=GetCursorPosition()t.dragStartCursorX,t.dragStartCursorY=S/r,d/r
if MSUF_EditModeSizing then
t.dragMode="SIZE"t.dragStartWidth=tonumber(n[e.w])or tonumber(n.castbarGlobalWidth)or t:GetWidth()or 250
t.dragStartHeight=tonumber(n[e.h])or tonumber(n.castbarGlobalHeight)or t:GetHeight()or 18
else
t.dragMode="MOVE"t.dragStartOffsetX,t.dragStartOffsetY=i(n,e),c(n,e)local e=t:GetEffectiveScale()or 1
local a,n,o,d=t:GetLeft()or 0,t:GetRight()or 0,t:GetTop()or 0,t:GetBottom()or 0
t._snapStartCX,t._snapStartCY=(a+n)*0.5*e/r,(o+d)*0.5*e/r
t._snapHW,t._snapHH=(n-a)*0.5*e/r,(o-d)*0.5*e/r
end
t:SetScript("OnUpdate",function(t)if not t.isDragging then t:SetScript("OnUpdate",nil);return end
local n=UIParent:GetEffectiveScale()or 1
local r,d=GetCursorPosition()local d,i=r/n-(t.dragStartCursorX or r/n),d/n-(t.dragStartCursorY or d/n)if not t.dragMoved and math.abs(d)+math.abs(i)<6 then return end
if not t.dragMoved then
t.dragMoved=true
if type(_G.MSUF_EM_UndoBeforeChange)=="function"then _G.MSUF_EM_UndoBeforeChange("castbar",a,false)end
end
local n=s()if t.dragMode=="SIZE"then
if not _(n,a)then n[e.w]=o(math.max(50,(t.dragStartWidth or 250)+d))end
n[e.h]=o(math.max(8,(t.dragStartHeight or 18)+i))else
local s,l=d,i
local r=_G.MSUF_EM2 and _G.MSUF_EM2.Snap
if r and r.IsEnabled and r.IsEnabled()and r.Apply then
local a,e=r.Apply((t._snapStartCX or 0)+d,(t._snapStartCY or 0)+i,t._snapHW or 0,t._snapHH or 0,"castbar_"..a)s,l=a-(t._snapStartCX or 0),e-(t._snapStartCY or 0)end
n[e.x],n[e.y]=o((t.dragStartOffsetX or 0)+s),o((t.dragStartOffsetY or 0)+l)if a=="boss"then f(n,e)end
end
l(a)end)end)n:SetScript("OnMouseUp",function(t,e)if e~="LeftButton"then return end
local e=t.dragMoved
if t.isDragging then
t.isDragging=false
t:SetScript("OnUpdate",nil)local t=_G.MSUF_EM2 and _G.MSUF_EM2.Snap
if t and t.HideGuides then t.HideGuides()end
end
u(a)if not e and _G.MSUF_UnitEditModeActive and not d()and type(MSUF_OpenCastbarPositionPopup)=="function"then MSUF_OpenCastbarPositionPopup(a,t)end
end)end