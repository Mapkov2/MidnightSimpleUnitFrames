-- ============================================================================
-- MidnightSimpleUnitFrames - Slash Menu
--
-- Readable Compact Edition (no file split)
--
-- Design goals:
--   - Keep the entire Slash Menu self-contained, but avoid boilerplate spam.
--   - Use UI primitives (UI_Btn/UI_Text/UI_Check) + data-driven rows where possible.
--   - Prefer build-once + refresh-on-show to avoid rebuild regressions.
--
-- Notes:
--   - This file is compact (some statements share lines), but it is NOT minified.
--   - Indentation reflects block structure (if/for/function/repeat).
-- ============================================================================

local addonName,ns=...;
ns=ns or {}
local L=ns.L or (_G.MSUF_L)
if not L then L={}
setmetatable(L,{__index=function(t,k)
return k end})
ns.L=L end
local isEn=(ns and ns.LOCALE)=="enUS"
local function T(v) if type(v)=="string" then if isEn then return v end return L[v] or v end return v end
local function MSUF_LeftJustifyButtonText(btn,leftPad) leftPad=leftPad or 10 if not btn or not btn.GetFontString then return end
local fs=btn:GetFontString()
if not fs then return end
if fs.SetJustifyH then fs:SetJustifyH("LEFT")
end
if fs.ClearAllPoints and fs.SetPoint then fs:ClearAllPoints();
fs:SetPoint("LEFT",btn,"LEFT",leftPad,0)
fs:SetPoint("RIGHT",btn,"RIGHT",-8,0)
end
end
_G.MSUF_LeftJustifyButtonText=_G.MSUF_LeftJustifyButtonText or MSUF_LeftJustifyButtonText;
_G.LeftJustify=_G.LeftJustify or MSUF_LeftJustifyButtonText local MSUF_BuildTools;
local MSUF_CapturePanelState;
local MSUF_RestorePanelState;
local MSUF_SaveWindowGeometry;
local MSUF_LoadWindowGeometry;
local MSUF_AddTooltip;
local MSUF_RegisterEscClose;
local MSUF_PickSessionTip;
local MSUF_SkinButton;
local MSUF_BuildButtonRow local MSUF_BuildButtonRowTL;
MSUF_CapturePanelState=MSUF_CapturePanelState or function(panel) local st={};
local sf=panel and(panel.ScrollFrame or panel.scrollFrame or panel.scroll or panel.Scroll or panel.scrollChild)
if sf and sf.GetVerticalScroll then st.vScroll=sf:GetVerticalScroll()
end
return st end
MSUF_RestorePanelState=MSUF_RestorePanelState or function(panel,st) if not panel or type(st)~="table"then return end
local sf=panel.ScrollFrame or panel.scrollFrame or panel.scroll or panel.Scroll or panel.scrollChild if sf and sf.SetVerticalScroll and st.vScroll then pcall(sf.SetVerticalScroll,sf,st.vScroll)
end
end
local S={win=nil,content=nil,scale={},mirror={host=nil,currentKey="home",currentPanel=nil,homePanel=nil,homeToolsApi=nil,tipText=nil,selectEpoch=0,},}
local _msufIsAlpha do local _v=_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames","Version")
_msufIsAlpha=(type(_v)=="string"and _v:lower():find("alpha")~=nil) end
if _msufIsAlpha then StaticPopupDialogs["MSUF_ALPHA_DISCORD"]={text="|cffb088f0MSUF Alpha Build|r\n\nThis is an early Alpha version.\nPlease report bugs and share feedback on our Discord!\n\n|cff7289dahttps://discord.gg/JQnhZXnTAK|r",button1="Copy Discord Link",button2=CLOSE,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() if type(MSUF_ShowCopyLink)=="function"then MSUF_ShowCopyLink("Discord","https://discord.gg/JQnhZXnTAK") end end} end
-- Transition helpers (populated after MSUF_Transitions loads; nil-safe fallback)
local function _T() return ns.MSUF_Transitions end
local function _TFadeIn(f,d,cb)  local t=_T() if t then t.FadeIn(f,d,cb)  elseif f and f.Show then f:Show() end end
local function _TDismiss(f,d,cb) local t=_T() if t then t.Dismiss(f,d,cb) elseif f and f.Hide then f:Hide() end end
local function _TScaleReveal(f,d,cb)  local t=_T() if t then t.ScaleReveal(f,d,cb)  else _TFadeIn(f,d,cb) end end
local function _TScaleDismiss(f,d,cb) local t=_T() if t then t.ScaleDismiss(f,d,cb) else _TDismiss(f,d,cb) end end
local function _TCancel(f) local t=_T() if t then t.Cancel(f) end end
local TRANS_OPEN  = 0.15   -- main window open
local TRANS_CLOSE = 0.12   -- main window close (faster = snappy)
local TRANS_PAGE  = 0.10   -- page switch crossfade
local function MSUF_UpdateHomePanel(panel) if not panel then return end
local tip=S and S.mirror and S.mirror.tipText if not tip and _G and type(_G.MSUF_GetNextTip)=="function"then tip=_G.MSUF_GetNextTip()
if S and S.mirror then S.mirror.tipText=tip end
end
if tip and panel._msufTipText and panel._msufTipText.SetText then panel._msufTipText:SetText(tip)
if type(MSUF_ForceItalicFont)=="function"then MSUF_ForceItalicFont(panel._msufTipText)
end
if panel._msufTipText.SetAlpha then panel._msufTipText:SetAlpha(0.82)
end
end
if S and S.mirror and S.mirror.homeToolsApi and S.mirror.homeToolsApi.Refresh then pcall(S.mirror.homeToolsApi.Refresh)
end
local win=_G.MSUF_StandaloneOptionsWindow;
local b=win and win._msufDashEditBtn if b and b._msufSetSelected and type(MSUF_IsMSUFEditModeActive)=="function"then b:_msufSetSelected(MSUF_IsMSUFEditModeActive())
end
local prof=(_G.MSUF_ActiveProfile)
or"Default"if panel._msufProfileValue and panel._msufProfileValue.SetText then panel._msufProfileValue:SetText(prof)
end
if panel._msufStatusLine and panel._msufStatusLine.SetText then local edit=(type(MSUF_IsMSUFEditModeActive)=="function"and MSUF_IsMSUFEditModeActive())
and"On"or"Off";
local combat=(InCombatLockdown and InCombatLockdown())
and"In combat"or"Out of combat"panel._msufStatusLine:SetText("Profile: "..tostring(prof).."   •   Edit Mode: "..edit.."   •   "..combat)
end
end
local function MSUF_Print(msg) if type(print)=="function"then print("|cff00ff00MSUF:|r "..tostring(msg))
end
end
local function clamp(v,lo,hi) if v<lo then return lo end
if v>hi then return hi end
return v end
local function MSUF_SafeCall(fn,...) if type(fn)~="function"then return end
local ok,a,b,c,d,e=pcall(fn,...)
if ok then return a,b,c,d,e end
end
local function MSUF_RefreshApi(api) if api and api.Refresh then return api.Refresh() end
end
local function MSUF_SetEnabled(w,enabled) if not w then return end
if w.SetEnabled then w:SetEnabled(enabled and true or false);
 return end
if enabled then if w.Enable then w:Enable()
end
if w.SetAlpha then w:SetAlpha(1.0)
end
else if w.Disable then w:Disable()
end
    if w.SetAlpha then w:SetAlpha(0.55)
end
end
end
local function UI_Button(parent,text,w,h,a1,rel,a2,x,y,onClick,template) local b=CreateFrame("Button",nil,parent,template or"UIPanelButtonTemplate")
if w and h then b:SetSize(w,h)
end
if a1 then b:SetPoint(a1,rel or parent,a2 or a1,x or 0,y or 0)
end
if text~=nil and b.SetText then b:SetText(T(text))
end
if type(MSUF_SkinButton)=="function"then MSUF_SkinButton(b)
end
if onClick then b:SetScript("OnClick",onClick)
end
return b end
local function UI_CloseButton(parent,a1,rel,a2,x,y,onClick) local b=CreateFrame("Button",nil,parent,"UIPanelCloseButton")
if a1 then b:SetPoint(a1,rel or parent,a2 or a1,x or 0,y or 0)
end
if onClick then b:SetScript("OnClick",onClick)
end
return b end
local function UI_Btn(parent,text,w,h,a1,rel,a2,x,y,onClick,tipTitle,tipBody,skinFn,template) local b=UI_Button(parent,text,w,h,a1,rel,a2,x,y,onClick,template)
if skinFn then skinFn(b)
end
if MSUF_AddTooltip and tipTitle then MSUF_AddTooltip(b,T(tipTitle),T(tipBody))
end
return b end
local function UI_Text(parent,font,a1,rel,a2,x,y,txt,skinFn) local fs=parent:CreateFontString(nil,"OVERLAY",font or"GameFontHighlight")
if a1 then fs:SetPoint(a1,rel or parent,a2 or a1,x or 0,y or 0)
end
if txt~=nil then fs:SetText(T(txt))
end
if skinFn then skinFn(fs)
end
return fs end
local function UI_Check(parent,label,a1,rel,a2,x,y,onClick,tipTitle,tipBody,skinFn,template) local cb=CreateFrame("CheckButton",nil,parent,template or"UICheckButtonTemplate")
if a1 then cb:SetPoint(a1,rel or parent,a2 or a1,x or 0,y or 0)
end
if cb.Text and cb.Text.SetText then cb.Text:SetText(T(label or""))
end
if skinFn and cb.Text then skinFn(cb.Text)
end
if onClick then cb:SetScript("OnClick",onClick)
end
if MSUF_AddTooltip and tipTitle then MSUF_AddTooltip(cb,T(tipTitle),T(tipBody))
end
return cb end
local function MSUF_LayoutColumn(parent,startX,startY,defaultRowH,defaultGap) local L={parent=parent,x=startX or 12,y=startY or-12,rowH=defaultRowH or 20,gap=defaultGap or 6,}
function L:Row(h,gap) local x,y=self.x,self.y;
self.y=self.y-(h or self.rowH)-(gap or self.gap) return x,y end
function L:MoveY(dy) self.y=self.y+(dy or 0);
 return self end
