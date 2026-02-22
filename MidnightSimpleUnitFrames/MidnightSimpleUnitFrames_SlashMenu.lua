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
local L=ns.L or (_G and _G.MSUF_L)
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
local S={win=nil,content=nil,scale={},mirror={host=nil,currentKey="home",currentPanel=nil,homePanel=nil,homeToolsApi=nil,tipText=nil,},}
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
local win=_G and _G.MSUF_StandaloneOptionsWindow;
local b=win and win._msufDashEditBtn if b and b._msufSetSelected and type(MSUF_IsMSUFEditModeActive)=="function"then b:_msufSetSelected(MSUF_IsMSUFEditModeActive())
end
local prof=(_G and _G.MSUF_ActiveProfile)
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
local MSUF_THEME={bgR=0.03,bgG=0.05,bgB=0.12,bgA=0.95,edgeR=0.10,edgeG=0.20,edgeB=0.45,edgeA=0.90,titleR=0.75,titleG=0.88,titleB=1.00,titleA=1.00,textR=0.86,textG=0.92,textB=1.00,textA=1.00}
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
_G.MSUF_GetNextTip=MSUF_GetNextTip local function MSUF_ForceItalicFont(fs) if not fs or not fs.GetFont or not fs.SetFont then return end
local font,size,flags=fs:GetFont()
if not font or not size then return end
flags=flags or""if flags:find("ITALIC")
then return end
if flags~=""then flags=flags..",ITALIC"else flags="ITALIC"end
fs:SetFont(font,size,flags) end
local MSUF_PRESETS=(ns and ns.MSUF_PRESETS)
or _G.MSUF_PRESETS if type(MSUF_PRESETS)~="table"then MSUF_PRESETS={}
end
if ns then ns.MSUF_PRESETS=MSUF_PRESETS end if _G then _G.MSUF_PRESETS=MSUF_PRESETS end
local MSUF_PRESET_ALLOWED_KEYS={"general","player","target","focus","pet","targettarget","boss","bars","auras","gameplay","npcColors","classColors","shortenNames",}
local function MSUF_WipeTable(t) if type(t)~="table"then return end
for k in pairs(t)
do t[k]=nil end
end
local function MSUF_DeepCopy(src,depth) if type(src)~="table"then return src end
depth=(depth or 0)+1 if depth>30 then return {} end
local dst={}
for k,v in pairs(src)
do if type(v)=="table"then dst[k]=MSUF_DeepCopy(v,depth)
else dst[k]=v end
end
return dst end
local function MSUF_CopyValue(v) if type(v)~="table"then return v end
if type(CopyTable)=="function"then return CopyTable(v) end
return MSUF_DeepCopy(v) end
local MSUF_ShowReloadRecommendedPopup local function MSUF_ApplyPreset(presetName) local preset=MSUF_PRESETS and MSUF_PRESETS[presetName]
if type(preset)~="table"then print("|cffff3333MSUF:|r Preset not found: "..tostring(presetName)) return end
if type(MSUF_InitProfiles)=="function"then pcall(MSUF_InitProfiles)
end
if type(MSUF_DB)~="table"then print("|cffff3333MSUF:|r DB not ready (MSUF_DB missing).") return end
local importStr=preset._msufImportString or preset._msufImport if type(importStr)=="string"then local okPrefix,prefix=pcall(string.match,importStr,"^%s*(MSUF%d+):")
if okPrefix and(prefix=="MSUF2"or prefix=="MSUF3")
then local imp=_G and _G.MSUF_ImportFromString if type(imp)=="function"then pcall(imp,importStr)
if type(ApplyAllSettings)=="function"then pcall(ApplyAllSettings)
end
if type(UpdateAllFonts)=="function"then pcall(UpdateAllFonts)
end
print("|cff00ff00MSUF:|r Loaded preset: "..tostring(presetName))
if type(MSUF_ShowReloadRecommendedPopup)=="function"then MSUF_ShowReloadRecommendedPopup("Preset: "..tostring(presetName))
end
return else print("|cffff3333MSUF:|r Cannot load this preset (MSUF_ImportFromString missing).")
end
end
end
MSUF_WipeTable(MSUF_DB)
for _,key in ipairs(MSUF_PRESET_ALLOWED_KEYS)
do local val=preset[key]
if val~=nil then MSUF_DB[key]=MSUF_CopyValue(val)
end
end
if type(EnsureDB)=="function"then pcall(EnsureDB)
end
if type(ApplyAllSettings)=="function"then pcall(ApplyAllSettings)
end
if type(UpdateAllFonts)=="function"then pcall(UpdateAllFonts)
end
print("|cff00ff00MSUF:|r Loaded preset: "..tostring(presetName))
if type(MSUF_ShowReloadRecommendedPopup)=="function"then MSUF_ShowReloadRecommendedPopup("Preset: "..tostring(presetName))
end
end
local function MSUF_GetPresetNames() local names={}
if type(MSUF_PRESETS)~="table"then return names end
for name in pairs(MSUF_PRESETS)
do table.insert(names,name)
end
table.sort(names) return names end
local MSUF_PENDING_PRESET=nil local function MSUF_ShowPresetConfirm(presetName) if not presetName or presetName==""then return end
MSUF_PENDING_PRESET=presetName local preset=MSUF_PRESETS and MSUF_PRESETS[presetName];
local warn=preset and preset._msufWarning if warn~=nil and warn~=""then warn=tostring(warn)
else warn=nil end
if not StaticPopupDialogs["MSUF_LOAD_PRESET_CONFIRM"]
then StaticPopupDialogs["MSUF_LOAD_PRESET_CONFIRM"]={text="Load preset: %s?\n\nThis will overwrite your CURRENT active profile settings.",button1=YES,button2=NO,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() if MSUF_PENDING_PRESET then MSUF_ApplyPreset(MSUF_PENDING_PRESET)
end
MSUF_PENDING_PRESET=nil end
,OnCancel=function() MSUF_PENDING_PRESET=nil end
,}
end
local dlg=StaticPopupDialogs["MSUF_LOAD_PRESET_CONFIRM"]
if dlg then if warn then dlg.text="Load preset: %s?\n\n|cffffaa00Warning:|r "..warn.."\n\nThis will overwrite your CURRENT active profile settings."else dlg.text="Load preset: %s?\n\nThis will overwrite your CURRENT active profile settings."end
end
StaticPopup_Show("MSUF_LOAD_PRESET_CONFIRM",presetName) end
local MSUF_PENDING_RELOAD_RECOMMEND_LABEL=nil MSUF_ShowReloadRecommendedPopup=function(label) if InCombatLockdown and InCombatLockdown()
then if type(MSUF_Print)=="function"then MSUF_Print("Reload recommended (cannot show popup in combat).")
else print("|cffffaa00MSUF:|r Reload recommended (cannot show popup in combat).")
end
return end
MSUF_PENDING_RELOAD_RECOMMEND_LABEL=tostring(label or"")
if MSUF_PENDING_RELOAD_RECOMMEND_LABEL==""then MSUF_PENDING_RELOAD_RECOMMEND_LABEL="these changes"end
if not StaticPopupDialogs["MSUF_RELOAD_RECOMMENDED"]
then StaticPopupDialogs["MSUF_RELOAD_RECOMMENDED"]={text="MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?",button1="Reload",button2="Not now",timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() MSUF_PENDING_RELOAD_RECOMMEND_LABEL=nil if type(ReloadUI)=="function"then ReloadUI()
end
end
,OnCancel=function() MSUF_PENDING_RELOAD_RECOMMEND_LABEL=nil end
,}
end
StaticPopup_Show("MSUF_RELOAD_RECOMMENDED",MSUF_PENDING_RELOAD_RECOMMEND_LABEL) end
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
if border and border.SetVertexColor then border:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.90)
end
if bg and bg.SetVertexColor then bg:SetVertexColor(0.09,0.10,0.12,0.92)
end
btn._msufBtnBorder=border btn._msufBtnBG=bg btn._msufBtnBG_base={0.09,0.10,0.12,0.92}
btn._msufBtnBG_hover={0.10,0.11,0.13,0.98}
btn._msufBtnBG_pressed={0.08,0.09,0.11,0.98}
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
btn:SetScript("OnEnable",function(self,...) if self._msufBtnBG then self._msufBtnBG:SetVertexColor(0.09,0.10,0.12,0.92)
end
if self._msufBtnBorder and self._msufBtnBorder.SetVertexColor then self._msufBtnBorder:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.90)
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
if active and active.SetVertexColor then active:SetVertexColor(0.16,0.36,0.80,0.55)
end
if border and border.SetVertexColor then border:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.90)
end
if bg and bg.SetVertexColor then if isIndented then bg:SetVertexColor(0.09,0.10,0.12,0.82)
else bg:SetVertexColor(0.09,0.10,0.12,0.92)
end
end
btn._msufNavBorder=border btn._msufNavBG=bg local fs=btn.GetFontString and btn:GetFontString()
if fs and fs.SetTextColor then if isHeader then fs:SetTextColor(0.86,0.92,1.00,0.92)
else if isIndented then fs:SetTextColor(0.80,0.88,1.00,0.92)
else fs:SetTextColor(0.82,0.90,1.00,1.00)
end
end
end
btn._msufApplyNavState=function(self,activeState,hovered) if self._msufNavActive3 then if activeState then self._msufNavActive3:Show()
else self._msufNavActive3:Hide()
end
end
activeState=activeState and true or false hovered=hovered and true or false local fs2=self.GetFontString and self:GetFontString()
if fs2 and fs2 .SetTextColor then if activeState then fs2:SetTextColor(0.92,0.96,1.00,1.00)
else if isHeader then fs2:SetTextColor(0.86,0.92,1.00,0.92)
else if isIndented then fs2:SetTextColor(0.80,0.88,1.00,0.92)
else fs2:SetTextColor(0.82,0.90,1.00,1.00)
end
end
end
end
if self._msufNavBG and self._msufNavBG.SetVertexColor then if activeState then self._msufNavBG:SetVertexColor(0.12,0.22,0.40,0.98)
else if hovered then if isIndented then self._msufNavBG:SetVertexColor(0.10,0.11,0.13,0.90)
else self._msufNavBG:SetVertexColor(0.10,0.11,0.13,0.99)
end
else if isIndented then self._msufNavBG:SetVertexColor(0.09,0.10,0.12,0.82)
else self._msufNavBG:SetVertexColor(0.09,0.10,0.12,0.92)
end
end
if self._msufNavBorder and self._msufNavBorder.SetVertexColor then if activeState then self._msufNavBorder:SetVertexColor(0.30,0.60,1.00,1.00)
else if hovered then self._msufNavBorder:SetVertexColor(0.22,0.45,0.90,0.95)
else self._msufNavBorder:SetVertexColor(MSUF_PILL_EDGE_R,MSUF_PILL_EDGE_G,MSUF_PILL_EDGE_B,0.80)
end
end
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
bgHost:SetBackdropColor(0.08,0.09,0.11,0.92)
if bgHost.SetBackdropBorderColor then bgHost:SetBackdropBorderColor(0,0,0,0.92)
end
end
btn._msufDashBGFrame=bgHost local bg=btn:CreateTexture(nil,"BACKGROUND")
bg:SetTexture("Interface/Buttons/WHITE8X8")
bg:SetAllPoints(bgHost)
bg:SetVertexColor(0.09,0.10,0.12,0.92)
if btn._msufDashBGFrame and btn._msufDashBGFrame.SetBackdrop then bg:SetAlpha(0.01)
end
btn._msufDashBG=bg local hover=btn:CreateTexture(nil,"HIGHLIGHT")
hover:SetTexture("Interface/Buttons/WHITE8X8")
hover:SetAllPoints(bg)
hover:SetVertexColor(0.25,0.55,1.0,0.18)
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
btn:SetScript("OnEnable",function(self,...) if self._msufDashBG then self._msufDashBG:SetVertexColor(0.08,0.09,0.11,0.92)
end
ApplyText(self._msufDashIsSelected)
if oldEnable then pcall(oldEnable,self,...)
end
end
) end
local function MSUF_IsYellowish(r,g,b) if not r or not g or not b then return false end
if r>=0.88 and g>=0.68 and b<=0.35 and(g>=(b+0.25))
then return true end
return false end
local function MSUF_ApplyWhiteTextToFrame(root) if not root then return end
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
local orig=obj.__MSUF_FontOrig pcall(obj.SetFont,obj,orig.font,(orig.size or size)+bump,orig.flags) end
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
local function MSUF_ApplySlashMenuScale(scale,opts) local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil if g and g.disableScaling and not(opts and opts.ignoreDisable)
then return end
scale=tonumber(scale)
if not scale then return end
scale=clamp(scale,0.25,1.5)
local win=_G and _G.MSUF_StandaloneOptionsWindow
if win and win.SetScale then pcall(win.SetScale,win,scale)
end
end
local function MSUF_IsScalingDisabled() local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil return (g and g.disableScaling)
and true or false end
local _MSUF_pendingMsufScale;
local _MSUF_pendingGlobalScale;
local _MSUF_pendingDisableScaling;
local _MSUF_pendingReloadOnScalingOff;
local _MSUF_scaleApplyWatcher local MSUF_EnsureScaleApplyAfterCombat local function MSUF_ApplyMsufScale(scale,opts) if MSUF_IsScalingDisabled()
and not(opts and opts.ignoreDisable)
then return end
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
local _MSUF_lastGlobalCVarScale local _MSUF_lastGlobalUiParentScale local function MSUF_GetCurrentGlobalUiScale() if UIParent and UIParent.GetScale then return tonumber(UIParent:GetScale()) end
return nil end
local function MSUF_SetCVarIfChanged(name,value) if not name or value==nil then return end
local v=tostring(value)
if C_CVar and C_CVar.GetCVar and C_CVar.SetCVar then local cur=C_CVar.GetCVar(name)
if cur~=v then pcall(C_CVar.SetCVar,name,v)
end
return end
if GetCVar and SetCVar then local cur=GetCVar(name)
if cur~=v then pcall(SetCVar,name,v)
end
end
end
local function MSUF_EnforceUIParentScale(scale) scale=tonumber(scale)
if not scale or scale<=0 then return end
scale=clamp(scale,0.3,2.0)
if not(UIParent and UIParent.SetScale)
then return end
local cur=nil if UIParent.GetScale then cur=tonumber(UIParent:GetScale())
end
cur=cur or 0 if math.abs(cur-scale)>0.001 then pcall(UIParent.SetScale,UIParent,scale)
end
_MSUF_lastGlobalUiParentScale=scale end
local function MSUF_ScheduleUIParentNudges(scale) if MSUF_IsScalingDisabled()
then return end
if not(C_Timer and C_Timer.After)
then return end
scale=tonumber(scale)
if not scale or scale<=0 then return end
local want=scale local function nudge() if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingGlobalScale=want if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
return end
MSUF_EnforceUIParentScale(want) end
C_Timer.After(0.05,nudge)
C_Timer.After(0.25,nudge)
C_Timer.After(0.60,nudge) end
local function MSUF_SetGlobalUiScale(scale,silent,opts) opts=opts or{}
if MSUF_IsScalingDisabled()
and not opts.ignoreDisable then return end
local applyCVars=(opts.applyCVars~=false)
and true or false scale=tonumber(scale)
if not scale or scale<=0 then return end
scale=clamp(scale,0.3,2.0)
if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingGlobalScale=scale if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
if not silent then MSUF_Print("Cannot change global UI scale in combat. Will apply after combat.")
end
return end
if applyCVars then local cvarScale=clamp(scale,0.3,2.0)
if _MSUF_lastGlobalCVarScale~=cvarScale then MSUF_SetCVarIfChanged("useUIScale","1")
MSUF_SetCVarIfChanged("useUiScale","1")
MSUF_SetCVarIfChanged("uiScale",cvarScale)
MSUF_SetCVarIfChanged("uiscale",cvarScale)
_MSUF_lastGlobalCVarScale=cvarScale end
end
MSUF_EnforceUIParentScale(scale)
MSUF_ScheduleUIParentNudges(scale)
if not silent then local cvarScale=clamp(scale,0.3,2.0)
MSUF_Print(string.format("Global UI scale set to %.4f (CVar %.4f)",scale,cvarScale))
end
end
MSUF_EnsureScaleApplyAfterCombat=function() if _MSUF_scaleApplyWatcher then return end
if not CreateFrame then return end
local f=CreateFrame("Frame")
_MSUF_scaleApplyWatcher=f f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent",function() if InCombatLockdown and InCombatLockdown()
then return end
if _MSUF_pendingDisableScaling then _MSUF_pendingDisableScaling=nil;
_MSUF_pendingMsufScale=nil _MSUF_pendingGlobalScale=nil;
MSUF_ResetGlobalUiScale(true)
MSUF_ApplyMsufScale(1.0,{ignoreDisable=true})
elseif MSUF_IsScalingDisabled()
then _MSUF_pendingMsufScale=nil;
_MSUF_pendingGlobalScale=nil else local s=_MSUF_pendingMsufScale;
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
local function MSUF_ResetGlobalUiScale(silent) if InCombatLockdown and InCombatLockdown()
then if not silent then MSUF_Print("Cannot reset global UI scale in combat.")
end
return end
MSUF_SetCVarIfChanged("useUIScale","0")
MSUF_SetCVarIfChanged("useUiScale","0")
MSUF_SetCVarIfChanged("uiScale","1.0")
MSUF_SetCVarIfChanged("uiscale","1.0")
if UIParent and UIParent.SetScale then pcall(UIParent.SetScale,UIParent,1.0)
end
_MSUF_lastGlobalCVarScale=nil _MSUF_lastGlobalUiParentScale=nil if not silent then MSUF_Print("Global UI scale reset (fallback).")
end
end
local function MSUF_SetScalingDisabled(disable,silent) local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil if not g then return end
disable=disable and true or false g.disableScaling=disable if not disable then _MSUF_pendingDisableScaling=nil return end
g.globalUiScalePreset="auto"g.globalUiScaleValue=nil MSUF_SetSavedMsufScale(1.0)
if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingDisableScaling=true if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
if not silent then MSUF_Print("MSUF scaling disabled. Will fully reset after combat.")
end
return end
MSUF_ResetGlobalUiScale(true)
MSUF_ApplyMsufScale(1.0,{ignoreDisable=true})
_MSUF_pendingDisableScaling=nil _MSUF_pendingMsufScale=nil _MSUF_pendingGlobalScale=nil if not silent then MSUF_Print("MSUF scaling disabled (Blizzard handles scaling now).")
end
end
_G.MSUF_SetScalingDisabled=MSUF_SetScalingDisabled local function MSUF_SaveGlobalPreset(preset,scale) local g=MSUF_EnsureGeneral()
if not g then return end
g.globalUiScalePreset=preset g.globalUiScaleValue=scale end
local function MSUF_GetDesiredGlobalScaleFromDB() local g=MSUF_EnsureGeneral()
if not g then return nil end
if g.disableScaling then return nil end
local preset=g.globalUiScalePreset if preset=="1080p"then return UI_SCALE_1080 elseif preset=="1440p"then return UI_SCALE_1440 elseif preset=="4k"then return UI_SCALE_4K elseif preset=="custom"and g.globalUiScaleValue then return tonumber(g.globalUiScaleValue) end
return nil end
local MSUF_SCALE_GUARD={suppressUntil=0}
local function MSUF_EnsureGlobalUiScaleApplied(silent) if MSUF_IsScalingDisabled()
then return end
local now=(GetTime and GetTime())
or 0 if now<(MSUF_SCALE_GUARD.suppressUntil or 0)
then return end
local want=MSUF_GetDesiredGlobalScaleFromDB()
want=tonumber(want)
if not want or want<=0 then return end
local have=MSUF_GetCurrentGlobalUiScale()
have=tonumber(have)
or want local diff=math.abs(have-want)
if diff>0.001 then MSUF_SCALE_GUARD.suppressUntil=now+0.10 if InCombatLockdown and InCombatLockdown()
then _MSUF_pendingGlobalScale=want if MSUF_EnsureScaleApplyAfterCombat then MSUF_EnsureScaleApplyAfterCombat()
end
return end
MSUF_EnforceUIParentScale(want)
if C_Timer and C_Timer.After then C_Timer.After(0,function() MSUF_EnforceUIParentScale(want) end
)
C_Timer.After(0.25,function() MSUF_EnforceUIParentScale(want) end
)
C_Timer.After(1.0,function() MSUF_EnforceUIParentScale(want) end
)
end
end
end
local function MSUF_IsMSUFEditModeActive() local st=_G and _G.MSUF_EditState if type(st)=="table"and st.active~=nil then return st.active and true or false end
if _G and type(_G.MSUF_IsEditModeActive)=="function"then local ok,res=pcall(_G.MSUF_IsEditModeActive)
if ok then return res and true or false end
end
if _G and _G.MSUF_EDITMODE_ACTIVE~=nil then return _G.MSUF_EDITMODE_ACTIVE and true or false end
return false end
local function MSUF_TryHookEditModeForDashboard() if _G and _G.__MSUF_DashEditHooked then return end
if not hooksecurefunc then return end
if _G and type(_G.MSUF_SetMSUFEditModeDirect)=="function"then hooksecurefunc("MSUF_SetMSUFEditModeDirect",function(active) local win=_G and _G.MSUF_StandaloneOptionsWindow;
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

local btn1080,btn1440,btn4k,btnAuto
local presetRow=MSUF_BuildButtonRow(parent,globalCur,"TOPLEFT","BOTTOMLEFT",0,-8,{
{text="1080",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 1080",tipBody="Applies MSUF's global scale preset for 1080p-like setups and reloads your UI. Auto restores Blizzard scaling on reload.",onClick=function()
MSUF_ShowReloadConfirm("Global UI Scale: 1080p",function()
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false,true)
end
MSUF_SaveGlobalPreset("1080p",UI_SCALE_1080)
MSUF_SetGlobalUiScale(UI_SCALE_1080,true)
ReloadUI()
end)
end},
{text="1440",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 1440",tipBody="Applies MSUF's global scale preset for 1440p-like setups and reloads your UI. Auto restores Blizzard scaling on reload.",onClick=function()
MSUF_ShowReloadConfirm("Global UI Scale: 1440p",function()
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false,true)
end
MSUF_SaveGlobalPreset("1440p",UI_SCALE_1440)
MSUF_SetGlobalUiScale(UI_SCALE_1440,true)
ReloadUI()
end)
end},
{text="4K",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: 4K",tipBody="Applies MSUF's global scale preset for 4K (2160p) setups (0.3556) and reloads your UI. Auto restores Blizzard scaling on reload.",onClick=function()
MSUF_ShowReloadConfirm("Global UI Scale: 4K (2160p)",function()
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false,true)
end
MSUF_SaveGlobalPreset("4k",UI_SCALE_4K)
MSUF_SetGlobalUiScale(UI_SCALE_4K,true)
ReloadUI()
end)
end},
{text="Auto",w=segW,h=segH,skinFn=MSUF_SkinDashboardButton,tipTitle="Global UI Scale: Auto",tipBody="Stops enforcing MSUF global scale and restores your previous Blizzard UI scale.",onClick=function()
MSUF_ShowReloadConfirm("Global UI Scale: Auto",function()
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false,true)
end
MSUF_SaveGlobalPreset("auto",nil)
MSUF_ResetGlobalUiScale(true)
ReloadUI()
end)
end},
},segGap)
btn1080,btn1440,btn4k,btnAuto=presetRow[1],presetRow[2],presetRow[3],presetRow[4]

