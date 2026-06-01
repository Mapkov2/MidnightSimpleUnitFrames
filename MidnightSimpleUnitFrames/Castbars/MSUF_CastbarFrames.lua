local a=_G
local function s(t)local e=a.MSUF_NS
local r=(type(e)=="table"and e.L)or a.MSUF_L
if type(e)=="table"and type(e.Translate)=="function"then return e.Translate(t)end
return(type(r)=="table"and rawget(r,t))or t
end
local function l()return(type(MSUF_GetCastbarTexture)=="function"and MSUF_GetCastbarTexture())or"Interface\\TargetingFrame\\UI-StatusBar"end
local function n()local t=l()if type(a.MSUF_GetCastbarBackgroundTexture)=="function"then
local e=a.MSUF_GetCastbarBackgroundTexture()if e and e~=""then t=e end
end
return t
end
local function i()if type(a.MSUF_GetCastbarBackgroundColor)=="function"then return a.MSUF_GetCastbarBackgroundColor()end
return 0.176,0.176,0.176,1
end
local function S(t,r)local e=t:CreateTexture(nil,"OVERLAY",nil,6)e:SetTexture(4417031)e:SetTexCoord(0.222168,0.232422,0.294434,0.317383)e:SetDesaturated(true)e:SetVertexColor(1,1,1,1)e:SetBlendMode("ADD")e:SetSize(16,r*2.1)local r=t:GetStatusBarTexture()e:SetPoint("CENTER",r or t,r and"RIGHT"or"LEFT",0,0)e:Hide()return e
end
local function T(e,l,t,r,o)local i,a,n=GameFontHighlight:GetFont()local e=e:CreateFontString(nil,"OVERLAY")e:SetFont(i,a,n)e:SetJustifyH(l)e:SetPoint(t,r,t,o or 0,0)return e
end
function a.MSUF_BuildCastbarFrameElements(e)local r=18
e:SetHeight(r)if(not e:GetWidth())or e:GetWidth()==0 then e:SetWidth(250)end
e.background=e:CreateTexture(nil,"BACKGROUND")e.background:SetAllPoints(e)e.background:SetColorTexture(0,0,0,1)local t=CreateFrame("StatusBar",nil,e)t:SetPoint("LEFT",e,"LEFT",r+1,0)t:SetSize(e:GetWidth()-r-1,e:GetHeight()-2)t:SetStatusBarTexture(l())if t:GetStatusBarTexture()then t:GetStatusBarTexture():SetHorizTile(true)end
if type(a.MSUF_ApplyCastbarTimerDirection)=="function"then a.MSUF_ApplyCastbarTimerDirection(t,nil,type(MSUF_GetCastbarReverseFillForFrame)=="function"and MSUF_GetCastbarReverseFillForFrame(e,false))elseif t.SetReverseFill and type(MSUF_GetCastbarReverseFillForFrame)=="function"then t:SetReverseFill(MSUF_GetCastbarReverseFillForFrame(e,false))end
e.statusBar=t
e.icon=t:CreateTexture(nil,"OVERLAY",nil,7)e.icon:SetSize(r,r)e.icon:SetPoint("LEFT",e,"LEFT",0,0)e.backgroundBar=t:CreateTexture(nil,"BACKGROUND")e.backgroundBar:SetAllPoints(t)e.backgroundBar:SetTexture(n())e.backgroundBar:SetVertexColor(i())e.castText=t:CreateFontString(nil,"OVERLAY")e.castText:SetFont("Fonts\\FRIZQT__.TTF",12,"OUTLINE")e.castText:SetPoint("LEFT",t,"LEFT",2,0)e.timeText=t:CreateFontString(nil,"OVERLAY")e.timeText:SetFont("Fonts\\FRIZQT__.TTF",12,"OUTLINE")e.timeText:SetPoint("RIGHT",t,"RIGHT",-2,0)e.timeText:SetText("")e.spark=S(t,r)if type(a.MSUF_ApplyCastbarOutline)=="function"then a.MSUF_ApplyCastbarOutline(e,true)end
end
function a.MSUF_CreateCastbarPreviewFrame(o,e,r)r=r or{}local t,c,n=r.parent or UIParent,tonumber(r.width)or 250,tonumber(r.height)or 18
local u=tonumber(r.statusBarHeight)or math.max(4,n-2)local e=CreateFrame("Frame",e,t,r.template or"BackdropTemplate")e.unit,e._msufIsPreview=o,true
e:SetClampedToScreen(true)e:SetFrameStrata(r.strata or"DIALOG")e:SetSize(c,n)e._msufFrameBG=e:CreateTexture(nil,"BACKGROUND")e._msufFrameBG:SetAllPoints(e)e._msufFrameBG:SetColorTexture(0,0,0,r.bgAlpha or 0.8)local t=CreateFrame("StatusBar",nil,e)if e.GetFrameLevel and t.SetFrameLevel then t:SetFrameLevel(e:GetFrameLevel()+1)end
t:SetPoint("LEFT",e,"LEFT",0,0)t:SetSize(c,u)t:SetStatusBarTexture(l())if t:GetStatusBarTexture()then t:GetStatusBarTexture():SetHorizTile(true)end
t:SetMinMaxValues(0,1)t:SetValue(tonumber(r.initialValue)or 0)e.statusBar=t
e.backgroundBar=t:CreateTexture(nil,"BACKGROUND")e.backgroundBar:SetAllPoints(t)e.backgroundBar:SetTexture("Interface\\Buttons\\WHITE8X8")e.backgroundBar:SetVertexColor(i())e.backgroundBar:SetAlpha(0.25)if r.hideFillTexture and t:GetStatusBarTexture()then t:GetStatusBarTexture():SetAlpha(0);t.MSUF_hideFillTexture=true end
if o=="player"then
e.latencyBar=t:CreateTexture(nil,"OVERLAY")e.latencyBar:SetColorTexture(1,0,0,0.25)e.latencyBar:SetPoint("TOPRIGHT",t,"TOPRIGHT")e.latencyBar:SetPoint("BOTTOMRIGHT",t,"BOTTOMRIGHT")e.latencyBar:SetWidth(0)e.latencyBar:Hide()end
if r.showIcon~=false then
e.icon=e:CreateTexture(nil,"OVERLAY",nil,7)e.icon:SetSize(tonumber(r.iconSize)or n,tonumber(r.iconSize)or n)e.icon:SetPoint("LEFT",e,"LEFT",0,0)e.icon:SetTexture(r.iconTexture or 136235)end
local n=CreateFrame("Frame",nil,e)n:SetAllPoints(t)if n.SetFrameLevel and t.GetFrameLevel then n:SetFrameLevel(t:GetFrameLevel()+10)end
e._msufTextOverlay=n
local o=r.label or(o=="player"and"Player castbar preview"or o=="target"and"Target castbar preview"or o=="focus"and"Focus castbar preview"or o=="boss"and"Boss castbar preview"or"Castbar preview")e.castText=T(n,"LEFT","LEFT",n,2)e.castText:SetText(s(o))if r.showTime~=false then
e.timeText=T(n,"RIGHT","RIGHT",n,-2)e.timeText:SetText(r.timeLabel or"3.2")end
e.spark=S(t,u)if type(a.MSUF_ApplyCastbarOutline)=="function"then a.MSUF_ApplyCastbarOutline(e,true)end
return e
end