function L:At(dx,dy) return self.x+(dx or 0),self.y+(dy or 0) end
return L end
local function UI_TextTL(parent,font,x,y,text,skinFn) return UI_Text(parent,font,"TOPLEFT",parent,"TOPLEFT",x,y,text,skinFn) end
local function UI_BtnTL(parent,text,w,h,x,y,onClick,tipTitle,tipBody,skinFn,template) return UI_Btn(parent,text,w,h,"TOPLEFT",parent,"TOPLEFT",x,y,onClick,tipTitle,tipBody,skinFn,template) end
local function MSUF_JoinLines(lines) if type(lines)~="table"then return tostring(lines or"") end
return table.concat(lines,"\n") end
function MSUF_BuildButtonRowTL(parent,x,y,defs,defaultGap) local out,prev={},nil for i,d in ipairs(defs or{})
do local gap=d.gap if gap==nil then gap=defaultGap end
if gap==nil then gap=8 end
local b if i==1 then b=UI_BtnTL(parent,d.text,d.w,d.h,x,y,d.onClick,d.tipTitle,d.tipBody,d.skinFn,d.template)
else b=UI_Btn(parent,d.text,d.w,d.h,"LEFT",prev,"RIGHT",gap,0,d.onClick,d.tipTitle,d.tipBody,d.skinFn,d.template)
end
out[i]=b;
prev=b if d.post then pcall(d.post,b)
end
end
function MSUF_BuildButtonRow(parent,anchorFrame,a1,a2,x,y,defs,defaultGap) local out,prev={},nil for i,d in ipairs(defs or{})
do local gap=d.gap if gap==nil then gap=defaultGap end
if gap==nil then gap=8 end
local b if i==1 then b=UI_Btn(parent,d.text,d.w,d.h,a1,anchorFrame,a2,x,y,d.onClick,d.tipTitle,d.tipBody,d.skinFn,d.template)
else b=UI_Btn(parent,d.text,d.w,d.h,"LEFT",prev,"RIGHT",gap,0,d.onClick,d.tipTitle,d.tipBody,d.skinFn,d.template)
end
out[i]=b;
prev=b if d.post then pcall(d.post,b)
end
end
return out end
return out end
local function UI_BtnTo(parent,text,w,h,anchor,relPoint,x,y,onClick,tipTitle,tipBody,skinFn,template) return UI_Btn(parent,text,w,h,anchor,parent,relPoint or anchor,x,y,onClick,tipTitle,tipBody,skinFn,template) end
local function MSUF_AttachManualResizeGrip(frame) if not frame or frame._msufResizeGrip then return end
local grip=CreateFrame("Button",nil,frame);
grip:SetSize(16,16)
grip:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",-2,2);
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight");
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
local function Stop() if not frame._msufResizing then return end
frame._msufResizing=false if grip and grip.SetScript then grip:SetScript("OnUpdate",nil)
end
if MSUF_SaveWindowGeometry then MSUF_SaveWindowGeometry(frame,frame._msufGeomKey or"full")
end
end
grip:SetScript("OnMouseDown",function(self,btn) if btn~="LeftButton"then return end
if not(frame and frame.GetWidth and frame.GetHeight)
then return end
local cx,cy=GetCursorPosition()
frame._msufResizing=true frame._msufResizeStartX=cx frame._msufResizeStartY=cy frame._msufResizeStartW=frame:GetWidth()
frame._msufResizeStartH=frame:GetHeight()
self:SetScript("OnUpdate",function() if not frame._msufResizing then return end
local x,y=GetCursorPosition();
local s=(frame.GetEffectiveScale and frame:GetEffectiveScale())
or 1 if s==0 then s=1 end
local dw=(x-(frame._msufResizeStartX or x))/s;
local dh=((frame._msufResizeStartY or y)-y)/s;
local newW=(frame._msufResizeStartW or frame:GetWidth())+dw;
local newH=(frame._msufResizeStartH or frame:GetHeight())+dh;
local minW=frame._msufMinW or 760 local minH=frame._msufMinH or 520;
local maxW=frame._msufMaxW or 2200;
local maxH=frame._msufMaxH or 1400 frame:SetSize(clamp(newW,minW,maxW),clamp(newH,minH,maxH)) end
) end
)
grip:SetScript("OnMouseUp",Stop);
grip:SetScript("OnHide",Stop)
do local prev=frame.GetScript and frame:GetScript("OnMouseUp");
frame:SetScript("OnMouseUp",function(self,btn) Stop()
if prev then pcall(prev,self,btn)
end
end
)
end
frame._msufResizeGrip=grip frame._msufStopManualResize=Stop end
local function MSUF_EnsureGeneral() MSUF_SafeCall(EnsureDB)
if type(MSUF_DB)~="table"then return nil end
MSUF_DB.general=MSUF_DB.general or{}
return MSUF_DB.general end
local function MSUF_EnsureGlobalSlashMenuState()
_G.MSUF_GlobalDB=_G.MSUF_GlobalDB or{}
local gdb=_G.MSUF_GlobalDB
gdb.global=gdb.global or{}
gdb.global.slashMenu=gdb.global.slashMenu or{}
gdb.global.slashMenu.navHeaders=gdb.global.slashMenu.navHeaders or{}
return gdb.global.slashMenu end
local function MSUF_GetSavedNavHeaderState(headerId,defaultOpen)
if type(headerId)~="string"or headerId==""then return defaultOpen and true or false end
local sm=MSUF_EnsureGlobalSlashMenuState()
local headers=sm and sm.navHeaders
local v=headers and headers[headerId]
if v==nil then return defaultOpen and true or false end
return v and true or false end
local function MSUF_SetSavedNavHeaderState(headerId,isOpen)
if type(headerId)~="string"or headerId==""then return end
local sm=MSUF_EnsureGlobalSlashMenuState()
if not(sm and sm.navHeaders)then return end
sm.navHeaders[headerId]=isOpen and true or false end
local function MSUF_GetGeomPrefix(which) return"flashFull"end
MSUF_RegisterEscClose=function(frame) if not frame or not frame.GetName then return end
local name=frame:GetName()
if not name or name==""then return end
if type(UISpecialFrames)=="table"then for _,v in ipairs(UISpecialFrames)
do if v==name then return end
end
table.insert(UISpecialFrames,name)
end
end
MSUF_SaveWindowGeometry=function(frame,which) if not frame or not frame.GetWidth or not frame.GetHeight or not frame.GetPoint then return end
local g=MSUF_EnsureGeneral()
if not g then return end
local pfx=MSUF_GetGeomPrefix(which);
local w=frame:GetWidth();
local h=frame:GetHeight()
if w and h then g[pfx.."W"]=w g[pfx.."H"]=h end
local point,relTo,relPoint,xOfs,yOfs=frame:GetPoint(1)
if point and relPoint and xOfs and yOfs then g[pfx.."Point"]=point g[pfx.."RelPoint"]=relPoint local s=(UIParent and UIParent.GetScale and UIParent:GetScale())
or 1 if not s or s==0 then s=1 end
g[pfx.."X"]=xOfs g[pfx.."Y"]=yOfs g[pfx.."Xpx"]=(tonumber(xOfs)
or 0)*s g[pfx.."Ypx"]=(tonumber(yOfs)
or 0)*s end
end
MSUF_LoadWindowGeometry=function(frame,which,defaultW,defaultH,defaultPoint,defaultX,defaultY) if not frame then return end
local g=MSUF_EnsureGeneral();
local pfx=MSUF_GetGeomPrefix(which);
local w=defaultW;
local h=defaultH;
local point=defaultPoint or"CENTER"local relPoint=point;
local x=defaultX or 0;
local y=defaultY or 0 if g then w=tonumber(g[pfx.."W"])
or w h=tonumber(g[pfx.."H"])
or h point=g[pfx.."Point"]
or point relPoint=g[pfx.."RelPoint"]
or relPoint local s=(UIParent and UIParent.GetScale and UIParent:GetScale())
or 1 if not s or s==0 then s=1 end
local xpx=tonumber(g[pfx.."Xpx"]);
local ypx=tonumber(g[pfx.."Ypx"])
if xpx~=nil then x=xpx/s else x=tonumber(g[pfx.."X"])
or x end
if ypx~=nil then y=ypx/s else y=tonumber(g[pfx.."Y"])
or y end
end
local minW=frame._msufMinW or 760;
local minH=frame._msufMinH or 520;
local maxW=frame._msufMaxW or 2200;
local maxH=frame._msufMaxH or 1400 if w and h then w=clamp(w,minW,maxW)
h=clamp(h,minH,maxH)
if frame.SetSize then frame:SetSize(w,h)
end
end
if frame.ClearAllPoints and frame.SetPoint then frame:ClearAllPoints()
frame:SetPoint(point,UIParent,relPoint,x,y)
end
end
MSUF_AddTooltip=function(widget,title,body) if not widget or not widget.SetScript then return end
widget:SetScript("OnEnter",function(self) if not GameTooltip then return end
GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
if title and title~=""then GameTooltip:SetText(title,1,1,1)
end
if body and body~=""then GameTooltip:AddLine(body,0.80,0.86,1.00,true)
end
GameTooltip:Show() end
)
widget:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide()
end
end
) end
local MSUF_GetNextTip MSUF_PickSessionTip=function() local tip=(_G.MSUF_GetNextTip and _G.MSUF_GetNextTip())
if tip then S.mirror.tipText=tip end
end
local MSUF_THEME={bgR=0.08,bgG=0.09,bgB=0.16,bgA=0.98,edgeR=0.12,edgeG=0.14,edgeB=0.28,edgeA=0.80,titleR=0.80,titleG=0.88,titleB=1.00,titleA=1.00,textR=0.84,textG=0.88,textB=1.00,textA=1.00,
accentR=0.22,accentG=0.78,accentB=0.94,
dangerR=0.88,dangerG=0.28,dangerB=0.28,
successR=0.24,successG=0.82,successB=0.46,
cardBgR=0.065,cardBgG=0.075,cardBgB=0.14,cardBgA=0.95,
cardEdgeR=0.12,cardEdgeG=0.14,cardEdgeB=0.26,cardEdgeA=0.40,
}
local function MSUF_Clamp01(x) x=tonumber(x)
or 0 if x<0 then return 0 end
if x>1 then return 1 end
return x end
local MSUF_PILL_EDGE_R=MSUF_Clamp01((MSUF_THEME.edgeR or 0.10)*1.25);
local MSUF_PILL_EDGE_G=MSUF_Clamp01((MSUF_THEME.edgeG or 0.20)*1.25);
local MSUF_PILL_EDGE_B=MSUF_Clamp01((MSUF_THEME.edgeB or 0.45)*1.18);
local MSUF_PILL_EDGE_A=MSUF_Clamp01((MSUF_THEME.edgeA or 0.90)+0.05);
local MSUF_SUPERELLIPSE_TEX="Interface/AddOns/"..tostring(addonName or"MidnightSimpleUnitFrames").."/Media/superellipse.tga"local function MSUF_EnsureSuperellipseLayers(btn,inset) if not btn or not btn.CreateTexture then return nil,nil end
inset=tonumber(inset)
or 2 local function SnapOff(tex) if tex and tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false)
if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0)
end
end
end
local function MakeGroup(key,layer,subLevel) local g=btn[key]
if g then return g end
g={}
g.L=btn:CreateTexture(nil,layer,nil,subLevel or 0)
g.M=btn:CreateTexture(nil,layer,nil,subLevel or 0)
g.R=btn:CreateTexture(nil,layer,nil,subLevel or 0)
g._msufSEParts={g.L,g.M,g.R}
g.L:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.M:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.R:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.L:SetTexCoord(0.0,0.25,0.0,1.0)
g.M:SetTexCoord(0.25,0.75,0.0,1.0)
g.R:SetTexCoord(0.75,1.0,0.0,1.0)
SnapOff(g.L);
SnapOff(g.M);
SnapOff(g.R)
g.SetVertexColor=function(self,r,gg,b,a) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.SetVertexColor then t:SetVertexColor(r,gg,b,a)
end
end
end
g.Hide=function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i];
if t and t.Hide then t:Hide()
end
end
end
g.Show=function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i];
if t and t.Show then t:Show()
end
end
end
btn[key]=g return g end
local border=MakeGroup("_msufSEBorder3","BACKGROUND",0);
local fill=MakeGroup("_msufSEFill3","BACKGROUND",1)
if btn.SetClipsChildren then pcall(btn.SetClipsChildren,btn,true)
end
local function Layout(g,pad) local w=(btn.GetWidth and btn:GetWidth())
or 140;
local h=(btn.GetHeight and btn:GetHeight())
or 22;
local innerW=math.max(1,w-pad*2);
local innerH=math.max(1,h-pad*2);
local r=math.floor(innerH*0.5+0.5)
local capW=math.min(r,math.floor(innerW*0.5))
g.L:ClearAllPoints()
g.M:ClearAllPoints()
g.R:ClearAllPoints()
g.L:SetPoint("TOPLEFT",btn,"TOPLEFT",pad,-pad)
g.L:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",pad,pad)
g.L:SetWidth(capW)
g.R:SetPoint("TOPRIGHT",btn,"TOPRIGHT",-pad,-pad)
g.R:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",-pad,pad)
g.R:SetWidth(capW)
g.M:SetPoint("TOPLEFT",g.L,"TOPRIGHT",0,0)
g.M:SetPoint("BOTTOMRIGHT",g.R,"BOTTOMLEFT",0,0) end
Layout(border,1)
Layout(fill,math.max(2,inset))
if btn.HookScript and not btn._msufSE3Hooked then btn._msufSE3Hooked=true btn:HookScript("OnSizeChanged",function() Layout(border,1);
Layout(fill,math.max(2,inset)) end
)
end
if border and border.SetVertexColor then border:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,MSUF_PILL_EDGE_A)
end
if fill and fill.SetVertexColor then fill:SetVertexColor(MSUF_THEME.bgR,MSUF_THEME.bgG,MSUF_THEME.bgB,0.90)
end
return fill,border end
local MSUF_TIPS={"Bigger steps: Hold |cff00ff00SHIFT|r while adjusting sliders to change values faster.","Fine tuning: Hold |cff00ff00CTRL|r while adjusting sliders for smaller steps.","Quick reset: If something feels off, try |cff00ff00/msuf reset|r (frame positions).","Factory reset: Use |cff00ff00Menu → Advanced → Factory Reset|r (or /msuf fullreset confirm + /reload).","Edit Mode: Use |cff00ff00Toggle Edit Mode|r to move frames quickly, then fine-tune with the position popup.","Profiles safety: Create a new profile before big experiments — switch back instantly if needed.","Colors: The |cff00ff00Colors|r tab lets you customize almost everything (fonts, bars, castbars, highlights).","Gameplay: The |cff00ff00Gameplay|r tab contains extra UI tools and warnings you can enable/disable.","Recommended: |cff00ff00Sensei Resource Bar|r pairs insanely well with MSUF to track resources cleanly.","UI scale tip: MSUF has its own UI scale — separate from the Global UI scale.","Troubleshoot: If visuals don’t update, a quick |cff00ff00/reload|r fixes most UI state issues.","Readability: Slightly larger fonts often help more than bigger frames (especially in raids).","During development of MSUF Unhalted, R41z0r and other great addon developers helped out!","Danders is a great Party/Raidframe addon and works really well with MSUF","Community: If you like MSUF, share it with a friend — UI addons grow by word of mouth.",}
MSUF_GetNextTip=function() local tips=MSUF_TIPS if not tips or#tips==0 then return nil,0,0 end
local general=MSUF_EnsureGeneral();
local idx=1 if general then idx=(tonumber(general.tipCycleIndex)
or 0)+1 if idx>#tips then idx=1 end
general.tipCycleIndex=idx end
return tips[idx],idx,#tips end
_G.MSUF_GetNextTip=MSUF_GetNextTip
-- MSUF_SafeSetFont: WoW 12.0 Midnight introduced strict validation on the SetFont
-- `flags` argument. Empty string "" is valid, but strings like "," / "OUTLINE," /
-- " ,ITALIC" now throw "bad argument #4 to '?'" and propagate, breaking whatever
-- UI is being built. This helper sanitizes the flags string and pcall-wraps the
-- call so no broken font argument can ever cascade through the skin pipeline.
-- Zero overhead on happy path (string:find is C-side, pcall is <50ns).
local function MSUF_NormalizeFontFlags(flags)
if type(flags)~="string"then return""end
flags=flags:gsub("^[%s,]+",""):gsub("[%s,]+$","")
if flags:find(",,",1,true)then flags=flags:gsub(",+",",") end
return flags
end
local function MSUF_SafeSetFont(fs,path,size,flags)
if not(fs and fs.SetFont and path and size)then return false end
local ok=pcall(fs.SetFont,fs,path,size,MSUF_NormalizeFontFlags(flags))
if ok then return true end
-- Fallback 1: retry with empty flags (path+size always valid)
if pcall(fs.SetFont,fs,path,size,"")then return true end
-- Fallback 2: retry via FontObject (last-resort, no throw)
if fs.SetFontObject then pcall(fs.SetFontObject,fs,"GameFontHighlightSmall") end
return false
end
local function MSUF_ForceItalicFont(fs) if not fs or not fs.GetFont or not fs.SetFont then return end
local font,size,flags=fs:GetFont()
if not font or not size then return end
flags=flags or""if flags:find("ITALIC")
then return end
if flags~=""then flags=flags..",ITALIC"else flags="ITALIC"end
MSUF_SafeSetFont(fs,font,size,flags) end
local MSUF_ShowReloadRecommendedPopup
local MSUF_PENDING_RELOAD_RECOMMEND_LABEL=nil MSUF_ShowReloadRecommendedPopup=function(label) if InCombatLockdown and InCombatLockdown()
then if type(MSUF_Print)=="function"then MSUF_Print("Reload recommended (cannot show popup in combat).")
else print("|cffffaa00MSUF:|r Reload recommended (cannot show popup in combat).")
end
return end
MSUF_PENDING_RELOAD_RECOMMEND_LABEL=tostring(label or"")
if MSUF_PENDING_RELOAD_RECOMMEND_LABEL==""then MSUF_PENDING_RELOAD_RECOMMEND_LABEL="these changes"end
if not StaticPopupDialogs["MSUF_RELOAD_RECOMMENDED"]
then StaticPopupDialogs["MSUF_RELOAD_RECOMMENDED"]={text=T("MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?"),button1=T("Reload"),button2=T("Not now"),timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() MSUF_PENDING_RELOAD_RECOMMEND_LABEL=nil if type(ReloadUI)=="function"then ReloadUI()
end
end
,OnCancel=function() MSUF_PENDING_RELOAD_RECOMMEND_LABEL=nil end
,}
end
StaticPopup_Show("MSUF_RELOAD_RECOMMENDED",MSUF_PENDING_RELOAD_RECOMMEND_LABEL) end
_G.MSUF_ShowReloadRecommendedPopup=MSUF_ShowReloadRecommendedPopup
local MSUF_PENDING_RELOAD_LABEL=nil;
local MSUF_PENDING_RELOAD_FN=nil local function MSUF_ShowReloadConfirm(label,fn) if InCombatLockdown and InCombatLockdown()
then MSUF_Print("Cannot reload UI in combat.") return end
MSUF_PENDING_RELOAD_LABEL=tostring(label or"")
MSUF_PENDING_RELOAD_FN=fn if not StaticPopupDialogs["MSUF_RELOAD_UI_CONFIRM"]
then StaticPopupDialogs["MSUF_RELOAD_UI_CONFIRM"]={text="Reload UI now?\n\nThis will apply: %s",button1=YES,button2=NO,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() local f=MSUF_PENDING_RELOAD_FN;
MSUF_PENDING_RELOAD_FN=nil MSUF_PENDING_RELOAD_LABEL=nil if type(f)=="function"then pcall(f)
end
end
,OnCancel=function() MSUF_PENDING_RELOAD_FN=nil;
MSUF_PENDING_RELOAD_LABEL=nil end
,}
end
StaticPopup_Show("MSUF_RELOAD_UI_CONFIRM",MSUF_PENDING_RELOAD_LABEL) end
local MSUF_CopyLinkPopup=nil local function MSUF_EnsureCopyLinkPopup() if MSUF_CopyLinkPopup then return MSUF_CopyLinkPopup end
local f=CreateFrame("Frame","MSUF_CopyLinkPopup",UIParent,"BackdropTemplate")
f:SetSize(420,150)
f:SetFrameStrata("DIALOG")
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart",f.StartMoving)
f:SetScript("OnDragStop",f.StopMovingOrSizing)
f:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=4,right=4,top=4,bottom=4},})
f:SetBackdropColor(0,0,0,0.90)
f:SetBackdropBorderColor(0.10,0.10,0.10,0.90)
local titleFS=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
titleFS:SetPoint("TOP",f,"TOP",0,-14)
titleFS:SetText("Link")
f._msufTitleFS=titleFS local hintFS=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
hintFS:SetPoint("TOP",titleFS,"BOTTOM",0,-6)
hintFS:SetText("Press Ctrl+C to copy:")
hintFS:SetTextColor(0.90,0.90,0.90,1)
local eb=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
eb:SetAutoFocus(false)
eb:SetSize(360,32)
eb:SetPoint("TOP",hintFS,"BOTTOM",0,-10)
if eb.SetTextInsets then eb:SetTextInsets(8,8,0,0)
end
eb:SetScript("OnEscapePressed",function() f:Hide() end
)
eb:SetScript("OnEnterPressed",function() f:Hide() end
)
f._msufEditBox=eb local ok=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
ok:SetSize(120,24)
ok:SetPoint("BOTTOM",f,"BOTTOM",0,12)
ok:SetText(OKAY)
ok:SetScript("OnClick",function() f:Hide() end
)
if type(MSUF_SkinButton)=="function"then MSUF_SkinButton(ok)
end
f:SetScript("OnShow",function(self) if self._msufTitleFS then self._msufTitleFS:SetText(self._msufTitle or"Link")
end
if self._msufEditBox then self._msufEditBox:SetText(self._msufUrl or"");
self._msufEditBox:HighlightText()
self._msufEditBox:SetFocus()
end
end
)
f:SetScript("OnHide",function(self) if self._msufEditBox then self._msufEditBox:SetText("");
self._msufEditBox:ClearFocus()
end
self._msufTitle=nil;
self._msufUrl=nil end
)
f:Hide()
MSUF_CopyLinkPopup=f return f end
local function MSUF_ShowCopyLink(title,url) local f=MSUF_EnsureCopyLinkPopup()
f._msufTitle=tostring(title or"Link")
f._msufUrl=tostring(url or"")
f:ClearAllPoints()
f:SetPoint("CENTER",UIParent,"CENTER",0,0)
f:Show()
if f.Raise then f:Raise()
end
end
_G.MSUF_ShowCopyLink=_G.MSUF_ShowCopyLink or MSUF_ShowCopyLink
local MIRROR_PANEL_SCALE=1.00;
local MENU_FONT_BUMP=3;
local MIRRORED_PANEL_FONT_BUMP=1;
local MSUF_MIRROR_MAIN_CROP_Y=42;
local MSUF_MIRROR_DEEPLINK_CROP_Y=96 local function MSUF_ApplyMidnightBackdrop(frame,alphaOverride) if not frame or not frame.SetBackdrop then return end
frame:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=16,insets={left=3,right=3,top=3,bottom=3},})
local a=alphaOverride or MSUF_THEME.bgA frame:SetBackdropColor(MSUF_THEME.bgR,MSUF_THEME.bgG,MSUF_THEME.bgB,a)
if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(MSUF_THEME.edgeR,MSUF_THEME.edgeG,MSUF_THEME.edgeB,MSUF_THEME.edgeA)
end
end
local function MSUF_SkinTitle(fs) if fs and fs.SetTextColor then fs:SetTextColor(MSUF_THEME.titleR,MSUF_THEME.titleG,MSUF_THEME.titleB,MSUF_THEME.titleA)
end
end
local function MSUF_SkinText(fs) if fs and fs.SetTextColor then fs:SetTextColor(MSUF_THEME.textR,MSUF_THEME.textG,MSUF_THEME.textB,MSUF_THEME.textA)
end
end
local function MSUF_SkinMuted(fs) if fs and fs.SetTextColor then fs:SetTextColor(MSUF_THEME.textR*0.80,MSUF_THEME.textG*0.80,MSUF_THEME.textB*0.80,0.85)
end
end
local function MSUF_EnsureNavActiveOverlay(btn,fillGroup) if not(btn and btn.CreateTexture and fillGroup and fillGroup.L and fillGroup.M and fillGroup.R)
then return nil end
if btn._msufNavActive3 then local g=btn._msufNavActive3 if g and g.L and g.L.SetAllPoints then g.L:SetAllPoints(fillGroup.L)
end
if g and g.M and g.M.SetAllPoints then g.M:SetAllPoints(fillGroup.M)
end
if g and g.R and g.R.SetAllPoints then g.R:SetAllPoints(fillGroup.R)
end
return g end
local g={}
g.L=btn:CreateTexture(nil,"ARTWORK",nil,2)
g.M=btn:CreateTexture(nil,"ARTWORK",nil,2)
g.R=btn:CreateTexture(nil,"ARTWORK",nil,2)
g._msufSEParts={g.L,g.M,g.R}
g.L:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.M:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.R:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.L:SetTexCoord(0.0,0.25,0.0,1.0)
g.M:SetTexCoord(0.25,0.75,0.0,1.0)
g.R:SetTexCoord(0.75,1.0,0.0,1.0)
for i=1,#g._msufSEParts do local t=g._msufSEParts[i]
if t and t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)
if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)
end
end
end
g.SetVertexColor=function(self,r,gg,b,a) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.SetVertexColor then t:SetVertexColor(r,gg,b,a)
end
end
end
g.Hide=function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.Hide then t:Hide()
end
end
end
g.Show=function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.Show then t:Show()
end
end
end
g.L:SetAllPoints(fillGroup.L)
g.M:SetAllPoints(fillGroup.M)
g.R:SetAllPoints(fillGroup.R)
g:Hide()
btn._msufNavActive3=g return g end
local function MSUF_UseModernDropdowns()
local g=MSUF_DB and MSUF_DB.general
local mode=g and g.dropdownStyleMode
if mode=="old"or mode=="blizzard"or mode=="legacy"then return false end
return true end
local function MSUF_EnsureNavWarmHoverOverlay(btn,fillGroup) if not(btn and btn.CreateTexture and fillGroup and fillGroup.L and fillGroup.M and fillGroup.R)
then return nil,nil end
if btn._msufNavWarmHover3 then local g=btn._msufNavWarmHover3 if g and g.L and g.L.SetAllPoints then g.L:SetAllPoints(fillGroup.L) end
if g and g.M and g.M.SetAllPoints then g.M:SetAllPoints(fillGroup.M) end
if g and g.R and g.R.SetAllPoints then g.R:SetAllPoints(fillGroup.R) end
local sheen=btn._msufNavWarmSheen3 if sheen then sheen:ClearAllPoints()
sheen:SetPoint("TOPLEFT",btn,"TOPLEFT",12,-2)
sheen:SetPoint("TOPRIGHT",btn,"TOPRIGHT",-12,-2)
sheen:SetHeight(1) end
return g,sheen end
local g={}
g.L=btn:CreateTexture(nil,"ARTWORK",nil,4)
g.M=btn:CreateTexture(nil,"ARTWORK",nil,4)
g.R=btn:CreateTexture(nil,"ARTWORK",nil,4)
g._msufSEParts={g.L,g.M,g.R}
g.L:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.M:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.R:SetTexture(MSUF_SUPERELLIPSE_TEX)
g.L:SetTexCoord(0.0,0.25,0.0,1.0)
g.M:SetTexCoord(0.25,0.75,0.0,1.0)
g.R:SetTexCoord(0.75,1.0,0.0,1.0)
for i=1,#g._msufSEParts do local t=g._msufSEParts[i]
if t and t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)
if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)
end
end
end
g.SetVertexColor=function(self,r,gg,b,a) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.SetVertexColor then t:SetVertexColor(r,gg,b,a)
end
end
end
g.Hide=function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.Hide then t:Hide()
end
end
end
g.Show=function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]
if t and t.Show then t:Show()
end
end
end
g.L:SetAllPoints(fillGroup.L)
g.M:SetAllPoints(fillGroup.M)
g.R:SetAllPoints(fillGroup.R)
g:Hide()
btn._msufNavWarmHover3=g
local sheen=btn:CreateTexture(nil,"ARTWORK",nil,5)
sheen:SetTexture("Interface/Buttons/WHITE8X8")
sheen:SetPoint("TOPLEFT",btn,"TOPLEFT",12,-2)
sheen:SetPoint("TOPRIGHT",btn,"TOPRIGHT",-12,-2)
sheen:SetHeight(1)
sheen:SetColorTexture(0.98,0.90,0.56,0.0)
sheen:Hide()
btn._msufNavWarmSheen3=sheen
return g,sheen end
local function MSUF_ApplyNavWarmHover(btn,fillAlpha,sheenAlpha)
local g,sheen=MSUF_EnsureNavWarmHoverOverlay(btn,btn and btn._msufNavBG or nil)
if g and g.SetVertexColor then g:SetVertexColor(0.96,0.86,0.42,fillAlpha or 0)
if(fillAlpha or 0)>0 then g:Show() else g:Hide() end
end
if sheen and sheen.SetColorTexture then sheen:SetColorTexture(0.98,0.90,0.56,sheenAlpha or 0)
if(sheenAlpha or 0)>0 then sheen:Show() else sheen:Hide() end
end
end
MSUF_SkinButton=function(btn) if not btn then return end
-- Opt-out: Options panels manage their own action buttons (Edit Mode / Copy / Import Cancel etc).
if btn._msufNoSlashSkin or btn.__msufMidnightActionSkinned or btn.__msufMidnightTabSkinned then
if type(_G.MSUF_ForceShowUIPanelButtonPieces)=="function"then pcall(_G.MSUF_ForceShowUIPanelButtonPieces,btn) end
return end
if btn.__MSUF_MidnightSkinned or btn.__MSUF_NavSkinned or btn.__MSUF_DashSkinned then return end
btn.__MSUF_MidnightSkinned=true local looksPanel=false if(btn.Left and btn.Middle and btn.Right)
then looksPanel=true elseif btn.GetRegions then local regions={btn:GetRegions()}
for i=1,#regions do local r=regions[i]
if r and r.GetObjectType and r:GetObjectType()=="Texture"and r.GetTexture then local ok,tex=pcall(r.GetTexture,r)
if ok and type(tex)=="string"then if tex:find("UI%-Panel%-Button")
or tex:find("UIPanelButton")
then looksPanel=true break end
end
end
end
end
if not looksPanel then local nt=btn.GetNormalTexture and btn:GetNormalTexture()
if nt and nt.SetVertexColor then nt:SetVertexColor(0.18,0.36,0.90,1.00)
end
local pt=btn.GetPushedTexture and btn:GetPushedTexture()
if pt and pt.SetVertexColor then pt:SetVertexColor(0.12,0.26,0.70,1.00)
end
local ht=btn.GetHighlightTexture and btn:GetHighlightTexture()
if ht and ht.SetVertexColor then ht:SetVertexColor(0.25,0.55,1.00,0.85)
end
local dt=btn.GetDisabledTexture and btn:GetDisabledTexture()
if dt and dt.SetVertexColor then dt:SetVertexColor(0.25,0.25,0.25,0.55)
end
return end
if btn.Left and btn.Left.Hide then btn.Left:Hide()
end
if btn.Middle and btn.Middle.Hide then btn.Middle:Hide()
end
if btn.Right and btn.Right.Hide then btn.Right:Hide()
end
if btn.GetRegions then local regions={btn:GetRegions()}
for i=1,#regions do local r=regions[i]
if r and r.GetObjectType and r:GetObjectType()=="Texture"and r.GetTexture then local ok,tex=pcall(r.GetTexture,r)
if ok and type(tex)=="string"then local isPanelArt=false if tex:find("UI%-Panel%-Button")
or tex:find("UIPanelButton")
then isPanelArt=true end
if isPanelArt then if r.SetAlpha then r:SetAlpha(0)
end
if r.Hide then r:Hide()
end
end
end
end
end
end
if btn.GetNormalTexture and btn.SetNormalTexture then local nt=btn:GetNormalTexture()
if nt and nt.SetAlpha then nt:SetAlpha(0)
end
pcall(btn.SetNormalTexture,btn,nil)
end
if btn.GetPushedTexture and btn.SetPushedTexture then local pt=btn:GetPushedTexture()
if pt and pt.SetAlpha then pt:SetAlpha(0)
end
pcall(btn.SetPushedTexture,btn,nil)
end
if btn.GetHighlightTexture and btn.SetHighlightTexture then local ht=btn:GetHighlightTexture()
if ht and ht.SetAlpha then ht:SetAlpha(0)
end
pcall(btn.SetHighlightTexture,btn,nil)
end
if btn.GetDisabledTexture and btn.SetDisabledTexture then local dt=btn:GetDisabledTexture()
if dt and dt.SetAlpha then dt:SetAlpha(0)
end
pcall(btn.SetDisabledTexture,btn,nil)
end
local bg,border=MSUF_EnsureSuperellipseLayers(btn,2)
if border and border.SetVertexColor then border:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.60)
end
if bg and bg.SetVertexColor then bg:SetVertexColor(0.06,0.07,0.13,0.92)
end
btn._msufBtnBorder=border btn._msufBtnBG=bg btn._msufBtnBG_base={0.06,0.07,0.13,0.92}
btn._msufBtnBG_hover={0.09,0.10,0.18,0.98}
btn._msufBtnBG_pressed={0.05,0.06,0.11,0.98}
local fs=btn.GetFontString and btn:GetFontString()
if fs and fs.SetTextColor then fs:SetTextColor(MSUF_THEME.textR,MSUF_THEME.textG,MSUF_THEME.textB,MSUF_THEME.textA)
if fs.SetShadowColor then fs:SetShadowColor(0,0,0,0.6)
end
if fs.SetShadowOffset then fs:SetShadowOffset(1,-1)
end
if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY",7)
end
if fs.SetAlpha then fs:SetAlpha(1)
end
if fs.Show then pcall(fs.Show,fs)
end
if fs.GetText and fs.SetText then local ok,t=pcall(fs.GetText,fs)
if ok then pcall(fs.SetText,fs,t or"")
end
end
end
if btn.SetAlpha then btn:SetAlpha(1)
end
if btn.HookScript and not btn.__msufBtnShowFix then btn.__msufBtnShowFix=true btn:HookScript("OnShow",function(self) if self.SetAlpha then self:SetAlpha(1)
end
local f=self.GetFontString and self:GetFontString()
if f then if f.Show then pcall(f.Show,f)
end
if f.SetDrawLayer then f:SetDrawLayer("OVERLAY",7)
end
if f.SetAlpha then f:SetAlpha(1)
end
if f.GetText and f.SetText then local ok,t=pcall(f.GetText,f)
if ok then pcall(f.SetText,f,t or"")
end
end
end
if self._msufBtnBG and self._msufBtnBG_base then local col=self._msufBtnBG_base if self._msufBtnBG.SetVertexColor then self._msufBtnBG:SetVertexColor(col[1],col[2],col[3],col[4])
end
end
end
)
end
if btn.HookScript and not btn.__msufBtnHideFix then btn.__msufBtnHideFix=true btn:HookScript("OnHide",function(self) if self.UnlockHighlight then pcall(self.UnlockHighlight,self)
end
if self.SetButtonState then pcall(self.SetButtonState,self,"NORMAL")
end
if self._msufBtnBG and self._msufBtnBG_base and self._msufBtnBG.SetVertexColor then local col=self._msufBtnBG_base;
self._msufBtnBG:SetVertexColor(col[1],col[2],col[3],col[4])
end
if self.SetAlpha then self:SetAlpha(1)
end
local f=self.GetFontString and self:GetFontString()
if f then if f.SetDrawLayer then f:SetDrawLayer("OVERLAY",7)
end
if f.SetAlpha then f:SetAlpha(1)
end
end
end
)
end
local oldEnter=btn:GetScript("OnEnter");
local oldLeave=btn:GetScript("OnLeave");
local oldDown=btn:GetScript("OnMouseDown");
local oldUp=btn:GetScript("OnMouseUp");
local oldDis=btn:GetScript("OnDisable")
local oldEn=btn:GetScript("OnEnable")
local function ApplyBG(self,col) if not self or type(col)~="table"then return end
local bg=self._msufBtnBG if bg and bg.SetVertexColor then bg:SetVertexColor(col[1],col[2],col[3],col[4])
end
end
btn:SetScript("OnEnter",function(self,...) ApplyBG(self,self._msufBtnBG_hover or self._msufBtnBG_base)
if oldEnter then pcall(oldEnter,self,...)
end
end
)
btn:SetScript("OnLeave",function(self,...) ApplyBG(self,self._msufBtnBG_base)
if oldLeave then pcall(oldLeave,self,...)
end
end
)
btn:SetScript("OnMouseDown",function(self,...) ApplyBG(self,self._msufBtnBG_pressed or self._msufBtnBG_hover)
if oldDown then pcall(oldDown,self,...)
end
end
)
btn:SetScript("OnMouseUp",function(self,...) if self.IsMouseOver and self:IsMouseOver()
then ApplyBG(self,self._msufBtnBG_hover or self._msufBtnBG_base)
else ApplyBG(self,self._msufBtnBG_base)
end
if oldUp then pcall(oldUp,self,...)
end
end
)
btn:SetScript("OnDisable",function(self,...) if self._msufBtnBG then self._msufBtnBG:SetVertexColor(0.07,0.07,0.08,0.65)
end
if self._msufBtnBorder and self._msufBtnBorder.SetVertexColor then self._msufBtnBorder:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.45)
end
local f=self.GetFontString and self:GetFontString()
if f and f.SetTextColor then f:SetTextColor(0.55,0.60,0.70,0.85)
end
if oldDis then pcall(oldDis,self,...)
end
end
)
btn:SetScript("OnEnable",function(self,...) if self._msufBtnBG then self._msufBtnBG:SetVertexColor(0.06,0.07,0.13,0.92)
end
if self._msufBtnBorder and self._msufBtnBorder.SetVertexColor then self._msufBtnBorder:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.60)
end
local f=self.GetFontString and self:GetFontString()
if f and f.SetTextColor then f:SetTextColor(MSUF_THEME.textR,MSUF_THEME.textG,MSUF_THEME.textB,MSUF_THEME.textA)
end
if oldEn then pcall(oldEn,self,...)
end
end
) end
local function MSUF_ApplyMidnightControlsToFrame(root) if not root or not root.GetChildren then return end
local function LooksLikePanelButton(b) if not b then return false end
if(b.Left and b.Middle and b.Right)
then return true end
if not b.GetRegions then return false end
local regions={b:GetRegions()}
for i=1,#regions do local r=regions[i]
if r and r.GetObjectType and r:GetObjectType()=="Texture"and r.GetTexture then local ok,tex=pcall(r.GetTexture,r)
if ok and type(tex)=="string"then if tex:find("UI%-Panel%-Button")
or tex:find("UIPanelButton")
then return true end
end
end
end
return false end
local function MaybeFixCheckLabel(cb) local fs=cb and(cb.Text or cb.text or(cb.GetFontString and cb:GetFontString()))
if not(fs and fs.GetTextColor and fs.SetTextColor)
then return end
local r,g,b=fs:GetTextColor()
if r and g and b and r>=0.86 and g>=0.66 and b<=0.45 then fs:SetTextColor(MSUF_THEME.textR,MSUF_THEME.textG,MSUF_THEME.textB,MSUF_THEME.textA)
end
end
local function Walk(f) if not f then return end
if f.GetObjectType then local ot=f:GetObjectType()
if ot=="Button"then if not(f.IsObjectType and f:IsObjectType("CheckButton"))
then if LooksLikePanelButton(f)
then MSUF_SkinButton(f)
end
end
elseif ot=="CheckButton"then MaybeFixCheckLabel(f)
end
end
if f.GetChildren then local kids={f:GetChildren()}
for i=1,#kids do Walk(kids[i])
end
end
end
Walk(root) end
local function MSUF_SkinNavButton(btn,isHeader,isIndented) if not btn or btn.__MSUF_NavSkinned then return end
btn.__MSUF_NavSkinned=true if btn.SetEnabled then pcall(btn.SetEnabled,btn,true)
end
if btn.Left and btn.Left.Hide then btn.Left:Hide()
end
if btn.Middle and btn.Middle.Hide then btn.Middle:Hide()
end
if btn.Right and btn.Right.Hide then btn.Right:Hide()
end
if btn.GetNormalTexture and btn.SetNormalTexture then local nt=btn:GetNormalTexture()
if nt and nt.SetAlpha then nt:SetAlpha(0)
end
pcall(btn.SetNormalTexture,btn,nil)
end
if btn.GetPushedTexture and btn.SetPushedTexture then local pt=btn:GetPushedTexture()
if pt and pt.SetAlpha then pt:SetAlpha(0)
end
pcall(btn.SetPushedTexture,btn,nil)
end
if btn.GetHighlightTexture and btn.SetHighlightTexture then local ht=btn:GetHighlightTexture()
if ht and ht.SetAlpha then ht:SetAlpha(0)
end
pcall(btn.SetHighlightTexture,btn,nil)
end
if btn.GetDisabledTexture and btn.SetDisabledTexture then local dt=btn:GetDisabledTexture()
if dt and dt.SetAlpha then dt:SetAlpha(0)
end
pcall(btn.SetDisabledTexture,btn,nil)
end
local bg,border=MSUF_EnsureSuperellipseLayers(btn,2);
local active=MSUF_EnsureNavActiveOverlay(btn,bg)
local warm,warmSheen=MSUF_EnsureNavWarmHoverOverlay(btn,bg)
if active and active.SetVertexColor then active:SetVertexColor(0.16,0.36,0.80,0.55)
end
if warm and warm.SetVertexColor then warm:SetVertexColor(0.96,0.86,0.42,0.0); warm:Hide() end
if warmSheen and warmSheen.SetColorTexture then warmSheen:SetColorTexture(0.98,0.90,0.56,0.0); warmSheen:Hide() end
if border and border.SetVertexColor then border:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.45)
end
if bg and bg.SetVertexColor then if isIndented then bg:SetVertexColor(0.06,0.07,0.13,0.80)
else bg:SetVertexColor(0.06,0.07,0.13,0.88)
end
end
btn._msufNavBorder=border btn._msufNavBG=bg
local accentStripe=btn:CreateTexture(nil,"ARTWORK",nil,6)
accentStripe:SetTexture("Interface/Buttons/WHITE8X8")
accentStripe:SetWidth(3)
accentStripe:SetPoint("TOPLEFT",btn,"TOPLEFT",1,-4)
accentStripe:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",1,4)
accentStripe:SetColorTexture(MSUF_THEME.accentR,MSUF_THEME.accentG,MSUF_THEME.accentB,1.00)
accentStripe:Hide()
btn._msufNavAccentStripe=accentStripe
local fs=btn.GetFontString and btn:GetFontString()
if fs and fs.SetTextColor then if isHeader then fs:SetTextColor(0.55,0.62,0.78,0.88)
if fs.GetFont and fs.SetFont then local fPath,fSize,fFlags=fs:GetFont()
if fPath and fSize then MSUF_SafeSetFont(fs,fPath,math.max(8,fSize-1),fFlags or"") end
end
else if isIndented then fs:SetTextColor(0.80,0.88,1.00,0.92)
else fs:SetTextColor(0.82,0.90,1.00,1.00)
end
end
end
btn._msufApplyNavState=function(self,activeState,hovered) if self._msufNavActive3 then if activeState then self._msufNavActive3:Show()
else self._msufNavActive3:Hide()
end
end
if self._msufNavAccentStripe then if activeState then self._msufNavAccentStripe:Show()
else self._msufNavAccentStripe:Hide()
end
end
if self._msufNavIcon then local c=self._msufNavIconColor
if c then if activeState then self._msufNavIcon:SetVertexColor(c[1],c[2],c[3],1.00)
elseif hovered then self._msufNavIcon:SetVertexColor(c[1],c[2],c[3],0.85)
else self._msufNavIcon:SetVertexColor(c[1],c[2],c[3],0.50)
end
end
end
activeState=activeState and true or false hovered=hovered and true or false local modern=MSUF_UseModernDropdowns() local fs2=self.GetFontString and self:GetFontString()
if fs2 and fs2 .SetTextColor then if activeState then fs2:SetTextColor(0.92,0.96,1.00,1.00)
else if isHeader then fs2:SetTextColor(0.55,0.62,0.78,0.88)
else if isIndented then fs2:SetTextColor(0.80,0.88,1.00,0.92)
else fs2:SetTextColor(0.82,0.90,1.00,1.00)
end
end
end
end
if self._msufNavBG and self._msufNavBG.SetVertexColor then if activeState then self._msufNavBG:SetVertexColor(0.12,0.15,0.32,0.95)
else if hovered then if isIndented then self._msufNavBG:SetVertexColor(0.08,0.09,0.16,0.88)
else self._msufNavBG:SetVertexColor(0.08,0.09,0.16,0.95)
end
else if isIndented then self._msufNavBG:SetVertexColor(0.06,0.07,0.13,0.80)
else self._msufNavBG:SetVertexColor(0.06,0.07,0.13,0.88)
end
end
if self._msufNavBorder and self._msufNavBorder.SetVertexColor then if activeState then self._msufNavBorder:SetVertexColor(0.20,0.34,0.80,0.85)
else if hovered then self._msufNavBorder:SetVertexColor(0.14,0.22,0.60,0.75)
else self._msufNavBorder:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.45)
end
end
end
if modern then if activeState then if hovered then MSUF_ApplyNavWarmHover(self,0.05,0.14)
else MSUF_ApplyNavWarmHover(self,0.0,0.0)
end
elseif hovered then MSUF_ApplyNavWarmHover(self,0.14,0.28)
else MSUF_ApplyNavWarmHover(self,0.0,0.0)
end
else MSUF_ApplyNavWarmHover(self,0.0,0.0)
end
end
end
end
local oldEnter=btn:GetScript("OnEnter");
local oldLeave=btn:GetScript("OnLeave")
btn:SetScript("OnEnter",function(self,...) if self._msufApplyNavState then self:_msufApplyNavState(self._msufNavIsActive,true)
end
if oldEnter then pcall(oldEnter,self,...)
end
end
)
btn:SetScript("OnLeave",function(self,...) if self._msufApplyNavState then self:_msufApplyNavState(self._msufNavIsActive,false)
end
if oldLeave then pcall(oldLeave,self,...)
end
end
) end
_G.MSUF_SkinNavButton=MSUF_SkinNavButton local function MSUF_SkinDashboardButton(btn) if not btn or btn.__MSUF_DashSkinned then return end
btn.__MSUF_DashSkinned=true if btn.Left and btn.Left.Hide then btn.Left:Hide()
end
if btn.Middle and btn.Middle.Hide then btn.Middle:Hide()
end
if btn.Right and btn.Right.Hide then btn.Right:Hide()
end
if btn.GetRegions then local regions={btn:GetRegions()}
for i=1,#regions do local r=regions[i]
if r and r.GetObjectType and r:GetObjectType()=="Texture"then local tex=r.GetTexture and r:GetTexture();
local atlas=r.GetAtlas and r:GetAtlas();
local isPanelArt=false if type(atlas)=="string"then if atlas:find("UI-Panel-Button",1,true)
or atlas:find("UIPanelButton",1,true)
then isPanelArt=true end
end
if(not isPanelArt)
and type(tex)=="string"then if tex:find("UI-Panel-Button",1,true)
or tex:find("UIPanelButton",1,true)
or tex:find("Buttons\\UI-Panel-Button",1,true)
then isPanelArt=true end
end
if isPanelArt then if r.SetAlpha then r:SetAlpha(0)
end
if r.Hide then r:Hide()
end
end
end
end
end
if btn.GetNormalTexture and btn.SetNormalTexture then local nt=btn:GetNormalTexture()
if nt and nt.SetAlpha then nt:SetAlpha(0)
end
pcall(btn.SetNormalTexture,btn,nil)
end
if btn.GetPushedTexture and btn.SetPushedTexture then local pt=btn:GetPushedTexture()
if pt and pt.SetAlpha then pt:SetAlpha(0)
end
pcall(btn.SetPushedTexture,btn,nil)
end
if btn.GetHighlightTexture and btn.SetHighlightTexture then local ht=btn:GetHighlightTexture()
if ht and ht.SetAlpha then ht:SetAlpha(0)
end
pcall(btn.SetHighlightTexture,btn,nil)
end
if btn.GetDisabledTexture and btn.SetDisabledTexture then local dt=btn:GetDisabledTexture()
if dt and dt.SetAlpha then dt:SetAlpha(0)
end
pcall(btn.SetDisabledTexture,btn,nil)
end
local bgHost=CreateFrame("Frame",nil,btn,"BackdropTemplate")
bgHost:SetPoint("TOPLEFT",btn,"TOPLEFT",1,-1)
bgHost:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",-1,1)
local lvl=(btn.GetFrameLevel and btn:GetFrameLevel())
or 1 if bgHost.SetFrameLevel then bgHost:SetFrameLevel((lvl>1)
and(lvl-1)
or 0)
end
if bgHost.SetBackdrop then bgHost:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3},})
bgHost:SetBackdropColor(0.06,0.07,0.12,0.94)
if bgHost.SetBackdropBorderColor then bgHost:SetBackdropBorderColor(0.08,0.10,0.22,0.70)
end
end
btn._msufDashBGFrame=bgHost local bg=btn:CreateTexture(nil,"BACKGROUND")
bg:SetTexture("Interface/Buttons/WHITE8X8")
bg:SetAllPoints(bgHost)
bg:SetVertexColor(0.06,0.07,0.13,0.94)
if btn._msufDashBGFrame and btn._msufDashBGFrame.SetBackdrop then bg:SetAlpha(0.01)
end
btn._msufDashBG=bg local hover=btn:CreateTexture(nil,"HIGHLIGHT")
hover:SetTexture("Interface/Buttons/WHITE8X8")
hover:SetAllPoints(bg)
hover:SetVertexColor(0.18,0.22,0.70,0.15)
hover:Hide()
btn._msufDashHover=hover local sel=btn:CreateTexture(nil,"ARTWORK")
sel:SetTexture("Interface/Buttons/WHITE8X8")
sel:SetAllPoints(bg)
sel:SetVertexColor(0.25,0.55,1.0,0.30)
sel:Hide()
btn._msufDashSelected=sel local down=btn:CreateTexture(nil,"OVERLAY")
down:SetTexture("Interface/Buttons/WHITE8X8")
down:SetAllPoints(bg)
down:SetVertexColor(0.25,0.55,1.0,0.22)
down:Hide()
btn._msufDashDown=down local function ApplyText(active) local fs=btn.GetFontString and btn:GetFontString()
if fs and fs.SetTextColor then if active then fs:SetTextColor(0.92,0.96,1.00,1.00)
else fs:SetTextColor(0.82,0.90,1.00,1.00)
end
end
end
ApplyText(false)
btn._msufSetSelected=function(self,active) self._msufDashIsSelected=active and true or false if self._msufDashSelected then if self._msufDashIsSelected then self._msufDashSelected:Show()
else self._msufDashSelected:Hide()
end
end
ApplyText(self._msufDashIsSelected)
if self._msufDashHover then if self._msufDashHover._msufHovering and not self._msufDashIsSelected then self._msufDashHover:Show()
else self._msufDashHover:Hide()
end
end
end
local oldEnter=btn:GetScript("OnEnter");
local oldLeave=btn:GetScript("OnLeave")
btn:SetScript("OnEnter",function(self,...) if self._msufDashHover then self._msufDashHover._msufHovering=true if not self._msufDashIsSelected then self._msufDashHover:Show()
end
end
if oldEnter then pcall(oldEnter,self,...)
end
end
)
btn:SetScript("OnLeave",function(self,...) if self._msufDashHover then self._msufDashHover._msufHovering=false;
self._msufDashHover:Hide()
end
if oldLeave then pcall(oldLeave,self,...)
end
end
)
local oldDown=btn:GetScript("OnMouseDown");
local oldUp=btn:GetScript("OnMouseUp")
btn:SetScript("OnMouseDown",function(self,...) if self._msufDashDown then self._msufDashDown:Show()
end
if oldDown then pcall(oldDown,self,...)
end
end
)
btn:SetScript("OnMouseUp",function(self,...) if self._msufDashDown then self._msufDashDown:Hide()
end
if oldUp then pcall(oldUp,self,...)
end
end
)
local oldDisable=btn:GetScript("OnDisable");
local oldEnable=btn:GetScript("OnEnable")
btn:SetScript("OnDisable",function(self,...) if self._msufDashBG then self._msufDashBG:SetVertexColor(0.06,0.06,0.07,0.65)
end
local fs=self.GetFontString and self:GetFontString()
if fs and fs.SetTextColor then fs:SetTextColor(0.55,0.60,0.70,0.85)
end
if oldDisable then pcall(oldDisable,self,...)
end
end
)
btn:SetScript("OnEnable",function(self,...) if self._msufDashBG then self._msufDashBG:SetVertexColor(0.06,0.07,0.13,0.94)
end
ApplyText(self._msufDashIsSelected)
if oldEnable then pcall(oldEnable,self,...)
end
end
) end
-- Accent button variants (Discord Admin style color-coded buttons)
-- Uses HookScript so accent hooks survive MSUF_AddTooltip's SetScript override
-- (UI_Btn calls skinFn first, then MSUF_AddTooltip replaces OnEnter/OnLeave)
local function MSUF_SkinAccentButton(btn,bgR,bgG,bgB,hoverR,hoverG,hoverB,pressR,pressG,pressB)
if not btn then return end
MSUF_SkinDashboardButton(btn)
local bgF=btn._msufDashBGFrame
local bgTex=btn._msufDashBG
local function ApplyAccent(r,g,b,a)
if bgF and bgF.SetBackdropColor then bgF:SetBackdropColor(r,g,b,a or 0.97)
if bgF.SetBackdropBorderColor then bgF:SetBackdropBorderColor(
r<1 and r*1.3 or 1,g<1 and g*1.3 or 1,b<1 and b*1.3 or 1,0.85) end
end
if bgTex and bgTex.SetVertexColor and bgTex.SetAlpha then
bgTex:SetVertexColor(r,g,b,a or 0.97)
bgTex:SetAlpha(a or 0.97) end
end
ApplyAccent(bgR,bgG,bgB,0.97)
if btn._msufDashHover and btn._msufDashHover.SetAlpha then btn._msufDashHover:SetAlpha(0) end
if btn._msufDashSelected and btn._msufDashSelected.SetAlpha then btn._msufDashSelected:SetAlpha(0) end
if btn._msufDashDown and btn._msufDashDown.SetAlpha then btn._msufDashDown:SetAlpha(0) end
local fs=btn.GetFontString and btn:GetFontString()
if fs and fs.SetTextColor then fs:SetTextColor(1.00,1.00,1.00,1.00)
if fs.SetShadowColor then fs:SetShadowColor(0,0,0,0.80) end
end
btn._msufAccentBase={bgR,bgG,bgB}
btn._msufAccentHover={hoverR,hoverG,hoverB}
btn._msufAccentPress={pressR,pressG,pressB}
btn:HookScript("OnShow",function(self)
local c=self._msufAccentBase
if c then ApplyAccent(c[1],c[2],c[3],0.97) end
local f=self.GetFontString and self:GetFontString()
if f and f.SetTextColor then f:SetTextColor(1.00,1.00,1.00,1.00) end
end)
btn:HookScript("OnEnter",function(self)
local c=self._msufAccentHover or self._msufAccentBase
if c then ApplyAccent(c[1],c[2],c[3],0.99) end
if self._msufDashHover then self._msufDashHover:Hide() end
end)
btn:HookScript("OnLeave",function(self)
local c=self._msufAccentBase
if c then ApplyAccent(c[1],c[2],c[3],0.97) end
end)
btn:HookScript("OnMouseDown",function(self)
local c=self._msufAccentPress or self._msufAccentHover
if c then ApplyAccent(c[1],c[2],c[3],0.99) end
if self._msufDashDown then self._msufDashDown:Hide() end
end)
btn:HookScript("OnMouseUp",function(self)
local hovering=self.IsMouseOver and self:IsMouseOver()
local c=hovering and(self._msufAccentHover or self._msufAccentBase) or self._msufAccentBase
if c then ApplyAccent(c[1],c[2],c[3],hovering and 0.99 or 0.97) end
end)
end
local function MSUF_SkinPrimaryButton(btn)
MSUF_SkinAccentButton(btn,0.16,0.56,0.72,0.20,0.64,0.82,0.12,0.48,0.62)
end
local function MSUF_SkinDangerButton(btn)
MSUF_SkinAccentButton(btn,0.72,0.22,0.22,0.82,0.28,0.28,0.60,0.16,0.16)
end
local function MSUF_SkinSuccessButton(btn)
MSUF_SkinAccentButton(btn,0.18,0.62,0.36,0.22,0.72,0.42,0.14,0.52,0.28)
end
_G.MSUF_SkinPrimaryButton=MSUF_SkinPrimaryButton
_G.MSUF_SkinDangerButton=MSUF_SkinDangerButton
_G.MSUF_SkinSuccessButton=MSUF_SkinSuccessButton
local function MSUF_IsYellowish(r,g,b) if not r or not g or not b then return false end
if r>=0.88 and g>=0.68 and b<=0.35 and(g>=(b+0.25))
then return true end
return false end
local function MSUF_ApplyWhiteTextToFrame(root) if not root then return end
-- PERF: Throttle per-root. Burst calls (OnShow hooks firing multiple times
-- during a single panel attach) coalesce into 1 walk. 100ms is much shorter
-- than any user-perceivable UI change, and longer-interval calls (real updates
-- or font changes) still run normally. Idempotency: if FontStrings are already
-- white, re-walk just re-verifies cheaply; skipping is safe for the burst case.
local now=GetTime and GetTime()or 0
local lastT=root.__MSUF_WhiteTextLastT or 0
if lastT>0 and(now-lastT)<0.1 then return end
root.__MSUF_WhiteTextLastT=now
local token=(root.__MSUF_WhiteTextToken or 0)+1 root.__MSUF_WhiteTextToken=token local useTimer=(C_Timer and C_Timer.After)
and true or false;
local maxNodes=useTimer and 4500 or 800;
local budgetMs=useTimer and 1.0 or nil;
local debugprofilestop=debugprofilestop;
local stack,sp={root},1 local seen={};
local nodes=0 local function ProcessChunk() if not root or root.__MSUF_WhiteTextToken~=token then return end
local t0=(budgetMs and debugprofilestop)
and debugprofilestop()
or nil while sp>0 do if t0 and(debugprofilestop()-t0)>=budgetMs then break end
local frame=stack[sp]
stack[sp]=nil sp=sp-1 if frame and not seen[frame]
then seen[frame]=true nodes=nodes+1 if nodes>maxNodes then break end
if frame.GetRegions then local regions={frame:GetRegions()}
for i=1,#regions do local reg=regions[i]
if reg and reg.GetObjectType and reg:GetObjectType()=="FontString"and reg.GetTextColor and reg.SetTextColor then local r,g,b=reg:GetTextColor()
if MSUF_IsYellowish(r,g,b)
then reg:SetTextColor(MSUF_THEME.textR,MSUF_THEME.textG,MSUF_THEME.textB,MSUF_THEME.textA)
end
end
end
end
if frame.GetChildren then local children={frame:GetChildren()}
for i=1,#children do local c=children[i]
if c and not seen[c]
then sp=sp+1 stack[sp]=c end
end
end
end
end
if sp>0 and nodes<=maxNodes and root and root.__MSUF_WhiteTextToken==token then if useTimer then C_Timer.After(0,ProcessChunk)
end
end
end
ProcessChunk() end
local function MSUF_ApplyFontBumpToFrame(root,bump) bump=tonumber(bump or 0)
or 0 if bump==0 or not root then return end
if root.__MSUF_FontBumpApplied==bump then return end
if root.__MSUF_FontBumpInProgress then root.__MSUF_FontBumpPending=bump return end
root.__MSUF_FontBumpInProgress=true root.__MSUF_FontBumpPending=nil local queue,qIndex={root},1;
local visited={}
local function bumpFont(obj) if not obj or not obj.GetFont or not obj.SetFont then return end
local ok,font,size,flags=pcall(obj.GetFont,obj)
if not ok or not font or not size then return end
if not obj.__MSUF_FontOrig then obj.__MSUF_FontOrig={font=font,size=size,flags=flags}
end
local orig=obj.__MSUF_FontOrig MSUF_SafeSetFont(obj,orig.font,(orig.size or size)+bump,orig.flags) end
local function enqueue(child) if not child or visited[child]
then return end
visited[child]=true queue[#queue+1]=child end
visited[root]=true local function processChunk() local t0=debugprofilestop();
local budgetMs=6.0 while qIndex<=#queue do local frame=queue[qIndex]
qIndex=qIndex+1 if frame then bumpFont(frame)
if frame.EnumerateRegions then for reg in frame:EnumerateRegions()
do bumpFont(reg)
end
elseif frame.GetRegions then local regions={frame:GetRegions()}
for i=1,#regions do bumpFont(regions[i])
end
end
if frame.EnumerateChildren then for child in frame:EnumerateChildren()
do enqueue(child)
end
elseif frame.GetChildren then local children={frame:GetChildren()}
for i=1,#children do enqueue(children[i])
end
end
end
if(debugprofilestop()-t0)>budgetMs then C_Timer.After(0,processChunk) return end
end
root.__MSUF_FontBumpApplied=bump root.__MSUF_FontBumpInProgress=nil local pending=root.__MSUF_FontBumpPending root.__MSUF_FontBumpPending=nil if pending and pending~=bump then C_Timer.After(0,function() if root and root.IsObjectType and root:IsObjectType("Frame")
then MSUF_ApplyFontBumpToFrame(root,pending)
end
end
)
end
end
C_Timer.After(0,processChunk) end
local function MSUF_CollectMsufScaleFrames() local frames,seen={},{}
local function add(f) if not f or seen[f]
then return end
if type(f)=="table"and type(f.SetScale)=="function"then seen[f]=true table.insert(frames,f)
end
end
if type(_G.MSUF_UnitFrames)=="table"then for _,f in pairs(_G.MSUF_UnitFrames)
do add(f)
end
end
add(_G.MSUF_PlayerCastbar)
add(_G.MSUF_TargetCastbar)
add(_G.MSUF_FocusCastbar)
add(_G.MSUF_PlayerCastbarPreview)
add(_G.MSUF_TargetCastbarPreview)
add(_G.MSUF_FocusCastbarPreview)
add(_G.MSUF_BossCastbar)
add(_G.MSUF_BossCastbarPreview) return frames end
local function MSUF_GetSavedMsufScale() local g=MSUF_EnsureGeneral()
if not g then return 1.0 end
local v=tonumber(g.msufUiScale)
if not v then v=tonumber(g.uiScale)
end
if not v then v=1.0 end
return clamp(v,0.25,1.5) end
local function MSUF_SetSavedMsufScale(v) local g=MSUF_EnsureGeneral()
if not g then return end
v=tonumber(v)
or 1.0 g.msufUiScale=clamp(v,0.25,1.5) end
local function MSUF_GetSavedSlashMenuScale() local g=MSUF_EnsureGeneral()
if not g then return 1.0 end
local v=tonumber(g.slashMenuScale)
if not v then v=1.0 end
return clamp(v,0.25,1.5) end
local function MSUF_SetSavedSlashMenuScale(v) local g=MSUF_EnsureGeneral()
if not g then return end
v=tonumber(v)
or 1.0 g.slashMenuScale=clamp(v,0.25,1.5) end
local function MSUF_ApplySlashMenuScale(scale,opts)
scale=tonumber(scale)
if not scale then return end
scale=clamp(scale,0.25,1.5)
local win=_G.MSUF_StandaloneOptionsWindow
if win and win.SetScale then pcall(win.SetScale,win,scale)
end
end
local _MSUF_pendingMsufScale;
local _MSUF_pendingGlobalScale;
local _MSUF_pendingDisableScaling;
local _MSUF_pendingReloadOnScalingOff;
local _MSUF_scaleApplyWatcher local MSUF_EnsureScaleApplyAfterCombat local MSUF_ResetGlobalUiScale local function MSUF_ApplyMsufScale(scale,opts)
scale=tonumber(scale)
if not scale then return end
scale=clamp(scale,0.25,1.5)
if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingMsufScale=scale if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
return end
local frames=MSUF_CollectMsufScaleFrames()
for i=1,#frames do local f=frames[i]
pcall(f.SetScale,f,scale)
end
end
local UI_SCALE_1080=768/1080;
local UI_SCALE_1440=768/1440;
local UI_SCALE_4K=768/2160;
local MSUF_DEFAULT_SLASH_MENU_W=900;
local MSUF_DEFAULT_SLASH_MENU_H=650;
local MSUF_DEFAULT_SLASH_MENU_POINT="CENTER";
local MSUF_DEFAULT_SLASH_MENU_RELPOINT="CENTER";
local MSUF_DEFAULT_SLASH_MENU_X=-60;
local MSUF_DEFAULT_SLASH_MENU_Y=10;
local function MSUF_SaveDefaultStandaloneGeometry(g)
if not g then return end
g.flashFullW=MSUF_DEFAULT_SLASH_MENU_W
g.flashFullH=MSUF_DEFAULT_SLASH_MENU_H
g.flashFullPoint=MSUF_DEFAULT_SLASH_MENU_POINT
g.flashFullRelPoint=MSUF_DEFAULT_SLASH_MENU_RELPOINT
g.flashFullX=MSUF_DEFAULT_SLASH_MENU_X
g.flashFullY=MSUF_DEFAULT_SLASH_MENU_Y
local s=(UIParent and UIParent.GetScale and UIParent:GetScale())
or 1 if not s or s==0 then s=1 end
g.flashFullXpx=MSUF_DEFAULT_SLASH_MENU_X*s
g.flashFullYpx=MSUF_DEFAULT_SLASH_MENU_Y*s
end
local function MSUF_ResetStandaloneWindowGeometry(frame,silent)
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
MSUF_SaveDefaultStandaloneGeometry(g)
local win=frame or _G.MSUF_StandaloneOptionsWindow
if win then
if win.SetScale then pcall(win.SetScale,win,1.0) end
if win.SetSize then pcall(win.SetSize,win,MSUF_DEFAULT_SLASH_MENU_W,MSUF_DEFAULT_SLASH_MENU_H) end
if win.ClearAllPoints then pcall(win.ClearAllPoints,win) end
if win.SetPoint then pcall(win.SetPoint,win,MSUF_DEFAULT_SLASH_MENU_POINT,UIParent,MSUF_DEFAULT_SLASH_MENU_RELPOINT,MSUF_DEFAULT_SLASH_MENU_X,MSUF_DEFAULT_SLASH_MENU_Y) end
end
if not silent then MSUF_Print("Slash Menu size reset to default.") end
end
local _MSUF_lastGlobalUiParentScale;
local _MSUF_blizzardUiParentScale;
local function MSUF_GetCurrentGlobalUiScale() if UIParent and UIParent.GetScale then return tonumber(UIParent:GetScale()) end
return nil end
local function MSUF_CaptureBlizzardUiScale()
if _MSUF_blizzardUiParentScale then return end
local cur=MSUF_GetCurrentGlobalUiScale()
if cur and cur>0 then _MSUF_blizzardUiParentScale=cur end
end
local function MSUF_GetBlizzardCVarScale()
local use=nil
if type(GetCVarBool)=="function"then local ok,v=pcall(GetCVarBool,"useUiScale") if ok then use=v end end
if use==nil and type(GetCVar)=="function"then local ok,v=pcall(GetCVar,"useUiScale") if ok then use=(tostring(v)=="1") end end
if use and type(GetCVar)=="function"then local ok,v=pcall(GetCVar,"uiScale") if ok then v=tonumber(v) if v and v>0 then return clamp(v,0.3,2.0) end end end
if type(GetPhysicalScreenSize)=="function"then local _,h=GetPhysicalScreenSize()
h=tonumber(h)
if h and h>0 then return clamp(768/h,0.3,2.0) end
end
if _MSUF_blizzardUiParentScale and _MSUF_blizzardUiParentScale>0 then return clamp(_MSUF_blizzardUiParentScale,0.3,2.0) end
return nil
end
local function MSUF_RestoreBlizzardUiScaleOnce()
if type(UIParent_UpdateScale)=="function"then local ok=pcall(UIParent_UpdateScale) if ok then return true end end
local scale=MSUF_GetBlizzardCVarScale()
if scale and UIParent and UIParent.SetScale then pcall(UIParent.SetScale,UIParent,scale) return true end
return false
end
local function MSUF_RestoreBlizzardUiScale(silent)
if InCombatLockdown and InCombatLockdown()
then if not silent then MSUF_Print("Cannot restore Blizzard UI scale in combat.")
end
return false end
MSUF_RestoreBlizzardUiScaleOnce()
if C_Timer and C_Timer.After then
C_Timer.After(0,function() MSUF_RestoreBlizzardUiScaleOnce() end)
C_Timer.After(0.25,function() MSUF_RestoreBlizzardUiScaleOnce() end)
C_Timer.After(1.0,function() MSUF_RestoreBlizzardUiScaleOnce() end)
end
_MSUF_lastGlobalUiParentScale=nil
if not silent then MSUF_Print("Global UI scale restored to Blizzard settings.") end
return true
end
local function MSUF_GetPixelPerfectScale() if type(GetPhysicalScreenSize)=="function"then local _,h=GetPhysicalScreenSize()
h=tonumber(h)
if h and h>0 then return clamp(768/h,0.3,2.0) end
end
return UI_SCALE_1440 end
local function MSUF_ResolveGlobalPresetScale(preset,scale) if preset=="1080p"then return UI_SCALE_1080 elseif preset=="1440p"then return UI_SCALE_1440 elseif preset=="4k"then return UI_SCALE_4K elseif preset=="pixel"then return MSUF_GetPixelPerfectScale() end
return tonumber(scale) end
local function MSUF_EnsureGlobalUiScaleTable(g) if not g then return nil end
local ui=(type(g.UIScale)=="table")and g.UIScale or nil
if not ui then ui={}
g.UIScale=ui
local preset=g.globalUiScalePreset
local scale=MSUF_ResolveGlobalPresetScale(preset,g.globalUiScaleValue) or 1.0
local enabled=(preset=="1080p"or preset=="1440p"or preset=="4k"or preset=="pixel"or preset=="custom")
ui.Enabled=enabled and true or false
ui.Scale=scale
ui._migratedFromGlobalPreset_v1=true
end
if ui.Enabled==nil then local preset=g.globalUiScalePreset
ui.Enabled=(preset=="1080p"or preset=="1440p"or preset=="4k"or preset=="pixel"or preset=="custom") end
ui.Enabled=(ui.Enabled==true)
ui.Scale=clamp(tonumber(ui.Scale)or MSUF_ResolveGlobalPresetScale(g.globalUiScalePreset,g.globalUiScaleValue)or 1.0,0.3,1.5)
g.disableScaling=false
return ui end
local function MSUF_SetGlobalUiScaleState(enabled,scale,preset) local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil if not g then return end
local ui=MSUF_EnsureGlobalUiScaleTable(g)
if not ui then return end
enabled=enabled and true or false
ui.Enabled=enabled
if scale~=nil then ui.Scale=clamp(tonumber(scale)or ui.Scale or 1.0,0.3,1.5) end
if enabled then g.globalUiScalePreset=preset or g.globalUiScalePreset or"custom"
g.globalUiScaleValue=ui.Scale else g.globalUiScalePreset=preset or"auto"
g.globalUiScaleValue=nil end
end
local function MSUF_WriteBlizzardUiScaleCVar(scale)
scale=tonumber(scale)
if not scale or scale<=0 then return false end
scale=clamp(scale,0.3,1.5)
local value=string.format("%.6f",scale)
local ok=false
if C_CVar and type(C_CVar.SetCVar)=="function"then
pcall(C_CVar.SetCVar,"useUiScale","1")
pcall(C_CVar.SetCVar,"uiScale",value)
ok=true
end
if type(SetCVar)=="function"then
pcall(SetCVar,"useUiScale","1")
pcall(SetCVar,"uiScale",value)
ok=true
end
return ok
end
local function MSUF_GetGlobalUiScaleHandoffValue(g,ui)
local cur=MSUF_GetCurrentGlobalUiScale()
cur=tonumber(cur)
if cur and cur>0 then return clamp(cur,0.3,1.5) end
if not ui and g then ui=MSUF_EnsureGlobalUiScaleTable(g) end
local saved=ui and tonumber(ui.Scale)
if saved and saved>0 then return clamp(saved,0.3,1.5) end
if _MSUF_lastGlobalUiParentScale and _MSUF_lastGlobalUiParentScale>0 then return clamp(_MSUF_lastGlobalUiParentScale,0.3,1.5) end
return 1.0
end
local function MSUF_HandOffGlobalUiScaleToBlizzard(scale)
scale=tonumber(scale)
if not scale or scale<=0 then return false end
scale=clamp(scale,0.3,1.5)
MSUF_WriteBlizzardUiScaleCVar(scale)
if type(UIParent_UpdateScale)=="function"then pcall(UIParent_UpdateScale) end
if UIParent and UIParent.SetScale then pcall(UIParent.SetScale,UIParent,scale) end
_MSUF_blizzardUiParentScale=scale
_MSUF_lastGlobalUiParentScale=nil
return true
end
local function MSUF_EnforceUIParentScale(scale) scale=tonumber(scale)
if not scale or scale<=0 then return end
scale=clamp(scale,0.3,1.5)
if not(UIParent and UIParent.SetScale)
then return end
local cur=nil if UIParent.GetScale then cur=tonumber(UIParent:GetScale())
end
cur=cur or 0 if math.abs(cur-scale)>0.001 then pcall(UIParent.SetScale,UIParent,scale)
end
_MSUF_lastGlobalUiParentScale=scale end
local function MSUF_ScheduleUIParentNudges(scale) end
local function MSUF_SetGlobalUiScale(scale,silent,opts) opts=opts or{}
scale=tonumber(scale)
if not scale or scale<=0 then return end
scale=clamp(scale,0.3,1.5)
if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingGlobalScale=scale if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
if not silent then MSUF_Print("Cannot change global UI scale in combat. Will apply after combat.")
end
return end
MSUF_EnforceUIParentScale(scale)
if not silent then MSUF_Print(string.format("Global UI scale set to %.4f",scale))
end
end
MSUF_EnsureScaleApplyAfterCombat=function() if _MSUF_scaleApplyWatcher then return end
if not CreateFrame then return end
local f=CreateFrame("Frame")
_MSUF_scaleApplyWatcher=f f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent",function() if InCombatLockdown and InCombatLockdown()
then return end
if _MSUF_pendingDisableScaling then _MSUF_pendingDisableScaling=nil;
_MSUF_pendingGlobalScale=nil;
MSUF_ResetGlobalUiScale(true)
else local s=_MSUF_pendingMsufScale;
local g=_MSUF_pendingGlobalScale;
_MSUF_pendingMsufScale=nil _MSUF_pendingGlobalScale=nil if s then MSUF_ApplyMsufScale(s)
end
if g then MSUF_SetGlobalUiScale(g,true)
end
end
if _MSUF_pendingReloadOnScalingOff then _MSUF_pendingReloadOnScalingOff=nil if type(ReloadUI)=="function"then ReloadUI();
 return end
end
if(not _MSUF_pendingDisableScaling)
and(not _MSUF_pendingMsufScale)
and(not _MSUF_pendingGlobalScale)
then f:UnregisterEvent("PLAYER_REGEN_ENABLED");
f:SetScript("OnEvent",nil)
_MSUF_scaleApplyWatcher=nil end
end
) end
MSUF_ResetGlobalUiScale=function(silent)
if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingDisableScaling=true _MSUF_pendingGlobalScale=nil if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
if not silent then MSUF_Print("Cannot disable global UI scale in combat. Will apply after combat.")
end
return false end
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
local ui=MSUF_EnsureGlobalUiScaleTable(g)
local handoff=MSUF_GetGlobalUiScaleHandoffValue(g,ui)
MSUF_HandOffGlobalUiScaleToBlizzard(handoff)
MSUF_SetGlobalUiScaleState(false,nil,"auto")
_MSUF_pendingGlobalScale=nil
if not silent then MSUF_Print(string.format("Global UI scale disabled. Blizzard UI scale kept at %d%%.",math.floor(handoff*100+0.5))) end
return true
end
local function MSUF_SetScalingDisabled(disable,silent)
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil if not g then return end
disable=disable and true or false
g.disableScaling=false
if not disable then _MSUF_pendingDisableScaling=nil return end
if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingDisableScaling=true if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
if not silent then MSUF_Print("Global UI scale will disable after combat. MSUF frame and menu scaling are unchanged.")
end
return end
MSUF_ResetGlobalUiScale(true)
_MSUF_pendingDisableScaling=nil _MSUF_pendingGlobalScale=nil if not silent then MSUF_Print("Global UI scale disabled. Blizzard keeps the current UI size.")
end
end
_G.MSUF_SetScalingDisabled=MSUF_SetScalingDisabled _G.MSUF_SetGlobalUiScale=MSUF_SetGlobalUiScale _G.MSUF_ResetGlobalUiScale=MSUF_ResetGlobalUiScale _G.MSUF_ResetStandaloneWindowGeometry=MSUF_ResetStandaloneWindowGeometry _G.MSUF_GetPixelPerfectScale=MSUF_GetPixelPerfectScale local function MSUF_SaveGlobalPreset(preset,scale) local g=MSUF_EnsureGeneral()
if not g then return end
if preset=="auto"then MSUF_SetGlobalUiScaleState(false,scale,"auto") return end
local resolved=MSUF_ResolveGlobalPresetScale(preset,scale) or scale or 1.0
MSUF_SetGlobalUiScaleState(true,resolved,preset or"custom") end
local function MSUF_GetDesiredGlobalScaleFromDB() local g=MSUF_EnsureGeneral()
if not g then return nil end
local ui=MSUF_EnsureGlobalUiScaleTable(g)
if ui and ui.Enabled then return tonumber(ui.Scale) end
return nil end
local MSUF_SCALE_GUARD={suppressUntil=0}
local function MSUF_EnsureGlobalUiScaleApplied(silent)
local want=MSUF_GetDesiredGlobalScaleFromDB()
want=tonumber(want)
if not want or want<=0 then return end
MSUF_SetGlobalUiScale(want,silent)
end
local function MSUF_IsMSUFEditModeActive() local st=_G.MSUF_EditState if type(st)=="table"and st.active~=nil then return st.active and true or false end
if _G and type(_G.MSUF_IsEditModeActive)=="function"then local ok,res=pcall(_G.MSUF_IsEditModeActive)
if ok then return res and true or false end
end
if _G.MSUF_EDITMODE_ACTIVE~=nil then return _G.MSUF_EDITMODE_ACTIVE and true or false end
return false end
local function MSUF_TryHookEditModeForDashboard() if _G.__MSUF_DashEditHooked then return end
if not hooksecurefunc then return end
if _G and type(_G.MSUF_SetMSUFEditModeDirect)=="function"then hooksecurefunc("MSUF_SetMSUFEditModeDirect",function(active) local win=_G.MSUF_StandaloneOptionsWindow;
local b=win and win._msufDashEditBtn if b and b._msufSetSelected then b:_msufSetSelected(active)
end
end
)
if _G then _G.__MSUF_DashEditHooked=true end
end
end
MSUF_BuildTools=function(parent,opts)
opts=opts or{}
if not parent then return {Refresh=function() end} end
local api=parent.__MSUF_ToolsApi
if api then
api.opts=opts
if api.Refresh then api.Refresh()
end
return api
end