local resetW=120
local offW=180
local msufReset,msufOff
local row=MSUF_BuildButtonRow(parent,btn1080 or globalCur,"TOPLEFT","BOTTOMLEFT",0,-10,{
{text="Reset",w=resetW,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Reset UI Scale",tipBody="Resets the global UI scale back to 100% (1.0) and marks it as Custom preset.",onClick=function()
do local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil if g then g.disableScaling=false end
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false,true)
end
end
MSUF_SaveGlobalPreset("custom",1.0)
MSUF_SetGlobalUiScale(1.0,true)
if api.Refresh then api.Refresh()
end
end},
{text="Scaling OFF",w=offW,h=18,skinFn=MSUF_SkinDashboardButton,tipTitle="Disable ALL MSUF scaling",tipBody="Turns off all scaling MSUF applies (global UI scale + MSUF unitframe scale + Slash Menu scale), then reloads your UI. Blizzard handles scaling.",onClick=function()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
local isDisabled=g and g.disableScaling
if isDisabled then
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false,true)
else if g then g.disableScaling=false end end
MSUF_ApplySlashMenuScale(MSUF_GetSavedSlashMenuScale(),{ignoreDisable=true})
if api.Refresh then api.Refresh()
end
return
end
if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(true,false)
MSUF_SetSavedSlashMenuScale(1.0)
MSUF_ApplySlashMenuScale(1.0,{ignoreDisable=true})
else
MSUF_ResetGlobalUiScale(true)
MSUF_SetSavedMsufScale(1.0)
MSUF_ApplyMsufScale(1.0)
MSUF_SetSavedSlashMenuScale(1.0)
MSUF_ApplySlashMenuScale(1.0,{ignoreDisable=true})
if g then g.disableScaling=true g.globalUiScalePreset="auto"g.globalUiScaleValue=nil end
end
if api.Refresh then api.Refresh()
end
MSUF_RequestReloadSafe()
end},
},8)
msufReset,msufOff=row and row[1],row and row[2]

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

