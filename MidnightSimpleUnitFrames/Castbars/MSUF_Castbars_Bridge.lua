local e,n=...n=n or _G.MSUF_NS or{}_G.MSUF_NS=n
n.UF=n.UF or{}local function t()if type(_G.MSUF_EnsureDB)=="function"then _G.MSUF_EnsureDB()end
return(_G.MSUF_DB and _G.MSUF_DB.general)or{}end
local function r(e)local n=_G.MSUF_GetCastbarBackend
if type(n)=="function"then return n(e)end
e=type(e)=="string"and e:match("^boss%d*$")and"boss"or e
local n=e=="player"and"enablePlayerCastbar"or e=="target"and"enableTargetCastbar"or e=="focus"and"enableFocusCastbar"or e=="boss"and"enableBossCastbar"if not n then return nil end
local a=t()if a[n]==false then return e=="player"and"BLIZZARD"or"HIDE"end
return"MSUF"end
local function a(e)return r(e)=="MSUF"end
local function s(e)return e=="player"and r(e)=="BLIZZARD"end
local function e(e)return r(e)=="HIDE"end
if type(_G.MSUF_IsCastbarEnabledForUnit)~="function"then function _G.MSUF_IsCastbarEnabledForUnit(e)return a(e)end end
if type(_G.MSUF_IsCastTimeEnabled)~="function"then
function _G.MSUF_IsCastTimeEnabled(e)local n,e=t(),e and e.unit
if e=="player"then return n.showPlayerCastTime~=false end
if e=="target"then return n.showTargetCastTime~=false end
if e=="focus"then return n.showFocusCastTime~=false end
if e=="boss"or(type(e)=="string"and e:match("^boss%d+$"))then return n.showBossCastTime~=false end
return true
end
end
local function r(a)local e={rawget(_G,"PlayerCastingBarFrame"),rawget(_G,"CastingBarFrame")}for t=1,#e do
local e=e[t]if e then e.MSUF_PlayerCastbarAllowShown=a and true or false;e.showCastbar=a and true or false end
end
n.UF.blizzardCastbarOwner=a and"Blizzard"or"MSUF"end
local function n(e)if e and not e.MSUF_PlayerCastbarAllowShown and e.Hide then e:Hide()end end
function _G.MSUF_SuppressBlizzardPlayerCastbars()if s("player")then r(true);return false end
r(false)local a=false
local e={rawget(_G,"PlayerCastingBarFrame"),rawget(_G,"CastingBarFrame")}for t=1,#e do
local e=e[t]if e then
a=true
if not e.MSUF_HideHooked and hooksecurefunc then
e.MSUF_HideHooked=true
hooksecurefunc(e,"Show",n)if e.SetShown then hooksecurefunc(e,"SetShown",function(e,a)if a then n(e)end end)end
if e.HookScript then e:HookScript("OnShow",n)end
end
n(e)end
end
return a
end
local e=CreateFrame("Frame")e:RegisterEvent("PLAYER_LOGIN")e:RegisterEvent("PLAYER_ENTERING_WORLD")e:RegisterEvent("ADDON_LOADED")e:SetScript("OnEvent",function(a,n,e)if n=="ADDON_LOADED"and e~="Blizzard_CastingBarFrame"and e~="Blizzard_CastingBar"then return end
_G.MSUF_SuppressBlizzardPlayerCastbars()end)_G.MSUF_AreAnyCastbarsEnabled=_G.MSUF_AreAnyCastbarsEnabled or function()if a("player")or a("target")or a("focus")then return true end
if a("boss")and not(_G.MSUF_DB and _G.MSUF_DB.boss and _G.MSUF_DB.boss.enabled==false)then return true end
local e=t()return e.enableFocusKickIcon==true and not(_G.MSUF_DB and _G.MSUF_DB.focus and _G.MSUF_DB.focus.enabled==false)end
_G.MSUF_Castbars_ForceHideAll=_G.MSUF_Castbars_ForceHideAll or function()local function e(n)if n and n.Hide then n:Hide()end end
e(_G.MSUF_PlayerCastBar);e(_G.MSUF_PlayerCastbar);e(_G.MSUF_TargetCastbar);e(_G.TargetCastBar);e(_G.MSUF_FocusCastbar);e(_G.FocusCastBar)local n=_G.MSUF_BossCastbars
if type(n)=="table"then for a=1,#n do e(n[a])end end
end
_G.MSUF_Castbars_OnSettingsChanged=_G.MSUF_Castbars_OnSettingsChanged or function(e)local e=_G.MSUF_SyncCastbarBackendLegacyFlags
if type(e)=="function"then e(t())end
_G.MSUF_SuppressBlizzardPlayerCastbars()local e=_G.MSUF_PlayerCastbar_ApplyBackendState
if type(e)=="function"then e()end
local e=_G.MSUF_CastbarDriver_ApplyBackendState
if type(e)=="function"then e("target");e("focus")end
local e=_G.MSUF_ApplyBossCastbarsEnabled
if type(e)=="function"then e()end
if not _G.MSUF_AreAnyCastbarsEnabled()then _G.MSUF_Castbars_ForceHideAll()end
end
local function n(e)if type(e)~="function"then return end;if C_Timer and C_Timer.After then C_Timer.After(0,e)else e()end end
_G.MSUF_Castbars_RunNextFrame=_G.MSUF_Castbars_RunNextFrame or n
local e=_G.MSUF_RegisterModule
if type(e)=="function"then
e("Castbars",{order=40,IsEnabled=function()return _G.MSUF_AreAnyCastbarsEnabled()end,Enable=function()end,Disable=_G.MSUF_Castbars_ForceHideAll,Shutdown=_G.MSUF_Castbars_ForceHideAll,RefreshSettings=function(n,e)_G.MSUF_Castbars_OnSettingsChanged(e or"module_refresh");if type(_G.MSUF_ApplyPlayerChannelTickMarkers)=="function"then _G.MSUF_ApplyPlayerChannelTickMarkers()end end,})end