api={opts=opts}
parent.__MSUF_ToolsApi=api

local isXL=opts.xl and true or false
local seg=opts.segmented and true or false
local segGap=seg and -1 or 8
local segW=seg and (isXL and 84 or 78) or 56
local segH=seg and 22 or 20

local titleText=opts.title or"Tools"
local title=UI_Text(parent,"GameFontNormal","TOPLEFT",parent,"TOPLEFT",6,-2,titleText,MSUF_SkinTitle)
local globalLabel=UI_Text(parent,"GameFontHighlight","TOPLEFT",title,"BOTTOMLEFT",0,-10,"Global UI Scale",MSUF_SkinText)
local globalCur=UI_Text(parent,"GameFontHighlightSmall","TOPLEFT",globalLabel,"BOTTOMLEFT",0,-6,"Current: ...",MSUF_SkinText)

local btn1080,btn1440,btn4k,btnPixel,btnAuto
local presetRow=MSUF_BuildButtonRow(parent,globalCur,"TOPLEFT","BOTTOMLEFT",0,-8,{
{text="1080",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 1080",tipBody="Applies the global UI scale preset for 1080p-like setups.",onClick=function()
MSUF_SaveGlobalPreset("1080p",UI_SCALE_1080)
MSUF_SetGlobalUiScale(UI_SCALE_1080,true)
if api.Refresh then api.Refresh() end
end},
{text="1440",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 1440",tipBody="Applies the global UI scale preset for 1440p-like setups.",onClick=function()
MSUF_SaveGlobalPreset("1440p",UI_SCALE_1440)
MSUF_SetGlobalUiScale(UI_SCALE_1440,true)
if api.Refresh then api.Refresh() end
end},
{text="4K",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 4K",tipBody="Applies the global UI scale preset for 4K (2160p) setups (0.3556).",onClick=function()
MSUF_SaveGlobalPreset("4k",UI_SCALE_4K)
MSUF_SetGlobalUiScale(UI_SCALE_4K,true)
if api.Refresh then api.Refresh() end
end},
{text="Pixel",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Pixel Perfect Scale",tipBody="Applies the pixel perfect UI scale for the current screen height (768 / screen height).",onClick=function()
local pixelScale=MSUF_GetPixelPerfectScale()
MSUF_SaveGlobalPreset("pixel",pixelScale)
MSUF_SetGlobalUiScale(pixelScale,true)
if api.Refresh then api.Refresh() end
end},
{text="Off",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: Off",tipBody="Disables MSUF global UI scale and hands the current visible size to Blizzard. MSUF frame and Slash Menu scale stay active.",onClick=function()
MSUF_SaveGlobalPreset("auto",nil)
MSUF_ResetGlobalUiScale(true)
if api.Refresh then api.Refresh() end
end},
},segGap)
btn1080,btn1440,btn4k,btnPixel,btnAuto=presetRow[1],presetRow[2],presetRow[3],presetRow[4],presetRow[5]