-- Slash menu scale slider (scales only the MSUF standalone options window)
local menuScaleLabel=UI_Text(parent,"GameFontHighlight","TOPLEFT",msufScaleSlider,"BOTTOMLEFT",0,-18,"MSUF Slash Menu Scale",MSUF_SkinText)
local menuScaleCur=UI_Text(parent,"GameFontHighlightSmall","TOPLEFT",menuScaleLabel,"BOTTOMLEFT",0,-6,"Current: ...",MSUF_SkinText)
local menuScaleSlider=CreateFrame("Slider","MSUF_Tools_SlashMenuScaleSlider",parent,"OptionsSliderTemplate")
menuScaleSlider:ClearAllPoints()
menuScaleSlider:SetPoint("TOP",menuScaleCur,"BOTTOM",0,-8)
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

local function MSUF_UpdateSlashMenuScaleRow(scale)
scale=tonumber(scale) or 1.0
scale=clamp(scale,0.25,1.5)
local pct=math.floor(scale*100+0.5)
if menuScaleCur and menuScaleCur.SetText then menuScaleCur:SetText(string.format("Current: %.2f (%d%%)",scale,pct)) end
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
MSUF_SetSavedSlashMenuScale(scale)
MSUF_ApplySlashMenuScale(scale,{ignoreDisable=true})
MSUF_UpdateSlashMenuScaleRow(scale)
end)

