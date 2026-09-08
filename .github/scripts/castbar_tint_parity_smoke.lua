-- Compare the complete tint sink/cache contract with an immutable source root.
-- Native stubs resolve opaque booleans; addon Lua may only forward them.
local root, baseline = arg[1] or ".", arg[2]
local function Forbidden() error("restricted tint value inspected by Lua") end
local meta = { __eq=Forbidden, __lt=Forbidden, __index=Forbidden, __tostring=Forbidden }
local YES, NO = setmetatable({}, meta), setmetatable({}, meta)
local function Secret(value) return rawequal(value, YES) or rawequal(value, NO) end
local function NativeSelect(value, yes, no)
  if rawequal(value, YES) then return yes end
  if rawequal(value, NO) then return no end
  return value and yes or no
end

local function Load(source, native, secretAPI, colors)
  local log, allocations, selections, probes = {}, 0, 0, 0
  local function Record(name, ...)
    local row={name}
    for i=1,select("#",...) do row[#row+1]=tostring(select(i,...)) end
    log[#log+1]=table.concat(row,"|")
  end
  _G.issecretvalue = secretAPI and function(value) probes=probes+1; return Secret(value) end or nil
  _G.CreateColor = colors and function(r,g,b,a)
    allocations=allocations+1
    return {r=r,g=g,b=b,a=a}
  end or nil
  _G.C_CurveUtil = native and {EvaluateColorFromBoolean=function(value,yes,no)
    selections=selections+1
    local color=NativeSelect(value,yes,no)
    return CreateColor(color.r,color.g,color.b,color.a)
  end} or nil
  local exports={}
  local ns={ExportPublic=function(name,value) exports[name]=value end}
  local file=source.."/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua"
  assert(loadfile(file))("MidnightSimpleUnitFrames",ns)
  local update=assert(exports.MSUF_Castbar_ApplyNonInterruptibleTint)
  local function Frame(booleanSink)
    local texture={}
    if booleanSink then
      function texture:SetVertexColorFromBoolean(value,yes,no)
        local color=NativeSelect(value,yes,no)
        Record("vertex",color.r,color.g,color.b,color.a)
      end
    end
    local bar={GetStatusBarTexture=function() return texture end,
      SetStatusBarColor=function(_,...) Record("bar",...) end}
    return {statusBar=bar}
  end
  local function Apply(frame, raw, ready, enabled, force, style)
    local unavailableR=.1
    if style==3 then unavailableR=nil end
    return update(frame,raw, .8,.1,.2,.7, .2,.7,.4,.9,force,
      unavailableR, .2,style==2 and .9 or .3,.6, ready,enabled)
  end
  local function State(frame)
    local keys={}
    for key,value in pairs(frame.statusBar) do
      if type(value)~="function" then keys[#keys+1]=key end
    end
    table.sort(keys)
    for _,key in ipairs(keys) do Record(key,frame.statusBar[key]) end
  end
  return {update=update,frame=Frame,apply=Apply,state=State,
    record=Record,log=log,file=file,counts=function() return allocations,selections,probes end}
end

local function Run(source)
  local outputs,cases={},0
  for _,native in ipairs({false,true}) do
    for _,secretAPI in ipairs({false,true}) do
      for _,colors in ipairs({false,true}) do
        local runtime=Load(source,native,secretAPI,colors)
        local values={true,false,0,"true"}
        if secretAPI then values[#values+1]=YES;values[#values+1]=NO end
        for _,booleanSink in ipairs({false,true}) do
          for rawIndex=0,#values do
            for readyIndex=0,#values do
              for _,enabled in ipairs({false,true}) do
                for _,force in ipairs({false,true}) do
                  local frame=runtime.frame(booleanSink)
                  for style=1,3 do
                    frame.statusBar._msufGlowSkipBase=style==2
                    local result=runtime.apply(frame,values[rawIndex],values[readyIndex],enabled,force,style)
                    runtime.record("result",result)
                    runtime.state(frame)
                    cases=cases+1
                  end
                end
              end
            end
          end
        end
        assert(runtime.update(nil)==false and runtime.update({})==false)
        outputs[#outputs+1]=table.concat(runtime.log,"\n")
      end
    end
  end
  return table.concat(outputs,"\n"),cases
end

local before,oldCases
if baseline then before,oldCases=Run(baseline) end
local after,cases=Run(root)
assert(not baseline or (before==after and cases==oldCases),"cast tint, glow/cache state or capability behavior changed")

local function Work(source, ready)
  local runtime=Load(source,true,true,true)
  local frame=runtime.frame(true)
  runtime.apply(frame,YES,ready,true,false,1) -- populate configured ColorObject caches
  local initialAlloc,initialSelections,initialProbes=runtime.counts()
  local instructions=0
  debug.sethook(function()
    local info=debug.getinfo(2,"S")
    if info and info.source=="@"..runtime.file then instructions=instructions+1 end
  end,"",1)
  for _=1,100 do runtime.apply(frame,NO,ready,true,false,1) end
  debug.sethook()
  local allocated,selected,probed=runtime.counts()
  return {work=instructions,allocations=allocated-initialAlloc,selections=selected-initialSelections,
    probes=probed-initialProbes}
end
for _,scenario in ipairs({{"ready",true},{"unavailable",false},{"opaqueReady",YES},{"opaqueUnavailable",NO}}) do
  local current=Work(root,scenario[2])
  assert(current.allocations==(Secret(scenario[2]) and 100 or 0),"avoidable result ColorObject allocation")
  if baseline then
    local old=Work(baseline,scenario[2])
    assert(current.work<old.work and current.probes<=old.probes,"tint path gained Lua work or secret probes")
    if Secret(scenario[2]) then
      assert(current.selections==old.selections,"restricted native selector was bypassed")
    else
      assert(current.selections==0 and old.selections==100,"public selector was not removed")
    end
    print(string.format("Tint %s /100: Lua instructions %d -> %d; result allocations %d -> %d; secret probes %d -> %d",
      scenario[1],old.work,current.work,old.allocations,current.allocations,old.probes,current.probes))
  end
end
print("castbar_tint_parity_smoke: ok ("..cases.." sink/cache/capability cases)")