local resetW=120
local offW=180
local msufReset,msufOff
local row=MSUF_BuildButtonRow(parent,btn1080 or globalCur,"TOPLEFT","BOTTOMLEFT",0,-10,{
{text="Reset",w=resetW,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Reset UI Scale",tipBody="Resets the global UI scale back to 100% (1.0) and marks it as Custom preset.",onClick=function()
MSUF_SaveGlobalPreset("custom",1.0)
MSUF_SetGlobalUiScale(1.0,true)
if api.Refresh then api.Refresh()
end
end},
{text="UI Scale OFF",w=offW,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Disable Global UI Scale",tipBody="Turns off MSUF global UI scale and keeps the current visible UI size through Blizzard UI scale. MSUF Unitframe Scale and Slash Menu Scale stay active.",onClick=function()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
local ui=MSUF_EnsureGlobalUiScaleTable(g)
if ui and ui.Enabled then
MSUF_ResetGlobalUiScale(true)
else
local scale=ui and tonumber(ui.Scale) or 1.0
MSUF_SetGlobalUiScaleState(true,scale,"custom")
MSUF_SetGlobalUiScale(scale,true)
end
if api.Refresh then api.Refresh()
end
end},
},8)
msufReset,msufOff=row and row[1],row and row[2]

local function StyleToolsSlider(slider)
local UI=ns and ns.UI
local style=(_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
if type(style)=="function"then pcall(style,slider) return end
if C_Timer and C_Timer.After then C_Timer.After(0,function()
local UI2=ns and ns.UI
local later=(_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI2 and UI2.StyleSlider)
if type(later)=="function"then pcall(later,slider) end
end) end
end

-- MSUF-only (unitframes + castbars) scale slider
-- Align header with the slider track (same left inset as the sliders).
local msufScaleLabel=UI_Text(parent,"GameFontHighlight","TOPLEFT",(msufReset or (row and row[1]) or (btn1080 or globalCur)),"BOTTOMLEFT",10,-12,"MSUF Unitframe Scale",MSUF_SkinText)
local msufScaleCur=UI_Text(parent,"GameFontHighlightSmall","TOPLEFT",msufScaleLabel,"BOTTOMLEFT",0,-6,"Current: ...",MSUF_SkinText)
local msufScaleSlider=CreateFrame("Slider","MSUF_Tools_MsufScaleSlider",parent,"OptionsSliderTemplate")
msufScaleSlider:ClearAllPoints()
-- Anchor within the box so the thumb never clips.
msufScaleSlider:SetPoint("TOP",msufScaleCur,"BOTTOM",0,-8)
msufScaleSlider:SetPoint("LEFT",parent,"LEFT",16,0)
msufScaleSlider:SetPoint("RIGHT",parent,"RIGHT",-28,0)
msufScaleSlider:SetMinMaxValues(25,150)
msufScaleSlider:SetValueStep(5)
msufScaleSlider:SetObeyStepOnDrag(true)
if msufScaleSlider.SetStepsPerPage then msufScaleSlider:SetStepsPerPage(1) end

do
local n=(msufScaleSlider.GetName and msufScaleSlider:GetName())
local t=(n and _G[n.."Text"]) or msufScaleSlider.Text
if t then t:SetText(""); t:Hide() end
local low=(n and _G[n.."Low"]) or msufScaleSlider.Low
if low then low:SetText(""); low:Hide() end
local high=(n and _G[n.."High"]) or msufScaleSlider.High
if high then high:SetText(""); high:Hide() end
end
StyleToolsSlider(msufScaleSlider)

local function MSUF_UpdateMsufScaleRow(scale)
scale=tonumber(scale) or 1.0
scale=clamp(scale,0.25,1.5)
local pct=math.floor(scale*100+0.5)
if msufScaleCur and msufScaleCur.SetText then msufScaleCur:SetText(string.format("Current: %.2f (%d%%)",scale,pct)) end
end

local function MSUF_SnapMsufScalePct(pct)
pct=tonumber(pct) or 100
pct=math.floor((pct/5)+0.5)*5
if pct<25 then pct=25 elseif pct>150 then pct=150 end
return pct
end

msufScaleSlider:EnableMouseWheel(true)
msufScaleSlider:SetScript("OnMouseWheel",function(self,delta)
if not delta then return end
local v=tonumber((self.GetValue and self:GetValue()) or 100) or 100
v=v+(delta>0 and 5 or -5)
self:SetValue(MSUF_SnapMsufScalePct(v))
end)

msufScaleSlider:SetScript("OnValueChanged",function(self,value)
if self.__msufSkip then return end
local pct=MSUF_SnapMsufScalePct(value)
if pct~=value then self.__msufSkip=true; self:SetValue(pct); self.__msufSkip=nil; return end
local scale=pct/100
MSUF_SetSavedMsufScale(scale)
MSUF_ApplyMsufScale(scale)
MSUF_UpdateMsufScaleRow(scale)
end)

if MSUF_AddTooltip then pcall(MSUF_AddTooltip,msufScaleSlider,"MSUF Unitframe Scale","TIP: Hover this slider and use the Mouse Wheel to change the scale in 5% steps.\n\nScales only MSUF frames (unitframes + castbars). Range 25%–150% (0.25–1.50). Drag or click to adjust. Applied immediately; in combat it applies after combat.") end

-- Slash menu scale (explicit Apply workflow for cleaner UX)
local menuScaleLabel=UI_Text(parent,"GameFontHighlight","TOPLEFT",msufScaleSlider,"BOTTOMLEFT",0,-18,"MSUF Slash Menu Scale",MSUF_SkinText)
local menuScaleCur=UI_Text(parent,"GameFontHighlightSmall","TOPLEFT",menuScaleLabel,"BOTTOMLEFT",0,-6,"Applied: ...",MSUF_SkinText)
local menuScalePending=UI_Text(parent,"GameFontHighlightSmall","TOPLEFT",menuScaleCur,"BOTTOMLEFT",0,-4,"Selected: ...",MSUF_SkinText)
local menuScaleSlider=CreateFrame("Slider","MSUF_Tools_SlashMenuScaleSlider",parent,"OptionsSliderTemplate")
menuScaleSlider:ClearAllPoints()
menuScaleSlider:SetPoint("TOP",menuScalePending,"BOTTOM",0,-8)
menuScaleSlider:SetPoint("LEFT",parent,"LEFT",16,0)
menuScaleSlider:SetPoint("RIGHT",parent,"RIGHT",-28,0)
menuScaleSlider:SetMinMaxValues(25,150)
menuScaleSlider:SetValueStep(5)
menuScaleSlider:SetObeyStepOnDrag(true)
if menuScaleSlider.SetStepsPerPage then menuScaleSlider:SetStepsPerPage(1) end

do
local n=(menuScaleSlider.GetName and menuScaleSlider:GetName())
local t=(n and _G[n.."Text"]) or menuScaleSlider.Text
if t then t:SetText(""); t:Hide() end
local low=(n and _G[n.."Low"]) or menuScaleSlider.Low
if low then low:SetText(""); low:Hide() end
local high=(n and _G[n.."High"]) or menuScaleSlider.High
if high then high:SetText(""); high:Hide() end
end
StyleToolsSlider(menuScaleSlider)

local menuScaleApply,menuScaleRevert
local function MSUF_GetPendingSlashMenuScale()
local pending=(api and api.pendingSlashMenuScale)
if pending==nil then pending=MSUF_GetSavedSlashMenuScale() end
pending=tonumber(pending) or 1.0
return clamp(pending,0.25,1.5)
end
local function MSUF_UpdateSlashMenuScaleRow(applied,pending)
applied=clamp(tonumber(applied) or 1.0,0.25,1.5)
pending=clamp(tonumber(pending) or applied,0.25,1.5)
local appliedPct=math.floor(applied*100+0.5)
local pendingPct=math.floor(pending*100+0.5)
local changed=math.abs(applied-pending)>0.001
if menuScaleCur and menuScaleCur.SetText then menuScaleCur:SetText(string.format("Applied: %.2f (%d%%)",applied,appliedPct)) end
if menuScalePending and menuScalePending.SetText then
if changed then menuScalePending:SetText(string.format("Selected: %.2f (%d%%)  |cffffd200Press Apply|r",pending,pendingPct))
else menuScalePending:SetText(string.format("Selected: %.2f (%d%%)",pending,pendingPct)) end
end
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
local disabled=false
if menuScaleApply then
MSUF_SetEnabled(menuScaleApply,(not disabled) and changed)
if menuScaleApply._msufSetSelected then menuScaleApply:_msufSetSelected((not disabled) and changed) end
end
if menuScaleRevert then MSUF_SetEnabled(menuScaleRevert,(not disabled) and changed) end
end

menuScaleSlider:EnableMouseWheel(true)
menuScaleSlider:SetScript("OnMouseWheel",function(self,delta)
if not delta then return end
local v=tonumber((self.GetValue and self:GetValue()) or 100) or 100
v=v+(delta>0 and 5 or -5)
self:SetValue(MSUF_SnapMsufScalePct(v))
end)

menuScaleSlider:SetScript("OnValueChanged",function(self,value)
if self.__msufSkip then return end
local pct=MSUF_SnapMsufScalePct(value)
if pct~=value then self.__msufSkip=true; self:SetValue(pct); self.__msufSkip=nil; return end
local scale=pct/100
api.pendingSlashMenuScale=scale
MSUF_UpdateSlashMenuScaleRow(MSUF_GetSavedSlashMenuScale(),scale)
end)

local menuScaleRow=MSUF_BuildButtonRow(parent,menuScaleSlider,"TOPLEFT","BOTTOMLEFT",0,-10,{
{text="Apply",w=104,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Apply Slash Menu Scale",tipBody="Applies the selected scale to the standalone MSUF Slash Menu window.",onClick=function()
local scale=MSUF_GetPendingSlashMenuScale()
MSUF_SetSavedSlashMenuScale(scale)
MSUF_ApplySlashMenuScale(scale,{ignoreDisable=true})
api.pendingSlashMenuScale=nil
if api.Refresh then api.Refresh() else MSUF_UpdateSlashMenuScaleRow(scale,scale) end
end},
{text="Revert",w=104,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Revert Selection",tipBody="Restores the slider to the currently applied Slash Menu scale without changing anything live.",onClick=function()
api.pendingSlashMenuScale=nil
local sms=clamp(MSUF_GetSavedSlashMenuScale(),0.25,1.5)
local smPct=MSUF_SnapMsufScalePct(sms*100)
if menuScaleSlider and menuScaleSlider.SetValue then menuScaleSlider.__msufSkip=true; menuScaleSlider:SetValue(smPct); menuScaleSlider.__msufSkip=nil end
MSUF_UpdateSlashMenuScaleRow(sms,sms)
end},
},8)
menuScaleApply,menuScaleRevert=menuScaleRow and menuScaleRow[1],menuScaleRow and menuScaleRow[2]

if MSUF_AddTooltip then pcall(MSUF_AddTooltip,menuScaleSlider,"MSUF Slash Menu Scale","TIP: Hover this slider and use the Mouse Wheel to change the scale in 5% steps.\n\nScales only the MSUF Slash Menu window. Range 25%–150% (0.25–1.50). Drag or click to choose a value, then press Apply.") end

api.ui={title=title,globalCur=globalCur,btn1080=btn1080,btn1440=btn1440,btn4k=btn4k,btnPixel=btnPixel,btnAuto=btnAuto,msufReset=msufReset,msufOff=msufOff,msufScaleLabel=msufScaleLabel,msufScaleCur=msufScaleCur,msufScaleSlider=msufScaleSlider,menuScaleLabel=menuScaleLabel,menuScaleCur=menuScaleCur,menuScalePending=menuScalePending,menuScaleSlider=menuScaleSlider,menuScaleApply=menuScaleApply,menuScaleRevert=menuScaleRevert,}

function api.UpdateEnabledStates()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
MSUF_SetEnabled(btn1080,true)
MSUF_SetEnabled(btn1440,true)
MSUF_SetEnabled(btn4k,true)
MSUF_SetEnabled(btnPixel,true)
MSUF_SetEnabled(btnAuto,true)
MSUF_SetEnabled(msufReset,true)
MSUF_SetEnabled(msufScaleSlider,true)
MSUF_SetEnabled(menuScaleSlider,true)
MSUF_SetEnabled(menuScaleApply,true)
MSUF_SetEnabled(menuScaleRevert,true)
if msufScaleLabel and msufScaleLabel.SetAlpha then msufScaleLabel:SetAlpha(1.0) end
if msufScaleCur and msufScaleCur.SetAlpha then msufScaleCur:SetAlpha(1.0) end
if menuScaleLabel and menuScaleLabel.SetAlpha then menuScaleLabel:SetAlpha(1.0) end
if menuScaleCur and menuScaleCur.SetAlpha then menuScaleCur:SetAlpha(1.0) end
if menuScalePending and menuScalePending.SetAlpha then menuScalePending:SetAlpha(1.0) end
return false
end

function api.Layout()
local pw=(parent.GetWidth and parent:GetWidth())
or 0
if not pw or pw<=1 then return end
local avail=pw-20
local gap=segGap
if gap==nil then gap=8 end
local n=5
local totalGap=(n-1)*gap
local wEach=math.floor((avail-totalGap)/n)
if wEach<1 then wEach=1 end
if btn1080 and btn1080.SetWidth then btn1080:SetWidth(wEach)
end
if btn1440 and btn1440.SetWidth then btn1440:SetWidth(wEach)
end
if btn4k and btn4k.SetWidth then btn4k:SetWidth(wEach)
end
if btnPixel and btnPixel.SetWidth then btnPixel:SetWidth(wEach)
end
if btnAuto and btnAuto.SetWidth then btnAuto:SetWidth(wEach)
end
if msufOff and msufOff.SetWidth and msufReset and msufReset.GetWidth then
local rw=msufReset:GetWidth()
or resetW
local ow=avail-rw-8
if ow<90 then ow=90 end
if ow>260 then ow=260 end
msufOff:SetWidth(ow)
end
end

function api.Refresh()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
local ui=MSUF_EnsureGlobalUiScaleTable(g)
local preset=g and g.globalUiScalePreset
local globalOff=not(ui and ui.Enabled)
local disabled=false
if api.UpdateEnabledStates then api.UpdateEnabledStates()
end
local cur=MSUF_GetCurrentGlobalUiScale()
if globalCur and globalCur.SetText then local txt=cur and string.format("Current: %.4f",cur) or"Current: ..."
if globalOff then txt=txt.." (Off)" elseif preset=="auto"or preset==nil then txt=txt.." (Custom)" end
globalCur:SetText(txt) end
local ms=clamp(MSUF_GetSavedMsufScale(),0.25,1.5)
local pct=MSUF_SnapMsufScalePct(ms*100)
local scale=pct/100
MSUF_UpdateMsufScaleRow(scale)
if msufScaleSlider and msufScaleSlider.SetValue then msufScaleSlider.__msufSkip=true; msufScaleSlider:SetValue(pct); msufScaleSlider.__msufSkip=nil end
if math.abs(ms-scale)>0.001 then MSUF_SetSavedMsufScale(scale); MSUF_ApplyMsufScale(scale) end

-- Slash menu scale: show applied value + separate pending selection
local sms=clamp(MSUF_GetSavedSlashMenuScale(),0.25,1.5)
local smPct=MSUF_SnapMsufScalePct(sms*100)
local smScale=smPct/100
local pendingScale=api.pendingSlashMenuScale
if pendingScale==nil then pendingScale=smScale end
pendingScale=clamp(tonumber(pendingScale) or smScale,0.25,1.5)
local pendingPct=MSUF_SnapMsufScalePct(pendingScale*100)
pendingScale=pendingPct/100
MSUF_UpdateSlashMenuScaleRow(smScale,pendingScale)
if menuScaleSlider and menuScaleSlider.SetValue then menuScaleSlider.__msufSkip=true; menuScaleSlider:SetValue(pendingPct); menuScaleSlider.__msufSkip=nil end
if math.abs(sms-smScale)>0.001 then MSUF_SetSavedSlashMenuScale(smScale) end
MSUF_ApplySlashMenuScale(smScale,{ignoreDisable=true})

if btn1080 and btn1080._msufSetSelected then btn1080:_msufSetSelected(preset=="1080p")
end
if btn1440 and btn1440._msufSetSelected then btn1440:_msufSetSelected(preset=="1440p")
end
if btn4k and btn4k._msufSetSelected then btn4k:_msufSetSelected(preset=="4k")
end
if btnPixel and btnPixel._msufSetSelected then btnPixel:_msufSetSelected(preset=="pixel")
end
if btnAuto and btnAuto._msufSetSelected then btnAuto:_msufSetSelected(globalOff or (preset=="auto")
or(preset==nil))
end

if MSUF_SetScalingToggleVisual then MSUF_SetScalingToggleVisual(globalOff and true or false)
end
if msufOff and msufOff._msufSetSelected then msufOff:_msufSetSelected(globalOff and true or false)
end
if msufOff and msufOff.SetText then msufOff:SetText(globalOff and "UI Scale ON" or "UI Scale OFF") end
api.Layout()
end

if not parent.__MSUF_ToolsLayoutHooked then
parent.__MSUF_ToolsLayoutHooked=true
parent:HookScript("OnShow",function() if C_Timer and C_Timer.After then C_Timer.After(0,api.Layout)
else api.Layout()
end end)
parent:HookScript("OnSizeChanged",function() if C_Timer and C_Timer.After then C_Timer.After(0,api.Layout)
else api.Layout()
end end)
end

api.Refresh()
return api
end
local function MSUF_ShowHideForLazy(panel,builtKey) if not panel then return end
if panel.__MSUF_LazyBuildHooked and builtKey and not panel[builtKey]
then panel:Show()
panel:Hide()
end
end
local function MSUF_EnsureMainOptionsPanelBuilt() MSUF_SafeCall(EnsureDB)
MSUF_SafeCall(_G.MSUF_RegisterOptionsCategoryLazy)
MSUF_SafeCall(_G.CreateOptionsPanel)
local p=_G.MSUF_OptionsPanel if not p then return nil end
MSUF_ShowHideForLazy(p,"__MSUF_FullBuilt") return p end
local function MSUF_GetMainSettingsCategory() return (_G.MSUF_SettingsCategory)
or(ns and ns.MSUF_MainCategory) end
local function MSUF_EnsureMainSettingsCategory() local cat=MSUF_GetMainSettingsCategory()
if not cat then MSUF_SafeCall(_G.MSUF_RegisterOptionsCategoryLazy)
cat=MSUF_GetMainSettingsCategory()
end
return cat end
local SETTINGS_PANEL_DEFS={colors={full="MSUF_RegisterColorsOptions_Full",fallback="MSUF_RegisterColorsOptions",globals={"MSUF_ColorsPanel","MSUF_ColorsOptionsPanel"},builtKey="__MSUF_ColorsBuilt",},auras2={full="MSUF_RegisterAurasOptions_Full",fallback="MSUF_RegisterAurasOptions",globals={"MSUF_AurasPanel","MSUF_AurasOptionsPanel"},builtKey="__MSUF_AurasBuilt",},gameplay={full="MSUF_RegisterGameplayOptions_Full",fallback="MSUF_RegisterGameplayOptions",globals={"MSUF_GameplayPanel","MSUF_GameplayOptionsPanel"},builtKey="__MSUF_GameplayBuilt",},portraits={full="MSUF_RegisterPortraitsOptions_Full",fallback="MSUF_RegisterPortraitsOptions",globals={"MSUF_PortraitsPanel"},builtKey="__MSUF_PortraitsBuilt",},}
local function MSUF_FindFirstGlobal(nameList) if not _G or type(nameList)~="table"then return nil end
for i=1,#nameList do local k=nameList[i];
local obj=_G[k]
if obj then return obj end
end
return nil end
local function MSUF_EnsureSubOptionsPanelBuilt(kind) local def=SETTINGS_PANEL_DEFS[kind]
if not def then return nil end
local cat=MSUF_EnsureMainSettingsCategory()
if not cat then return nil end
if ns then local fn=ns[def.full]
if type(fn)=="function"then pcall(fn,cat)
else fn=ns[def.fallback]
if type(fn)=="function"then pcall(fn,cat)
end
end
end
local p=MSUF_FindFirstGlobal(def.globals)
MSUF_ShowHideForLazy(p,def.builtKey) return p end
local function MSUF_EnsureColorsPanelBuilt() return MSUF_EnsureSubOptionsPanelBuilt("colors") end
local function MSUF_EnsureAuras2PanelBuilt() return MSUF_EnsureSubOptionsPanelBuilt("auras2") end
local function MSUF_EnsureGameplayPanelBuilt() return MSUF_EnsureSubOptionsPanelBuilt("gameplay") end
local function MSUF_EnsurePortraitsPanelBuilt() return MSUF_EnsureSubOptionsPanelBuilt("portraits") end
local function MSUF_EnsureModulesPanelBuilt() if _G.MSUF_ModulesMirrorPanel and _G.MSUF_ModulesMirrorPanel.__MSUF_ModulesBuilt then return _G.MSUF_ModulesMirrorPanel end
local p=CreateFrame("Frame","MSUF_ModulesMirrorPanel",UIParent)
_G.MSUF_ModulesMirrorPanel=p p.__MSUF_ModulesBuilt=true p.__MSUF_MirrorNoRestoreShow=true p:SetPoint("TOPLEFT",0,0)
p:SetPoint("BOTTOMRIGHT",0,0)
if p.Hide then p:Hide()
end
local title=p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
title:SetPoint("TOPLEFT",12,-12)
title:SetText("Modules")
local sub=p:CreateFontString(nil,"OVERLAY","GameFontNormal")
sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-6)
sub:SetText("Optional MSUF modules and UI styling (MSUF only).")
if type(_G.MSUF_ApplyMidnightBackdrop)=="function"then pcall(_G.MSUF_ApplyMidnightBackdrop,p,0.96)
end
if type(_G.MSUF_SkinTitle)=="function"then pcall(_G.MSUF_SkinTitle,title)
end
if type(_G.MSUF_SkinMuted)=="function"then pcall(_G.MSUF_SkinMuted,sub)
end
local cb=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
cb:SetPoint("TOPLEFT",sub,"BOTTOMLEFT",0,-14)
if cb.Text then cb.Text:SetText("Enable MSUF Style")
if type(_G.MSUF_SkinText)=="function"then pcall(_G.MSUF_SkinText,cb.Text)
end
end
local note=p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
note:SetPoint("TOPLEFT",cb,"BOTTOMLEFT",28,-6)
note:SetText("Disabling may require /reload to fully remove existing styling.")
if type(_G.MSUF_SkinMuted)=="function"then pcall(_G.MSUF_SkinMuted,note)
end
local function GetEnabled() if type(_G.MSUF_StyleIsEnabled)=="function"then local ok,v=pcall(_G.MSUF_StyleIsEnabled)
if ok then return v and true or false end
end
if _G.MSUF_DB and _G.MSUF_DB.general then return _G.MSUF_DB.general.styleEnabled~=false end
return true end
local function SetEnabled(v) if type(_G.MSUF_SetStyleEnabled)=="function"then pcall(_G.MSUF_SetStyleEnabled,v and true or false)
else if _G.MSUF_DB and _G.MSUF_DB.general then _G.MSUF_DB.general.styleEnabled=v and true or false end
end
end
cb:SetScript("OnShow",function() cb:SetChecked(GetEnabled()) end
)
cb:SetScript("OnClick",function(self) SetEnabled(self:GetChecked()) end
)
local rb=CreateFrame("CheckButton",nil,p,"UICheckButtonTemplate")
rb:SetPoint("TOPLEFT",note,"BOTTOMLEFT",-28,-12)
if rb.Text then rb.Text:SetText("Rounded unitframes")
if type(_G.MSUF_SkinText)=="function"then pcall(_G.MSUF_SkinText,rb.Text)
end
end
rb.tooltipText="Round MSUF unitframes by masking HP/Power/Absorb bars and backgrounds with the superellipse mask."local function GetRoundedEnabled() if _G.MSUF_DB and _G.MSUF_DB.general then return _G.MSUF_DB.general.roundedUnitframes==true end
return false end
local function SetRoundedEnabled(v) if _G.MSUF_DB and _G.MSUF_DB.general then _G.MSUF_DB.general.roundedUnitframes=v and true or false end
if type(_G.MSUF_ApplyModules)=="function"then pcall(_G.MSUF_ApplyModules)
end
end
rb:SetScript("OnShow",function() rb:SetChecked(GetRoundedEnabled()) end
)
rb:SetScript("OnClick",function(self) SetRoundedEnabled(self:GetChecked()) end
) return p end
local function MSUF_SelectMainOptionsKey(key) local p=_G.MSUF_OptionsPanel if not p then return end
if type(MSUF_GetTabButtonHelpers)~="function"then return end
local _,setKey=MSUF_GetTabButtonHelpers(p)
if type(setKey)=="function"then setKey(key)
if p.LoadFromDB then pcall(p.LoadFromDB,p)
end
end
end
local function MSUF_ScrollBarsToAnchor(anchorFrame)
    local scroll = _G.MSUF_BarsMenuScrollFrame
    local child  = _G.MSUF_BarsMenuScrollChild
    if not (scroll and child and anchorFrame and anchorFrame.GetTop and child.GetTop) then return end
    local top = child:GetTop()
    local aTop = anchorFrame:GetTop()
    if not (top and aTop) then return end
    local off = (top - aTop) - 12
    if off < 0 then off = 0 end
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(off) end
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    if _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
end
local function MSUF_SelectClassResourcesPage()
    -- Dedicated "Class Resources" tab (no Bars content).
    MSUF_SelectMainOptionsKey("classpower")
    if type(_G.MSUF_EnsureClassPowerMenuBuilt) == "function" then
        pcall(_G.MSUF_EnsureClassPowerMenuBuilt)
    end