if MSUF_AddTooltip then pcall(MSUF_AddTooltip,menuScaleSlider,"MSUF Slash Menu Scale","TIP: Hover this slider and use the Mouse Wheel to change the scale in 5% steps.\n\nScales only the MSUF Slash Menu window. Range 25%–150% (0.25–1.50). Drag or click to adjust. Applied immediately.") end

api.ui={title=title,globalCur=globalCur,btn1080=btn1080,btn1440=btn1440,btn4k=btn4k,btnAuto=btnAuto,msufReset=msufReset,msufOff=msufOff,msufScaleLabel=msufScaleLabel,msufScaleCur=msufScaleCur,msufScaleSlider=msufScaleSlider,menuScaleLabel=menuScaleLabel,menuScaleCur=menuScaleCur,menuScaleSlider=menuScaleSlider,}

function api.UpdateEnabledStates()
local g=MSUF_EnsureGeneral and MSUF_EnsureGeneral()
or nil
local disabled=g and g.disableScaling
MSUF_SetEnabled(btn1080,not disabled)
MSUF_SetEnabled(btn1440,not disabled)
MSUF_SetEnabled(btn4k,not disabled)
MSUF_SetEnabled(btnAuto,not disabled)
MSUF_SetEnabled(msufReset,not disabled)
MSUF_SetEnabled(msufScaleSlider,not disabled)
MSUF_SetEnabled(menuScaleSlider,not disabled)
if msufScaleLabel and msufScaleLabel.SetAlpha then msufScaleLabel:SetAlpha(disabled and 0.55 or 1.0) end
if msufScaleCur and msufScaleCur.SetAlpha then msufScaleCur:SetAlpha(disabled and 0.55 or 1.0) end
if menuScaleLabel and menuScaleLabel.SetAlpha then menuScaleLabel:SetAlpha(disabled and 0.55 or 1.0) end
if menuScaleCur and menuScaleCur.SetAlpha then menuScaleCur:SetAlpha(disabled and 0.55 or 1.0) end
return disabled and true or false
end

function api.Layout()
local pw=(parent.GetWidth and parent:GetWidth())
or 0
if not pw or pw<=1 then return end
local avail=pw-20
local gap=segGap
if gap==nil then gap=8 end
local n=4
local totalGap=(n-1)*gap
local wEach=math.floor((avail-totalGap)/n)
if wEach<1 then wEach=1 end
if btn1080 and btn1080.SetWidth then btn1080:SetWidth(wEach)
end
if btn1440 and btn1440.SetWidth then btn1440:SetWidth(wEach)
end
if btn4k and btn4k.SetWidth then btn4k:SetWidth(wEach)
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
local preset=g and g.globalUiScalePreset
local disabled=g and g.disableScaling
if api.UpdateEnabledStates then api.UpdateEnabledStates()
end
local cur=MSUF_GetCurrentGlobalUiScale()
local ms=clamp(MSUF_GetSavedMsufScale(),0.25,1.5)
local pct=MSUF_SnapMsufScalePct(ms*100)
local scale=pct/100
MSUF_UpdateMsufScaleRow(scale)
if msufScaleSlider and msufScaleSlider.SetValue then msufScaleSlider.__msufSkip=true; msufScaleSlider:SetValue(pct); msufScaleSlider.__msufSkip=nil end
if math.abs(ms-scale)>0.001 then MSUF_SetSavedMsufScale(scale); MSUF_ApplyMsufScale(scale) end


-- Slash menu scale: show + apply
local sms=clamp(MSUF_GetSavedSlashMenuScale(),0.25,1.5)
local smPct=MSUF_SnapMsufScalePct(sms*100)
local smScale=smPct/100
if disabled then smScale=1.0 smPct=100 end
MSUF_UpdateSlashMenuScaleRow(smScale)
if menuScaleSlider and menuScaleSlider.SetValue then menuScaleSlider.__msufSkip=true; menuScaleSlider:SetValue(smPct); menuScaleSlider.__msufSkip=nil end
if not disabled and math.abs(sms-smScale)>0.001 then MSUF_SetSavedSlashMenuScale(smScale) end
MSUF_ApplySlashMenuScale(smScale,{ignoreDisable=true})

if disabled then
if btn1080 and btn1080._msufSetSelected then btn1080:_msufSetSelected(false)
end
if btn1440 and btn1440._msufSetSelected then btn1440:_msufSetSelected(false)
end
if btn4k and btn4k._msufSetSelected then btn4k:_msufSetSelected(false)
end
if btnAuto and btnAuto._msufSetSelected then btnAuto:_msufSetSelected(false)
end
else
if btn1080 and btn1080._msufSetSelected then btn1080:_msufSetSelected(preset=="1080p")
end
if btn1440 and btn1440._msufSetSelected then btn1440:_msufSetSelected(preset=="1440p")
end
if btn4k and btn4k._msufSetSelected then btn4k:_msufSetSelected(preset=="4k")
end
if btnAuto and btnAuto._msufSetSelected then btnAuto:_msufSetSelected((preset=="auto")
or(preset==nil))
end
end

