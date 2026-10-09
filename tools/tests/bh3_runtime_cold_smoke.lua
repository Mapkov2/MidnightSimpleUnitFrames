-- Behavior regressions for profile ownership and runtime state transitions.
local root = assert(arg[1], "repo root required")
local failed, passed = 0, 0
local function Read(path)
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/" .. path, "rb"))
    local s = file:read("*a"); file:close()
    return s:gsub("\r\n", "\n"):gsub("^\239\187\191", "")
end
local function Slice(path, first, last)
    local s = Read(path)
    local start = assert(s:find(first, 1, true), first)
    local stop = assert(s:find(last, start + #first, true), last)
    return s:sub(start, stop - 1)
end
local function Compile(source, env)
    env = setmetatable(env or {}, { __index = _G })
    local fn = assert(loadstring(source))
    setfenv(fn, env)
    return fn, env
end
local function Check(id, fn)
    local ok, message = pcall(fn)
    if ok then passed = passed + 1; print("PASS " .. id)
    else failed = failed + 1; print("FAIL " .. id .. ": " .. tostring(message)) end
end

Check("CX2-06",function()
 local count=0
 local function texture() count=count+1;return {Hide=function() end,SetTexture=function() end,SetBlendMode=function() end} end
 local env={NewLayerTexture=texture,WHITE8="white",MSUF_RoundedUF_OnDispelOverlayChanged=function(_,tex,enabled) tex.masked=enabled~=false end}
 env._G=env
 local base,overlay,clip=Compile(Slice("UnitFrames/Effects/MSUF_UF_TextureLayer.lua","local function EnsureBaseTexture", "-- `event` is").."return EnsureBaseTexture,EnsureOverlayTexture,ApplyClip",env)()
 local holder={};local b,o
 for i=1,100 do
   b=base(holder,true);o=overlay(holder,"LEFT",true);clip({},holder,b,true);clip({},holder,o,true)
   assert(b.masked and o.masked,"clip missing")
   assert(base(holder,false)==b and overlay(holder,"LEFT",false)==o,"clip toggle replaced texture")
   clip({},holder,b,false);clip({},holder,o,false);assert(not b.masked and not o.masked,"clip not released")
 end
 assert(count==2,"texture growth after repeated clip changes")
end)
Check("C11-A3",function()
 local f=Compile(Slice("UnitFrames/Engine/Group/MSUF_UF_Group_EM2.lua","local function GetRuntimePreviewCount", "local function GetRequestedPreviewCount").."return GetRuntimePreviewCount",{
 NormalizeKind=function(k)return k end,UsesRuntimeAnchor=function()return true end,
 GF=function()return {GetLayoutGroupCount=function()return 20 end}end,GetNumGroupMembers=function()return 22 end})()
 assert(f("raid")==20,"edit mode uses raw roster instead of visible layout tier")
end)
Check("C05-A2",function()
 local source=Slice("UnitFrames/Engine/MSUF_UF_PreviewAnimation.lua","local PREVIEW_NAME_LABELS", "local driver")
 local labels,casts=Compile("local Translate=MSUF.Translate\n"..source.."return PREVIEW_NAME_LABELS,CASTBAR_PREVIEWS",{MSUF={Translate=function(s)return "de:"..s end,UF={}}})()
 assert(labels.player=="de:Player Name Position" and labels.pettarget=="de:Pet Target Name Position","preview names untranslated")
 for _,entry in ipairs(casts)do assert(entry.label=="de:Test Cast","preview cast untranslated")end
end)
Check("MT3-A1",function()
 local source=Read("Features/Gameplay/MSUF_Feature_GameplayRuntime.lua")
 local first=source:find("local function PlayerNamePlate",1,true) and "local function PlayerNamePlate" or "local function MSUF_ShouldCrosshairFollowCamera"
 local frame={points=0,SetParent=function(self,p)self.parent=p end,ClearAllPoints=function()end,SetPoint=function(self,_,a,_,x,y)self.points=self.points+1;self.anchor=a;self.y=y end}
 local plate={UnitFrame={},GetHeight=function()return 100 end,IsShown=function()return true end}
 local queries=0;local active=plate;local zoom=15;local parent={}
 local env={crosshairFrame=frame,UIParent=parent,GetCVar=function(k)return k=="cameraDistanceMaxZoomFactor" and "1" or "0" end,GetCVarBool=function()return false end,GetCameraZoom=function()return zoom end,math_min=math.min}
 env.MSUF={Util={IsSecret=function()return false end}} -- plain heights; rc1_b_smoke covers a secret one
 env._G={C_NamePlate={GetNamePlateForUnit=function(unit)assert(unit=="player");queries=queries+1;return active end}}
 local apply=Compile(Slice("Features/Gameplay/MSUF_Feature_GameplayRuntime.lua",first,"local UpdateCrosshairRangeColor").."return AnchorCombatCrosshair",env)()
 apply();assert(frame.anchor==plate.UnitFrame and frame.parent==parent,"personal nameplate not used or adopted")
 assert(frame.y==-60,"zoomed-out offset wrong");zoom=0;apply();assert(frame.y==-96,"camera zoom offset stale")
 local writes=frame.points;for i=1,100 do apply()end;assert(frame.points==writes,"steady anchor restamped")
 assert(queries==102,"duplicate native nameplate query")
 active=nil;apply();assert(frame.anchor==parent and frame.y==-20,"nameplate removal does not restore UI anchor")
end)
Check("C02-K4",function()
 local tx=Compile("local ImportTx={}\n"..Slice("State/MSUF_Profiles.lua","function ImportTx.Merge", "function ImportTx.Stage").."return ImportTx",{
 MSUF_GeneralKeysOfKind=function()return {} end,MSUF_WipeGeneralSubset=function()end,MSUF_ApplyGeneralSubset=function()end,
 MSUF_DeepCopy=function(x)return x end,MSUF_WipeTable=function(t)for k in pairs(t)do t[k]=nil end end})()
 local gameplay={enabled=true};local class={color=1};local npc={color=2};local db={player={width=10},gameplay=gameplay,classColors=class,npcColors=npc}
 tx.Merge("unitframe",{player={width=20},gameplay={enabled=false},classColors={color=8},npcColors={color=9}},db)
 assert(db.player.width==20 and gameplay.enabled and class.color==1 and npc.color==2,"unitframe import overwrote another owner's settings")
end)
Check("CX1-01",function()
 local command;local gen=1;local reset=0
 local runtime={Identity=function()return {g=gen}end,IsCurrentIdentity=function(x)return type(x)=="table" and x.g==gen end}
 Compile(Slice("Runtime/MSUF_SlashCommands.lua","local MSUF_ProfileResetPending", "--- Should clean this up"),{
 Commands={Register=function(t)command=t.run end},CommandsInCombat=function()return false end,MSUF={ProfileRuntime=runtime},Tr=function(s)return s end,print=function()end,
 _G={MSUF_ActiveProfile="A"},ResetProfile=function()reset=reset+1 end})()
 command("");gen=2;command("confirm");assert(reset==0,"confirmation reset a different profile identity")
 command("");command("confirm");command("confirm");assert(reset==1,"confirmation is not single-use")
end)
Check("C02-K5",function()
 local calls=0
 local msuf={Util={InCombat=function()return false end},SuiteLink={NotifyProfileChanged=function()calls=calls+1 end},EventBus={Register=function()end}}
 local source=Slice("State/MSUF_Profiles.lua","MSUF_ProfileIO_NotifySuiteProfileChanged = (function()","function MSUF_SwitchProfile")
 local f=Compile(source.."return MSUF_ProfileIO_NotifySuiteProfileChanged",{MSUF=msuf,_G={MSUF_InCombat=true,InCombatLockdown=function()return false end}})()
 assert(f("switch","B")==true and calls==1,"stale combat latch stranded Suite notification")
end)
Check("L07-A4",function()
 local applied=0;local listener
 local e={MSUF_IsSpecAutoSwitchEnabled=function()return true end,MSUF_ApplySpecProfileIfEnabled=function()applied=applied+1 end,ExportPublic=function()end}
 e._G={CreateFrame=function()return {RegisterEvent=function()end,SetScript=function(_,_,f)listener=f end}end}
 Compile(Slice("State/MSUF_Profiles.lua","--- Event driver (very small; only does work when enabled)","--- Profile Export / Import"),e)()
 listener(nil,"PLAYER_LOGIN");assert(applied==0,"auto spec runs before startup profile binding")
 e.MSUF_ActiveProfile="Ready";listener(nil,"PLAYER_ENTERING_WORLD");assert(applied==1,"ready profile spec edge ignored")
end)

Check("CX1-02",function()
 local retries=0;local parent={};local frame={ClearAllPoints=function()end,SetPoint=function()end}
 local conf={combatTimerAnchor="focus",enableCombatTimer=true}
 local env={MSUF={UF={},Client={SupportsUnit=function(k)return k~="focus"end}},UIParent=parent,_G={},combatFrame=frame,GameplayDefaults=function()return conf end,C_Timer={After=function()retries=retries+1 end}}
 local apply=Compile(Slice("Features/Gameplay/MSUF_Feature_GameplayRuntime.lua","local function ValidateCombatTimerAnchor", "MSUF.MSUF_ApplyGameplayFontFromGlobal").."return ApplyCombatTimerAnchor",env)()
 for i=1,100 do apply(conf)end
 assert(retries==0 and frame._msufAppliedAnchor==parent,"unsupported focus anchor retries forever")
 conf.combatTimerAnchor="target";conf.enableCombatTimer=false;apply(conf);assert(retries==0,"disabled timer starts anchor retry")
 conf.enableCombatTimer=true;apply(conf);assert(retries==1,"supported not-yet-born target lost bounded pending retry")
end)
Check("C04-A2",function()
 local restored=0;local native={};local env={_G={TotemFrame=native,MSUF_DB={player={enabled=false}}},_CanMoveBlizzardTotemFrame=function()return true end,_RestoreBlizzardTotemFrame=function()restored=restored+1;return true end,
 _StoreOriginalLayout=function()error("disabled player took native totem ownership")end}
 local apply=Compile(Slice("Features/Gameplay/MSUF_Feature_TotemPreview.lua","    local function _ApplyBlizzardTotemFrame", "    local function _ApplyPreviewAnchorOnly").."return _ApplyBlizzardTotemFrame",env)()
 assert(apply({})==true and restored==1,"native totem not released when MSUF player is disabled")
end)
Check("C10-A3",function()
 local f=Compile(Slice("UnitFrames/Engine/Group/MSUF_UF_Group_Config.lua","local function CollectSpellIndicatorSpecs", "local function BuildSpellIndicatorAuraHashes").."return CollectSpellIndicatorSpecs")()
 local si={SpecInfo={OtherHealer={}},GetPlayerSpec=function()return nil end}
 assert(#f({spec="auto"},si)==0,"auto spec borrowed arbitrary other-class preset")
 assert(f({spec="OtherHealer"},si)[1]=="OtherHealer","explicit selection changed")
end)

Check("C30-A1",function()
 local conf={};local gf={GetConf=function()return conf end}
 local f=Compile(Slice("GroupFrames/MSUF_GroupFrames_DB_Textures.lua","local ResolveTextureKey, GetBarTexture, GetBarBackgroundTexture", "--- Resolve highlight border edge texture"),{
 GF=gf,MSUF={Require=function(name)
  if name=="MSUF_ResolveStatusbarTextureKey" then return function(k)return "local:"..k end end
  return function()return name=="MSUF_GetBarTexture" and "global:bar" or "global:background" end
 end}});f()
 for _,old in ipairs({false,true})do
  conf.hlOverride=old;conf.barTexture="A";conf.barBackgroundTexture="B"
  conf.barTextureOverride=nil;assert(gf.ResolveBarTexture("raid")== (old and "local:A" or "global:bar"))
  conf.barTextureOverride=true;assert(gf.ResolveBarTexture("raid")=="local:A" and gf.ResolveBarBgTexture("raid")=="local:B")
  assert(conf.hlOverride==old,"texture resolver changed highlight ownership")
  conf.barTextureOverride=false;assert(gf.ResolveBarTexture("raid")=="global:bar" and gf.ResolveBarBgTexture("raid")=="global:background")
  conf.barTextureOverride=true;conf.barBackgroundTexture="";assert(gf.ResolveBarBgTexture("raid")=="local:A","empty background should inherit foreground")
 end
end)

Check("C15-A1",function()
 local file="UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"
 local source=Slice(file,"local function BorderHighlightEnabled","local function BorderNormalThickness")
 local active=Compile(source.."return BorderHighlightEnabled",{IS_CLASSIC=true,IsBossUnit=function()return false end})()
 local frame={_msufA3PurgeActive=true,_msufBorderShown=true,MSUFUnitKey="target",_msufBorderRuntimeHighlightThickness=4}
 local cfg={purge=true,purgeR=0.3,purgeG=0.8,purgeB=0.1};frame._msufBorderRuntimeCfg=cfg
 assert(active(frame,cfg),"Classic purge does not enable border element")
 local color,thickness
 local apply=Compile(Slice(file,"local function ApplyHighlightBorder","function Borders.Create").."return ApplyHighlightBorder",{
 IS_CLASSIC=true,RuntimeHighlightBorderLevel=function()return 35 end,
 PurgeColor=function(c)return c.purgeR,c.purgeG,c.purgeB,1 end,
 ApplyResolvedBorder=function(_,_,key,_,width,r,g,b)color={r,g,b};thickness=width;return key=="purge"end})()
 assert(apply(frame,cfg,"purge",false) and color[1]==0.3 and thickness==4,"purge not painted with configured style")
 frame._msufA3PurgeActive=nil;assert(not apply(frame,cfg,"purge",false),"removed purge still paints")
 frame._msufA3PurgeActive=true;cfg.purge=false;assert(not apply(frame,cfg,"purge",false),"disabled purge still paints")
end)
Check("C12-A1",function()
 local World=assert(loadfile(root.."/tools/tests/client_world.lua"))()
 for _,flavor in ipairs({"Mainline","Forever","Vanilla","TBC","Mists"}) do
  local world=World.New(root,flavor);world.env.MAX_BOSS_FRAMES=5;world:Boot()
  assert(not world:FirstFailure(),"boot failed")
  world.env.MSUF_EnsureDB(true)
  local model=world.core.MSUF_Auras3.MenuModel
  assert(model.AddCustomContainerSpell("player",1,"424242",true))
  assert(model.AddCustomContainerSpell("player",1,"424242 item:12345",true),"new item binding reported unchanged")
  assert(model.CustomContainer("player",1,true).reminderItems[424242]==12345)
  local ok,why=model.AddCustomContainerSpell("player",1,"424242 item:12345",true)
  assert(ok==false and why=="unchanged","same binding should not repaint")
  assert(model.AddCustomContainerSpell("player",1,"424242 item:54321",true),"replaced item reported unchanged")
  assert(model.CustomContainer("player",1,true).reminderItems[424242]==54321)
 end
end)
Check("C10-A2",function()
 local World=assert(loadfile(root.."/tools/tests/client_world.lua"))()
 for _,flavor in ipairs({"Vanilla","TBC","Mists"}) do
  local world=World.New(root,flavor)
  world.env.MAX_BOSS_FRAMES=5
  world.env.GetSpellInfo=function(id) return id==139 and "Renew" or "Other" end
  world.env.C_Spell.GetSpellName=world.env.GetSpellInfo
  world:Boot();assert(not world:FirstFailure(),"boot failed")
  world.env.MSUF_EnsureDB(true)
  local gf=world.core.GF;gf.EnsureDB()
  local si=gf.SpellIndicators
  si.SpecInfo.Test={class="PRIEST",specID=1};si.SpellIDs.Test={Renew=139};si.SpecDefaults.Test={}
  local conf=gf.GetConf("party")
  conf.spellIndicators={enabled=true,spec="Test",specs={Test={Renew={enabled=true,autoBlacklist=true,placed={type="icon"}}}}}
  gf.InvalidateCompiledSpecs("party")
  local spec=gf.CompileSpec("party",nil,"party1")
  assert(spec.auras.buffAutoBlacklistNames and spec.auras.buffAutoBlacklistNames.Renew==true,
   "group compiler did not publish generated rank-family blacklist")
 end
end)
print(string.format("bh3_runtime_cold: %d passed, %d failed",passed,failed));assert(failed==0)