end
local function MSUF_SelectCastbarSubPage(unitKey) if type(_G.MSUF_SetActiveCastbarSubPage)=="function"then pcall(_G.MSUF_SetActiveCastbarSubPage,unitKey)
elseif type(MSUF_SetActiveCastbarSubPage)=="function"then pcall(MSUF_SetActiveCastbarSubPage,unitKey)
end
local p=_G.MSUF_OptionsPanel if p and p.LoadFromDB then pcall(p.LoadFromDB,p)
end
end
local function MSUF_MirrorSelectMain(subkey) if not subkey then return end
if type(subkey)=="table"then local tab=subkey.tab or subkey.key or subkey.page;
if tab then MSUF_SelectMainOptionsKey(tab)
end
local castSub=subkey.castbarSub or subkey.castbar or subkey.sub;
if tab=="castbar"and castSub then MSUF_SelectCastbarSubPage(castSub)
end
elseif type(subkey)=="string"then MSUF_SelectMainOptionsKey(subkey)
end
end
-- === Page Registry (MIRROR_PAGES) ===

local MIRROR_PAGES={home={title="Midnight Simple Unitframes (Version 1.9b3)",nav="Dashboard",build=nil},main={title="MSUF Options",nav="Options",build=MSUF_EnsureMainOptionsPanelBuilt,select=MSUF_MirrorSelectMain},uf_player={title="MSUF Player",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("player") end
},uf_target={title="MSUF Target",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("target") end
},uf_targettarget={title="MSUF Target of Target",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("targettarget") end
},uf_focus={title="MSUF Focus",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("focus") end
},uf_boss={title="MSUF Boss Frames",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("boss") end
},uf_pet={title="MSUF Pet",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("pet") end
},opt_bars={title="MSUF Bars",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("bars") end
},opt_fonts={title="MSUF Fonts",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("fonts") end
},opt_auras={title="MSUF Auras",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("auras") end
},auras2={title="MSUF Unit Auras",build=MSUF_EnsureAuras2PanelBuilt},opt_castbar={title="MSUF Castbar",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("castbar") end
},opt_misc={title="MSUF Miscellaneous",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("misc") end
},opt_colors={title="MSUF Colors",build=MSUF_EnsureColorsPanelBuilt},castbar={title="MSUF Castbar",build=MSUF_EnsureMainOptionsPanelBuilt,select=function(subkey) MSUF_SelectMainOptionsKey("castbar");
if subkey and subkey~=""then MSUF_SelectCastbarSubPage(subkey)
end
end
},profiles={title="MSUF Profiles",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("profiles") end
},colors={title="MSUF Colors",build=MSUF_EnsureColorsPanelBuilt},portraits={title="MSUF Portraits",build=MSUF_EnsurePortraitsPanelBuilt},opt_portraits={title="MSUF Portraits",build=MSUF_EnsurePortraitsPanelBuilt},classpower={title="MSUF Class Resources",build=MSUF_EnsureMainOptionsPanelBuilt,select=MSUF_SelectClassResourcesPage},gameplay={title="MSUF Gameplay",build=MSUF_EnsureGameplayPanelBuilt},modules={title="MSUF Modules",build=MSUF_EnsureModulesPanelBuilt},groupframes={title="MSUF Group Frames",build=function() local fn=_G.MSUF_EnsureGFPanelBuilt; if type(fn)=="function" then return fn() end end,select=function(sub) if sub and _G.MSUF_GF_SwitchTab then _G.MSUF_GF_SwitchTab(sub) end end},gf_layout={title="MSUF Group Frames",build=function() local fn=_G.MSUF_EnsureGFPanelBuilt; if type(fn)=="function" then return fn() end end,select=function() if _G.MSUF_GF_SwitchTab then _G.MSUF_GF_SwitchTab("frame") end end},gf_bars={title="MSUF Group Frames",build=function() local fn=_G.MSUF_EnsureGFPanelBuilt; if type(fn)=="function" then return fn() end end,select=function() if _G.MSUF_GF_SwitchTab then _G.MSUF_GF_SwitchTab("health") end end},gf_auras={title="MSUF Group Frames",build=function() local fn=_G.MSUF_EnsureGFPanelBuilt; if type(fn)=="function" then return fn() end end,select=function() if _G.MSUF_GF_SwitchTab then _G.MSUF_GF_SwitchTab("auras") end end},gf_indicators={title="MSUF Group Frames",build=function() local fn=_G.MSUF_EnsureGFPanelBuilt; if type(fn)=="function" then return fn() end end,select=function() if _G.MSUF_GF_SwitchTab then _G.MSUF_GF_SwitchTab("indicators") end end},
-- Search results virtual page (panel built lazily by MSUF_Search.lua)
search={title="Search Results",nav="Search",build=function()
    local fn=ns and ns.MSUF_Search_EnsurePanel
    if type(fn)=="function" then return fn() end
    return nil
end},}
local function MSUF_GetMirrorPageInfo(key) return MIRROR_PAGES and key and MIRROR_PAGES[key]
or nil end
local function MSUF_NormalizeMirrorKey(key,allowHome) key=key or(allowHome and"home"or"main")
if allowHome and key=="home"then return"home"end
local info=MSUF_GetMirrorPageInfo(key)
if info and key~="home"then return key end
return allowHome and"home"or"main" end
local function MSUF_GetPanelForKey(key) key=MSUF_NormalizeMirrorKey(key,false)
local info=MSUF_GetMirrorPageInfo(key)
or MSUF_GetMirrorPageInfo("main");
local builder=info and info.build if type(builder)=="function"then return builder() end
return nil end
local MSUF_MirrorSetHeaderHidden local function MSUF_DetachMirroredPanel(panel) if not panel or not panel.__MSUF_MirrorActive then return end
MSUF_MirrorSetHeaderHidden(panel,false)
if panel.__MSUF_MirrorState then MSUF_RestorePanelState(panel,panel.__MSUF_MirrorState)
end
local orig=panel.__MSUF_MirrorOrig if orig then if panel.Hide then pcall(panel.Hide,panel)
end
if panel.SetScale and orig.scale then pcall(panel.SetScale,panel,orig.scale)
end
if panel.SetFrameStrata and orig.strata then pcall(panel.SetFrameStrata,panel,orig.strata)
end
if panel.SetFrameLevel and orig.level then pcall(panel.SetFrameLevel,panel,orig.level)
end
if panel.SetParent and orig.parent then pcall(panel.SetParent,panel,orig.parent)
end
if panel.ClearAllPoints then pcall(panel.ClearAllPoints,panel)
end
if panel.SetPoint and orig.points and#orig.points>0 then for i=1,#orig.points do local pt=orig.points[i]
if pt and pt[1]
then pcall(panel.SetPoint,panel,pt[1],pt[2],pt[3],pt[4],pt[5])
end
end
end
if orig.shown and not panel.__MSUF_MirrorNoRestoreShow and panel.Show then pcall(panel.Show,panel)
end
else if panel.Hide then pcall(panel.Hide,panel)
end
end
panel.__MSUF_MirrorActive=nil panel.__MSUF_MirrorState=nil end
MSUF_MirrorSetHeaderHidden=function(panel,hidden) if not panel then return end
if hidden then if panel.__MSUF_MirrorHiddenHeader then return end
panel.__MSUF_MirrorHiddenHeader={}
local targets=panel.__MSUF_MirrorHeaderTargets if type(targets)=="table"and#targets>0 then for i=1,#targets do local r=targets[i]
if r then panel.__MSUF_MirrorHiddenHeader[r]=(r.IsShown and r:IsShown())
and 1 or 0 if r.Hide then r:Hide()
end
end
end
return end
if type(targets)~="table"then targets={}
panel.__MSUF_MirrorHeaderTargets=targets end
if panel.__MSUF_MirrorHeaderScanToken then panel.__MSUF_MirrorHeaderScanToken=nil panel.__MSUF_MirrorHeaderScanState=nil end
local function IsHeaderText(t) if type(t)~="string"or t==""then return false end
local tl=string.lower(t)
return string.find(tl,"midnight simple unit frames",1,true)
or string.find(tl,"beta version",1,true)
or string.find(tl,"early version",1,true)
or string.find(tl,"thank you for using",1,true) end
local function ScanChunk() if not panel.__MSUF_MirrorHiddenHeader then panel.__MSUF_MirrorHeaderScanToken=nil panel.__MSUF_MirrorHeaderScanState=nil return end
local token=panel.__MSUF_MirrorHeaderScanToken if not token then return end
local st=panel.__MSUF_MirrorHeaderScanState if type(st)~="table"then st={stack={panel},sp=1,nodes=0,maxNodes=450,}
panel.__MSUF_MirrorHeaderScanState=st end
local debugprofilestop=debugprofilestop;
local t0=debugprofilestop and debugprofilestop()
or nil;
local budgetMs=1.0;
local stack=st.stack;
local sp=st.sp or 0 local nodes=st.nodes or 0;
local maxNodes=st.maxNodes or 450 while sp>0 do if t0 and(debugprofilestop()-t0)>=budgetMs then break end
local frame=stack[sp]
stack[sp]=nil sp=sp-1 if frame then nodes=nodes+1 if nodes>maxNodes then break end
if frame.GetRegions then local regions={frame:GetRegions()}
for i=1,#regions do local r=regions[i]
if r and r.GetObjectType and r:GetObjectType()=="FontString"and r.GetText then local t=r:GetText()
if IsHeaderText(t)
then panel.__MSUF_MirrorHiddenHeader[r]=(r.IsShown and r:IsShown())
and 1 or 0 if r.Hide then r:Hide()
end
targets[#targets+1]=r if#targets>=6 then nodes=maxNodes+1 break end
end
end
end
end
if frame.GetChildren then local children={frame:GetChildren()}
for i=1,#children do local c=children[i]
if c then sp=sp+1 stack[sp]=c end
end
end
end
end
st.sp=sp st.nodes=nodes if sp>0 and nodes<=maxNodes and panel.__MSUF_MirrorHiddenHeader and panel.__MSUF_MirrorHeaderScanToken==token then if C_Timer and C_Timer.After then C_Timer.After(0,ScanChunk)
end
return end
panel.__MSUF_MirrorHeaderScanToken=nil panel.__MSUF_MirrorHeaderScanState=nil end
panel.__MSUF_MirrorHeaderScanToken=tostring(GetTime and GetTime()
or math.random())
if C_Timer and C_Timer.After then C_Timer.After(0,ScanChunk)
else ScanChunk()
end
else local st=panel.__MSUF_MirrorHiddenHeader if not st then return end
    panel.__MSUF_MirrorHeaderScanToken=nil panel.__MSUF_MirrorHeaderScanState=nil panel.__MSUF_MirrorHiddenHeader=nil for r,wasShown in pairs(st)
do if r and wasShown==1 then if r.Show then r:Show()
end
end
end
end
end
local function MSUF_AttachMirroredPanel(panel,parent,activeKey) if not panel or not parent then return end
if not panel.__MSUF_MirrorOrig then local orig={}
orig.parent=(panel.GetParent and panel:GetParent())
or nil orig.scale=(panel.GetScale and panel:GetScale())
or 1 orig.strata=(panel.GetFrameStrata and panel:GetFrameStrata())
or nil orig.level=(panel.GetFrameLevel and panel:GetFrameLevel())
or nil if panel.__MSUF_MirrorNoRestoreShow then orig.shown=false else orig.shown=(panel.IsShown and panel:IsShown())
and true or false end
orig.points={}
if panel.GetNumPoints and panel.GetPoint then local n=panel:GetNumPoints()
or 0 for i=1,n do local p,relTo,relPoint,xOfs,yOfs=panel:GetPoint(i)
orig.points[i]={p,relTo,relPoint,xOfs,yOfs}
end
end
panel.__MSUF_MirrorOrig=orig end
if not panel.__MSUF_MirrorActive then panel.__MSUF_MirrorState=MSUF_CapturePanelState(panel)
panel.__MSUF_MirrorActive=true end
if panel.SetParent then pcall(panel.SetParent,panel,parent)
end
if panel.ClearAllPoints then pcall(panel.ClearAllPoints,panel)
end
if panel.SetPoint then local cropY=0 if panel==(_G.MSUF_OptionsPanel)
then local deep=(type(activeKey)=="string"and activeKey~="main")
and true or false cropY=deep and MSUF_MIRROR_DEEPLINK_CROP_Y or MSUF_MIRROR_MAIN_CROP_Y MSUF_MirrorSetHeaderHidden(panel,true)
end
pcall(panel.SetPoint,panel,"TOPLEFT",parent,"TOPLEFT",0,cropY)
pcall(panel.SetPoint,panel,"BOTTOMRIGHT",parent,"BOTTOMRIGHT",0,0)
end
if panel.SetScale then pcall(panel.SetScale,panel,MIRROR_PANEL_SCALE)
end
if panel.SetFrameStrata then pcall(panel.SetFrameStrata,panel,"DIALOG")
end
if panel.Show then pcall(panel.Show,panel)
end
if not panel.__MSUF_MirrorWhiteHooked and panel.HookScript then panel.__MSUF_MirrorWhiteHooked=true panel:HookScript("OnShow",function() MSUF_ApplyWhiteTextToFrame(panel);
MSUF_ApplyFontBumpToFrame(panel,MIRRORED_PANEL_FONT_BUMP)
MSUF_ApplyMidnightControlsToFrame(panel) end
)
end
if panel.LoadFromDB then pcall(panel.LoadFromDB,panel)
elseif panel.Refresh then pcall(panel.Refresh,panel)
end
MSUF_ApplyWhiteTextToFrame(panel)
MSUF_ApplyFontBumpToFrame(panel,MIRRORED_PANEL_FONT_BUMP)
MSUF_ApplyMidnightControlsToFrame(panel) end
local function MSUF_Standalone_SetCastbarTopButtonsHidden(hidden) local panel=_G.MSUF_OptionsPanel;
local editBtn=_G and _G["MSUF_CastbarEditModeButton"];
local focusBtn=_G and _G["MSUF_CastbarFocusButton"]
local function Capture(btn) if not btn or btn.__msufStandaloneAnchorBackup then return end
local st={}
st.parent=(btn.GetParent and btn:GetParent())
or nil st.shown=(btn.IsShown and btn:IsShown())
and true or false st.points={}
if btn.GetNumPoints and btn.GetPoint then local n=btn:GetNumPoints()
or 0 for i=1,n do local pnt,relTo,relPoint,xOfs,yOfs=btn:GetPoint(i)
st.points[i]={pnt,relTo,relPoint,xOfs,yOfs}
end
end
btn.__msufStandaloneAnchorBackup=st end
local function Restore(btn) if not btn then return end
local st=btn.__msufStandaloneAnchorBackup if not st then return end
btn.__msufStandaloneAnchorBackup=nil if st.parent and btn.SetParent then pcall(btn.SetParent,btn,st.parent)
end
if btn.ClearAllPoints then pcall(btn.ClearAllPoints,btn)
end
if btn.SetPoint and st.points then for i=1,#st.points do local pt=st.points[i]
if pt and pt[1]
then pcall(btn.SetPoint,btn,pt[1],pt[2],pt[3],pt[4],pt[5])
end
end
end
if st.shown then if btn.Show then pcall(btn.Show,btn)
end
else if btn.Hide then pcall(btn.Hide,btn)
end
end
end
if hidden then Capture(focusBtn)
Capture(editBtn)
if panel and focusBtn and focusBtn.ClearAllPoints and focusBtn.SetPoint then if focusBtn.SetParent then pcall(focusBtn.SetParent,focusBtn,panel)
end
if focusBtn.Show then pcall(focusBtn.Show,focusBtn)
end
pcall(focusBtn.ClearAllPoints,focusBtn)
pcall(focusBtn.SetPoint,focusBtn,"TOPLEFT",panel,"TOPLEFT",16,-150)
end
if editBtn and editBtn.Hide then pcall(editBtn.Hide,editBtn)
end
else Restore(editBtn)
Restore(focusBtn)
end
end
local function MSUF_IsCastbarKey(k) return k=="castbar"or k=="opt_castbar" end
local function MSUF_Standalone_UpdateTitle(activeKey) if not(S.win and S.win._msufTitleFS and S.win._msufTitleFS.SetText)
then return end
local _ver = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
local _vStr = (type(_ver) == "string" and _ver ~= "") and ("  |cff9ece6av" .. _ver .. "|r") or ""
if activeKey=="home"then S.win._msufTitleFS:SetText("MSUF Menu" .. _vStr) return end
local info=MSUF_GetMirrorPageInfo(activeKey)
S.win._msufTitleFS:SetText(((info and info.title)
or"MSUF Menu") .. _vStr) end
local function MSUF_Standalone_UpdateNav(activeKey) if not(S.win and S.win._msufNavButtons)
then return end
local buttons=S.win._msufNavButtons;
local highlightKey=activeKey do local b=buttons and buttons[activeKey];
local visible=b and b.IsShown and b:IsShown()
if not visible then if type(activeKey)=="string"then if activeKey:match("^uf_")
then highlightKey="hdr_unitframes"elseif activeKey:match("^opt_")
then highlightKey="hdr_options"elseif activeKey=="modules"then highlightKey="hdr_modules"end
end
end
end
for k,btn in pairs(buttons)
do if btn then if btn.SetEnabled then btn:SetEnabled(true)
end
btn._msufNavIsActive=(k==highlightKey)
if btn._msufApplyNavState then btn:_msufApplyNavState(btn._msufNavIsActive,false)
end
end
end
end
local function MSUF_Standalone_ApplySelection(key,subkey,isCastbarKey) local info=MSUF_GetMirrorPageInfo(key);
local sel=info and info.select;
local wantSub=subkey if wantSub==nil and S and S.mirror then wantSub=S.mirror.pendingSubKey S.mirror.pendingSubKey=nil end
if S and S.mirror then if isCastbarKey and type(wantSub)=="string"and wantSub~=""then S.mirror.currentSubKey=wantSub elseif not isCastbarKey then S.mirror.currentSubKey=nil end
end
if type(sel)=="function"then local epoch=S.mirror.selectEpoch pcall(sel,wantSub) if C_Timer and C_Timer.After then C_Timer.After(0,function() if S.mirror.selectEpoch~=epoch then return end pcall(sel,wantSub) end
)
C_Timer.After(0.05,function() if S.mirror.selectEpoch~=epoch then return end pcall(sel,wantSub) end
)
end
end
end
local function MSUF_Standalone_AttachMirrorPanel(key) local panel=MSUF_GetPanelForKey(key)
if panel and S.mirror and S.mirror.host then MSUF_AttachMirroredPanel(panel,S.mirror.host,key)
MSUF_ApplyWhiteTextToFrame(panel)
MSUF_ApplyFontBumpToFrame(panel,MIRRORED_PANEL_FONT_BUMP)
if C_Timer and C_Timer.After then C_Timer.After(0,function() if panel and panel.__MSUF_MirrorActive then MSUF_ApplyWhiteTextToFrame(panel);
MSUF_ApplyFontBumpToFrame(panel,MIRRORED_PANEL_FONT_BUMP)
end
end
)
end
end
return panel end
local function MSUF_Standalone_AfterAttachFixups(key,isCastbarKey) if not isCastbarKey then return end
MSUF_Standalone_SetCastbarTopButtonsHidden(true)
if C_Timer and C_Timer.After then local epoch=S.mirror.selectEpoch C_Timer.After(0,function() if S.mirror.selectEpoch~=epoch then return end MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
C_Timer.After(0.05,function() if S.mirror.selectEpoch~=epoch then return end MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
C_Timer.After(0.15,function() if S.mirror.selectEpoch~=epoch then return end MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
C_Timer.After(0.30,function() if S.mirror.selectEpoch~=epoch then return end MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
end
local p=S and S.mirror and S.mirror.currentPanel if p and p.HookScript and not p.__MSUF_FocusKickResizeHooked then p.__MSUF_FocusKickResizeHooked=true p:HookScript("OnSizeChanged",function() if S and S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey)
then local function repin() if S and S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey)
then MSUF_Standalone_SetCastbarTopButtonsHidden(true)
end
end
if C_Timer and C_Timer.After then C_Timer.After(0,repin);
C_Timer.After(0.05,repin)
C_Timer.After(0.15,repin);
C_Timer.After(0.30,repin)
else repin()
end
end
end
)
end
end
local function MSUF_SwitchMirrorPage(key,subkey) key=MSUF_NormalizeMirrorKey(key,true)
S.mirror.selectEpoch=(S.mirror.selectEpoch or 0)+1
if key=="home"then if S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey)
and not MSUF_IsCastbarKey(key)
then MSUF_Standalone_SetCastbarTopButtonsHidden(false)
end
if S.mirror.currentPanel then local _p=S.mirror.currentPanel MSUF_DetachMirroredPanel(_p)
S.mirror.currentPanel=nil if _p and _p.Hide then pcall(_p.Hide,_p) end end
S.mirror.currentKey="home"if S.mirror.homePanel then _TFadeIn(S.mirror.homePanel,TRANS_PAGE)
MSUF_UpdateHomePanel(S.mirror.homePanel)
end
MSUF_Standalone_UpdateTitle("home")
MSUF_Standalone_UpdateNav("home")
do local _w=S and S.win if _w and _w._msufRefreshStatusBar then pcall(_w._msufRefreshStatusBar) end end
return end
if S.mirror.homePanel then _TCancel(S.mirror.homePanel)
if S.mirror.homePanel.SetAlpha then S.mirror.homePanel:SetAlpha(1) end
if S.mirror.homePanel.Hide then S.mirror.homePanel:Hide() end
end
local isCastbarKey=MSUF_IsCastbarKey(key)
if S.mirror.currentKey==key and S.mirror.currentPanel and S.mirror.currentPanel.IsShown and S.mirror.currentPanel:IsShown()
then MSUF_Standalone_ApplySelection(key,subkey,isCastbarKey)
MSUF_Standalone_UpdateTitle(key)
MSUF_Standalone_UpdateNav(key) return end
if S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey)
and not isCastbarKey then MSUF_Standalone_SetCastbarTopButtonsHidden(false)
end
local prevPanel = S.mirror.currentPanel
if S.mirror.currentPanel then local _p=S.mirror.currentPanel MSUF_DetachMirroredPanel(_p)
S.mirror.currentPanel=nil if _p and _p.Hide then pcall(_p.Hide,_p) end end
S.mirror.currentKey=key S.mirror.currentPanel=MSUF_Standalone_AttachMirrorPanel(key)
-- Track current key on the window frame so MSUF_Search.lua can read it
do local _w=_G.MSUF_StandaloneOptionsWindow if _w then _w._msufCurrentKey=key end end
if S.mirror.currentPanel and S.mirror.currentPanel ~= prevPanel then _TFadeIn(S.mirror.currentPanel,TRANS_PAGE) end
MSUF_Standalone_ApplySelection(key,subkey,isCastbarKey)
MSUF_Standalone_AfterAttachFixups(key,isCastbarKey)
MSUF_Standalone_UpdateTitle(key)
MSUF_Standalone_UpdateNav(key)
do local _w=S and S.win if _w and _w._msufRefreshStatusBar then pcall(_w._msufRefreshStatusBar) end end
end
local MSUF_NAV_ICON_TEX="Interface/AddOns/"..tostring(addonName or"MidnightSimpleUnitFrames").."/Media/msuf_nav_icons"
local MSUF_NAV_ICON_GRID={
home={0,0},
uf_player={1,0},uf_target={2,0},uf_targettarget={3,0},
uf_focus={4,0},uf_boss={5,0},uf_pet={6,0},
opt_bars={7,0},opt_fonts={0,1},auras2={1,1},
opt_castbar={2,1},opt_misc={3,1},opt_colors={4,1},
opt_portraits={5,1},classpower={6,1},gameplay={7,1},groupframes={0,2},gf_layout={0,2},gf_bars={0,2},gf_auras={0,2},gf_indicators={0,2},
modules={1,2},profiles={2,2},
}
local MSUF_NAV_ICON_COLORS={
home={0.30,0.60,1.00},
uf_player={0.40,0.78,0.98},uf_target={0.40,0.78,0.98},uf_targettarget={0.40,0.78,0.98},
uf_focus={0.40,0.78,0.98},uf_boss={0.40,0.78,0.98},uf_pet={0.40,0.78,0.98},
opt_bars={0.88,0.74,0.36},opt_fonts={0.88,0.74,0.36},auras2={0.88,0.74,0.36},
opt_castbar={0.88,0.74,0.36},opt_misc={0.88,0.74,0.36},opt_colors={0.88,0.74,0.36},
opt_portraits={0.88,0.74,0.36},
classpower={0.35,0.82,0.50},gameplay={0.72,0.50,0.92},groupframes={0.45,0.75,0.88},gf_layout={0.45,0.75,0.88},gf_bars={0.45,0.75,0.88},gf_auras={0.45,0.75,0.88},gf_indicators={0.45,0.75,0.88},
modules={0.40,0.80,0.75},profiles={0.90,0.62,0.30},
}
local function MSUF_AttachNavIcon(btn,navKey,isChild)
if not(btn and btn.CreateTexture and navKey)then return end
local g=MSUF_NAV_ICON_GRID[navKey]
local c=MSUF_NAV_ICON_COLORS[navKey]
if not(g and c)then return end
local icon=btn:CreateTexture(nil,"ARTWORK",nil,3)
icon:SetSize(14,14)
icon:SetTexture(MSUF_NAV_ICON_TEX)
local col,row=g[1],g[2]
icon:SetTexCoord(col/8,(col+1)/8,row/8,(row+1)/8)
icon:SetVertexColor(c[1],c[2],c[3],0.65)
icon:SetPoint("LEFT",btn,"LEFT",isChild and 8 or 10,0)
btn._msufNavIcon=icon btn._msufNavIconColor=c end
local function MSUF_BuildMirrorNavButtons(navParent,btnW,btnH) if not navParent then return {} end
btnH=btnH or 24 local padL=2;
local padT=(navParent and navParent._msufSearchInjected) and 2 or 10;
local padB=8;
local gap=5;
local indent=10 local extraRight=42;
local railW=navParent.GetWidth and navParent:GetWidth()
or 174 btnW=btnW or math.max(110,railW-(padL*2)-extraRight)
local out={};
local headers=navParent._msufTreeHeaders or{}
navParent._msufTreeHeaders=headers local hasTitle=not navParent._msufSkipNavTitle;
local title,sub if hasTitle and not navParent._msufNavTitle then title=navParent:CreateFontString(nil,"OVERLAY","GameFontNormal")
title:SetPoint("TOPLEFT",navParent,"TOPLEFT",padL,-padT)
title:SetText("Navigation")
MSUF_SkinTitle(title)
sub=navParent:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
sub:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-2)
sub:SetText("Quick access")
MSUF_SkinMuted(sub)
navParent._msufNavTitle=title navParent._msufNavSub=sub else title=navParent._msufNavTitle sub=navParent._msufNavSub end
if not navParent._msufNavHighlight then local hl=navParent:CreateTexture(nil,"BACKGROUND")
hl:SetTexture(MSUF_SUPERELLIPSE_TEX)
hl:SetVertexColor(1,1,1,0.06)
hl:Hide()
navParent._msufNavHighlight=hl local stripe=navParent:CreateTexture(nil,"BORDER")
stripe:SetTexture("Interface/Buttons/WHITE8X8")
stripe:SetVertexColor(0.18,0.45,1.00,0.55)
stripe:SetWidth(3)
stripe:Hide()
navParent._msufNavStripe=stripe end
local function MakeButton(label,w,onClick,isHeader,isChild) local b=UI_Button(navParent,tostring(label or""),w,btnH,"TOPLEFT",navParent,"TOPLEFT",0,0,onClick)
MSUF_LeftJustifyButtonText(b,isHeader and 18 or(isChild and 22 or 24))
MSUF_SkinNavButton(b,isHeader,isChild) return b end
local NAV={{type="leaf",key="home",label="Dashboard"},{type="header",id="unitframes",label="Unit Frames",defaultOpen=true,children={{key="uf_player",label="Player"},{key="uf_target",label="Target"},{key="uf_targettarget",label="Target of Target"},{key="uf_focus",label="Focus"},{key="uf_boss",label="Boss Frames"},{key="uf_pet",label="Pet"},}},{type="header",id="groupframes",label="Group Frames",defaultOpen=true,children={{key="gf_layout",label="Layout"},{key="gf_bars",label="Health & Text"},{key="gf_auras",label="Buffs & Debuffs"},{key="gf_indicators",label="Indicators"},}},{type="header",id="options",label="Global Style",defaultOpen=true,children={{key="opt_bars",label="Bars"},{key="opt_fonts",label="Fonts"},{key="auras2",label="Unit Auras"},{key="opt_castbar",label="Castbar"},{key="opt_portraits",label="Portraits"},{key="opt_colors",label="Colors"},{key="opt_misc",label="Miscellaneous"},}},{type="leaf",key="classpower",label="Class Resources"},{type="leaf",key="gameplay",label="Gameplay"},{type="header",id="modules",label="Modules",defaultOpen=false,children={{key="modules",label="Style"},}},{type="leaf",key="profiles",label="Profiles"},}
local headerLabels={}
for _,node in ipairs(NAV)
do if node.type=="header"then headerLabels[node.id]=node.label end
end
local created={}
for _,node in ipairs(NAV)
do if node.type=="leaf"then local b=MakeButton(node.label,btnW,function() MSUF_SwitchMirrorPage(node.key) end
,false,false)
MSUF_AttachNavIcon(b,node.key,false)
out[node.key]=b table.insert(created,{kind="leaf",btn=b})
elseif node.type=="header"then headers[node.id]=(headers[node.id]~=nil)
and headers[node.id]
or MSUF_GetSavedNavHeaderState(node.id,node.defaultOpen) local b=MakeButton(string.upper(node.label),btnW,function() headers[node.id]=not headers[node.id]
MSUF_SetSavedNavHeaderState(node.id,headers[node.id])
if navParent._msufTreeReflow then navParent._msufTreeReflow()
end
end
,true,false)
do local arrow=b:CreateTexture(nil,"OVERLAY")
arrow:SetSize(10,10)
arrow:SetPoint("LEFT",b,"LEFT",4,0)
arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
arrow:SetVertexColor(0.45,0.55,0.72)
if node.defaultOpen then arrow:SetRotation(math.pi*0.5) end
b._msufNavArrow=arrow end
out["hdr_"..node.id]=b table.insert(created,{kind="header",id=node.id,btn=b})
local kids={}
for _,ch in ipairs(node.children or{})
do local w=math.max(40,btnW-indent)
local cb=MakeButton(ch.label,w,function() MSUF_SwitchMirrorPage(ch.key) end
,false,true)
MSUF_AttachNavIcon(cb,ch.key,true)
out[ch.key]=cb table.insert(kids,cb)
table.insert(created,{kind="child",id=node.id,btn=cb})
end
end
end
local function Reflow() local yOfs=-padT if hasTitle then yOfs=-(padT+26)
end
local lowestBottomY=0 local function Place(btn,x) if not btn then return end
if btn.ClearAllPoints and btn.SetPoint then btn:ClearAllPoints()
btn:SetPoint("TOPLEFT",navParent,"TOPLEFT",padL+(x or 0),yOfs)
end
local bottomY=yOfs-btnH if bottomY<lowestBottomY then lowestBottomY=bottomY end
yOfs=yOfs-(btnH+gap) end
for _,it in ipairs(created)
do if it.kind=="leaf"then if it.btn.Show then it.btn:Show()
end
Place(it.btn,0)
elseif it.kind=="header"then local open=headers[it.id]
local baseLabel=headerLabels[it.id]
if baseLabel and it.btn.SetText then it.btn:SetText(string.upper(baseLabel))
end
if it.btn._msufNavArrow then if open then it.btn._msufNavArrow:SetRotation(math.pi*0.5) else it.btn._msufNavArrow:SetRotation(0) end
end
if it.btn.Show then it.btn:Show()
end
Place(it.btn,0)
elseif it.kind=="child"then if headers[it.id]
then if it.btn.Show then it.btn:Show()
end
Place(it.btn,indent)
else if it.btn.Hide then it.btn:Hide()
end
end
end
end
local function ApplyMinHeight()
local navRail=navParent and navParent.GetParent and navParent:GetParent() if not navRail then return end
local content=navRail.GetParent and navRail:GetParent() if not content then return end
local win=content.GetParent and content:GetParent() if not win then return end