if MSUF_SetScalingToggleVisual then MSUF_SetScalingToggleVisual(disabled and true or false)
end
if msufOff and msufOff._msufSetSelected then msufOff:_msufSetSelected(disabled and true or false)
end
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
MSUF_SafeCall(_G and _G.MSUF_RegisterOptionsCategoryLazy)
MSUF_SafeCall(_G and _G.CreateOptionsPanel)
local p=_G and _G.MSUF_OptionsPanel if not p then return nil end
MSUF_ShowHideForLazy(p,"__MSUF_FullBuilt") return p end
local function MSUF_GetMainSettingsCategory() return (_G and _G.MSUF_SettingsCategory)
or(ns and ns.MSUF_MainCategory) end
local function MSUF_EnsureMainSettingsCategory() local cat=MSUF_GetMainSettingsCategory()
if not cat then MSUF_SafeCall(_G and _G.MSUF_RegisterOptionsCategoryLazy)
cat=MSUF_GetMainSettingsCategory()
end
return cat end
local SETTINGS_PANEL_DEFS={colors={full="MSUF_RegisterColorsOptions_Full",fallback="MSUF_RegisterColorsOptions",globals={"MSUF_ColorsPanel","MSUF_ColorsOptionsPanel"},builtKey="__MSUF_ColorsBuilt",},auras2={full="MSUF_RegisterAurasOptions_Full",fallback="MSUF_RegisterAurasOptions",globals={"MSUF_AurasPanel","MSUF_AurasOptionsPanel"},builtKey="__MSUF_AurasBuilt",},gameplay={full="MSUF_RegisterGameplayOptions_Full",fallback="MSUF_RegisterGameplayOptions",globals={"MSUF_GameplayPanel","MSUF_GameplayOptionsPanel"},builtKey="__MSUF_GameplayBuilt",},}
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
local function MSUF_SelectMainOptionsKey(key) local p=_G and _G.MSUF_OptionsPanel if not p then return end
if type(MSUF_GetTabButtonHelpers)~="function"then return end
local _,setKey=MSUF_GetTabButtonHelpers(p)
if type(setKey)=="function"then setKey(key)
if p.LoadFromDB then pcall(p.LoadFromDB,p)
end
end
end
local function MSUF_SelectCastbarSubPage(unitKey) if type(_G and _G.MSUF_SetActiveCastbarSubPage)=="function"then pcall(_G.MSUF_SetActiveCastbarSubPage,unitKey)
elseif type(MSUF_SetActiveCastbarSubPage)=="function"then pcall(MSUF_SetActiveCastbarSubPage,unitKey)
end
local p=_G and _G.MSUF_OptionsPanel if p and p.LoadFromDB then pcall(p.LoadFromDB,p)
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
},auras2={title="MSUF Auras 2.0",build=MSUF_EnsureAuras2PanelBuilt},opt_castbar={title="MSUF Castbar",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("castbar") end
},opt_misc={title="MSUF Miscellaneous",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("misc") end
},opt_colors={title="MSUF Colors",build=MSUF_EnsureColorsPanelBuilt},castbar={title="MSUF Castbar",build=MSUF_EnsureMainOptionsPanelBuilt,select=function(subkey) MSUF_SelectMainOptionsKey("castbar");
if subkey and subkey~=""then MSUF_SelectCastbarSubPage(subkey)
end
end
},profiles={title="MSUF Profiles",build=MSUF_EnsureMainOptionsPanelBuilt,select=function() MSUF_SelectMainOptionsKey("profiles") end
},colors={title="MSUF Colors",build=MSUF_EnsureColorsPanelBuilt},gameplay={title="MSUF Gameplay",build=MSUF_EnsureGameplayPanelBuilt},modules={title="MSUF Modules",build=MSUF_EnsureModulesPanelBuilt}}
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
if panel.SetPoint then local cropY=0 if panel==(_G and _G.MSUF_OptionsPanel)
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
local function MSUF_Standalone_SetCastbarTopButtonsHidden(hidden) local panel=_G and _G.MSUF_OptionsPanel;
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
if type(sel)=="function"then if C_Timer and C_Timer.After then C_Timer.After(0,function() pcall(sel,wantSub) end
)
C_Timer.After(0.05,function() pcall(sel,wantSub) end
)
else pcall(sel,wantSub)
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
if C_Timer and C_Timer.After then C_Timer.After(0,function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
C_Timer.After(0.05,function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
C_Timer.After(0.15,function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
)
C_Timer.After(0.30,function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end
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
if key=="home"then if S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey)
and not MSUF_IsCastbarKey(key)
then MSUF_Standalone_SetCastbarTopButtonsHidden(false)
end
if S.mirror.currentPanel then MSUF_DetachMirroredPanel(S.mirror.currentPanel)
S.mirror.currentPanel=nil end
S.mirror.currentKey="home"if S.mirror.homePanel then _TFadeIn(S.mirror.homePanel,TRANS_PAGE)
MSUF_UpdateHomePanel(S.mirror.homePanel)
end
MSUF_Standalone_UpdateTitle("home")
MSUF_Standalone_UpdateNav("home") return end
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
if S.mirror.currentPanel then MSUF_DetachMirroredPanel(S.mirror.currentPanel)
S.mirror.currentPanel=nil end
S.mirror.currentKey=key S.mirror.currentPanel=MSUF_Standalone_AttachMirrorPanel(key)
if S.mirror.currentPanel and S.mirror.currentPanel ~= prevPanel then _TFadeIn(S.mirror.currentPanel,TRANS_PAGE) end
MSUF_Standalone_ApplySelection(key,subkey,isCastbarKey)
MSUF_Standalone_AfterAttachFixups(key,isCastbarKey)
MSUF_Standalone_UpdateTitle(key)
MSUF_Standalone_UpdateNav(key) end
local function MSUF_BuildMirrorNavButtons(navParent,btnW,btnH) if not navParent then return {} end
btnH=btnH or 24 local padL=2;
local padT=10;
local padB=8;
local gap=8;
local indent=10 local extraRight=42;
local railW=navParent.GetWidth and navParent:GetWidth()
or 150 btnW=btnW or math.max(110,railW-(padL*2)-extraRight)
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
MSUF_LeftJustifyButtonText(b,isChild and 10 or 12)
MSUF_SkinNavButton(b,isHeader,isChild) return b end
local NAV={{type="leaf",key="home",label="Dashboard"},{type="header",id="unitframes",label="Unit Frames",defaultOpen=true,children={{key="uf_player",label="Player"},{key="uf_target",label="Target"},{key="uf_targettarget",label="Target of Target"},{key="uf_focus",label="Focus"},{key="uf_boss",label="Boss Frames"},{key="uf_pet",label="Pet"},}},{type="header",id="options",label="Options",defaultOpen=true,children={{key="opt_bars",label="Bars"},{key="opt_fonts",label="Fonts"},{key="auras2",label="Auras 2.0"},{key="opt_castbar",label="Castbar"},{key="opt_misc",label="Miscellaneous"},{key="opt_colors",label="Colors"},}},{type="leaf",key="gameplay",label="Gameplay"},{type="header",id="modules",label="Modules",defaultOpen=false,children={{key="modules",label="Style"},}},{type="leaf",key="profiles",label="Profiles"},}
local headerLabels={}
for _,node in ipairs(NAV)
do if node.type=="header"then headerLabels[node.id]=node.label end
end
local created={}
for _,node in ipairs(NAV)
do if node.type=="leaf"then local b=MakeButton(node.label,btnW,function() MSUF_SwitchMirrorPage(node.key) end
,false,false)
out[node.key]=b table.insert(created,{kind="leaf",btn=b})
elseif node.type=="header"then headers[node.id]=(headers[node.id]~=nil)
and headers[node.id]
or node.defaultOpen local b=MakeButton("+ "..node.label,btnW,function() headers[node.id]=not headers[node.id]
if navParent._msufTreeReflow then navParent._msufTreeReflow()
end
end
,true,false)
out["hdr_"..node.id]=b table.insert(created,{kind="header",id=node.id,btn=b})
local kids={}
for _,ch in ipairs(node.children or{})
do local w=math.max(40,btnW-indent)
local cb=MakeButton(ch.label,w,function() MSUF_SwitchMirrorPage(ch.key) end
,false,true)
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
if baseLabel and it.btn.SetText then it.btn:SetText((open and"- "or"+ ")..baseLabel)
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
navParent._msufTreeReflow=Reflow Reflow() return out end
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
local disabled=g and g.disableScaling
local sc=(disabled and 1.0) or MSUF_GetSavedSlashMenuScale()
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
local title=f:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
title:SetPoint("TOPLEFT",12,-10)
title:SetText("MSUF Options")
MSUF_SkinTitle(title)
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
navRail:SetWidth(150)
MSUF_ApplyMidnightBackdrop(navRail,0.22)
f._msufNavRail=navRail local host=CreateFrame("Frame",nil,content)
host:SetPoint("TOPLEFT",navRail,"TOPRIGHT",8,0)
host:SetPoint("BOTTOMRIGHT",content,"BOTTOMRIGHT",0,0)
host:SetScale(1.0)
if host.SetClipsChildren then host:SetClipsChildren(false)
end
f._msufMirrorHost=host local clip=CreateFrame("Frame",nil,host)
clip:SetPoint("TOPLEFT",host,"TOPLEFT",0,0)
clip:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
if clip.SetClipsChildren then clip:SetClipsChildren(true)
end
f._msufMirrorClipHost=clip local navStack=CreateFrame("Frame",nil,navRail)
navStack._msufSkipNavTitle=true local railW=navRail.GetWidth and navRail:GetWidth()
or 150 if navStack.SetWidth then navStack:SetWidth(math.max(80,railW-16))
end
f._msufNavStack=navStack f._msufNavButtons=MSUF_BuildMirrorNavButtons(navStack,130,22)
do local pad=8 if navStack.ClearAllPoints then navStack:ClearAllPoints()
end
navStack:SetPoint("TOPLEFT",navRail,"TOPLEFT",pad,-pad)
navStack:SetPoint("TOPRIGHT",navRail,"TOPRIGHT",-pad,-pad)
navStack:SetPoint("BOTTOMLEFT",navRail,"BOTTOMLEFT",pad,pad)
navStack:SetPoint("BOTTOMRIGHT",navRail,"BOTTOMRIGHT",-pad,pad)
end
local home=CreateFrame("Frame",nil,host,"BackdropTemplate")
home:SetAllPoints(host)
MSUF_ApplyMidnightBackdrop(home,0.35)
home:Hide()
S.mirror.homePanel=home f._msufHomePanel=home MSUF_ApplyMidnightControlsToFrame(home)
local homeTitle=home:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
homeTitle:SetPoint("TOPLEFT",12,-10)
homeTitle:SetText("Main Menu")
MSUF_SkinTitle(homeTitle)
local homeHint=home:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
homeHint:SetPoint("TOPLEFT",homeTitle,"BOTTOMLEFT",0,-2)
homeHint:SetText("Quick tools & UI scale (same content as /msuf options).")
MSUF_SkinText(homeHint)
local tipBox=CreateFrame("Frame",nil,home)
tipBox:SetPoint("TOPLEFT",home,"TOPLEFT",12,-44)
tipBox:SetPoint("TOPRIGHT",home,"TOPRIGHT",-12,-44)
tipBox:SetHeight(22)
local tipLabel=tipBox:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
tipLabel:SetPoint("TOPLEFT",tipBox,"TOPLEFT",0,0)
tipLabel:SetJustifyH("LEFT")
tipLabel:SetJustifyV("TOP")
tipLabel:SetAlpha(0.82)
tipLabel:SetText("Tip:")
MSUF_SkinMuted(tipLabel)
local tipText=tipBox:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
tipText:SetPoint("TOPLEFT",tipLabel,"TOPRIGHT",6,0)
tipText:SetPoint("TOPRIGHT",tipBox,"TOPRIGHT",0,0)
tipText:SetJustifyH("LEFT")
tipText:SetJustifyV("TOP")
tipText:SetAlpha(0.82)
tipText:SetText("")
MSUF_SkinMuted(tipText)
MSUF_ForceItalicFont(tipText)
home._msufTipLabel=tipLabel home._msufTipText=tipText home:SetScript("OnShow",function(self) MSUF_UpdateHomePanel(self) end
)
MSUF_ApplyFontBumpToFrame(home,MENU_FONT_BUMP)
MSUF_ForceItalicFont(tipText)
local statusLine=home:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
statusLine:SetPoint("TOPLEFT",tipBox,"BOTTOMLEFT",0,-6)
statusLine:SetPoint("TOPRIGHT",tipBox,"BOTTOMRIGHT",0,-6)
statusLine:SetJustifyH("LEFT")
statusLine:SetJustifyV("TOP")
statusLine:SetAlpha(0.78)
statusLine:SetText("")
MSUF_SkinMuted(statusLine)
home._msufStatusLine=statusLine local split=CreateFrame("Frame",nil,home)
split:SetPoint("TOPLEFT",home,"TOPLEFT",12,-96)
split:SetPoint("BOTTOMRIGHT",home,"BOTTOMRIGHT",-12,14)
local colGap=14;
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
if anchorTo then card:SetPoint("TOPLEFT",anchorTo,"BOTTOMLEFT",0,yOff or-12)
card:SetPoint("TOPRIGHT",anchorTo,"BOTTOMRIGHT",0,yOff or-12)
else card:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0)
card:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,0)
end
MSUF_ApplyMidnightBackdrop(card,0.18)
if not skipTitle then local title=UI_TextTL(card,"GameFontNormal",10,-8,titleText or"",MSUF_SkinTitle)
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
then StaticPopupDialogs["MSUF_RESET_POS_CONFIRM"]={text="Reset MSUF frame positions now?\n\nThis resets MSUF frame positions + visibility to defaults for the ACTIVE profile.",button1=YES,button2=NO,timeout=0,whileDead=1,hideOnEscape=1,preferredIndex=3,OnAccept=function() if _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
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
local quick=CreateCard(colL,"Quick Actions")
quick:SetHeight(206)
local bigW=410;
local bigH=26;
local LQ=MSUF_LayoutColumn(quick,12,-34,bigH,8);
local qx1,qy1=LQ:Row(bigH,8);
local bEdit=UI_BtnTL(quick,"Toggle Edit Mode",bigW,bigH,qx1,qy1,DashToggleEditMode,"Toggle Edit Mode","Enter MSUF Edit Mode to drag frames and adjust positions.",MSUF_SkinDashboardButton)
local win=_G and _G.MSUF_StandaloneOptionsWindow if win then win._msufDashEditBtn=bEdit end
if bEdit and bEdit._msufSetSelected then bEdit:_msufSetSelected(MSUF_IsMSUFEditModeActive())
end
MSUF_TryHookEditModeForDashboard()
local qx2,qy2=LQ:Row(bigH,10);
local bReset=UI_BtnTL(quick,"Reset Frame Positions",bigW,bigH,qx2,qy2,MSUF_ShowResetPositionsConfirm,"Reset Frame Positions","Resets MSUF frame positions + visibility to defaults (active profile).",MSUF_SkinDashboardButton);
local smallH=22;
local qx3,qy3=LQ:Row(smallH,0);
local rowBtns=MSUF_BuildButtonRowTL(quick,qx3,qy3,{{text="Colors",w=160,h=smallH,gap=10,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("colors") end
},{text="Gameplay",w=118,h=smallH,skinFn=MSUF_SkinDashboardButton,onClick=function() MSUF_SwitchMirrorPage("gameplay") end
},},10)
local bColors=rowBtns[1];
local bGameplay=rowBtns[2];
local profCard=CreateCard(colL,"Profile",quick,-12)
profCard:SetHeight(92)
local LP=MSUF_LayoutColumn(profCard,12,-34,18,6);
local px,py=LP:Row(18,0);
local profLabel=UI_TextTL(profCard,"GameFontHighlight",px,py,"Active profile:",MSUF_SkinText);
local profValue=UI_Text(profCard,"GameFontHighlight","LEFT",profLabel,"RIGHT",8,0,((_G and _G.MSUF_ActiveProfile)
or"Default"),MSUF_SkinTitle)
home._msufProfileValue=profValue local bProfiles=UI_Btn(profCard,"Open Profiles",160,22,"TOPRIGHT",profCard,"TOPRIGHT",-12,-30,function() MSUF_SwitchMirrorPage("profiles") end
,nil,nil,MSUF_SkinDashboardButton)
do local DISCORD_URL="https://discord.gg/JQnhZXnTAK";
local discordRow=CreateFrame("Frame",nil,profCard)
discordRow:SetPoint("TOPLEFT",profCard,"TOPLEFT",12,-56)
discordRow:SetPoint("TOPRIGHT",profCard,"TOPRIGHT",-12,-56)
discordRow:SetHeight(20)
local discordLabel=discordRow:CreateFontString(nil,"OVERLAY","GameFontHighlight")
discordLabel:SetPoint("LEFT",discordRow,"LEFT",0,0)
discordLabel:SetText("Discord:")
MSUF_SkinText(discordLabel)
local bDiscordSelect=UI_Btn(discordRow,"Select",72,18,"RIGHT",discordRow,"RIGHT",0,0,function() if discordRow._msufDiscordBox and discordRow._msufDiscordBox.SetFocus then discordRow._msufDiscordBox:SetFocus()
if discordRow._msufDiscordBox.HighlightText then discordRow._msufDiscordBox:HighlightText()
end
end
end
,"Select","Click to select this text.",MSUF_SkinDashboardButton)
local discordBox=CreateFrame("EditBox",nil,discordRow,"InputBoxTemplate")
discordBox:SetAutoFocus(false)
discordBox:SetHeight(18)
discordBox:SetPoint("LEFT",discordLabel,"RIGHT",8,0)
discordBox:SetPoint("RIGHT",bDiscordSelect,"LEFT",-8,0)
discordBox:SetText(DISCORD_URL)
discordBox:SetCursorPosition(0)
if discordBox.SetTextColor then discordBox:SetTextColor(0.30,0.60,1.00)
end
if discordBox.SetScript then discordBox:SetScript("OnEditFocusGained",function(self) if self.HighlightText then self:HighlightText()
end
end
)
discordBox:SetScript("OnEscapePressed",function(self) if self.ClearFocus then self:ClearFocus()
end
if self.HighlightText then self:HighlightText(0,0)
end
end
)
discordBox:SetScript("OnEnterPressed",function(self) if self.ClearFocus then self:ClearFocus()
end
end
)
end
discordRow._msufDiscordBox=discordBox end
local adv=CreateCard(colL,"Advanced",profCard,-12)
adv:SetPoint("BOTTOMLEFT",colL,"BOTTOMLEFT",0,0)
adv:SetPoint("BOTTOMRIGHT",colL,"BOTTOMRIGHT",0,0)
local advTitle=adv._msufTitle local advToggle=UI_Btn(adv,"Show",88,18,"TOPRIGHT",adv,"TOPRIGHT",-12,-8,function() end
,nil,nil,MSUF_SkinDashboardButton)
local advHint=adv:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
advHint:SetPoint("TOPLEFT",adv,"TOPLEFT",12,-34)
advHint:SetWidth(410)
advHint:SetJustifyH("LEFT")
advHint:SetJustifyV("TOP")
advHint:SetAlpha(0.82)
MSUF_SkinMuted(advHint)
local advBody=CreateFrame("Frame",nil,adv)
advBody:SetPoint("TOPLEFT",advHint,"BOTTOMLEFT",0,-8)
advBody:SetPoint("TOPRIGHT",adv,"TOPRIGHT",-12,-58)
advBody:SetPoint("BOTTOMLEFT",adv,"BOTTOMLEFT",12,12)
advBody:SetPoint("BOTTOMRIGHT",adv,"BOTTOMRIGHT",-12,12)
local cmds=advBody:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
cmds:SetPoint("TOPLEFT",advBody,"TOPLEFT",0,0)
cmds:SetJustifyH("LEFT")
cmds:SetJustifyV("TOP")
cmds:SetWidth(410)
cmds:SetText(MSUF_JoinLines({"/msuf  - Open MSUF menu","/msuf options  - Open Options","/msuf colors  - Open Colors","/msuf gameplay  - Open Gameplay","/msuf reset  - Reset frame positions","/msuf fullreset  - Factory reset","/msuf absorb  - Toggle absorb in HP text","/msufprofile on/off/reset/show","/msuf help  - Print help in chat",}))
MSUF_SkinText(cmds)
local btnRow=CreateFrame("Frame",nil,advBody)
btnRow:SetPoint("BOTTOMLEFT",advBody,"BOTTOMLEFT",0,0)
btnRow:SetPoint("BOTTOMRIGHT",advBody,"BOTTOMRIGHT",0,0)
btnRow:SetHeight(24)
do local defs={{text="Print Help",w=120,h=20,onClick=function() if _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
then pcall(_G.SlashCmdList["MIDNIGHTSUF"],"help")
end
end
,},{text="Factory Reset",w=120,h=20,gap=8,onClick=function() MSUF_ShowFactoryResetConfirm() end
,},}
local prev for i,d in ipairs(defs)
do local b if i==1 then b=UI_Btn(btnRow,d.text,d.w,d.h,"BOTTOMLEFT",btnRow,"BOTTOMLEFT",0,0,d.onClick,d.tipTitle,d.tipBody,MSUF_SkinDashboardButton)
else b=UI_Btn(btnRow,d.text,d.w,d.h,"LEFT",prev,"RIGHT",d.gap or 8,0,d.onClick,d.tipTitle,d.tipBody,MSUF_SkinDashboardButton)
end
prev=b end
end
local function AdvApplyState(open) if open then advToggle:SetText("Hide")
advHint:SetText("")
advBody:Show()
else advToggle:SetText("Show")
advHint:SetText("Hidden. Click Show to reveal slash commands + power tools.")
advBody:Hide()
end
end
advToggle:SetScript("OnClick",function() S.mirror.dashAdvOpen=not S.mirror.dashAdvOpen;
AdvApplyState(S.mirror.dashAdvOpen) end
)
AdvApplyState(S.mirror.dashAdvOpen==true)
local scaleCard=CreateCard(colR,nil,nil,nil,true)
scaleCard:SetHeight(300)
S.mirror.homeToolsApi=MSUF_BuildTools(scaleCard,{compact=false,wide=true,xl=true,title="Scale & Layout",segmented=true,showValue=true})
local presetsCard=CreateCard(colR,"Presets",scaleCard,-12)
presetsCard:SetPoint("BOTTOMLEFT",colR,"BOTTOMLEFT",0,0)
presetsCard:SetPoint("BOTTOMRIGHT",colR,"BOTTOMRIGHT",0,0)
local presetsTitle=presetsCard._msufTitle;
local presetDrop=CreateFrame("Frame","MSUF_PresetDropdown",presetsCard,"UIDropDownMenuTemplate")
presetDrop:SetPoint("TOPLEFT",presetsTitle,"BOTTOMLEFT",-16,-4)
UIDropDownMenu_SetWidth(presetDrop,220)
UIDropDownMenu_SetText(presetDrop,presetsCard._msufSelectedPreset or"Select preset...")
UIDropDownMenu_Initialize(presetDrop,function(self,level) local names=MSUF_GetPresetNames()
if not names or#names==0 then local info=UIDropDownMenu_CreateInfo();
info.text="(no presets)"info.notCheckable=true;
UIDropDownMenu_AddButton(info,level) return end
for _,name in ipairs(names)
do local pname=name local info=UIDropDownMenu_CreateInfo();
info.text=pname info.checked=(presetsCard._msufSelectedPreset==pname);
info.func=function() presetsCard._msufSelectedPreset=pname;
UIDropDownMenu_SetText(presetDrop,pname) end
UIDropDownMenu_AddButton(info,level)
end
end
)
do local names=MSUF_GetPresetNames()
if(not presetsCard._msufSelectedPreset)
and names and names[1]
then presetsCard._msufSelectedPreset=names[1]
UIDropDownMenu_SetText(presetDrop,names[1])
end
end
local bLoadPreset=UI_Btn(presetsCard,"Load preset",240,24,"TOPLEFT",presetDrop,"BOTTOMLEFT",16,-6,function() local sel=presetsCard._msufSelectedPreset if not sel then MSUF_Print("Select a preset first.");
 return end
MSUF_ShowPresetConfirm(sel) end
,"Load preset","Applies the selected preset to your current active profile. This overwrites settings (export first if unsure).",MSUF_SkinDashboardButton)
local presetHint=presetsCard:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
presetHint:SetPoint("TOPLEFT",bLoadPreset,"BOTTOMLEFT",0,-4)
presetHint:SetText("Overwrites your current active profile settings.")
MSUF_SkinMuted(presetHint)
do local KO_FI_URL="https://ko-fi.com/midnightsimpleunitframes#linkModal";
local PAYPAL_URL="https://www.paypal.com/ncp/payment/H3N2P87S53KBQ";
local GITHUB_URL="https://github.com/Mapkov2/MidnightSimpleUnitFrames";
local ICON_DIR="Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\";
local supportLabel=presetsCard:CreateFontString(nil,"OVERLAY","GameFontNormal")
supportLabel:SetPoint("BOTTOMLEFT",presetsCard,"BOTTOMLEFT",12,14)
supportLabel:SetText("Support the MSUF Development:")
supportLabel:SetTextColor(0.90,0.90,0.90)
supportLabel:SetJustifyH("LEFT")
supportLabel:SetJustifyV("MIDDLE")
if MSUF_SkinMuted then pcall(MSUF_SkinMuted,supportLabel)
end
local row=CreateFrame("Frame",nil,presetsCard)
row:SetHeight(24)
row:SetWidth(120)
row:SetPoint("BOTTOMRIGHT",presetsCard,"BOTTOMRIGHT",-12,12)
local function CreateIcon(texFile,size,tooltipTitle,tooltipText,onClick) local b=CreateFrame("Button",nil,row)
b:SetSize(size,size)
local t=b:CreateTexture(nil,"ARTWORK")
t:SetAllPoints()
t:SetTexture(ICON_DIR..texFile)
local hl=b:CreateTexture(nil,"HIGHLIGHT")
hl:SetAllPoints()
hl:SetColorTexture(1,1,1,0.10)
b:SetScript("OnClick",onClick)
if MSUF_AddTooltip then MSUF_AddTooltip(b,tooltipTitle,tooltipText)
else b:SetScript("OnEnter",function(self) if not GameTooltip then return end
GameTooltip:SetOwner(self,"ANCHOR_TOPLEFT");
GameTooltip:AddLine(tooltipTitle or"",1,1,1)
if tooltipText and tooltipText~=""then GameTooltip:AddLine(tooltipText,0.85,0.85,0.85,true)
end
GameTooltip:Show() end
)
b:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide()
end
end
)
end
return b end
local sz=22;
local gap=7 local icons={{tex="PayPal.png",title="PayPal",tip="Click to copy the PayPal support link.",onClick=function() MSUF_ShowCopyLink("PayPal",PAYPAL_URL) end
},{tex="Ko-Fi.png",title="Ko-fi",tip="Click to copy the Ko-fi link.",onClick=function() MSUF_ShowCopyLink("Ko-fi",KO_FI_URL) end
},{tex="GitHub.png",title="GitHub",tip="Click to copy the GitHub repository link.",onClick=function() MSUF_ShowCopyLink("GitHub",GITHUB_URL) end
},}
local prev for _,d in ipairs(icons)
do local b=CreateIcon(d.tex,sz,d.title,d.tip,d.onClick)
if not prev then b:SetPoint("RIGHT",row,"RIGHT",0,0)
else b:SetPoint("RIGHT",prev,"LEFT",-gap,0)
end
prev=b end
end
do
    local aboutLine = presetsCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    aboutLine:SetPoint("BOTTOMLEFT", supportLabel, "TOPLEFT", 0, 4)
    aboutLine:SetJustifyH("LEFT")
    local aboutVer = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
    local aboutStr = "by |cffccd0d9Mapko|r"
    if type(aboutVer) == "string" and aboutVer ~= "" then
        aboutStr = "v" .. aboutVer .. "  •  " .. aboutStr .. "  •  with help from |cffccd0d9R41z0r|r and the community"
    end
    aboutLine:SetText(aboutStr)
    aboutLine:SetAlpha(0.65)
    if MSUF_SkinMuted then pcall(MSUF_SkinMuted, aboutLine) end
