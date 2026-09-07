-- Test the production ownership selector with live resolver changes. An
-- optional source snapshot also checks removed closure allocations/Lua work.
local root, baseline = arg[1] or ".", arg[2]
local function Load(source)
  local file=assert(io.open(source.."/MidnightSimpleUnitFrames/Castbars/MSUF_CastbarUtils.lua","rb"))
  local text=file:read("*a");file:close()
  local first=assert(text:find("local function UnitSupportsInterruptUnavailableTint(",1,true))
  local last=assert(text:find("local function ShouldUseInterruptUnavailableColor(",first,true))
  return assert(loadstring(text:sub(first,last-1).."\nreturn UnitSupportsInterruptUnavailableTint",
    "@"..source.."/ownership"))()
end
local after=Load(root)
local before=baseline and Load(baseline)
local count,key,lastGeneral,response=0
local function Resolver(which,general)
  count=count+1;key=which;lastGeneral=general;return response
end
local values={false,true,0,1,"true","false",{}}
local units={"player","target","focus","boss1","boss5","boss","bossdog","party1","",false,123,{}}
local cases=0
for _,unit in ipairs(units) do
  for flags=0,124 do
    local general={kickReadyShowTarget=values[flags%5+1],
      kickReadyShowFocus=values[math.floor(flags/5)%5+1],
      kickReadyShowBoss=values[math.floor(flags/25)%5+1]}
    local frame={unit=unit}
    local expectedKey,enabled
    if unit=="target" then expectedKey,enabled="target",general.kickReadyShowTarget
    elseif unit=="focus" then expectedKey,enabled="focus",general.kickReadyShowFocus
    elseif type(unit)=="string" and unit:sub(1,4)=="boss" then expectedKey,enabled="boss",general.kickReadyShowBoss end
    for capability=0,8 do
      response=values[capability]
      if capability==0 then _G.MSUF_ShouldUseMSUFCastbar=nil else _G.MSUF_ShouldUseMSUFCastbar=Resolver end
      local eligible=expectedKey~=nil and enabled==true
      local expected=eligible and (capability==0 or response==true)
      local expectedCount=eligible and capability~=0 and 1 or 0
      count,key,lastGeneral=0,nil,nil
      assert(after(frame,general)==expected,"ownership result changed")
      assert(count==expectedCount and (count==0 or (key==expectedKey and lastGeneral==general)),"resolver contract changed")
      if before then
        count,key,lastGeneral=0,nil,nil
        assert(before(frame,general)==expected and count==expectedCount,"baseline contract differs")
      end
      cases=cases+1
    end
  end
end
assert(after(nil,{})==false and after({},{})==false)
local function Measure(fn,source,unit,enabled)
  local frame={unit=unit}
  local general={kickReadyShowTarget=enabled,kickReadyShowFocus=enabled,kickReadyShowBoss=enabled}
  response=true;_G.MSUF_ShouldUseMSUFCastbar=Resolver
  local work=0
  debug.sethook(function()
    local info=debug.getinfo(2,"S")
    if info and info.source=="@"..source.."/ownership" then work=work+1 end
  end,"",1)
  for i=1,100 do fn(frame,general) end
  debug.sethook()
  collectgarbage("collect");collectgarbage("stop")
  local kb=collectgarbage("count")
  for i=1,10000 do fn(frame,general) end
  local allocated=collectgarbage("count")-kb
  collectgarbage("restart")
  return work,allocated
end
for _,unit in ipairs({"target","focus","boss1","player"}) do
  for _,enabled in ipairs({false,true}) do
    local a,ak=Measure(after,root,unit,enabled)
    assert(ak<.1,"selector allocates per-call state")
    if before then
      local b,bk=Measure(before,baseline,unit,enabled)
      assert(a<=b and ak<bk,"ownership work/allocation increased")
      print(string.format("%s enabled=%s: instructions/100 %d -> %d; KiB/10000 %.3f -> %.3f",unit,tostring(enabled),b,a,bk,ak))
    end
  end
end
print("castbar_ownership_allocation_smoke: ok ("..cases.." cases)")