local neededNavStackH=math.abs(lowestBottomY)+padB+14
local minW=win._msufBaseMinW or 760
local baseMinH=win._msufBaseMinH or 560

-- Overhead between window height and nav stack height is constant due to anchored offsets.
local overhead=54
if win.GetHeight and navParent.GetHeight then
local wh=win:GetHeight();
local nh=navParent:GetHeight()
if wh and nh and wh>0 and nh>0 then overhead=wh-nh end
end
if overhead<40 then overhead=54 end

local minH=math.max(baseMinH,overhead+neededNavStackH)
local maxW=win._msufMaxW or 2200
local maxH=win._msufMaxH or 1400

win._msufMinW,win._msufMinH=minW,minH
if win.SetResizeBounds then pcall(win.SetResizeBounds,win,minW,minH,maxW,maxH)
elseif win.SetMinResize then pcall(win.SetMinResize,win,minW,minH)
end

-- Clamp persisted too-small sizes from saved geometry.
if win.GetWidth and win.GetHeight and win.SetSize then
local w,h=win:GetWidth(),win:GetHeight()
if w and h then
local nw,nh=w,h
if w<minW then nw=minW end
if h<minH then nh=minH end
if nw~=w or nh~=h then win:SetSize(nw,nh)
end
end
end
end
if C_Timer and C_Timer.After then C_Timer.After(0,ApplyMinHeight)
C_Timer.After(0.05,ApplyMinHeight)
else ApplyMinHeight()
end
end
navParent._msufTreeReflow=Reflow Reflow()
-- Inject search EditBox at bottom of navRail (below Profiles) — MSUF_Search.lua
if ns and type(ns.MSUF_Search_InjectNavEditBox)=="function" then
    pcall(ns.MSUF_Search_InjectNavEditBox,navParent)
