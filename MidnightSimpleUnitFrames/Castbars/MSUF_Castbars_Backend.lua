local e,n=...n=n or _G.MSUF_NS or{}_G.MSUF_NS=n
local e={}n.MSUF_CastbarBackend=e
local l={player="castbarPlayerBackend",target="castbarTargetBackend",focus="castbarFocusBackend",boss="bossCastbarBackend"}local o={player="enablePlayerCastbar",target="enableTargetCastbar",focus="enableFocusCastbar",boss="enableBossCastbar"}local s={player=true}local function r(e)if type(e)~="string"then return nil end
e=e:lower()if e:match("^boss%d*$")or e=="bosscastbar"or e=="msuf_bosscastbar"then return"boss"end
if e=="playercastbar"or e=="msuf_playercastbar"then return"player"end
if e=="targetcastbar"or e=="msuf_targetcastbar"then return"target"end
if e=="focuscastbar"or e=="msuf_focuscastbar"then return"focus"end
return e
end
local function a(e)if type(e)=="table"then return e end
return _G.MSUF_DB and _G.MSUF_DB.general or nil
end
function e.Normalize(e)if e==true then return"MSUF"elseif e==false then return"BLIZZARD"end
if type(e)~="string"then return nil end
e=e:upper()if e=="MSUF"then return"MSUF"end
if e=="BLIZZARD"or e=="BLIZZ"or e=="DEFAULT"or e=="SHOW"then return"BLIZZARD"end
if e=="HIDE"or e=="HIDDEN"or e=="NONE"or e=="DISABLED"then return"HIDE"end
return nil
end
function e.NormalizeForUnit(t,n)local n,e=r(t),e.Normalize(n)if e=="BLIZZARD"and not s[n]then return"HIDE"end
return e
end
function e.Unit(e)return r(e)end
function e.BackendKey(e)return l[r(e)]end
function e.LegacyEnableKey(e)return o[r(e)]end
function e.Get(t,n)local r=r(t)local t,o=l[r],o[r]if not t then return nil end
n=a(n)if not n then return"MSUF"end
local e=e.NormalizeForUnit(r,n[t])if not e then e=(n[o]==false)and(s[r]and"BLIZZARD"or"HIDE")or"MSUF"end
n[t],n[o]=e,e=="MSUF"return e
end
function e.Set(t,s,n)local r=r(t)local t,o=l[r],o[r]n=t and a(n)if not n then return nil end
local e=e.NormalizeForUnit(r,s)or"MSUF"n[t],n[o]=e,e=="MSUF"return e
end
function e.Sync(n)n=a(n)if not n then return nil end
e.Get("player",n);e.Get("target",n);e.Get("focus",n);e.Get("boss",n)return n
end
function e.IsMSUF(r,n)return e.Get(r,n)=="MSUF"end
function e.IsBlizzard(r,n)return e.Get(r,n)=="BLIZZARD"end
function e.IsHide(r,n)return e.Get(r,n)=="HIDE"end
_G.MSUF_NormalizeCastbarBackend=e.Normalize
_G.MSUF_NormalizeCastbarBackendForUnit=e.NormalizeForUnit
_G.MSUF_GetCastbarBackendKey=e.BackendKey
_G.MSUF_GetCastbarEnableKey=e.LegacyEnableKey
_G.MSUF_GetCastbarBackend=e.Get
_G.MSUF_SetCastbarBackend=e.Set
_G.MSUF_SyncCastbarBackendLegacyFlags=e.Sync
_G.MSUF_ShouldUseMSUFCastbar=e.IsMSUF
_G.MSUF_ShouldUseBlizzardCastbar=e.IsBlizzard
_G.MSUF_ShouldHideCastbar=e.IsHide