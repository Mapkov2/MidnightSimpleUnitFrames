local n=_G n.MSUF_FocusKickUseEngineDriver=true
local r=CreateFrame local E=(n.C_Timer and n.C_Timer.After)or nil
local function S()local e=n.MSUF_DB
if not e or not e.general then return false end if e.focus and e.focus.enabled==false then
return false end
local n=n.MSUF_ShouldUseMSUFCastbar if type(n)=="function"and not n("focus",e.general)then
return false end
return e.general.enableFocusKickIcon==true end
local function T(t)local e=n.FocusCastBar or n.MSUF_FocusCastBar or n["MSUF_FocusCastBar"]if e and e.SetAlpha then e:SetAlpha(t and 0 or 1)end end
local function U()if n.__MSUF_FocusKickUIInit then return end
if type(n.MSUF_InitFocusKickIcon)~="function"then return end n.__MSUF_FocusKickUIInit=true
n.MSUF_InitFocusKickIcon()end
local t=false local e
local _=false local function s(n)n=n and true or false if _==n then return end
_=n if n then
e:RegisterUnitEvent("UNIT_SPELLCAST_START","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_STOP","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_FAILED","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE","focus")e:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE","focus")else
e:UnregisterEvent("UNIT_SPELLCAST_START")e:UnregisterEvent("UNIT_SPELLCAST_STOP")e:UnregisterEvent("UNIT_SPELLCAST_FAILED")e:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")e:UnregisterEvent("UNIT_SPELLCAST_DELAYED")e:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")e:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")e:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")e:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_START")e:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")e:UnregisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")e:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")e:UnregisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")end
end local function i()local e=S()s(e)if e then U()end if not e then
T(false)if type(n.MSUF_FocusKick_ApplyCastState)=="function"then
n.MSUF_FocusKick_ApplyCastState(nil)else
local e=n.MSUF_FocusKickIcon if e and e.Hide then e:Hide()end
end return
end T(true)local e if type(n.MSUF_BuildCastState)=="function"then
e=n.MSUF_BuildCastState("focus")end
if type(n.MSUF_FocusKick_ApplyCastState)=="function"then n.MSUF_FocusKick_ApplyCastState(e)end end
local function T()t=false
i()end
local function _()if t then return end
t=true if E then
E(0,T)else
t=false i()end end
e=r("Frame")e:RegisterEvent("PLAYER_LOGIN")e:RegisterEvent("PLAYER_ENTERING_WORLD")e:RegisterEvent("PLAYER_FOCUS_CHANGED")e:SetScript("OnEvent",function(E,t,e)if t=="UNIT_SPELLCAST_INTERRUPTED"and e=="focus"then
if S()and type(n.MSUF_FocusKick_PlayInterruptFeedback)=="function"then n.MSUF_FocusKick_PlayInterruptFeedback()end end
_()end)n.MSUF_FocusKickDriver_ForceUpdate=_ if E then
E(0.2,_)else
_()end