end
return out end
local function MSUF_CreateOptionsWindow() if S.win then return S.win end
local f=CreateFrame("Frame","MSUF_StandaloneOptionsWindow",UIParent,"BackdropTemplate")
f:SetSize(900,650)
f:SetPoint("CENTER",UIParent,"CENTER",-60,10)
if f.SetClipsChildren then f:SetClipsChildren(false)
end
f:SetFrameStrata("DIALOG")
f:SetClampedToScreen(true)
if f.SetClampRectInsets then f:SetClampRectInsets(8,8,8,8)
end
if MSUF_RegisterEscClose then MSUF_RegisterEscClose(f)
end
f:EnableMouse(true)
f:SetMovable(true)
f:SetResizable(true)
do local minW,minH=760,560;
local maxW,maxH=2200,1400 if f.SetResizeBounds then f:SetResizeBounds(minW,minH,maxW,maxH)
elseif f.SetMinResize then f:SetMinResize(minW,minH)
end
f._msufBaseMinW,f._msufBaseMinH=minW,minH f._msufMinW,f._msufMinH,f._msufMaxW,f._msufMaxH=minW,minH,maxW,maxH end
f._msufGeomKey="full"if MSUF_LoadWindowGeometry then MSUF_LoadWindowGeometry(f,"full",900,650,"CENTER",-60,10)
end
do
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
local sc=MSUF_GetSavedSlashMenuScale()
MSUF_ApplySlashMenuScale(sc,{ignoreDisable=true})
end
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart",function(self) self:StartMoving() end
)
f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing()
if MSUF_SaveWindowGeometry then MSUF_SaveWindowGeometry(self,self._msufGeomKey or"full")
end
end
)
MSUF_AttachManualResizeGrip(f)
MSUF_ApplyMidnightBackdrop(f,1.0)
if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.08,0.10,0.22,0.90) end
local title=f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
title:SetPoint("TOPLEFT",12,-6)
title:SetText("MSUF OPTIONS")
title:SetTextColor(MSUF_THEME.accentR,MSUF_THEME.accentG,MSUF_THEME.accentB,0.50)
f._msufTitleFS=title local close=UI_CloseButton(f,"TOPRIGHT",f,"TOPRIGHT",-4,-4)
close:SetScript("OnClick",function() _TScaleDismiss(f,TRANS_CLOSE) end)
local function MSUF_SetPropagateKeyboardInputSafe(frame,enabled) if not frame or not frame.SetPropagateKeyboardInput then return end
if type(InCombatLockdown)=="function"and InCombatLockdown()
then frame._msufPendingPropagateKeyboard=enabled return end
frame._msufPendingPropagateKeyboard=nil frame:SetPropagateKeyboardInput(enabled) end
if not f._msufPropagateRegenFrame then local rf=CreateFrame("Frame")
rf:RegisterEvent("PLAYER_REGEN_ENABLED")
rf:SetScript("OnEvent",function() if f and f._msufPendingPropagateKeyboard~=nil then if f:IsShown()
then MSUF_SetPropagateKeyboardInputSafe(f,f._msufPendingPropagateKeyboard)
else f._msufPendingPropagateKeyboard=nil end
end
end
)
f._msufPropagateRegenFrame=rf end
local content=CreateFrame("Frame",nil,f)
content:SetPoint("TOPLEFT",f,"TOPLEFT",8,-30)
content:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-8,8)
content:SetScale(1.0)
if content.SetClipsChildren then content:SetClipsChildren(false)
end
S.content=content local navRail=CreateFrame("Frame",nil,content,"BackdropTemplate")
navRail:SetPoint("TOPLEFT",content,"TOPLEFT",0,0)
navRail:SetPoint("BOTTOMLEFT",content,"BOTTOMLEFT",0,0)
navRail:SetWidth(174)
MSUF_ApplyMidnightBackdrop(navRail,0.40)
do local navSep=navRail:CreateTexture(nil,"ARTWORK",nil,6)
navSep:SetTexture("Interface/Buttons/WHITE8X8")
navSep:SetWidth(1)
navSep:SetPoint("TOPRIGHT",navRail,"TOPRIGHT",0,-4)
navSep:SetPoint("BOTTOMRIGHT",navRail,"BOTTOMRIGHT",0,4)
navSep:SetColorTexture(MSUF_THEME.edgeR,MSUF_THEME.edgeG,MSUF_THEME.edgeB,0.28)
end
f._msufNavRail=navRail local host=CreateFrame("Frame",nil,content)
host:SetPoint("TOPLEFT",navRail,"TOPRIGHT",8,0)
host:SetPoint("BOTTOMRIGHT",content,"BOTTOMRIGHT",0,0)
host:SetScale(1.0)
if host.SetClipsChildren then host:SetClipsChildren(false)
end
f._msufMirrorHost=host
local statusBar=CreateFrame("Frame",nil,host,"BackdropTemplate")
statusBar:SetHeight(22)
statusBar:SetPoint("TOPLEFT",host,"TOPLEFT",0,0)
statusBar:SetPoint("TOPRIGHT",host,"TOPRIGHT",0,0)
MSUF_ApplyMidnightBackdrop(statusBar,0.30)
local sbProfile=statusBar:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
sbProfile:SetPoint("LEFT",statusBar,"LEFT",10,0)
sbProfile:SetJustifyH("LEFT")
MSUF_SkinMuted(sbProfile)
local sbEdit=statusBar:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
sbEdit:SetPoint("LEFT",sbProfile,"RIGHT",14,0)
sbEdit:SetJustifyH("LEFT")
MSUF_SkinMuted(sbEdit)
local sbCombat=statusBar:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
sbCombat:SetPoint("LEFT",sbEdit,"RIGHT",14,0)
sbCombat:SetJustifyH("LEFT")
MSUF_SkinMuted(sbCombat)
local sbVersion=statusBar:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
sbVersion:SetPoint("RIGHT",statusBar,"RIGHT",-10,0)
sbVersion:SetJustifyH("RIGHT")
sbVersion:SetAlpha(0.50)
MSUF_SkinMuted(sbVersion)
f._msufStatusBar=statusBar
local sbTopLine=statusBar:CreateTexture(nil,"ARTWORK",nil,6)
sbTopLine:SetTexture("Interface/Buttons/WHITE8X8")
sbTopLine:SetHeight(1)
sbTopLine:SetPoint("TOPLEFT",statusBar,"TOPLEFT",0,0)
sbTopLine:SetPoint("TOPRIGHT",statusBar,"TOPRIGHT",0,0)
sbTopLine:SetColorTexture(MSUF_THEME.accentR,MSUF_THEME.accentG,MSUF_THEME.accentB,0.25)
local function MSUF_RefreshStatusBar()
if not f._msufStatusBar then return end
local prof=(_G.MSUF_ActiveProfile)or"Default"
sbProfile:SetText("|cff4a90d9Profile:|r |cffccd8e8"..tostring(prof).."|r  |cff3a4a66\194\183|r")
local editOn=(type(MSUF_IsMSUFEditModeActive)=="function"and MSUF_IsMSUFEditModeActive())
if editOn then sbEdit:SetText("|cff4ade80Edit: On|r  |cff3a4a66\194\183|r")
else sbEdit:SetText("|cff5a6a88Edit: Off|r  |cff3a4a66\194\183|r")
end
local inCombat=(InCombatLockdown and InCombatLockdown())
if inCombat then sbCombat:SetText("|cffef4444In Combat|r")
else sbCombat:SetText("|cff22c55eOut of Combat|r")
end
local ver=_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames","Version")
sbVersion:SetText(type(ver)=="string"and ver~=""and("v"..ver)or"")
end
f._msufRefreshStatusBar=MSUF_RefreshStatusBar
statusBar:RegisterEvent("PLAYER_REGEN_DISABLED")
statusBar:RegisterEvent("PLAYER_REGEN_ENABLED")
statusBar:SetScript("OnEvent",function() if f and f:IsShown() then MSUF_RefreshStatusBar() end end)
local clip=CreateFrame("Frame",nil,host)
clip:SetPoint("TOPLEFT",statusBar,"BOTTOMLEFT",0,0)
clip:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
if clip.SetClipsChildren then clip:SetClipsChildren(true)
end
f._msufMirrorClipHost=clip local navStack=CreateFrame("Frame",nil,navRail)
navStack._msufSkipNavTitle=true local railW=navRail.GetWidth and navRail:GetWidth()
or 174 if navStack.SetWidth then navStack:SetWidth(math.max(80,railW-16))
end
f._msufNavStack=navStack f._msufNavButtons=MSUF_BuildMirrorNavButtons(navStack,154,24)
do local pad=8 local topReserve=(tonumber(navStack._msufSearchReservePx) or 0)
if navStack.ClearAllPoints then navStack:ClearAllPoints()
end
navStack:SetPoint("TOPLEFT",navRail,"TOPLEFT",pad,-(pad+topReserve))
navStack:SetPoint("TOPRIGHT",navRail,"TOPRIGHT",-pad,-(pad+topReserve))
navStack:SetPoint("BOTTOMLEFT",navRail,"BOTTOMLEFT",pad,pad)
navStack:SetPoint("BOTTOMRIGHT",navRail,"BOTTOMRIGHT",-pad,pad)
end
local home=CreateFrame("Frame",nil,host,"BackdropTemplate")
home:SetPoint("TOPLEFT",statusBar,"BOTTOMLEFT",0,0)
home:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
MSUF_ApplyMidnightBackdrop(home,0.30)
home:Hide()
S.mirror.homePanel=home f._msufHomePanel=home MSUF_ApplyMidnightControlsToFrame(home)
local homeAccent=home:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
homeAccent:SetPoint("TOPLEFT",12,-10)
homeAccent:SetText("MSUF CONTROL CENTER")
homeAccent:SetTextColor(MSUF_THEME.accentR,MSUF_THEME.accentG,MSUF_THEME.accentB,0.55)
do local ok,fPath,fSize,fFlags=pcall(homeAccent.GetFont,homeAccent)
if ok and fPath and fSize then MSUF_SafeSetFont(homeAccent,fPath,math.max(8,fSize-2),fFlags or"") end
end
local homeTitle=home:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
homeTitle:SetPoint("TOPLEFT",homeAccent,"BOTTOMLEFT",0,-3)
homeTitle:SetText("Dashboard")
MSUF_SkinTitle(homeTitle)
local homeHint=home:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
homeHint:SetPoint("TOPLEFT",homeTitle,"BOTTOMLEFT",0,-2)
homeHint:SetText("")
homeHint:Hide()
MSUF_SkinText(homeHint)
local tipBox=CreateFrame("Frame",nil,home,"BackdropTemplate")
tipBox:SetPoint("TOPLEFT",homeTitle,"BOTTOMLEFT",0,-12)
tipBox:SetPoint("TOPRIGHT",home,"TOPRIGHT",-12,-56)
tipBox:SetHeight(26)
tipBox:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3},})
tipBox:SetBackdropColor(0.06,0.07,0.13,0.70)
if tipBox.SetBackdropBorderColor then tipBox:SetBackdropBorderColor(0.10,0.12,0.24,0.40) end
local tipAccent=tipBox:CreateTexture(nil,"ARTWORK",nil,6)
tipAccent:SetTexture("Interface/Buttons/WHITE8X8")
tipAccent:SetWidth(3)
tipAccent:SetPoint("TOPLEFT",tipBox,"TOPLEFT",3,-3)
tipAccent:SetPoint("BOTTOMLEFT",tipBox,"BOTTOMLEFT",3,3)
tipAccent:SetColorTexture(MSUF_THEME.accentR,MSUF_THEME.accentG,MSUF_THEME.accentB,0.70)
local tipLabel=tipBox:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
tipLabel:SetPoint("LEFT",tipBox,"LEFT",14,0)
tipLabel:SetJustifyH("LEFT")
tipLabel:SetAlpha(1.00)
tipLabel:SetText("Tip")
tipLabel:SetTextColor(MSUF_THEME.accentR,MSUF_THEME.accentG,MSUF_THEME.accentB,0.90)
local tipText=tipBox:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
tipText:SetPoint("LEFT",tipLabel,"RIGHT",6,0)
tipText:SetPoint("RIGHT",tipBox,"RIGHT",-10,0)
tipText:SetJustifyH("LEFT")
tipText:SetJustifyV("MIDDLE")
tipText:SetAlpha(0.88)
tipText:SetText("")
MSUF_SkinMuted(tipText)
MSUF_ForceItalicFont(tipText)
home._msufTipLabel=tipLabel home._msufTipText=tipText home:SetScript("OnShow",function(self) MSUF_UpdateHomePanel(self) end
)
MSUF_ApplyFontBumpToFrame(home,MENU_FONT_BUMP)
MSUF_ForceItalicFont(tipText)
home._msufStatusLine=nil local actionRow=CreateFrame("Frame",nil,home)
actionRow:SetPoint("TOPLEFT",tipBox,"BOTTOMLEFT",0,-12)
actionRow:SetPoint("TOPRIGHT",tipBox,"BOTTOMRIGHT",0,-12)
actionRow:SetHeight(34)
local split=CreateFrame("Frame",nil,home)
split:SetPoint("TOPLEFT",actionRow,"BOTTOMLEFT",0,-12)
split:SetPoint("TOPRIGHT",actionRow,"BOTTOMRIGHT",0,-12)
split:SetPoint("BOTTOMLEFT",home,"BOTTOMLEFT",12,96)
split:SetPoint("BOTTOMRIGHT",home,"BOTTOMRIGHT",-12,96)
local colGap=12;
local colL=CreateFrame("Frame",nil,split)
colL:SetPoint("TOPLEFT",split,"TOPLEFT",0,0)
colL:SetPoint("BOTTOMLEFT",split,"BOTTOMLEFT",0,0)
colL:SetPoint("TOPRIGHT",split,"TOP",-(colGap/2),0)
colL:SetPoint("BOTTOMRIGHT",split,"BOTTOM",-(colGap/2),0)
local colR=CreateFrame("Frame",nil,split)
colR:SetPoint("TOPLEFT",split,"TOP",(colGap/2),0)
colR:SetPoint("BOTTOMLEFT",split,"BOTTOM",(colGap/2),0)
colR:SetPoint("TOPRIGHT",split,"TOPRIGHT",0,0)
colR:SetPoint("BOTTOMRIGHT",split,"BOTTOMRIGHT",0,0)
local function CreateCard(parent,titleText,anchorTo,yOff,skipTitle) local card=CreateFrame("Frame",nil,parent,"BackdropTemplate")
if anchorTo then card:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT",0,yOff or-10)
card:SetPoint("TOPRIGHT",anchorTo,"BOTTOMRIGHT",0,yOff or-10)
else card:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0)
card:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,0)
end
card:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background",edgeFile="Interface/Tooltips/UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=14,insets={left=3,right=3,top=3,bottom=3},})
card:SetBackdropColor(MSUF_THEME.cardBgR,MSUF_THEME.cardBgG,MSUF_THEME.cardBgB,MSUF_THEME.cardBgA)
if card.SetBackdropBorderColor then card:SetBackdropBorderColor(MSUF_THEME.cardEdgeR,MSUF_THEME.cardEdgeG,MSUF_THEME.cardEdgeB,MSUF_THEME.cardEdgeA) end
if not skipTitle then local title=UI_TextTL(card,"GameFontNormal",12,-10,titleText or"",MSUF_SkinTitle)
card._msufTitle=title end
return card end
local function DashToggleEditMode() if type(_G.MSUF_SetMSUFEditModeDirect)=="function"then local st=_G.MSUF_EditState;
local nextActive=true if st and st.active~=nil then nextActive=not st.active end
pcall(_G.MSUF_SetMSUFEditModeDirect,nextActive) return end
if type(_G.MSUF_ToggleEditMode)=="function"then pcall(_G.MSUF_ToggleEditMode)
elseif type(_G.MSUF_EditMode_Toggle)=="function"then pcall(_G.MSUF_EditMode_Toggle)
else MSUF_Print("Edit Mode function not found.")
end
end
local function MSUF_ShowResetPositionsConfirm() if InCombatLockdown and InCombatLockdown()
then MSUF_Print("Cannot reset while in combat.") return end
-- === Slash Commands ===

if not StaticPopupDialogs["MSUF_RESET_POS_CONFIRM"]
then StaticPopupDialogs["MSUF_RESET_POS_CONFIRM"]={text="Reset MSUF frame positions now?\n\nThis affects the ACTIVE profile only:\n- Resets Player, Target, Focus, Pet and ToT frame size/position/visibility defaults.\n- Anchors unitframes back to the screen center (UIParent).\n- Disables CDM/custom global anchors.\n- Clears per-frame custom/unitframe anchors.\n- Applies the layout immediately.",button1=YES,button2=NO,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() if _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
then pcall(_G.SlashCmdList["MIDNIGHTSUF"],"reset")
else MSUF_Print("/msuf reset handler not found.")
end
end
,}
end
StaticPopup_Show("MSUF_RESET_POS_CONFIRM") end
local function MSUF_ShowFactoryResetConfirm() if InCombatLockdown and InCombatLockdown()
then MSUF_Print("Cannot factory reset while in combat.") return end
if not StaticPopupDialogs["MSUF_FACTORY_RESET_CONFIRM"]
then StaticPopupDialogs["MSUF_FACTORY_RESET_CONFIRM"]={text="FACTORY RESET MSUF now?\n\nThis deletes ALL MSUF profiles & settings for this account.\n\nThe UI will reload.",button1=YES,button2=NO,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() if type(_G.MSUF_DoFullReset)=="function"then pcall(_G.MSUF_DoFullReset);
 return end
_G.MSUF_DB=nil;
_G.MSUF_GlobalDB=nil _G.MSUF_ActiveProfile=nil if type(ReloadUI)=="function"then ReloadUI()
end
end
,}
end
StaticPopup_Show("MSUF_FACTORY_RESET_CONFIRM") end
local bigH=34
local halfGap=12
local bEdit=UI_Btn(actionRow,"Toggle Edit Mode",120,bigH,"TOPLEFT",actionRow,"TOPLEFT",0,0,DashToggleEditMode,"Toggle Edit Mode","Enter MSUF Edit Mode to drag frames and adjust positions.",MSUF_SkinPrimaryButton)
local win=_G.MSUF_StandaloneOptionsWindow if win then win._msufDashEditBtn=bEdit end
if bEdit and bEdit._msufSetSelected then bEdit:_msufSetSelected(MSUF_IsMSUFEditModeActive()) end
MSUF_TryHookEditModeForDashboard()
local bReset=UI_Btn(actionRow,"Reset Positions",120,bigH,"TOPRIGHT",actionRow,"TOPRIGHT",0,0,MSUF_ShowResetPositionsConfirm,"Reset Positions","Resets MSUF frame positions + visibility to defaults (active profile).",MSUF_SkinDangerButton)

local navCard=CreateCard(colL,"Quick Navigation")
navCard:SetHeight(108)
local navDesc=UI_TextTL(navCard,"GameFontDisableSmall",12,-30,"Jump into the most-used MSUF sections.",MSUF_SkinMuted)
local navRow1=MSUF_BuildButtonRowTL(navCard,12,-56,{{text="Colors",w=140,h=22,gap=10,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("colors") end},{text="Gameplay",w=140,h=22,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("gameplay") end},},10)
local navRow2=MSUF_BuildButtonRowTL(navCard,12,-84,{{text="Unit Auras",w=140,h=22,gap=10,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("auras2") end},{text="Class Resources",w=140,h=22,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("classpower") end},},10)
local bColors,bGameplay=navRow1[1],navRow1[2]
local bAuras,bClass=navRow2[1],navRow2[2]

local profileCard=CreateCard(colR,"Active Profile")
profileCard:SetHeight(108)
local bProfiles=UI_Btn(profileCard,"Manage",88,22,"TOPRIGHT",profileCard,"TOPRIGHT",-12,-26,function() MSUF_SwitchMirrorPage("profiles") end,nil,nil,MSUF_SkinDashboardButton)
local profValue=UI_TextTL(profileCard,"GameFontNormalLarge",12,-42,((_G.MSUF_ActiveProfile) or "Default"),MSUF_SkinTitle)
home._msufProfileValue=profValue
local profMeta=UI_TextTL(profileCard,"GameFontDisableSmall",12,-70,"Use the Profiles page for switching, export and import.",MSUF_SkinMuted)
profMeta:SetWidth(260)
profMeta:SetJustifyH("LEFT")

