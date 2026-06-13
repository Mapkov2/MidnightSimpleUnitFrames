-- Legacy compact castbar preview runtime.
-- This file is intentionally compact legacy code that creates draggable player/target/focus
-- preview bars for edit-mode/Menu2. Keep new behavior in the shared castbar preview helpers
-- where possible, and preserve these globals for compatibility.
local function _(e)local t=_G.MSUF_NS
if type(e)~="string"then return e end
if type(t)=="table"and type(t.Translate)=="function"then return t.Translate(e)end
local t=(type(t)=="table"and t.L)or _G.MSUF_L
return(type(t)=="table"and rawget(t,e))or e
end
local l={player="Player castbar preview",target="Target castbar preview",focus="Focus castbar preview",boss="Celestial Ruin",test="Test Cast",}local o={player={name="MSUF_PlayerCastbarPreview",width="castbarPlayerBarWidth",height="castbarPlayerBarHeight",x="castbarPlayerOffsetX",y="castbarPlayerOffsetY",detached="castbarPlayerDetached",showTime="showPlayerCastTime",test="playerCastbarTestMode"},target={name="MSUF_TargetCastbarPreview",width="castbarTargetBarWidth",height="castbarTargetBarHeight",x="castbarTargetOffsetX",y="castbarTargetOffsetY",detached="castbarTargetDetached",showTime="showTargetCastTime",test="targetCastbarTestMode"},focus={name="MSUF_FocusCastbarPreview",width="castbarFocusBarWidth",height="castbarFocusBarHeight",x="castbarFocusOffsetX",y="castbarFocusOffsetY",detached="castbarFocusDetached",showTime="showFocusCastTime",test="focusCastbarTestMode"},}local function r()if type(EnsureDB)=="function"then EnsureDB()end
MSUF_DB=MSUF_DB or{}MSUF_DB.general=MSUF_DB.general or{}return MSUF_DB.general
end
local function n()return _G.MSUF_InCombat==true
or((_G.InCombatLockdown and _G.InCombatLockdown())and true or false)or((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))and true or false)end
local function i()local e=r()local e=tonumber(e.msufUiScale or e.uiScale)or 1
if e<0.25 then return 0.25 end
if e>1.5 then return 1.5 end
return e
end
local function d(e,t)if not e then return end
if type(_G.MSUF_SetTextIfChanged)=="function"then _G.MSUF_SetTextIfChanged(e,t or"")elseif e.SetText then e:SetText(t or"")end
end
local function S(e,a,r)local t="CURRENT"if type(_G.MSUF_GetCastbarTimeFormat)=="function"then t=_G.MSUF_GetCastbarTimeFormat(e and e.unit)end
if e then e._msufCastTimeFormat=t end
if type(_G.MSUF_FormatCastbarTimeText)=="function"then return _G.MSUF_FormatCastbarTimeText(t,a,r)end
return string.format("%.1f",tonumber(a)or 0)end
local function u(t,n)local e,a=r(),o[t]if type(_G.MSUF_GetCastbarDesiredSize)=="function"then return _G.MSUF_GetCastbarDesiredSize(t,e,n,250,18)end
local r=tonumber(e[a.width])or tonumber(e.castbarGlobalWidth)or 250
local n=tonumber(e[a.height])or tonumber(e.castbarGlobalHeight)or 18
if not e[a.detached]and _G.MSUF_UnitFrames and _G.MSUF_UnitFrames[t]and _G.MSUF_UnitFrames[t].GetWidth then
r=tonumber(e[a.width])or _G.MSUF_UnitFrames[t]:GetWidth()or r
end
return r,n
end
local function s(e)local a=o[e]local t=_G[a.name]if t then return t end
local n,r=u(e)local t=_G.MSUF_CreateCastbarPreviewFrame
if type(t)~="function"then return nil end
local t=t(e,a.name,{parent=UIParent,strata="DIALOG",width=n,height=r,label=_(l[e]),showIcon=true,showTime=true,bgAlpha=0.8,initialValue=0.5,})if not t then return nil end
t:SetScale(i())_G[a.name]=t
if e=="player"then MSUF_PlayerCastbarPreview=t
elseif e=="target"then MSUF_TargetCastbarPreview=t
elseif e=="focus"then MSUF_FocusCastbarPreview=t end
if type(_G.MSUF_SetupCastbarPreviewEditHandlers)=="function"then _G.MSUF_SetupCastbarPreviewEditHandlers(t,e)end
return t
end
function MSUF_CreatePlayerCastbarPreview()return s("player")end
function MSUF_CreateTargetCastbarPreview()return s("target")end
function MSUF_CreateFocusCastbarPreview()return s("focus")end
local function i(t,e)if not e then return end
local a,s=r(),o[t]local r,n=u(t,e)if type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout)=="function"then _G.MSUF_ApplyPlayerCastbarSizeAndLayout(e,a,r,n)else e:SetSize(r or 250,n or 18)end
local n=tonumber(a[t=="player"and"castbarPlayerTimeOffsetX"or t=="target"and"castbarTargetTimeOffsetX"or"castbarFocusTimeOffsetX"])or tonumber(a.castbarPlayerTimeOffsetX)or-2
local r=tonumber(a[t=="player"and"castbarPlayerTimeOffsetY"or t=="target"and"castbarTargetTimeOffsetY"or"castbarFocusTimeOffsetY"])or tonumber(a.castbarPlayerTimeOffsetY)or 0
if e.timeText and e.statusBar then e.timeText:ClearAllPoints();e.timeText:SetPoint("RIGHT",e.statusBar,"RIGHT",n,r)end
if type(_G.MSUF_ApplyCastbarTimeTextLayout)=="function"then _G.MSUF_ApplyCastbarTimeTextLayout(e,t)end
local r=_G.MSUF_UnitFrames
local o=a[s.detached]and UIParent or(r and r[t])if not o then return end
local n=tonumber(a[s.x])local r=tonumber(a[s.y])if t=="player"then n,r=n or 0,r or 5
elseif t=="target"then n,r=n or 65,r or-15
else n,r=n or tonumber(a.castbarTargetOffsetX)or 65,r or tonumber(a.castbarTargetOffsetY)or-15 end
e:ClearAllPoints()if a[s.detached]then e:SetPoint("CENTER",o,"CENTER",n,r)elseif t=="player"then e:SetPoint("BOTTOM",o,"TOP",n,r)else e:SetPoint("BOTTOMLEFT",o,"TOPLEFT",n,r)end
if type(_G.MSUF_HardSyncCastbarPreview)=="function"then
_G.MSUF_HardSyncCastbarPreview(e,t=="player"and _G.MSUF_PlayerCastbar or t=="target"and _G.MSUF_TargetCastbar or _G.MSUF_FocusCastbar)end
end
function MSUF_PositionPlayerCastbarPreview()i("player",_G.MSUF_PlayerCastbarPreview or s("player"))end
function MSUF_PositionTargetCastbarPreview()i("target",_G.MSUF_TargetCastbarPreview or s("target"))end
function MSUF_PositionFocusCastbarPreview()i("focus",_G.MSUF_FocusCastbarPreview or s("focus"))end
local function u(e,t)if not e then return end
e.MSUF_testMode,e._msufTestActive,e.MSUF_testStart,e.MSUF_testDur=nil,nil,nil,nil
e:SetScript("OnUpdate",nil)if e.statusBar and e.statusBar.SetMinMaxValues then e.statusBar:SetMinMaxValues(0,1);e.statusBar:SetValue(0.5)end
if type(_G.MSUF_ResetCastbarGlowFade)=="function"then _G.MSUF_ResetCastbarGlowFade(e)end
if e.latencyBar then e.latencyBar:Hide()end
d(e.timeText,"")if e.castText then d(e.castText,_(l[t]or l.boss))end
end
local function c(e)if n()then u(e,e.unit);return end
local t=e.MSUF_testDur or 4.0
local a=(GetTimePreciseSec and GetTimePreciseSec())or GetTime()local a=(a-(e.MSUF_testStart or a))%t
local n=t-a
if e.statusBar then
if not e.statusBar._msufTestMinMax then e.statusBar:SetMinMaxValues(0,t);e.statusBar._msufTestMinMax=true end
e.statusBar:SetValue(a)end
local r=r()local a=o[e.unit]local a=not a or r[a.showTime]~=false
if e.timeText then
e.timeText:Show()e.timeText:SetAlpha(a and 1 or 0)d(e.timeText,a and S(e,n,t)or"")end
if e.latencyBar and type(_G.MSUF_PlayerCastbar_UpdateLatencyZone)=="function"then _G.MSUF_PlayerCastbar_UpdateLatencyZone(e,false,t)end
if type(_G.MSUF_ApplyCastbarGlowFade)=="function"then _G.MSUF_ApplyCastbarGlowFade(e,n,t)end
end
local function S(e,t)if not(e and e.statusBar)then return end
e.MSUF_testMode,e._msufTestActive=true,true
e.MSUF_testStart=(GetTimePreciseSec and GetTimePreciseSec())or GetTime()e.MSUF_testDur=4.0
e.statusBar._msufTestMinMax=nil
d(e.castText,_(l.test))if e.icon then e.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");if e.icon.Show then e.icon:Show()end end
e:Show()e:SetScript("OnUpdate",c)end
local function a(e,t,l)local r=r()if t and n()then t=false end
local a=o[e]if not l then r[a.test]=t and true or false end
local n=_G.MSUF_UnitEditModeActive==true and r[a.test]==true
local t
if e=="player"and not(r.castbarPlayerPreviewEnabled and _G.MSUF_PlayerCastbarPreview)then
if type(MSUF_InitSafePlayerCastbar)=="function"then MSUF_InitSafePlayerCastbar()end
t=_G.MSUF_PlayerCastbar
else
t=_G[a.name]or s(e)end
if not n then u(t,e);return end
i(e,t)S(t,e)if type(_G.MSUF_UpdateCastbarVisuals)=="function"then _G.MSUF_UpdateCastbarVisuals()end
end
function _G.MSUF_SetPlayerCastbarTestMode(t,e)a("player",t,e)end
function _G.MSUF_SetTargetCastbarTestMode(t,e)a("target",t,e)end
function _G.MSUF_SetFocusCastbarTestMode(e,t)a("focus",e,t)end
local function l(a)local e=tonumber(_G.MAX_BOSS_FRAMES)or 5
if e<1 or e>12 then e=5 end
if _G.MSUF_BossCastbarPreview then a(_G.MSUF_BossCastbarPreview,1)end
for t=2,e do local e=_G["MSUF_BossCastbarPreview"..t];if e then a(e,t)end end
end
function _G.MSUF_SetBossCastbarTestMode(e,a)local t=r()if e and n()then e=false end
if not a then t.bossCastbarTestMode=e and true or false end
local a=_G.MSUF_UnitEditModeActive==true and t.bossCastbarTestMode==true
if not n()and type(_G.MSUF_UpdateBossCastbarPreview)=="function"then _G.MSUF_UpdateBossCastbarPreview()end
l(function(e)if a then e.unit="boss";e._msufTestShowTime=t.showBossCastTime~=false;S(e,"boss")else u(e,"boss");if e.statusBar and e.statusBar.GetStatusBarTexture then local t=e.statusBar:GetStatusBarTexture();if t then t:SetAlpha(0)end;e.statusBar.MSUF_hideFillTexture=true end end
end)end
local function d()local e=r()if not e.castbarPlayerPreviewEnabled then return false end
if MSUF_DB.boss and MSUF_DB.boss.enabled==false then return false end
local t=_G.MSUF_ShouldUseMSUFCastbar
return type(t)=="function"and t("boss",e)==true or e.enableBossCastbar~=false
end
local e=false
function MSUF_RefreshBossPreview()if n()then e=true;return end
if d()and type(_G.MSUF_UpdateBossCastbarPreview)=="function"then _G.MSUF_UpdateBossCastbarPreview()end
end
local function S()e=true end
local function _()if e then e=false;MSUF_RefreshBossPreview()end
end
local function u()if _G.MSUF_BossPreviewEventDriver then return end
_G.MSUF_BossPreviewEventDriver=true
local e=_G.MSUF_EventBus_Register
if type(e)=="function"then
local t={"INSTANCE_ENCOUNTER_ENGAGE_UNIT","ENCOUNTER_START","ENCOUNTER_END","PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE"}for a=1,#t do e(t[a],"MSUF_BOSS_PREVIEW",MSUF_RefreshBossPreview)end
e("PLAYER_REGEN_DISABLED","MSUF_BOSS_PREVIEW_COMBAT_START",S)e("PLAYER_REGEN_ENABLED","MSUF_BOSS_PREVIEW_COMBAT_END",_)end
end
function MSUF_SetupBossCastbarPreviewEditMode()if n()or not d()then return end
if type(_G.MSUF_UpdateBossCastbarPreview)=="function"and not _G.MSUF_BossCastbarPreview then _G.MSUF_UpdateBossCastbarPreview()end
l(function(e)if e.statusBar and e.statusBar.GetStatusBarTexture then local t=e.statusBar:GetStatusBarTexture();if t then t:SetAlpha(0)end;e.statusBar.MSUF_hideFillTexture=true end
if type(_G.MSUF_SetupCastbarPreviewEditHandlers)=="function"then _G.MSUF_SetupCastbarPreviewEditHandlers(e,"boss")end
end)end
local function l()local e=_G.MSUF_ShouldUseBlizzardCastbar
local t=type(e)=="function"and e("player")==true
local function a(e)if e and not e.MSUF_PlayerCastbarAllowShown and e.Hide then e:Hide()end end
local e={_G.PlayerCastingBarFrame,_G.CastingBarFrame}for r=1,#e do
local e=e[r]if e then
e.MSUF_PlayerCastbarAllowShown=t
e.showCastbar=t
if not t then a(e)end
if not e.MSUF_HideHooked and hooksecurefunc then e.MSUF_HideHooked=true;hooksecurefunc(e,"Show",a)end
end
end
end
function MSUF_UpdatePlayerCastbarPreview()local e=r()if not e.castbarPlayerPreviewEnabled then
for t,e in pairs(o)do local e=_G[e.name];if e then e:Hide()end;a(t,false,true)end
if type(_G.MSUF_SetBossCastbarTestMode)=="function"then _G.MSUF_SetBossCastbarTestMode(false,true)end
if _G.MSUF_BossCastbarPreview then _G.MSUF_BossCastbarPreview:Hide()end
return
end
for t in pairs(o)do
local e=s(t)if e then i(t,e);e:Show()end
end
if not n()and type(_G.MSUF_UpdateBossCastbarPreview)=="function"then _G.MSUF_UpdateBossCastbarPreview();MSUF_SetupBossCastbarPreviewEditMode()end
if type(_G.MSUF_UpdateCastbarVisuals)=="function"then _G.MSUF_UpdateCastbarVisuals()end
if type(_G.MSUF_UpdateCastbarTextures)=="function"then _G.MSUF_UpdateCastbarTextures()end
end
function MSUF_PositionCastbarPreviewUnit(e)if _G.MSUF_UnitEditModeActive~=true or not r().castbarPlayerPreviewEnabled then return false end
if o[e]then local t=s(e);i(e,t);if t then t:Show();return true end end
if(e=="boss"or tostring(e):match("^boss%d*$"))and not n()and type(_G.MSUF_UpdateBossCastbarPreview)=="function"then _G.MSUF_UpdateBossCastbarPreview();return true end
return false
end
function MSUF_SyncBossCastbarSliders()local e=r()local e={MSUF_CastbarBossXOffsetSlider=e.bossCastbarOffsetX or 0,MSUF_CastbarBossYOffsetSlider=e.bossCastbarOffsetY or 0,MSUF_CastbarBossWidthSlider=e.bossCastbarWidth or 240,MSUF_CastbarBossHeightSlider=e.bossCastbarHeight or 18,}for e,t in pairs(e)do
local e=_G[e]if e and type(MSUF_SetSliderValueSilent)=="function"and type(MSUF_ClampToSlider)=="function"then
MSUF_SetSliderValueSilent(e,MSUF_ClampToSlider(e,tonumber(t)or 0))end
end
end
_G.MSUF_HideBlizzardPlayerCastbar=l
_G.MSUF_CreatePlayerCastbarPreview=_G.MSUF_CreatePlayerCastbarPreview or MSUF_CreatePlayerCastbarPreview
_G.MSUF_CreateTargetCastbarPreview=_G.MSUF_CreateTargetCastbarPreview or MSUF_CreateTargetCastbarPreview
_G.MSUF_CreateFocusCastbarPreview=_G.MSUF_CreateFocusCastbarPreview or MSUF_CreateFocusCastbarPreview
_G.MSUF_PositionPlayerCastbarPreview=MSUF_PositionPlayerCastbarPreview
_G.MSUF_PositionTargetCastbarPreview=MSUF_PositionTargetCastbarPreview
_G.MSUF_PositionFocusCastbarPreview=MSUF_PositionFocusCastbarPreview
_G.MSUF_PositionCastbarPreviewUnit=MSUF_PositionCastbarPreviewUnit
_G.MSUF_UpdatePlayerCastbarPreview=MSUF_UpdatePlayerCastbarPreview
_G.MSUF_SetupBossCastbarPreviewEditMode=MSUF_SetupBossCastbarPreviewEditMode
_G.MSUF_SyncBossCastbarSliders=MSUF_SyncBossCastbarSliders
u()if hooksecurefunc and type(_G.MSUF_UpdateBossCastbarPreview)=="function"and not _G.MSUF_BossPreviewSetupHooked then
_G.MSUF_BossPreviewSetupHooked=true
hooksecurefunc("MSUF_UpdateBossCastbarPreview",function()if not n()then MSUF_SetupBossCastbarPreviewEditMode()end end)end

