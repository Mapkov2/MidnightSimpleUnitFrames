local root=assert(arg[1])
local passed,failed=0,0
local function Check(id,f)
 local ok,why=pcall(f);if ok then passed=passed+1;print("PASS "..id) else failed=failed+1;print("FAIL "..id..": "..tostring(why))end
end
local function NewRuntime()
 local e=setmetatable({}, {__index=_G});e._G=e
 local ns={Client={},NumberFormat={Refresh=function()end},UF={DisableBlizzardFrames=function()end}}
 local function noop()end
 for _,name in ipairs({"MSUF_ApplyMsufScale","MSUF_TargetSoundDriver_ApplySetting","MSUF_NSRTNicknames_ApplySetting","MSUF_Grid2EditMode_SetEnabled","MSUF_DetailsEditMode_SetEnabled","MSUF_DominosEditMode_SetEnabled","MSUF_DandersEditMode_SetEnabled","MSUF_GF_InvalidateConfCache","MSUF_UFCore_NotifyConfigChanged","MSUF_ApplyModules","MSUF_GF_RebuildAll","MSUF_ClassPower_Apply","MSUF_ApplyPowerBarEmbedLayout_All","MSUF_Castbars_OnSettingsChanged","MSUF_ApplyAllCastbarsAndSync","MSUF_UpdateAllFonts_Immediate"}) do e[name]=noop end
 ns.Require=function()return noop end
 e.InCombatLockdown=function()return e.combat==true end
 e.MSUF_ActiveProfile="A";e.MSUF_DB={general={},gameplay={color="A"}}
 e.CreateFrame=function()local f={SetScript=function(self,_,cb)self.cb=cb end,RegisterEvent=noop,UnregisterEvent=noop};e.defer=f;return f end
 local state={tooltip="A",highlight="A",gameplay="A",spellIDs="A",casters="A"}
 ns.Tooltips={Refresh=function()state.tooltip=e.MSUF_ActiveProfile end}
 e.MSUF_RefreshMouseoverHighlight=function()state.highlight=e.MSUF_ActiveProfile end
 ns.Highlight={Refresh=e.MSUF_RefreshMouseoverHighlight}
 ns.MSUF_ApplyGameplayVisuals=function()state.gameplay=e.MSUF_DB.gameplay.color end
 ns.TooltipSpellIDs={Apply=function()state.spellIDs=e.MSUF_ActiveProfile end,ApplyCasterNames=function()state.casters=e.MSUF_ActiveProfile end}
 local f=assert(loadfile(root.."/MidnightSimpleUnitFrames/State/MSUF_ProfileRuntime.lua"));setfenv(f,e);f("MSUF",ns)
 return ns,e,state
end
for id,key in pairs({["CX1-06"]="tooltip",["CX1-05"]="gameplay",["C05-A1"]="highlight",["C04-A4"]="spellIDs"}) do
 Check(id,function()
  local ns,e,state=NewRuntime()
  e.MSUF_ActiveProfile="B";e.MSUF_DB={general={},gameplay={color="B"}};ns.ProfileRuntime.Apply()
  assert(state[key]=="B","profile follower retained previous profile")
  if key=="spellIDs" then assert(state.casters=="B","caster name follower stale")end
  e.combat=true;e.MSUF_ActiveProfile="C";e.MSUF_DB.gameplay.color="C";ns.ProfileRuntime.Apply()
  assert(state[key]=="B","protected profile fanout ran in combat")
  e.MSUF_ActiveProfile="D";e.MSUF_DB.gameplay.color="D";ns.ProfileRuntime.Apply()
  e.combat=false;e.defer.cb(e.defer,"PLAYER_REGEN_ENABLED")
  assert(state[key]=="D","deferred profile follower did not apply latest state")
 end)
end
print(string.format("bh3_runtime_followers: %d passed, %d failed",passed,failed));assert(failed==0)