local scaleCard=CreateCard(colL,"UI Scale",navCard,-10)
scaleCard:SetPoint("BOTTOMLEFT",colL,"BOTTOMLEFT",0,0)
scaleCard:SetPoint("BOTTOMRIGHT",colL,"BOTTOMRIGHT",0,0)
local scaleDesc=nil
local function HideSliderParts(slider)
local n=(slider and slider.GetName and slider:GetName()) or nil
local t=(n and _G[n.."Text"]) or (slider and slider.Text)
if t then t:SetText(""); t:Hide() end
local low=(n and _G[n.."Low"]) or (slider and slider.Low)
if low then low:SetText(""); low:Hide() end
local high=(n and _G[n.."High"]) or (slider and slider.High)
if high then high:SetText(""); high:Hide() end
end
local function SnapScalePct(value,minPct,maxPct,stepPct)
minPct=minPct or 25
maxPct=maxPct or 150
stepPct=stepPct or 5
local pct=math.floor((tonumber(value) or 100)/stepPct+0.5)*stepPct
if pct<minPct then pct=minPct elseif pct>maxPct then pct=maxPct end
return pct
end
local function SetSliderValueSafe(slider,value)
if slider and slider.SetValue then slider.__msufSkip=true slider:SetValue(value) slider.__msufSkip=nil end
end
local function StyleDashboardSlider(slider)
local UI=ns and ns.UI
local style=(_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
if type(style)=="function"then pcall(style,slider) return end
if C_Timer and C_Timer.After then C_Timer.After(0,function()
local UI2=ns and ns.UI
local later=(_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI2 and UI2.StyleSlider)
if type(later)=="function"then pcall(later,slider) end
end) end
end

local globalScaleLabel=UI_TextTL(scaleCard,"GameFontHighlight",12,-36,"Global UI Scale",MSUF_SkinText)
local globalScaleStatus=UI_TextTL(scaleCard,"GameFontDisableSmall",12,-53,"Applied: Off",MSUF_SkinMuted)
globalScaleStatus:SetWidth(280)
local globalScaleSlider=CreateFrame("Slider","MSUF_DashboardGlobalScaleSlider",scaleCard,"OptionsSliderTemplate")
globalScaleSlider:ClearAllPoints()
globalScaleSlider:SetPoint("TOPLEFT",globalScaleStatus,"BOTTOMLEFT",0,-8)
globalScaleSlider:SetPoint("RIGHT",scaleCard,"RIGHT",-26,0)
globalScaleSlider:SetMinMaxValues(30,150)
globalScaleSlider:SetValueStep(1)
globalScaleSlider:SetObeyStepOnDrag(true)
if globalScaleSlider.SetStepsPerPage then globalScaleSlider:SetStepsPerPage(1) end
HideSliderParts(globalScaleSlider)
StyleDashboardSlider(globalScaleSlider)
local bGlobalApply,bGlobalRevert,bGlobalAuto,bGlobalOff,bGlobal1080,bGlobal1440,bGlobal4k,bGlobalPixel
local function GetGlobalUiState()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
local ui=MSUF_EnsureGlobalUiScaleTable(g)
local enabled=ui and ui.Enabled
local scale=clamp(tonumber(ui and ui.Scale) or 1.0,0.3,1.5)
return false,enabled and true or false,scale
end
local function GetPendingGlobalScale(enabled,applied)
local pending=scaleCard._msufPendingGlobalScale
if pending==nil then pending=applied end
pending=clamp(tonumber(pending) or applied or 1.0,0.3,1.5)
local pendingEnabled=scaleCard._msufPendingGlobalEnabled
if pendingEnabled==nil then pendingEnabled=enabled end
return pendingEnabled and true or false,pending
end
local function RefreshGlobalScaleControls()
local disabled,enabled,applied=GetGlobalUiState()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
local preset=g and g.globalUiScalePreset
local pendingEnabled,pending=GetPendingGlobalScale(enabled,applied)
local changed=((pendingEnabled~=enabled) or math.abs((pending or 1)-(applied or 1))>0.001)
local appliedTxt=enabled and string.format("%d%%",math.floor(applied*100+0.5)) or "Off"
local pendingTxt=pendingEnabled and string.format("%d%%",math.floor(pending*100+0.5)) or "Off"
if globalScaleStatus and globalScaleStatus.SetText then
if changed then globalScaleStatus:SetText("Applied: "..appliedTxt.."  Selected: "..pendingTxt.."  |cffffd200Apply|r")
else globalScaleStatus:SetText("Applied: "..appliedTxt.."  Selected: "..pendingTxt) end
end
SetSliderValueSafe(globalScaleSlider,SnapScalePct((pending or applied or 1)*100,30,150,1))
MSUF_SetEnabled(globalScaleSlider,true)
MSUF_SetEnabled(bGlobalApply,changed)
MSUF_SetEnabled(bGlobalRevert,changed)
MSUF_SetEnabled(bGlobalAuto,true)
MSUF_SetEnabled(bGlobalOff,true)
MSUF_SetEnabled(bGlobal1080,true)
MSUF_SetEnabled(bGlobal1440,true)
MSUF_SetEnabled(bGlobal4k,true)
MSUF_SetEnabled(bGlobalPixel,true)
if bGlobalApply and bGlobalApply._msufSetSelected then bGlobalApply:_msufSetSelected(changed) end
if bGlobalAuto and bGlobalAuto._msufSetSelected then bGlobalAuto:_msufSetSelected(pendingEnabled==false) end
if bGlobalOff and bGlobalOff._msufSetSelected then bGlobalOff:_msufSetSelected(not enabled) end
if bGlobal1080 and bGlobal1080._msufSetSelected then bGlobal1080:_msufSetSelected(enabled and preset=="1080p") end
if bGlobal1440 and bGlobal1440._msufSetSelected then bGlobal1440:_msufSetSelected(enabled and preset=="1440p") end
if bGlobal4k and bGlobal4k._msufSetSelected then bGlobal4k:_msufSetSelected(enabled and preset=="4k") end
if bGlobalPixel and bGlobalPixel._msufSetSelected then bGlobalPixel:_msufSetSelected(enabled and preset=="pixel") end
if bGlobalOff and bGlobalOff.SetText then bGlobalOff:SetText(enabled and "UI Off" or "UI On") end
local a=1.0
if globalScaleLabel and globalScaleLabel.SetAlpha then globalScaleLabel:SetAlpha(a) end
if globalScaleStatus and globalScaleStatus.SetAlpha then globalScaleStatus:SetAlpha(a) end
end
globalScaleSlider:EnableMouseWheel(true)
globalScaleSlider:SetScript("OnMouseWheel",function(self,delta) if not delta then return end local v=tonumber((self.GetValue and self:GetValue()) or 100) or 100 v=v+(delta>0 and 1 or -1) self:SetValue(SnapScalePct(v,30,150,1)) end)
globalScaleSlider:SetScript("OnValueChanged",function(self,value)
if self.__msufSkip then return end
local pct=SnapScalePct(value,30,150,1)
if pct~=value then self.__msufSkip=true self:SetValue(pct) self.__msufSkip=nil return end
scaleCard._msufPendingGlobalEnabled=true
scaleCard._msufPendingGlobalScale=pct/100
RefreshGlobalScaleControls()
end)
if MSUF_AddTooltip then pcall(MSUF_AddTooltip,globalScaleSlider,"Global UI Scale","Selects the global UIParent scale. Drag or use the mouse wheel, then press Apply. Off stops MSUF enforcing global scale and keeps the current size through Blizzard UI scale.") end
local RefreshScaleCard
local function ApplyDashboardGlobalPreset(preset,scale)
scaleCard._msufPendingGlobalEnabled=nil
scaleCard._msufPendingGlobalScale=nil
MSUF_SaveGlobalPreset(preset,scale)
MSUF_SetGlobalUiScale(scale,true)
RefreshGlobalScaleControls()
end
local presetGlobalRow=MSUF_BuildButtonRowTL(scaleCard,12,-96,{{text="1080p",w=64,h=18,gap=6,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 1080p",tipBody="Applies the global UI scale preset for 1080p-like setups.",onClick=function() ApplyDashboardGlobalPreset("1080p",UI_SCALE_1080) end},{text="1440p",w=64,h=18,gap=6,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 1440p",tipBody="Applies the global UI scale preset for 1440p-like setups.",onClick=function() ApplyDashboardGlobalPreset("1440p",UI_SCALE_1440) end},{text="4K",w=54,h=18,gap=6,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 4K",tipBody="Applies the global UI scale preset for 4K (2160p) setups.",onClick=function() ApplyDashboardGlobalPreset("4k",UI_SCALE_4K) end},{text="Pixel",w=64,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Pixel Perfect Scale",tipBody="Applies the pixel perfect UI scale for the current screen height (768 / screen height).",onClick=function() ApplyDashboardGlobalPreset("pixel",MSUF_GetPixelPerfectScale()) end},},6)
bGlobal1080,bGlobal1440,bGlobal4k,bGlobalPixel=presetGlobalRow[1],presetGlobalRow[2],presetGlobalRow[3],presetGlobalRow[4]
local globalRow=MSUF_BuildButtonRowTL(scaleCard,12,-120,{{text="Apply",w=72,h=20,gap=6,skinFn=MSUF_SkinDashboardButton,onClick=function()
local disabled,enabled,applied=GetGlobalUiState()
local pendingEnabled,pending=GetPendingGlobalScale(enabled,applied)
if pendingEnabled then
MSUF_SetGlobalUiScaleState(true,pending,"custom")
MSUF_SetGlobalUiScale(pending,true)
else
MSUF_SaveGlobalPreset("auto",nil)
MSUF_ResetGlobalUiScale(true)
end
scaleCard._msufPendingGlobalEnabled=nil
scaleCard._msufPendingGlobalScale=nil
RefreshGlobalScaleControls()
end},{text="Revert",w=72,h=20,gap=6,skinFn=MSUF_SkinDashboardButton,onClick=function()
scaleCard._msufPendingGlobalEnabled=nil
scaleCard._msufPendingGlobalScale=nil
RefreshGlobalScaleControls()
end},{text="Off",w=58,h=20,gap=6,skinFn=MSUF_SkinDashboardButton,tipTitle="Select Off",tipBody="Selects Off for the global UI scale. Press Apply to hand the current size to Blizzard and stop MSUF enforcing it.",onClick=function()
scaleCard._msufPendingGlobalEnabled=false
RefreshGlobalScaleControls()
end},{text="UI Off",w=76,h=20,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: Off",tipBody="Turns off MSUF global UI scale and keeps the current visible UI size through Blizzard UI scale.",onClick=function()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
local ui=MSUF_EnsureGlobalUiScaleTable(g)
if ui and ui.Enabled then
MSUF_ResetGlobalUiScale(true)
else
local scale=ui and tonumber(ui.Scale) or 1.0
MSUF_SetGlobalUiScaleState(true,scale,"custom")
MSUF_SetGlobalUiScale(scale,true)
end
scaleCard._msufPendingGlobalEnabled=nil
scaleCard._msufPendingGlobalScale=nil
scaleCard._msufPendingMenuScale=nil
if RefreshScaleCard then RefreshScaleCard() else RefreshGlobalScaleControls() end
end},},6)
bGlobalApply,bGlobalRevert,bGlobalAuto,bGlobalOff=globalRow[1],globalRow[2],globalRow[3],globalRow[4]

local msufScaleLabel=UI_TextTL(scaleCard,"GameFontHighlight",12,-146,"MSUF Frame Scale",MSUF_SkinText)
local msufScaleCur=UI_TextTL(scaleCard,"GameFontDisableSmall",12,-163,"Current: 1.00",MSUF_SkinMuted)
local msufScaleSlider=CreateFrame("Slider","MSUF_DashboardMsufScaleSlider",scaleCard,"OptionsSliderTemplate")
msufScaleSlider:ClearAllPoints()
msufScaleSlider:SetPoint("TOPLEFT",msufScaleCur,"BOTTOMLEFT",0,-8)
msufScaleSlider:SetPoint("RIGHT",scaleCard,"RIGHT",-26,0)
msufScaleSlider:SetMinMaxValues(25,150)
msufScaleSlider:SetValueStep(5)
msufScaleSlider:SetObeyStepOnDrag(true)
if msufScaleSlider.SetStepsPerPage then msufScaleSlider:SetStepsPerPage(1) end
HideSliderParts(msufScaleSlider)
StyleDashboardSlider(msufScaleSlider)
msufScaleSlider:EnableMouseWheel(true)
msufScaleSlider:SetScript("OnMouseWheel",function(self,delta) if not delta then return end local v=tonumber((self.GetValue and self:GetValue()) or 100) or 100 v=v+(delta>0 and 5 or -5) self:SetValue(SnapScalePct(v,25,150,5)) end)
msufScaleSlider:SetScript("OnValueChanged",function(self,value) if self.__msufSkip then return end local pct=SnapScalePct(value,25,150,5) if pct~=value then self.__msufSkip=true self:SetValue(pct) self.__msufSkip=nil return end local scale=pct/100 MSUF_SetSavedMsufScale(scale) MSUF_ApplyMsufScale(scale) if msufScaleCur and msufScaleCur.SetText then msufScaleCur:SetText(string.format("Current: %.2f",scale)) end end)
if MSUF_AddTooltip then pcall(MSUF_AddTooltip,msufScaleSlider,"MSUF Frame Scale","Scales only MSUF frames (unitframes + castbars). Use the mouse wheel for 5% steps.") end

local menuScaleLabel=UI_TextTL(scaleCard,"GameFontHighlight",12,-210,"MSUF Slash Menu Scale",MSUF_SkinText)
local menuScaleStatus=UI_TextTL(scaleCard,"GameFontDisableSmall",12,-227,"Applied: 100%  Selected: 100%",MSUF_SkinMuted)
menuScaleStatus:SetWidth(280)
local menuScaleSlider=CreateFrame("Slider","MSUF_DashboardSlashMenuScaleSlider",scaleCard,"OptionsSliderTemplate")
menuScaleSlider:ClearAllPoints()
menuScaleSlider:SetPoint("TOPLEFT",menuScaleStatus,"BOTTOMLEFT",0,-8)
menuScaleSlider:SetPoint("RIGHT",scaleCard,"RIGHT",-26,0)
menuScaleSlider:SetMinMaxValues(25,150)
menuScaleSlider:SetValueStep(5)
menuScaleSlider:SetObeyStepOnDrag(true)
if menuScaleSlider.SetStepsPerPage then menuScaleSlider:SetStepsPerPage(1) end
HideSliderParts(menuScaleSlider)
StyleDashboardSlider(menuScaleSlider)
menuScaleSlider:EnableMouseWheel(true)
menuScaleSlider:SetScript("OnMouseWheel",function(self,delta) if not delta then return end local v=tonumber((self.GetValue and self:GetValue()) or 100) or 100 v=v+(delta>0 and 5 or -5) self:SetValue(SnapScalePct(v,25,150,5)) end)
local function GetAppliedMenuScale(disabled) return clamp(MSUF_GetSavedSlashMenuScale(),0.25,1.5) end
local function GetPendingMenuScale(disabled) local pending=scaleCard._msufPendingMenuScale if pending==nil then pending=GetAppliedMenuScale(disabled) end pending=tonumber(pending) or 1.0 return clamp(pending,0.25,1.5) end
local bMenuApply,bMenuRevert
local function RefreshMenuScaleControls(disabled)
local applied=GetAppliedMenuScale(disabled)
local pending=GetPendingMenuScale(disabled)
local changed=(math.abs(applied-pending)>0.001) and (not disabled)
if menuScaleStatus and menuScaleStatus.SetText then
local txt=string.format("Applied: %d%%  Selected: %d%%",math.floor(applied*100+0.5),math.floor(pending*100+0.5))
if changed then txt=txt.."  |cffffd200Apply|r" end
menuScaleStatus:SetText(txt)
end
SetSliderValueSafe(menuScaleSlider,SnapScalePct(pending*100,25,150,5))
MSUF_SetEnabled(menuScaleSlider,not disabled)
MSUF_SetEnabled(bMenuApply,changed)
MSUF_SetEnabled(bMenuRevert,changed)
if bMenuApply and bMenuApply._msufSetSelected then bMenuApply:_msufSetSelected(changed) end
local a=disabled and 0.55 or 1.0
if menuScaleLabel and menuScaleLabel.SetAlpha then menuScaleLabel:SetAlpha(a) end
if menuScaleStatus and menuScaleStatus.SetAlpha then menuScaleStatus:SetAlpha(a) end
end
menuScaleSlider:SetScript("OnValueChanged",function(self,value)
if self.__msufSkip then return end
local pct=SnapScalePct(value,25,150,5)
if pct~=value then self.__msufSkip=true self:SetValue(pct) self.__msufSkip=nil return end
scaleCard._msufPendingMenuScale=pct/100
RefreshMenuScaleControls(false)
end)
if MSUF_AddTooltip then pcall(MSUF_AddTooltip,menuScaleSlider,"MSUF Slash Menu Scale","Chooses the standalone Slash Menu scale. Drag or use the mouse wheel, then press Apply.") end
local menuRow=MSUF_BuildButtonRowTL(scaleCard,12,-272,{{text="Apply",w=96,h=20,gap=8,skinFn=MSUF_SkinDashboardButton,onClick=function() local scale=GetPendingMenuScale(false) MSUF_SetSavedSlashMenuScale(scale) MSUF_ApplySlashMenuScale(scale,{ignoreDisable=true}) scaleCard._msufPendingMenuScale=nil RefreshMenuScaleControls(false) end},{text="Revert",w=96,h=20,skinFn=MSUF_SkinDashboardButton,onClick=function() scaleCard._msufPendingMenuScale=nil RefreshMenuScaleControls(false) end},},8)
bMenuApply,bMenuRevert=menuRow[1],menuRow[2]
RefreshScaleCard=function()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
local disabled=false
RefreshGlobalScaleControls()
MSUF_SetEnabled(msufScaleSlider,true)
if msufScaleLabel and msufScaleLabel.SetAlpha then msufScaleLabel:SetAlpha(1.0) end
if msufScaleCur and msufScaleCur.SetAlpha then msufScaleCur:SetAlpha(1.0) end
local scale=clamp(MSUF_GetSavedMsufScale(),0.25,1.5)
if msufScaleCur and msufScaleCur.SetText then msufScaleCur:SetText(string.format("Current: %.2f",scale)) end
SetSliderValueSafe(msufScaleSlider,SnapScalePct(scale*100,25,150,5))
RefreshMenuScaleControls(disabled)
end
home._msufRefreshScaleCard=RefreshScaleCard
RefreshScaleCard()

local wagoCard=CreateCard(colR,"Wago Profiles",profileCard,-10)
wagoCard:SetPoint("BOTTOMLEFT",colR,"BOTTOMLEFT",0,0)
wagoCard:SetPoint("BOTTOMRIGHT",colR,"BOTTOMRIGHT",0,0)
local wagoDesc=UI_TextTL(wagoCard,"GameFontDisableSmall",12,-30,"Browse shared MSUF imports on Wago.",MSUF_SkinMuted)
wagoDesc:SetWidth(260)
wagoDesc:SetJustifyH("LEFT")
local MSUF_WAGO_PROFILES_URL="https://wago.io/search/imports/wow/msuf"
local bWagoProfiles=UI_Btn(wagoCard,"Browse Wago Profiles",220,44,"TOPLEFT",wagoDesc,"BOTTOMLEFT",0,-12,function() MSUF_ShowCopyLink("Wago MSUF Profiles",MSUF_WAGO_PROFILES_URL) end,"Wago Profiles","Copies the Wago MSUF profile search link.",MSUF_SkinPrimaryButton)
local wagoHint=UI_Text(wagoCard,"GameFontDisableSmall","TOPLEFT",bWagoProfiles,"BOTTOMLEFT",0,-8,"Copies the Wago link so you can open it in your browser.",MSUF_SkinMuted)
wagoHint:SetWidth(260)
wagoHint:SetJustifyH("LEFT")
local presetDrop=nil
local bLoadPreset=bWagoProfiles
local presetHint=wagoHint
local presetsCard=wagoCard
do local KO_FI_URL="https://ko-fi.com/midnightsimpleunitframes#linkModal"; local PAYPAL_URL="https://www.paypal.com/ncp/payment/H3N2P87S53KBQ"; local PATREON_URL="https://www.patreon.com/cw/MidnightSimpleUnitframes"; local GITHUB_URL="https://github.com/Mapkov2/MidnightSimpleUnitFrames"; local ICON_DIR="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"; local supportLabel=presetsCard:CreateFontString(nil,"OVERLAY","GameFontDisableSmall") supportLabel:SetPoint("BOTTOMLEFT",presetsCard,"BOTTOMLEFT",12,12) supportLabel:SetJustifyH("LEFT") supportLabel:SetText("Support MSUF Development") supportLabel:SetAlpha(0.72) if MSUF_SkinMuted then pcall(MSUF_SkinMuted,supportLabel) end local aboutLine=presetsCard:CreateFontString(nil,"OVERLAY","GameFontDisableSmall") aboutLine:SetPoint("BOTTOMLEFT",supportLabel,"TOPLEFT",0,4) aboutLine:SetJustifyH("LEFT") local aboutVer=_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames","Version") local aboutStr="by |cffccd0d9Mapko|r" if type(aboutVer)=="string" and aboutVer~="" then aboutStr="v"..aboutVer.."  •  by |cffccd0d9Mapko|r  •  with help from |cffccd0d9R41z0r|r" end aboutLine:SetText(aboutStr) aboutLine:SetAlpha(0.65) if MSUF_SkinMuted then pcall(MSUF_SkinMuted,aboutLine) end local row=CreateFrame("Frame",nil,presetsCard) row:SetHeight(24) row:SetWidth(160) row:SetPoint("BOTTOMRIGHT",presetsCard,"BOTTOMRIGHT",-12,10) local function CreateIcon(texFile,size,tooltipTitle,tooltipText,onClick) local b=CreateFrame("Button",nil,row) b:SetSize(size,size) local t=b:CreateTexture(nil,"ARTWORK") t:SetAllPoints() t:SetTexture(ICON_DIR..texFile) local hl=b:CreateTexture(nil,"HIGHLIGHT") hl:SetAllPoints() hl:SetColorTexture(1,1,1,0.10) b:SetScript("OnClick",onClick) if MSUF_AddTooltip then MSUF_AddTooltip(b,tooltipTitle,tooltipText) else b:SetScript("OnEnter",function(self) if not GameTooltip then return end GameTooltip:SetOwner(self,"ANCHOR_TOPLEFT"); GameTooltip:AddLine(tooltipTitle or "",1,1,1) if tooltipText and tooltipText~="" then GameTooltip:AddLine(tooltipText,0.85,0.85,0.85,true) end GameTooltip:Show() end) b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end) end return b end local sz=22 local gap=7 local icons={{tex="Patreon.png",title="Patreon",tip="Click to copy the Patreon support link.",onClick=function() MSUF_ShowCopyLink("Patreon",PATREON_URL) end},{tex="PayPal.png",title="PayPal",tip="Click to copy the PayPal support link.",onClick=function() MSUF_ShowCopyLink("PayPal",PAYPAL_URL) end},{tex="Ko-Fi.png",title="Ko-fi",tip="Click to copy the Ko-fi link.",onClick=function() MSUF_ShowCopyLink("Ko-fi",KO_FI_URL) end},{tex="GitHub.png",title="GitHub",tip="Click to copy the GitHub repository link.",onClick=function() MSUF_ShowCopyLink("GitHub",GITHUB_URL) end},} local prev for _,d in ipairs(icons) do local b=CreateIcon(d.tex,sz,d.title,d.tip,d.onClick) if not prev then b:SetPoint("RIGHT",row,"RIGHT",0,0) else b:SetPoint("RIGHT",prev,"LEFT",-gap,0) end prev=b end end

local adv=CreateCard(home,"Advanced")
adv:ClearAllPoints()
adv:SetPoint("BOTTOMLEFT",home,"BOTTOMLEFT",12,14)
adv:SetPoint("BOTTOMRIGHT",home,"BOTTOMRIGHT",-12,14)
adv:SetHeight(66)
local advHint=UI_TextTL(adv,"GameFontDisableSmall",12,-30,"Fast access to recovery and support tools.",MSUF_SkinMuted)
local advRow=MSUF_BuildButtonRowTL(adv,12,-54,{{text="Print Help",w=100,h=22,gap=8,skinFn=MSUF_SkinDashboardButton,onClick=function() if _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"] then pcall(_G.SlashCmdList["MIDNIGHTSUF"],"help") end end},{text="Factory Reset",w=110,h=22,skinFn=MSUF_SkinDangerButton,onClick=function() MSUF_ShowFactoryResetConfirm() end},{text="Profiles",w=100,h=22,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("profiles") end},{text="Discord",w=88,h=22,skinFn=MSUF_SkinPrimaryButton,onClick=function() if type(MSUF_ShowCopyLink)=="function" then MSUF_ShowCopyLink("Discord","https://discord.gg/JQnhZXnTAK") end end},},8)
local function MSUF_DashboardLayout() local rowW=(actionRow and actionRow.GetWidth and actionRow:GetWidth()) or 0 local wL=(colL and colL.GetWidth and colL:GetWidth()) or 0 local wR=(colR and colR.GetWidth and colR:GetWidth()) or 0 if rowW<=0 or wL<=0 or wR<=0 then return end local actionW=math.floor((rowW-halfGap)/2) if actionW<1 then actionW=1 end if bEdit and bEdit.SetWidth then bEdit:SetWidth(actionW) end if bReset and bReset.SetWidth then bReset:SetWidth(actionW) end local innerL=math.floor(wL-24) local innerR=math.floor(wR-24) if innerL<1 then innerL=1 end if innerR<1 then innerR=1 end if scaleDesc and scaleDesc.SetWidth then scaleDesc:SetWidth(math.max(220,math.min(innerL-24,380))) end local navW=math.floor((innerL-10)/2) if navW<96 then navW=96 end for _,btn in ipairs({bColors,bGameplay,bAuras,bClass}) do if btn and btn.SetWidth then btn:SetWidth(navW) end end if profMeta and profMeta.SetWidth then profMeta:SetWidth(innerR-110) end local ddW=math.floor(innerR-28) if ddW>300 then ddW=300 end if ddW<160 then ddW=160 end if presetDrop and UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(presetDrop,ddW) end if bLoadPreset and bLoadPreset.SetWidth then bLoadPreset:SetWidth(math.max(160,math.min(innerR-24,ddW+24))) end if presetHint and presetHint.SetWidth then presetHint:SetWidth(innerR-24) end if home and home._msufRefreshScaleCard then pcall(home._msufRefreshScaleCard) end end
if not home.__MSUF_DashboardLayoutHooked then home.__MSUF_DashboardLayoutHooked=true if home.HookScript then home:HookScript("OnShow",function() if C_Timer and C_Timer.After then C_Timer.After(0,MSUF_DashboardLayout)
else MSUF_DashboardLayout()
end
end
)
home:HookScript("OnSizeChanged",function() if C_Timer and C_Timer.After then C_Timer.After(0,MSUF_DashboardLayout)
else MSUF_DashboardLayout()
end
end
)
end
end
if C_Timer and C_Timer.After then C_Timer.After(0,MSUF_DashboardLayout)
else MSUF_DashboardLayout()
end
-- Background atmosphere (layered on visible dark navy base)
local MEDIA_DIR="Interface/AddOns/"..tostring(addonName or"MidnightSimpleUnitFrames").."/Media/"
-- Layer 1: Subtle indigo wash (adds slight horizontal color variation)
local bgWash=f:CreateTexture(nil,"BACKGROUND",nil,1)
bgWash:SetTexture(MEDIA_DIR.."Bars/Smoothv2")
bgWash:SetPoint("TOPLEFT",host,"TOPLEFT",0,0)
bgWash:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
bgWash:SetVertexColor(0.14,0.08,0.30,0.25)
-- Layer 2: Vertical depth (lighter top, darker bottom)
local bgDepth=f:CreateTexture(nil,"BACKGROUND",nil,2)
bgDepth:SetTexture(MEDIA_DIR.."Bars/Smoothv2")
bgDepth:SetPoint("TOPLEFT",host,"TOPLEFT",0,0)
bgDepth:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
bgDepth:SetTexCoord(0,0,1,0,0,1,1,1)
bgDepth:SetVertexColor(0.08,0.06,0.20,0.20)
-- Layer 3: Charcoal grain (texture/noise)
local bgGrain=f:CreateTexture(nil,"BACKGROUND",nil,3)
bgGrain:SetTexture(MEDIA_DIR.."Bars/Charcoal")
bgGrain:SetPoint("TOPLEFT",host,"TOPLEFT",0,0)
bgGrain:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
bgGrain:SetVertexColor(0.10,0.08,0.20,0.15)
-- MSUF watermark (bottom-right)
local bgLogo=f:CreateTexture(nil,"BORDER",nil,0)
bgLogo:SetTexture(MEDIA_DIR.."MSUF_MinimapIcon")
bgLogo:SetSize(120,120)
bgLogo:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",-12,12)
bgLogo:SetVertexColor(0.30,0.22,0.55,0.05)
bgLogo:SetBlendMode("ADD")
-- Nav rail: visible purple wash
local navBgWash=navRail:CreateTexture(nil,"BORDER",nil,1)
navBgWash:SetTexture(MEDIA_DIR.."Bars/Smoothv2")
navBgWash:SetPoint("TOPLEFT",navRail,"TOPLEFT",3,-3)
navBgWash:SetPoint("BOTTOMRIGHT",navRail,"BOTTOMRIGHT",-3,3)
navBgWash:SetTexCoord(0,0,1,0,0,1,1,1)
navBgWash:SetVertexColor(0.10,0.06,0.24,0.20)
f._msufTint=bgWash f._msufTintLogo=bgLogo f:SetScript("OnShow",function() S.mirror.host=f._msufMirrorClipHost or f._msufMirrorHost or content if f._msufNavStack and f._msufNavStack._msufTreeReflow then f._msufNavStack._msufTreeReflow() end
if MSUF_PickSessionTip then MSUF_PickSessionTip()
end
if f._msufRefreshStatusBar then pcall(f._msufRefreshStatusBar) end
local startKey=f._msufInitialKey or"home";
local startSubKey=f._msufInitialSubKey;
f._msufInitialKey=nil f._msufInitialSubKey=nil;
S.mirror.currentKey=startKey MSUF_SwitchMirrorPage(startKey,startSubKey)
if _msufIsAlpha then StaticPopup_Show("MSUF_ALPHA_DISCORD") end end
)
f:SetScript("OnHide",function() MSUF_Standalone_SetCastbarTopButtonsHidden(false)
if MSUF_SaveWindowGeometry then MSUF_SaveWindowGeometry(f,f._msufGeomKey or"full")
end
if S.mirror.currentPanel then local _p=S.mirror.currentPanel MSUF_DetachMirroredPanel(_p);
S.mirror.currentPanel=nil if _p and _p.Hide then pcall(_p.Hide,_p) end end
end
)
f:Hide()
S.win=f return f end
local function MSUF_ToggleOptionsWindow(key,subkey) local w=MSUF_CreateOptionsWindow()
if w:IsShown()
then if key and S.mirror.currentKey~=key then MSUF_SwitchMirrorPage(key,subkey) return end
if subkey then MSUF_SwitchMirrorPage(key or S.mirror.currentKey or"home",subkey) return end
_TScaleDismiss(w,TRANS_CLOSE) return end
w._msufInitialKey=key w._msufInitialSubKey=subkey or"home"w._msufInitialSubKey=subkey _TScaleReveal(w,TRANS_OPEN) end
local function MSUF_ShowOptionsWindow(key,subkey) local w=MSUF_CreateOptionsWindow()
key=key or"home"if w.IsShown and w:IsShown()
then if key and S and S.mirror and S.mirror.currentKey~=key then MSUF_SwitchMirrorPage(key,subkey)
elseif key then MSUF_SwitchMirrorPage(key,subkey)
end
return w end
w._msufInitialKey=key w._msufInitialSubKey=subkey _TScaleReveal(w,TRANS_OPEN)
return w end
local function MSUF_HideOptionsWindow() if S and S.win and S.win.IsShown and S.win:IsShown()
then _TScaleDismiss(S.win,TRANS_CLOSE)
end
end
_G.MSUF_ShowStandaloneOptionsWindow=MSUF_ShowOptionsWindow _G.MSUF_OpenStandaloneOptionsWindow=MSUF_ShowOptionsWindow _G.MSUF_HideStandaloneOptionsWindow=MSUF_HideOptionsWindow
-- Export page-switch for MSUF_Search.lua result row navigation
_G.MSUF_SwitchMirrorPage=MSUF_SwitchMirrorPage _G.MSUF_OpenPage=function(key,subkey) key=(key or"home")

-- Export current page so MSUF_Search.lua can temporarily switch sub-pages while building the auto-index,
-- then restore the user's current location. (Standalone menu only; zero combat overhead.)
_G.MSUF_GetCurrentMirrorPage=function()
local mk=(S and S.mirror and S.mirror.currentKey) or nil
local ms=(S and S.mirror and S.mirror.currentSubKey) or nil
return mk,ms
end

_G.MSUF_GetMirrorPages=function() return MIRROR_PAGES end
if type(key)=="string"then key=key:lower()
else key="home"end
if key=="menu"or key=="flash"then key="home"elseif key=="options"then key="main"elseif key=="unit"or key=="frames"then key="main"elseif key=="boss_castbar"or key=="bosscastbar"then key="castbar"subkey=subkey or"boss"end
if key=="player"or key=="target"or key=="focus"or key=="targettarget"or key=="pet"or key=="boss"then subkey=key key="main"end
if key=="bars"or key=="fonts"or key=="auras"or key=="misc"or key=="profiles"then subkey=key key="main"end
if MSUF_IsCastbarKey(key)
and(subkey==nil or subkey==true)
then end
local info=(type(MSUF_GetMirrorPageInfo)=="function")
and MSUF_GetMirrorPageInfo(key)
or nil if info then local panel if type(info.build)=="function"then panel=info.build()
end
if(key~="home")
and(type(info.build)=="function")
and(not panel)
then MSUF_ShowOptionsWindow("home") return false end
MSUF_ShowOptionsWindow(key,subkey) return true end
MSUF_ShowOptionsWindow("home") return false end
_G.MSUF_OpenOptionsMenu=function() if _G.MSUF_OpenPage then _G.MSUF_OpenPage("home")
else MSUF_ShowOptionsWindow("home")
end
end
local function MSUF_InstallSlashHook() if _G.MSUF_SlashHooked then return end
if SlashCmdList and SlashCmdList["MIDNIGHTSUF"]
then local original=SlashCmdList["MIDNIGHTSUF"]
SlashCmdList["MIDNIGHTSUF"]=function(msg) local raw=msg or""raw=raw:gsub("^%s+","")
local first,rest=raw:match("^(%S+)%s*(.-)%s*$")
first=first and first:lower()
or""rest=rest or""local function openKey(key) MSUF_ToggleOptionsWindow(key) end
if first==""then openKey("home") return end
if first=="menu"or first=="home"then openKey("home") return end
if first=="options"then openKey("main") return end
if first=="colors"or first=="colours"then openKey("colors") return end
if first=="gameplay"then openKey("gameplay") return end
if first=="castbar"then local sub=rest and rest:lower()
or""if sub~=""then MSUF_ToggleOptionsWindow("castbar",sub)
else openKey("castbar")
end
return end
if first=="profiles"then openKey("profiles") return end
if first=="versiontest"then if _G.MSUF_VersionCheck_DebugFakeUpdate then _G.MSUF_VersionCheck_DebugFakeUpdate() end return end
return original(msg) end
end
SLASH_MSUFOPTIONS1="/msufoptions"SlashCmdList["MSUFOPTIONS"]=function() MSUF_ToggleOptionsWindow("main") end
_G.MSUF_SlashHooked=true end
MSUF_InstallSlashHook()
local scaleEvent=CreateFrame("Frame")
scaleEvent:RegisterEvent("PLAYER_LOGIN")
scaleEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
scaleEvent:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleEvent:SetScript("OnEvent",function(_,event,arg1)
MSUF_ApplyMsufScale(MSUF_GetSavedMsufScale());
local want=MSUF_GetDesiredGlobalScaleFromDB()
if want then if event=="PLAYER_LOGIN"then MSUF_SetGlobalUiScale(want,true);
MSUF_EnsureGlobalUiScaleApplied(true)
else MSUF_EnsureGlobalUiScaleApplied(true)
end
end
end
)
if C_Timer and C_Timer.After then C_Timer.After(0,function()
MSUF_ApplyMsufScale(MSUF_GetSavedMsufScale());
local want=MSUF_GetDesiredGlobalScaleFromDB()
if want then MSUF_SetGlobalUiScale(want,true);
MSUF_EnsureGlobalUiScaleApplied(true)
end
end
)
end
