local e,t=...t=t or{}t.MSUF_CastbarStyle=t.MSUF_CastbarStyle or{}local o=t.MSUF_CastbarStyle
local function u()if type(EnsureDB)=="function"then EnsureDB()end
return(_G.MSUF_DB and _G.MSUF_DB.general)or{}end
local function f(t)t=t and tostring(t)or""if t:match("^boss")then return"boss"end
return t
end
local function T(t)t=f(t)if t=="player"then return"castbarPlayer"end
if t=="target"then return"castbarTarget"end
if t=="focus"then return"castbarFocus"end
return nil
end
local function l(t,e)if type(_G.MSUF_SetAlphaIfChanged)=="function"then _G.MSUF_SetAlphaIfChanged(t,e)else t:SetAlpha(e)end
end
local function s(t,e)if type(_G.MSUF_SetTextIfChanged)=="function"then _G.MSUF_SetTextIfChanged(t,e or"")else t:SetText(e or"")end
end
local function n(e)if not e or e._msufOutline then return end
local function t()local t=e:CreateTexture(nil,"OVERLAY")t:SetColorTexture(1,1,1,1)t:Hide()return t
end
e._msufOutline={top=t(),bottom=t(),left=t(),right=t()}end
function o:ApplyCastbarOutline(e,s)if not e then return end
n(e)local t=e._msufOutline
local o=u()local n=math.max(0,math.min(math.floor((tonumber(o.castbarOutlineThickness)or 1)+0.5),12))if n<=0 then t.top:Hide();t.bottom:Hide();t.left:Hide();t.right:Hide();e._msufOutlineT=0;return end
local i,o,a,r=tonumber(o.castbarBorderR)or 0,tonumber(o.castbarBorderG)or 0,tonumber(o.castbarBorderB)or 0,tonumber(o.castbarBorderA)or 1
if s or e._msufOutlineT~=n then
t.top:ClearAllPoints();t.top:SetPoint("TOPLEFT",e,"TOPLEFT",0,n);t.top:SetPoint("TOPRIGHT",e,"TOPRIGHT",0,n);t.top:SetHeight(n)t.bottom:ClearAllPoints();t.bottom:SetPoint("BOTTOMLEFT",e,"BOTTOMLEFT",0,-n);t.bottom:SetPoint("BOTTOMRIGHT",e,"BOTTOMRIGHT",0,-n);t.bottom:SetHeight(n)t.left:ClearAllPoints();t.left:SetPoint("TOPLEFT",e,"TOPLEFT",-n,n);t.left:SetPoint("BOTTOMLEFT",e,"BOTTOMLEFT",-n,-n);t.left:SetWidth(n)t.right:ClearAllPoints();t.right:SetPoint("TOPRIGHT",e,"TOPRIGHT",n,n);t.right:SetPoint("BOTTOMRIGHT",e,"BOTTOMRIGHT",n,-n);t.right:SetWidth(n)e._msufOutlineT=n
end
if s or e._msufOutlineR~=i or e._msufOutlineG~=o or e._msufOutlineB~=a or e._msufOutlineA~=r then
t.top:SetVertexColor(i,o,a,r);t.bottom:SetVertexColor(i,o,a,r);t.left:SetVertexColor(i,o,a,r);t.right:SetVertexColor(i,o,a,r)e._msufOutlineR,e._msufOutlineG,e._msufOutlineB,e._msufOutlineA=i,o,a,r
end
t.top:Show();t.bottom:Show();t.left:Show();t.right:Show()end
function o:ApplyCastbarOutlineToAll(o)local t={_G.MSUF_PlayerCastbar,_G.MSUF_TargetCastbar,_G.MSUF_FocusCastbar,_G.MSUF_PlayerCastbarPreview,_G.MSUF_TargetCastbarPreview,_G.MSUF_FocusCastbarPreview,_G.MSUF_BossCastbarPreview}for e=2,tonumber(_G.MAX_BOSS_FRAMES)or 5 do t[#t+1]=_G["MSUF_BossCastbarPreview"..e]end
local e=_G.MSUF_BossCastbars
if type(e)=="table"then for n=1,#e do t[#t+1]=e[n]end end
for e=1,#t do if t[e]then self:ApplyCastbarOutline(t[e],o)end end
end
local function i(n,t,e)if type(_G.MSUF_IsCastTimeEnabled)=="function"then return _G.MSUF_IsCastTimeEnabled(n or{unit=t})end
if t=="player"then return e.showPlayerCastTime~=false end
if t=="target"then return e.showTargetCastTime~=false end
if t=="focus"then return e.showFocusCastTime~=false end
if t=="boss"then return e.showBossCastTime~=false end
return true
end
local function r(t,a)local o=T(a)local e,n
if o then e,n=t[o.."TimeOffsetX"],t[o.."TimeOffsetY"]end
if a=="boss"then e,n=t.bossCastTimeOffsetX,t.bossCastTimeOffsetY end
if e==nil then e=t.castbarPlayerTimeOffsetX end
if n==nil then n=t.castbarPlayerTimeOffsetY end
return tonumber(e)or-2,tonumber(n)or 0
end
function o:ApplyCastbarTimeTextLayout(t,e)if not(t and t.timeText and t.statusBar)then return end
local n=u()e=f(e or t.unit)local o=i(t,e,n)t.timeText:Show()l(t.timeText,o and 1 or 0)if not o then s(t.timeText,"")end
local e,n=r(n,e)t.timeText:ClearAllPoints()t.timeText:SetPoint("RIGHT",t.statusBar,"RIGHT",e,n)t.timeText:SetJustifyH("RIGHT")end
function o:ApplyBossCastbarTextsLayout(t,e)if not(t and t.statusBar and t.castText and t.timeText)then return end
e=e or{}local o,n=tonumber(e.baselineTimeX)or-2,tonumber(e.baselineTimeY)or 0
local r,a=tonumber(e.textOffsetX)or 0,tonumber(e.textOffsetY)or 0
local o,n=tonumber(e.timeOffsetX)or o,tonumber(e.timeOffsetY)or n
t.castText:ClearAllPoints();t.timeText:ClearAllPoints()t.castText:SetJustifyH("LEFT");t.timeText:SetJustifyH("RIGHT")t.castText:SetPoint("LEFT",t.statusBar,"LEFT",2+r,a)t.timeText:SetPoint("RIGHT",t.statusBar,"RIGHT",o,n)t.castText:SetPoint("RIGHT",t.timeText,"LEFT",-6,0)if e.showName~=nil then t.castText:Show();l(t.castText,e.showName and 1 or 0);if not e.showName and e.clearIfHidden~=false then s(t.castText,"")end end
if e.showTime~=nil then t.timeText:Show();l(t.timeText,e.showTime and 1 or 0);if not e.showTime and e.clearIfHidden~=false then s(t.timeText,"")end end
if tonumber(e.nameFontSize)then local o,a,n=t.castText:GetFont();t.castText:SetFont(o,tonumber(e.nameFontSize),n)end
if tonumber(e.timeFontSize)then local n,a,o=t.timeText:GetFont();t.timeText:SetFont(n,tonumber(e.timeFontSize),o)end
end
function _G.MSUF_UpdateCastbarFillDirection()local function e(t)if not(t and t.statusBar)then return end
local o=t.isEmpower or t.MSUF_isChanneled or(t.unit and UnitChannelInfo and UnitChannelInfo(t.unit))local n=type(_G.MSUF_GetReverseFillSafe)=="function"and _G.MSUF_GetReverseFillSafe(t,o and true or false)or false
if type(_G.MSUF_ApplyCastbarTimerDirection)=="function"then _G.MSUF_ApplyCastbarTimerDirection(t.statusBar,t.MSUF_durationObj,n,o)elseif t.statusBar.SetReverseFill then t.statusBar:SetReverseFill(n and true or false)end
end
e(_G.MSUF_PlayerCastbar);e(_G.MSUF_TargetCastbar);e(_G.MSUF_FocusCastbar)e(_G.MSUF_PlayerCastbarPreview);e(_G.MSUF_TargetCastbarPreview);e(_G.MSUF_FocusCastbarPreview)local t=_G.MSUF_BossCastbars
if type(t)=="table"then for n=1,#t do e(t[n])end end
if type(_G.MSUF_UpdateCastbarVisuals)=="function"then _G.MSUF_UpdateCastbarVisuals()end
end
_G.MSUF_ApplyCastbarOutline=function(t,e)return o:ApplyCastbarOutline(t,e)end
_G.MSUF_ApplyCastbarOutlineToAll=function(t)return o:ApplyCastbarOutlineToAll(t)end
_G.MSUF_ApplyBossCastbarTextsLayout=function(e,t)return o:ApplyBossCastbarTextsLayout(e,t)end
_G.MSUF_ApplyCastbarTimeTextLayout=function(e,t)return o:ApplyCastbarTimeTextLayout(e,t)end