do
local function MSUF_HideCastbarPreviewFrame(frame)
if not frame then return end
frame.MSUF_testMode=nil
frame._msufTestActive=nil
frame.MSUF_testStart=nil
frame.MSUF_testDur=nil
if frame.SetScript then frame:SetScript("OnUpdate",nil)end
if frame.statusBar then
if frame.statusBar.SetMinMaxValues then frame.statusBar:SetMinMaxValues(0,1)end
if frame.statusBar.SetValue then frame.statusBar:SetValue(0)end
local tex=frame.statusBar.GetStatusBarTexture and frame.statusBar:GetStatusBarTexture()
if tex and tex.SetAlpha then tex:SetAlpha(0)end
frame.statusBar.MSUF_hideFillTexture=true
end
if frame.timeText and frame.timeText.SetText then frame.timeText:SetText("")end
if frame.latencyBar and frame.latencyBar.Hide then frame.latencyBar:Hide()end
if frame.Hide then frame:Hide()end
end

function _G.MSUF_HideAllCastbarPreviews()
local db=_G.MSUF_DB
local g=db and db.general
if g then
g.castbarPlayerPreviewEnabled=false
g.playerCastbarTestMode=false
g.targetCastbarTestMode=false
g.focusCastbarTestMode=false
g.bossCastbarTestMode=false
end
MSUF_HideCastbarPreviewFrame(_G.MSUF_PlayerCastbarPreview)
MSUF_HideCastbarPreviewFrame(_G.MSUF_TargetCastbarPreview)
MSUF_HideCastbarPreviewFrame(_G.MSUF_FocusCastbarPreview)
if type(_G.MSUF_HideAllBossCastbarPreviews)=="function"then _G.MSUF_HideAllBossCastbarPreviews()end
local maxBoss=tonumber(_G.MSUF_MAX_BOSS_FRAMES or _G.MAX_BOSS_FRAMES)or 5
if maxBoss<1 or maxBoss>12 then maxBoss=5 end
MSUF_HideCastbarPreviewFrame(_G.MSUF_BossCastbarPreview)
MSUF_HideCastbarPreviewFrame(_G.MSUF_BossCastbarPreview1)
for i=2,maxBoss do
MSUF_HideCastbarPreviewFrame(_G["MSUF_BossCastbarPreview"..i])
end
end
end
