--- Castbars/MSUF_Castbars_Core.lua
--- Legacy/minified castbar settings, media resolution, font helpers, visual
--- refresh glue, and global compatibility exports.
---
--- This is a compatibility hub rather than a clean ownership layer. Keep new
--- feature logic in the newer readable modules when possible, and use this file
--- mainly to preserve old globals and bridge profile/media settings.

local ExportPublic = ((select(2, ...) or _G.MSUF_NS or _G.MSUF or {}).ExportPublic) or function(name, value)
_G[name] = value
return value
end

local e,a=...local e=a.Cache and a.Cache.F or{}local e,n,t,S=type,tonumber,ipairs,pairs local t=string.format local m=math.floor
local i=(a and a.LSM)or _G.MSUF_LSM or(LibStub and LibStub("LibSharedMedia-3.0",true))local l=_G.MSUF_FONT_LIST
local function c(o,n,r,t)local a=a and a.Util
local a=a and a.Enabled if e(a)=="function"then
return a(nil,n,r,t)end
if e(n)~="table"then return t~=false
end local e=n[r]if e==nil then return t~=false
end return e~=false
end local function d()local e=(a and a.LSM)or _G.MSUF_LSM or i if e then i=e end
return e end
local function r(t)if e(t)~="string"or t==""then return false end
local a=_G.MSUF_IsKnownFileAsset if e(a)=="function"and a(t)==false then return false end
return true end
local function t(t)if e(t)~="string"then return t end
if e(a)=="table"and e(a.Translate)=="function"then return a.Translate(t)end local a=(e(a)=="table"and a.L)or _G.MSUF_L
if e(a)=="table"then local e=rawget(a,t)if e~=nil then return e end end
return t end
local o=_G.MSUF_ResolveFontPath or function(t)if e(_G.MSUF_NormalizeFontPath)=="function"then
return _G.MSUF_NormalizeFontPath(t)end
return t end
local t=_G.MSUF_Castbars_RunNextFrame or function(t)if e(t)~="function"then return end
local e=_G.C_Timer if e and e.After then
e.After(0,t)else
t()end
end local function t()if _G.MSUF_InCombat==true or((_G.InCombatLockdown and _G.InCombatLockdown())and true or false)or((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))and true or false)then return
end if _G.MSUF_UpdateBossCastbarPreview then
_G.MSUF_UpdateBossCastbarPreview()end
if _G.MSUF_SetupBossCastbarPreviewEditMode then _G.MSUF_SetupBossCastbarPreviewEditMode()end end
MSUF_BossTestMode=MSUF_BossTestMode or false local t
ExportPublic("MSUF_CastbarUnitInfo", _G.MSUF_CastbarUnitInfo or{player={label="Player Castbar",prefix="castbarPlayer",defaultX=0,defaultY=5,showTimeKey="showPlayerCastTime",isBoss=false},target={label="Target Castbar",prefix="castbarTarget",defaultX=65,defaultY=-15,showTimeKey="showTargetCastTime",isBoss=false},focus={label="Focus Castbar",prefix="castbarFocus",defaultX=65,defaultY=-15,showTimeKey="showFocusCastTime",isBoss=false},boss={label="Boss Castbar",prefix=nil,defaultX=0,defaultY=0,showTimeKey="showBossCastTime",isBoss=true},})function MSUF_GetCastbarUnitInfo(t)local e=_G.MSUF_CastbarUnitInfo
return e and e[t]or nil end
function MSUF_IsBossCastbarUnit(e)local e=MSUF_GetCastbarUnitInfo(e)return(e and e.isBoss)and true or false end
function MSUF_GetCastbarPrefix(e)local e=MSUF_GetCastbarUnitInfo(e)return e and e.prefix or nil end
function MSUF_GetCastbarDefaultOffsets(e)local e=MSUF_GetCastbarUnitInfo(e)if not e then return 0,0 end return e.defaultX or 0,e.defaultY or 0
end function MSUF_GetCastbarUnitFromFrame(e)if not e then return nil end if _G.MSUF_BossCastbarPreview and e==_G.MSUF_BossCastbarPreview then
return"boss"end
if(MSUF_PlayerCastbar and e==MSUF_PlayerCastbar)or(MSUF_PlayerCastbarPreview and e==MSUF_PlayerCastbarPreview)then return"player"end if(MSUF_TargetCastbar and e==MSUF_TargetCastbar)or(MSUF_TargetCastbarPreview and e==MSUF_TargetCastbarPreview)then
return"target"end
if(MSUF_FocusCastbar and e==MSUF_FocusCastbar)or(MSUF_FocusCastbarPreview and e==MSUF_FocusCastbarPreview)then return"focus"end return nil
end function MSUF_ApplyCastbarUnitAndSync(t)if not t then return end
if not MSUF_DB then MSUF_EnsureDB()end if MSUF_IsBossCastbarUnit(t)then
if _G.MSUF_ApplyBossCastbarPositionSetting then _G.MSUF_ApplyBossCastbarPositionSetting()end if _G.MSUF_ApplyBossCastbarTimeSetting then
_G.MSUF_ApplyBossCastbarTimeSetting()end
if not(_G.MSUF_InCombat==true or((_G.InCombatLockdown and _G.InCombatLockdown())and true or false))and _G.MSUF_UpdateBossCastbarPreview
then _G.MSUF_UpdateBossCastbarPreview()end if e(_G.MSUF_PositionCastbarPreviewUnit)=="function"then
_G.MSUF_PositionCastbarPreviewUnit("boss")end
if e(MSUF_SyncCastbarPositionPopup)=="function"then MSUF_SyncCastbarPositionPopup("boss")end return
end if t=="player"and e(MSUF_ReanchorPlayerCastBar)=="function"then
MSUF_ReanchorPlayerCastBar()elseif t=="target"and e(MSUF_ReanchorTargetCastBar)=="function"then
MSUF_ReanchorTargetCastBar()elseif t=="focus"and e(MSUF_ReanchorFocusCastBar)=="function"then
MSUF_ReanchorFocusCastBar()end
MSUF_UpdateCastbarVisuals()if e(_G.MSUF_PositionCastbarPreviewUnit)=="function"then
_G.MSUF_PositionCastbarPreviewUnit(t)end
if e(MSUF_UpdateCastbarEditInfo)=="function"then MSUF_UpdateCastbarEditInfo(t)end if e(MSUF_SyncCastbarPositionPopup)=="function"then
MSUF_SyncCastbarPositionPopup(t)end
end local s
local function F()if not MSUF_DB then MSUF_EnsureDB()end
MSUF_DB=MSUF_DB or{}local n=MSUF_DB.general or{}MSUF_DB.general=n local t=n.fontKey
local r=_G.MSUF_GetFontPathForKey or(a and a.MSUF_GetFontPathForKey)if e(r)=="function"and t and t~=""then
local e=r(t)if e then return o(e,n.fontSize or 14,s())end
end local r
if e(_G.MSUF_GetInternalFontPathByKey)=="function"then r=_G.MSUF_GetInternalFontPathByKey(t)end if r then return o(r,n.fontSize or 14,s())end
local r=i or(a and a.LSM)or _G.MSUF_LSM if r and t and t~=""then
local a=_G.MSUF_NormalizeFontKey or function(e)return e end local l=a(t)local a if e(r.Fetch)=="function"then
a=r:Fetch("font",l,true)if not a and l~=t then
a=r:Fetch("font",t,true)end
end if a then return o(a,n.fontSize or 14,s())end
end local e=(l and l[1]and l[1].path)or"Fonts\\FRIZQT__.TTF"return o(e,n.fontSize or 14,s())end
s=function()if not MSUF_DB then MSUF_EnsureDB()end
MSUF_DB=MSUF_DB or{}MSUF_DB.general=MSUF_DB.general or{}local e=MSUF_DB.general if e.noOutline then
local t=""if e.fontMonochrome then return"MONOCHROME"end return t elseif e.boldText then
local t="THICKOUTLINE"if e.fontMonochrome then return t..",MONOCHROME"end return t else
local t="OUTLINE"if e.fontMonochrome then return t..",MONOCHROME"end return t end
end function a.MSUF_GetGlobalFontSettings()if not MSUF_DB then MSUF_EnsureDB()end local e=MSUF_DB.general or{}local t=F()local n=s()local a,o,l=a.MSUF_GetConfiguredFontColor()local r=e.fontSize or 14
local e=e.textBackdrop~=false return t,n,a,o,l,r,e
end function MSUF_GetGlobalFontSettings()if a and a.MSUF_GetGlobalFontSettings then return a.MSUF_GetGlobalFontSettings()end return"Fonts\\FRIZQT__.TTF","OUTLINE",1,1,1,14,true
end function MSUF_GetCastbarTexture()if not MSUF_DB then MSUF_EnsureDB()end local t=(MSUF_DB and MSUF_DB.general)or nil
local l=t and t.castbarTexture or nil local o=t and t.barTexture or nil
local a=_G.MSUF_CastbarTextureCache if not a then
a={}ExportPublic("MSUF_CastbarTextureCache", a)
end local i=(l or"").."|"..(o or"")local t=a[i]if t~=nil then
return t end
local function n(t)if e(t)~="string"or t==""then
return nil,true end
local a=_G.MSUF_BUILTIN_BAR_TEXTURES if e(a)=="table"then
local t=a[t]if e(t)=="string"and t~=""then
if r(t)then return t,true
end return nil,false
end end
if t:find("\\")or t:find("/")then if r(t)then
return t,true end
return nil,false end
local a=d()if a and a.Fetch then
local t=a:Fetch("statusbar",t,true)if e(t)=="string"and t~=""then
if r(t)then return t,true
end return nil,false
end end
return nil,false end
local e,t=n(l)local t=t
if not e then local a,n=n(o)e=a t=t and n
end e=e or"Interface\\TARGETINGFRAME\\UI-StatusBar"if t then a[i]=e
end return e
end ExportPublic("MSUF_GetCastbarTexture", MSUF_GetCastbarTexture)
function MSUF_GetCastbarBackgroundTexture()if not MSUF_DB then MSUF_EnsureDB()end local t=MSUF_DB and MSUF_DB.general
local n=t and t.castbarBackgroundTexture or nil local a=t and t.castbarTexture or nil
local r=t and t.barTexture or nil local t=n
if t==nil or t==""then t=a
end if t==nil or t==""then
t=r end
local n=_G.MSUF_CastbarBackgroundTextureCache if not n then
n={}ExportPublic("MSUF_CastbarBackgroundTextureCache", n)
end local r=t or""local a=n[r]if a then
return a end
local a if e(MSUF_ResolveStatusbarTextureKey)=="function"then
a=MSUF_ResolveStatusbarTextureKey(t)end
if not a or a==""then a="Interface\\TARGETINGFRAME\\UI-StatusBar"end n[r]=a
return a end
ExportPublic("MSUF_GetCastbarBackgroundTexture", MSUF_GetCastbarBackgroundTexture)
local function T(e)local t=MSUF_DB and MSUF_DB.general
if not(e and e.unit and t)then return true end local e=e.unit
local e=(e=="player"and"showPlayerCastTime")or(e=="target"and"showTargetCastTime")or(e=="focus"and"showFocusCastTime")return(not e)and true or c(nil,t,e,true)end function MSUF_GetCastbarReverseFill(r)if not MSUF_DB then MSUF_EnsureDB()end local t=MSUF_DB and MSUF_DB.general
local e=t and t.castbarFillDirection or"RTL"local o=t and t.castbarUnifiedDirection or false
if e=="LEFT"then e="RTL"elseif e=="RIGHT"then e="LTR"end if e~="RTL"and e~="LTR"then
e="RTL"end
local t=_G.MSUF_CastbarReverseFillCache if not t then
t={}ExportPublic("MSUF_CastbarReverseFillCache", t)
end local a=(e=="RTL"and 4 or 0)+(o and 2 or 0)+(r and 1 or 0)local n=t[a]if n~=nil then
return n end
local n=(e=="RTL")local e
if o then e=n
else if r then
e=not n else
e=n end
end t[a]=e and true or false
return t[a]end
if not _G.MSUF_CastbarStyleRevision then ExportPublic("MSUF_CastbarStyleRevision", 1)
end function MSUF_BumpCastbarStyleRevision()local e=_G.MSUF_CastbarStyleRevision or 1 ExportPublic("MSUF_CastbarStyleRevision", e+1)
return _G.MSUF_CastbarStyleRevision end
function MSUF_GetGlobalCastbarStyleCache()local t=_G.MSUF_CastbarStyleRevision or 1
local e=_G.MSUF_GlobalCastbarStyleCache if e and e.rev==t then
return e end
e=e or{}e.rev=t
if not MSUF_DB then MSUF_EnsureDB()end local t=(MSUF_DB and MSUF_DB.general)or{}e.unifiedDirection=(t.castbarUnifiedDirection==true)local t=MSUF_GetCastbarTexture()if not t or t==""then t="Interface\\TARGETINGFRAME\\UI-StatusBar"end e.texture=t
local a=MSUF_GetCastbarBackgroundTexture()if not a or a==""then
a=t end
e.bgTexture=a e.reverseFillNormal=MSUF_GetCastbarReverseFill(false)and true or false
e.reverseFillChanneled=MSUF_GetCastbarReverseFill(true)and true or false ExportPublic("MSUF_GlobalCastbarStyleCache", e)
return e end
function MSUF_RefreshCastbarStyleCache(e)if not e then return end
local a=_G.MSUF_CastbarStyleRevision or 1 if e.MSUF_castbarStyleRev==a then
return end
local t=MSUF_GetGlobalCastbarStyleCache and MSUF_GetGlobalCastbarStyleCache()or nil e.MSUF_castbarStyleRev=a
if t then e.MSUF_cachedUnifiedDirection=(t.unifiedDirection==true)e.MSUF_cachedCastbarTexture=t.texture e.MSUF_cachedCastbarBackgroundTexture=t.bgTexture or t.texture
e.MSUF_cachedReverseFillNormal=(t.reverseFillNormal==true)e.MSUF_cachedReverseFillChanneled=(t.reverseFillChanneled==true)end end
local function l(t,a)MSUF_RefreshCastbarStyleCache(t)local e if t then
if a then e=(t.MSUF_cachedReverseFillChanneled==true)else e=(t.MSUF_cachedReverseFillNormal==true)end else
e=MSUF_GetCastbarReverseFill(a)or false end
return e and true or false end
ExportPublic("MSUF_GetCastbarReverseFillForFrame", l) local function o(e)e(MSUF_PlayerCastbar)e(MSUF_TargetCastbar)e(MSUF_FocusCastbar)e(MSUF_PlayerCastbarPreview)e(MSUF_TargetCastbarPreview)e(MSUF_FocusCastbarPreview)end function MSUF_UpdateCastbarTextures()MSUF_BumpCastbarStyleRevision()local r=_G.MSUF_CastbarStyleRevision or 1
local t=MSUF_GetCastbarTexture()if not t then return end
local a=t local n=MSUF_GetCastbarBackgroundTexture()if n and n~=""then a=n
end local function n(e)if e and e.statusBar then e.statusBar:SetStatusBarTexture(t)local a=e.statusBar:GetStatusBarTexture()if a then a:SetHorizTile(true)end
e.MSUF_castbarStyleRev=r e.MSUF_cachedCastbarTexture=t
e.MSUF_cachedReverseFillNormal=MSUF_GetCastbarReverseFill(false)and true or false e.MSUF_cachedReverseFillChanneled=MSUF_GetCastbarReverseFill(true)and true or false
if not MSUF_DB then MSUF_EnsureDB()end;local t=MSUF_DB and MSUF_DB.general;e.MSUF_cachedUnifiedDirection=(t and t.castbarUnifiedDirection)==true end
if e and e.backgroundBar then e.backgroundBar:SetTexture(a)e.MSUF_cachedCastbarBackgroundTexture=a end
end o(n)local n=_G.MSUF_BossCastbars if n and e(n)=="table"then
for e=1,#n do local e=n[e]if e and e.statusBar then e.statusBar:SetStatusBarTexture(t)local a=e.statusBar:GetStatusBarTexture()if a then a:SetHorizTile(true)end
e.MSUF_cachedCastbarTexture=t end
if e and e.backgroundBar then e.backgroundBar:SetTexture(a)e.MSUF_cachedCastbarBackgroundTexture=a end
end end
end function MSUF_UpdateCastbarFillDirection()MSUF_BumpCastbarStyleRevision()local function a(e)if e and e.statusBar and e.statusBar.SetReverseFill then local t=false
if e.isEmpower then t=true
elseif e.MSUF_isChanneled then t=true
elseif e.unit and(e.unit=="player"or e.unit=="target"or e.unit=="focus")then if UnitChannelInfo and UnitChannelInfo(e.unit)then
t=true end
end MSUF_RefreshCastbarStyleCache(e)local t=l(e,t)if e.statusBar and e.statusBar.SetReverseFill then e.statusBar:SetReverseFill(t and true or false)end
end end
o(a)end
local o={}function MSUF_ClearResolvedStatusbarTextureCache()o={}local t=_G.MSUF_CastbarTextureCache
if e(t)=="table"then for e in S(t)do
t[e]=nil end
end local e=a and a.Bars and a.Bars._DetachedPowerBarTextures
if e then e.fgK=false
e.fgC=nil e.bgK=false
e.bgC=nil end
d()end
ExportPublic("MSUF_ClearResolvedStatusbarTextureCache", MSUF_ClearResolvedStatusbarTextureCache) function MSUF_ResolveStatusbarTextureKey(t)if e(t)~="string"or t==""then return"Interface\\TargetingFrame\\UI-StatusBar"end local a=o[t]if a then return a end local a
local n=false local l=_G.MSUF_BUILTIN_BAR_TEXTURES
if e(l)=="table"then local t=l[t]if e(t)=="string"and t~=""then if r(t)then
a=t n=true
end end
end if not a then
if t:find("\\")or t:find("/")then if r(t)then
a=t n=true
end else
local o=d()if o and e(o.Fetch)=="function"then
local t=o:Fetch("statusbar",t,true)if e(t)=="string"and t~=""then
if r(t)then a=t
n=true end
end end
end end
if a then if n then o[t]=a end
return a end
local e="Interface\\TargetingFrame\\UI-StatusBar"if n then o[t]=e end
return e end
ExportPublic("MSUF_ResolveStatusbarTextureKey", MSUF_ResolveStatusbarTextureKey) ExportPublic("MSUF_BUILTIN_BAR_TEXTURES", _G.MSUF_BUILTIN_BAR_TEXTURES or{Blizzard="Interface\\TargetingFrame\\UI-StatusBar",Flat="Interface\\Buttons\\WHITE8x8",RaidHP="Interface\\RaidFrame\\Raid-Bar-Hp-Fill",RaidPower="Interface\\RaidFrame\\Raid-Bar-Resource-Fill",Skills="Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",Outline="Interface\\Tooltips\\UI-Tooltip-Background",TooltipBorder="Interface\\Tooltips\\UI-Tooltip-Border",DialogBG="Interface\\DialogFrame\\UI-DialogBox-Background",Parchment="Interface\\AchievementFrame\\UI-Achievement-StatsBackground",})function MSUF_GetBarTexture()if not MSUF_DB then MSUF_EnsureDB()end
local e=(MSUF_DB and MSUF_DB.general)or nil local e=e and e.barTexture
return MSUF_ResolveStatusbarTextureKey(e)end
function MSUF_GetBarBackgroundTexture()if not MSUF_DB then MSUF_EnsureDB()end
local t=(MSUF_DB and MSUF_DB.general)or nil local e=t and t.barBackgroundTexture
if e==nil or e==""then e=t and t.barTexture
end return MSUF_ResolveStatusbarTextureKey(e)end function MSUF_UpdateCastbarVisuals()MSUF_BumpCastbarStyleRevision()if not MSUF_DB then MSUF_EnsureDB()end local d=MSUF_DB.general or{}local C=c(nil,d,"castbarShowIcon",true)local B=c(nil,d,"castbarShowSpellName",true)local i=n(d.castbarSpellNameFontSize)or 0 local _=n(d.castbarIconOffsetX)or 0
local U=n(d.castbarIconOffsetY)or 0 local c=F()local l=s()local o,r,t=1,1,1
if e(MSUF_GetCastbarTextColor)=="function"then o,r,t=MSUF_GetCastbarTextColor()elseif e(a.MSUF_GetConfiguredFontColor)=="function"then o,r,t=a.MSUF_GetConfiguredFontColor()else local e=(d.fontColor or"white"):lower()local e=(MSUF_FONT_COLORS and(MSUF_FONT_COLORS[e]or MSUF_FONT_COLORS.white))or{1,1,1}o,r,t=e[1],e[2],e[3]end local S=d.textBackdrop~=false local U=n(d.fontTextAlpha)or 1 if U<.7 then U=.7 elseif U>1 then U=1 end local A,R,Y=1,1,-1 local E=tostring(d.fontShadowStrength or"NORMAL"):upper()if E=="SOFT"then A,R,Y=.55,1,-1 elseif E=="DEEP"then A,R,Y=1,2,-2 end
local s=d.fontSize or 14 local M=(i>0)and i or s
local i=_G.MSUF_SetFontSafe local function h(a,n)if e(i)=="function"then i(a,c,n,l,d.fontKey)else a:SetFont(c,n,l)end a:SetTextColor(o,r,t,U)end local function b(e)if S then e:SetShadowColor(0,0,0,A)e:SetShadowOffset(R,Y)else
e:SetShadowOffset(0,0)end
end local function s(t)if not t or not t.statusBar then return end local r=t.statusBar
local o=t.icon or t.Icon or(t.IconFrame and(t.IconFrame.Icon or t.IconFrame.icon))or t.iconTexture or t.IconTexture local f=t:GetWidth()or r:GetWidth()or 250
local S=t:GetHeight()or r:GetHeight()or 18 local l=MSUF_DB and MSUF_DB.general
local u,a if l then
local o=n(l.castbarGlobalWidth)local r=n(l.castbarGlobalHeight)u=MSUF_GetCastbarUnitFromFrame(t)local d=_G.MSUF_NormalizeCastbarWidthSource or _G.MSUF_NormalizePlayerCastbarWidthSource
local s=_G.MSUF_GetCastbarWidthSourceKey and _G.MSUF_GetCastbarWidthSourceKey(u)local i=nil
if s then local t=l[s]if e(d)=="function"then i=d(t)elseif t=="unitframe"or t=="essential"or t=="utility"then i=t
end end
local i=(i~=nil)if o and o>0 and not i then f=o;t:SetWidth(f)end
if r and r>0 then S=r;t:SetHeight(r)end a=u and MSUF_GetCastbarPrefix(u)or nil
if a then local r=n(l[a.."BarWidth"])local e=n(l[a.."BarHeight"])if r and r>0 and not i then f=r;t:SetWidth(f)end
if e and e>0 then S=e;t:SetHeight(e)end end
end local F=C
local _=_ local C=U
local i=S local c=l
if c then if a then
local e=c[a.."ShowIcon"]if e~=nil then F=(e~=false)end
e=c[a.."IconOffsetX"];if e~=nil then _=n(e)or 0 end e=c[a.."IconOffsetY"];if e~=nil then C=n(e)or 0 end
e=c[a.."IconSize"]if e~=nil then
i=n(e)or i else
local e=n(c.castbarIconSize)or 0 if e and e>0 then i=e end
end else
local e=n(c.castbarIconSize)or 0 if e and e>0 then i=e end
end end
if i<6 then i=6 end if i>128 then i=128 end
local G=(t==MSUF_PlayerCastbar or t==MSUF_PlayerCastbarPreview)local U=(_~=0)local c=t.backgroundBar if G and e(_G.MSUF_ApplyPlayerCastbarIconLayout)=="function"then
_G.MSUF_ApplyPlayerCastbarIconLayout(t,d,-1,1)if c and t.statusBar then
c:ClearAllPoints()c:SetAllPoints(t.statusBar)end else
if o and r and o.GetParent and o.SetParent then local e=U and r or t
if o:GetParent()~=e then o:SetParent(e)end end
if o then o:SetShown(F)o:ClearAllPoints()o:SetPoint("LEFT",t,"LEFT",_,C)o:SetSize(i,i)if o.SetDrawLayer then o:SetDrawLayer("OVERLAY",7)end
end r:ClearAllPoints()if F and o and not U then r:SetPoint("LEFT",t,"LEFT",i+1,0)r:SetWidth(f-(i+1))else
r:SetPoint("LEFT",t,"LEFT",0,0)r:SetWidth(f)end r:SetHeight(S-2)if c then c:ClearAllPoints()c:SetAllPoints(r)end
end do
local a=l and l.castbarShowSpark==true local e=t.spark
if a and not e then e=r:CreateTexture(nil,"OVERLAY",nil,6)e:SetTexture(4417031)e:SetTexCoord(0.222168,0.232422,0.294434,0.317383)e:SetDesaturated(true)e:SetVertexColor(1,1,1,1)e:SetBlendMode("ADD")t.spark=e
end if e then
e:SetShown(a)if a then
local t=(l and l.castbarSparkOverflow~=false)local t=t and math.max(4,S*2.1)or S
e:SetSize(16,t)local t=r:GetStatusBarTexture()if t then e:ClearAllPoints()e:SetPoint("CENTER",t,"RIGHT",0,0)end
end end
end if _G.MSUF_KickReady_ApplyLayout then
_G.MSUF_KickReady_ApplyLayout(t)end
local e=l or{}local f=B
local o=M local c,S=0,0
local l=o local d,i=-2,0
if a then local t=e[a.."ShowSpellName"]if t~=nil then f=(t~=false)end c=n(e[a.."TextOffsetX"])or 0
S=n(e[a.."TextOffsetY"])or 0 d=n(e[a.."TimeOffsetX"])or n(e.castbarPlayerTimeOffsetX)or-2
i=n(e[a.."TimeOffsetY"])or n(e.castbarPlayerTimeOffsetY)or 0 local t=n(e[a.."SpellNameFontSize"])or 0
if t and t>0 then o=t end local e=n(e[a.."TimeFontSize"])or 0
if e and e>0 then l=e
else l=o
end elseif MSUF_IsBossCastbarUnit(u)then
d=-2+(n(e.bossCastTimeOffsetX)or 0)i=n(e.bossCastTimeOffsetY)or 0
local e=n(e.bossCastTimeFontSize)or 0 if e and e>0 then l=e end
end local Y=T(t)if type(_G.MSUF_IsCastTimeEnabled)=="function"then Y=_G.MSUF_IsCastTimeEnabled(t)end local e=t.castText or t.Text or t.text
if e then e:SetShown(f)h(e,o)if e.SetMaxLines then e:SetMaxLines(1)end if e.SetWordWrap then e:SetWordWrap(false)end if e.SetNonSpaceWrap then e:SetNonSpaceWrap(false)end if e.SetPoint then
e:ClearAllPoints()e:SetPoint("LEFT",r,"LEFT",2+c,0+S)end local _,__,R if type(_G.MSUF_GetCastbarSpellNameShorteningConfig)=="function"then _,__,R=_G.MSUF_GetCastbarSpellNameShorteningConfig(t)end local W=(r.GetWidth and r:GetWidth())or(t.GetWidth and t:GetWidth())or 250
if W<20 then W=20 end local X=0 if Y and t.timeText then local q=n(l)or 12 if q<6 then q=6 elseif q>128 then q=128 end local z=t._msufCastTimeFormat X=m(q*((z=="CURRENT"or not z)and 3.2 or 6.8)+8.5)local M=m(W*0.45+0.5)if X>M then X=M end end
local R=_ and(tonumber(R)or 0)or 0 local w=m(W-X-R-(6+(tonumber(c)or 0))+0.5)if w<20 then w=20 end
if e.SetWidth and e._msufCastbarTextWidth~=w then e:SetWidth(w)e._msufCastbarTextWidth=w end
if type(_G.MSUF_RefreshCastbarSpellNameText)=="function"then _G.MSUF_RefreshCastbarSpellNameText(t)end b(e)end local e=t.timeText
if e and Y then h(e,l or M)if e.SetPoint then e:ClearAllPoints()e:SetPoint("RIGHT",r,"RIGHT",d,i)end
b(e)end
end s(MSUF_PlayerCastbar)s(MSUF_TargetCastbar)s(MSUF_FocusCastbar)local t=_G.MSUF_InCombat==true or((_G.InCombatLockdown and _G.InCombatLockdown())and true or false)or((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))and true or false)if not t then
s(MSUF_PlayerCastbarPreview)s(MSUF_TargetCastbarPreview)s(MSUF_FocusCastbarPreview)if _G.MSUF_BossCastbarPreview then
s(_G.MSUF_BossCastbarPreview)end
end if not t and e(_G.MSUF_UpdateBossCastbarPreview)=="function"and not _G.MSUF_BossPreviewRefreshLock then
ExportPublic("MSUF_BossPreviewRefreshLock", true) _G.MSUF_UpdateBossCastbarPreview()if _G.MSUF_SetupBossCastbarPreviewEditMode then _G.MSUF_SetupBossCastbarPreviewEditMode()end ExportPublic("MSUF_BossPreviewRefreshLock", false)
end local e=_G.MSUF_MAX_BOSS_FRAMES or 5
for e=1,e do local e=_G["MSUF_boss"..e.."CastBar"]if e then s(e)end end
end a.Castbars=a.Castbars or{}a.Castbars._GetFontPath=F a.Castbars._GetFontFlags=s
a.MSUF_GetFontPath=F a.MSUF_GetFontFlags=s
ExportPublic("MSUF_GetFontPath", F) ExportPublic("MSUF_GetFontFlags", s)
