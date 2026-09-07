-- Isolate the real identity-gate functions to compare their sinks, Lua work,
-- and transient allocations without native AuraContainer or Perfy overhead.
local root=arg and arg[1] or "."
local baselineRoot=arg and arg[2]
local function Forbidden() error("restricted identity inspected") end
local SECRET=setmetatable({}, {__eq=Forbidden,__index=Forbidden,__tostring=Forbidden})
local function Run(sourceRoot)
  local probes,writes,parents=0,0,0
  _G.issecretvalue=function(v) probes=probes+1; return rawequal(v,SECRET) end
  local path=sourceRoot.."/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Identity.lua"
  local file=assert(io.open(path,"rb")); local source=file:read("*a"); file:close()
  local start=assert(source:find("local function SetAssistAlpha(",1,true))
  local stop=assert(source:find("A3._SeedGroupAuraAssistGate =",start,true))
  local apply=assert(loadstring("local A3, GetGroupSlotsRootConfig, SpellIndicatorsRuntime = ...\n"
    ..source:sub(start,stop-1).."\nreturn ApplyGroupAuraAssistGate","@"..path))({},
    function(cfg) return cfg and cfg.groupSlotsRoot end,
    {ApplyGroupAssistGate=function(frame,canAssist,ready)
      frame.spellReady=ready; frame.spellAssist=rawequal(canAssist,SECRET) and "secret" or tostring(canAssist)
      return false
    end})
  local keys={"GroupSlots","Secondary","Tertiary","Buffs","Debuffs","TrackedBuffs","Externals"}
  local lanes={"buff","debuff","trackedBuff","external"}
  local function MakeFrame(ownerMask,laneMask,hostile,parentAbsent)
    local cfg={group=true,lanes={}}
    local frame={}
    local parent={}
    local auraRoot={_msufA3NativeRoot=true,_msufA3Config=cfg}
    auraRoot.GetParent=function() parents=parents+1; return not parentAbsent and parent or nil end
    for _,key in ipairs(keys) do
      auraRoot[key]={SetAlpha=function(self,alpha) writes=writes+1; self.alpha=alpha end}
    end
    if ownerMask>0 then
      local primary={rootKey="GroupSlots",assistGated=ownerMask%2==1,
        identityCandidateMode=hostile and "hostile" or "assist"}
      if math.floor(ownerMask/2)%2==1 then primary.secondaryRoot={rootKey="Secondary",assistGated=true,identityCandidateMode="assist"} end
      if math.floor(ownerMask/4)%2==1 then primary.tertiaryRoot={rootKey="Tertiary",assistGated=true,identityCandidateMode="hostile"} end
      cfg.groupSlotsRoot=primary
    end
    for i,key in ipairs(lanes) do
      if math.floor(laneMask/2^(i-1))%2==1 then
        cfg.lanes[key]={groupAccessGate=true,alpha=i/4,identityCandidateMode=hostile and "hostile" or "assist"}
      end
    end
    frame.Auras=auraRoot
    return frame,parent
  end
  local results,cases={},0
  local states={true,false,SECRET,"invalid",17}
  for owners=0,7 do
    for laneMask=0,15 do
      for flags=0,31 do
        local frame,parent=MakeFrame(owners,laneMask,flags%2==1,math.floor(flags/2)%2==1)
        if flags>=16 then
          for _,key in ipairs(keys) do
            frame.Auras[key].SetAlphaFromBoolean=function(self,value,on,off)
              assert(type(value)=="boolean","native boolean sink lost plain visibility")
              writes=writes+1; self.alpha=value and on or off
            end
          end
        end
        frame._msufA3GroupAuraPresenceVisible=math.floor(flags/4)%2==1
        parent._msufA3GroupAuraPresenceVisible=math.floor(flags/8)%2==1
        for state=1,6 do
          local canAssist=states[state]
          for readyState=0,2 do
            local ready
            if readyState~=0 then ready=readyState==2 end
            local changed=apply(frame,canAssist,ready)
            local sample={tostring(changed),tostring(frame._msufA3GroupAuraAssistReady),
              tostring(frame._msufA3GroupAuraCanAssist),tostring(frame.spellReady),frame.spellAssist}
            for _,key in ipairs(keys) do sample[#sample+1]=tostring(frame.Auras[key].alpha) end
            results[#results+1]=table.concat(sample,":")
            cases=cases+1
          end
        end
      end
    end
  end
  assert(apply({},true,true)==false,"missing root was accepted")
  local work={}
  for _,shape in ipairs({{0,0,"empty"},{7,0,"owners"},{0,15,"lanes"},{7,15,"both"}}) do
    local frame=MakeFrame(shape[1],shape[2],false,false)
    apply(frame,true,true)
    local count=0
    debug.sethook(function()
      local info=debug.getinfo(2,"S")
      if info and info.source=="@"..path then count=count+1 end
    end,"",1)
    for i=1,100 do apply(frame,true,true) end
    debug.sethook()
    work[shape[3]]=count
  end
  local frame=MakeFrame(7,15,false,false)
  apply(frame,true,true)
  collectgarbage("collect"); collectgarbage("stop")
  local before=collectgarbage("count")
  for i=1,10000 do apply(frame,true,true) end
  local allocated=collectgarbage("count")-before
  collectgarbage("restart")
  return table.concat(results,"\n"),cases,probes,writes,parents,work,allocated
end
local values,cases,probes,writes,parents,work,allocated=Run(root)
if baselineRoot then
  local oldValues,oldCases,oldProbes,oldWrites,oldParents,oldWork,oldAllocated=Run(baselineRoot)
  assert(values==oldValues and cases==oldCases,"identity-gate visibility or state changed")
  assert(writes==oldWrites and parents==oldParents,"native alpha/parent work changed")
  assert(probes<oldProbes and allocated<oldAllocated,"duplicate work did not decrease")
  print(string.format("Aura identity parity: %d cases; secret probes %d -> %d; unchanged alpha writes %d; temporary KiB/10000 calls %.3f -> %.3f",
    cases,oldProbes,probes,writes,oldAllocated,allocated))
  for _,shape in ipairs({"empty","owners","lanes","both"}) do
    assert(work[shape]<=oldWork[shape],"identity Lua work increased: "..shape)
    print(string.format("Identity Lua instructions (%s, 100 calls): %d -> %d",shape,oldWork[shape],work[shape]))
  end
else
  assert(allocated<1,"identity gate still allocates per update")
  print(string.format("Aura identity gates: %d cases; secret/public/presence/owner/lane parity and no per-update table",cases))
end
