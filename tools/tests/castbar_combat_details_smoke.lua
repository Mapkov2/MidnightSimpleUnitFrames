local root = assert(arg[1], "root required")
local Secret = {}
local function fail() error("secret used in Lua") end
local SecretMT={__add=fail,__sub=fail,__mul=fail,__div=fail,__lt=fail,__le=fail,__eq=fail,__tostring=fail}
local function hidden() return setmetatable({},SecretMT) end
issecretvalue=function(v) return getmetatable(v)==SecretMT end
local Region={};Region.__index=Region
local function Frame() return setmetatable({points={},shown=false,level=2},Region) end
for _,key in ipairs({"SetStatusBarTexture","SetStatusBarColor","SetReverseFill","SetFrameStrata","EnableMouse",
    "SetTexCoord","SetScript","RegisterEvent","RegisterUnitEvent","UnregisterEvent","UnregisterAllEvents"}) do Region[key]=function() end end
function Region:CreateTexture() return Frame() end
function Region:CreateFontString() return Frame() end
-- Every region masks like the client: mask textures attach once per region.
function Region:CreateMaskTexture() local mask=Frame();mask.isMask=true;return mask end
function Region:SetTexture(...) self.texture={...} end
function Region:AddMaskTexture(mask)
    assert(mask.isMask,"only mask textures mask");self.masks=self.masks or {}
    for _,existing in ipairs(self.masks) do assert(existing~=mask,"mask attached twice") end
    self.masks[#self.masks+1]=mask
end
function Region:RemoveMaskTexture(mask)
    for index,existing in ipairs(self.masks or {}) do if existing==mask then table.remove(self.masks,index);return end end
end
function Region:GetNumMaskTextures() return #(self.masks or {}) end
function Region:GetMaskTexture(index) return (self.masks or {})[index] end
function Region:SetPoint(...) self.points[#self.points+1]={...} end
function Region:ClearAllPoints() self.points={} end
function Region:SetAllPoints(o) self.owner=o end
function Region:GetWidth() return 200 end
function Region:GetHeight() return 18 end
function Region:SetWidth(v) self.width=v end
function Region:SetSize(w,h) self.width,self.height=w,h end
function Region:SetFrameLevel(v) self.level=v end
function Region:GetFrameLevel() return self.level end
function Region:SetMinMaxValues(a,b) self.minimum,self.maximum=a,b end
function Region:SetValue(v) self.value=v end
function Region:GetStatusBarTexture() if not self.fill then self.fill=Frame() end;return self.fill end
function Region:SetColorTexture(...) self.color={...} end
function Region:SetAlpha(v) self.alpha=v end
function Region:SetAlphaFromBoolean(v,a,b) self.alpha=v and a or b end
function Region:SetFont(...) self.font={...} end
function Region:GetFont() return "font",12,"OUTLINE" end
function Region:SetTextColor() end
function Region:SetFormattedText(fmt,value) self.text=string.format(fmt,value) end
function Region:Show() self.shown=true end
function Region:Hide() self.shown=false end
function Region:SetShown(v) self.shown=v end
CreateFrame=Frame
UIParent=Frame()
InCombatLockdown=function() return false end
GetTime=function() return 100 end
C_Timer={After=function(_,fn) fn() end,NewTimer=function() return {Cancel=function() end} end}
MSUF_Castbar_PlainNumber=function(v) return not issecretvalue(v) and type(v)=="number" and v or nil end
MSUF_EnsureDBLazy=function() end
GetCVar=function() return "400" end
local reads=0
GetNetStats=function() reads=reads+1;return 0,0,28,43 end
local ns={Client={IsRetail=true},ExportPublic=function(k,v) _G[k]=v end}
assert(loadfile(root.."/MidnightSimpleUnitFrames/Castbars/MSUF_PlayerCastbarRuntime.lua"))("MSUF",ns)
MSUF_DB={general={castbarShowLatency=false,castbarShowLatencyText=true}}
local player={statusBar=Frame(),latencyBar=Frame(),timeText=Frame()}
MSUF_PlayerCastbar_UpdateLatencyZone(player,false,2)
assert(player.latencyText.text=="43 ms" and player.latencyText.shown and not player.latencyBar.shown,
    "numeric network latency must stay independent from queue-window zone")
MSUF_DB.general.castbarShowLatencyText=false
MSUF_PlayerCastbar_UpdateLatencyZone(player,false,2)
assert(not player.latencyText.shown and reads==1,"disabled label read network stats or stayed visible")
-- Restricted timestamps must be passed through to native geometry unchanged.
local start,finish,kickEnd=hidden(),hidden(),hidden()
local duration={GetStartTime=function() return start end,GetEndTime=function() return finish end}
local cooldown={GetEndTime=function() return kickEnd end,GetRemainingDuration=function() return 5 end}
C_Spell={GetSpellCooldownDuration=function() return cooldown end}
C_SpellBook={IsSpellKnownOrInSpellBook=function() return false end}
UnitClass=function() return "Warrior","WARRIOR" end
MSUF_ShouldUseMSUFCastbar=function() return true end
MSUF_DB={general={kickReadyShowTarget=true,kickReadyStyle="border",kickReadyTimeMarker=true,kickReadyTimeSegment=true}}
assert(loadfile(root.."/MidnightSimpleUnitFrames/Castbars/MSUF_InterruptReady.lua"))("MSUF",ns)
local target={unit="target",statusBar=Frame(),MSUF_castActive=true,MSUF_durationObj=duration,
    isNotInterruptible=false,MSUF_kickInterruptibleConfirmed=true}
MSUF_KickReady_RefreshFrame(target)
local projection=assert(target._msufKickTimeProjections[1])
assert(rawequal(projection.minimum,start) and rawequal(projection.maximum,finish) and rawequal(projection.value,kickEnd),
    "secret timestamps did not reach native min/max/value sinks")
assert(projection.marker.shown and projection.segment.shown)
assert(projection.marker.points[1][2]==projection:GetStatusBarTexture(),"marker does not follow native geometry")
target.MSUF_castActive=false;MSUF_KickReady_RefreshFrame(target);assert(not projection.shown,"timeline survived cast teardown")
print("castbar_combat_details_smoke: ok")