end
local function MSUF_DashboardLayout() local wL=(colL and colL.GetWidth and colL:GetWidth())
or 0;
local wR=(colR and colR.GetWidth and colR:GetWidth())
or 0 if wL<=0 or wR<=0 then return end
local innerL=math.floor(wL-24);
local innerR=math.floor(wR-24)
if innerL<1 then innerL=1 end
if innerR<1 then innerR=1 end
if bEdit and bEdit.SetWidth then bEdit:SetWidth(innerL)
end
if bReset and bReset.SetWidth then bReset:SetWidth(innerL)
end
local gap=7;
local each=math.floor((innerL-(gap*2))/3)
if each<1 then each=1 end
if bOptions and bOptions.SetWidth then bOptions:SetWidth(each)
end
if bColors and bColors.SetWidth then bColors:SetWidth(each)
end
if bGameplay and bGameplay.SetWidth then bGameplay:SetWidth(each)
end
if advHint and advHint.SetWidth then advHint:SetWidth(innerL)
end
if cmds and cmds.SetWidth then cmds:SetWidth(innerL)
end
local ddW=math.floor(innerR-18)
if ddW>320 then ddW=320 end
if ddW<1 then ddW=1 end
if presetDrop and UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(presetDrop,ddW)
end
if bLoadPreset and bLoadPreset.SetWidth then bLoadPreset:SetWidth(math.max(1,math.min(innerR,ddW+20)))
end
if presetHint and presetHint.SetWidth then presetHint:SetWidth(innerR)
end
if S and S.mirror and S.mirror.homeToolsApi and S.mirror.homeToolsApi.Layout then pcall(S.mirror.homeToolsApi.Layout)
end
end
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
local tint=f:CreateTexture(nil,"BORDER")
tint:SetColorTexture(0.06,0.12,0.25,0.16)
tint:SetPoint("TOPLEFT",host,"TOPLEFT",0,0)
tint:SetPoint("BOTTOMRIGHT",host,"BOTTOMRIGHT",0,0)
f._msufTint=tint f:SetScript("OnShow",function() S.mirror.host=f._msufMirrorClipHost or f._msufMirrorHost or content do local nav=f._msufNavRail if nav and nav._msufTreeHeaders then nav._msufTreeHeaders.unitframes=true;
nav._msufTreeHeaders.options=true if nav._msufTreeReflow then nav._msufTreeReflow()
end
end
end
if MSUF_PickSessionTip then MSUF_PickSessionTip()
end
local startKey=f._msufInitialKey or"home";
local startSubKey=f._msufInitialSubKey;
f._msufInitialKey=nil f._msufInitialSubKey=nil;
S.mirror.currentKey=startKey MSUF_SwitchMirrorPage(startKey,startSubKey) end
)
f:SetScript("OnHide",function() MSUF_Standalone_SetCastbarTopButtonsHidden(false)
if MSUF_SaveWindowGeometry then MSUF_SaveWindowGeometry(f,f._msufGeomKey or"full")
end
if S.mirror.currentPanel then MSUF_DetachMirroredPanel(S.mirror.currentPanel);
S.mirror.currentPanel=nil end
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
_G.MSUF_ShowStandaloneOptionsWindow=MSUF_ShowOptionsWindow _G.MSUF_OpenStandaloneOptionsWindow=MSUF_ShowOptionsWindow _G.MSUF_HideStandaloneOptionsWindow=MSUF_HideOptionsWindow _G.MSUF_OpenPage=function(key,subkey) key=(key or"home")
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
_G.MSUF_OpenOptionsMenu=function() if _G and _G.MSUF_OpenPage then _G.MSUF_OpenPage("home")
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
return original(msg) end
end
SLASH_MSUFOPTIONS1="/msufoptions"SlashCmdList["MSUFOPTIONS"]=function() MSUF_ToggleOptionsWindow("main") end
_G.MSUF_SlashHooked=true end
MSUF_InstallSlashHook()
local scaleEvent=CreateFrame("Frame")
scaleEvent:RegisterEvent("PLAYER_LOGIN")
scaleEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
scaleEvent:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleEvent:SetScript("OnEvent",function(_,event,arg1) if MSUF_IsScalingDisabled and MSUF_IsScalingDisabled()
then return end
MSUF_ApplyMsufScale(MSUF_GetSavedMsufScale());
local want=MSUF_GetDesiredGlobalScaleFromDB()
if want then if event=="PLAYER_LOGIN"then MSUF_SetGlobalUiScale(want,true);
MSUF_EnsureGlobalUiScaleApplied(true)
else MSUF_EnsureGlobalUiScaleApplied(true)
end
end
end
)
if C_Timer and C_Timer.After then C_Timer.After(0,function() if MSUF_IsScalingDisabled and MSUF_IsScalingDisabled()
then return end
MSUF_ApplyMsufScale(MSUF_GetSavedMsufScale());
local want=MSUF_GetDesiredGlobalScaleFromDB()
if want then MSUF_SetGlobalUiScale(want,true,{applyCVars=false});
MSUF_EnsureGlobalUiScaleApplied(true)
end
end
)
end
