-- Error delivery must retain the throwing callback and still drain/rearm work.
local root=arg and arg[1] or "."
local driver,reported,stacks,prints=nil,{},{},{}
local OriginalCallback,callbackPresent
_G.CreateFrame=function()
  driver={}
  function driver:SetScript(_,fn) self.tick=fn end
  return driver
end
_G.C_Timer=nil
_G.geterrorhandler=function()
  return function(err)
    reported[#reported+1]=err
    stacks[#stacks+1]=debug.traceback("original callback")
    for depth=2,25 do
      local info=debug.getinfo(depth,"f")
      if not info then break end
      if info.func==OriginalCallback then callbackPresent=true end
    end
  end
end
local nativePrint=print
_G.print=function(...)
  local parts={...}
  for i=1,#parts do parts[i]=tostring(parts[i]) end
  prints[#prints+1]=table.concat(parts," ")
end
local ns={ExportPublic=function(name,value) _G[name]=value return value end}
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MSUF",ns)
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))("MSUF",ns)
local scheduler=ns.Scheduler
local survived,deferred=0,0
OriginalCallback=function()
  scheduler.ScheduleOnce("deferred",function() deferred=deferred+1 end)
  error("intentional callback failure")
end
scheduler.ScheduleOnce("failing",OriginalCallback)
scheduler.ScheduleOnce("survivor",function() survived=survived+1 end)
local ok = xpcall(driver.tick, _G.geterrorhandler()) -- models the client's script boundary
assert(not ok and #reported==1 and callbackPresent,"direct callback lost its original stack")
assert(survived==0 and deferred==0 and driver.tick,"failure stranded work or hid exception")
driver.tick()
assert(survived==1 and deferred==1 and not driver.tick,"next-frame work was lost")
assert(scheduler.head==1 and scheduler.tail==0 and next(scheduler.pending)==nil,"queue state leaked after error")
assert(#prints==0,"scheduler replaced error handling with chat output")
_G.print=nativePrint
print("Scheduler traceback: original callback retained; direct exceptions; remaining work resumed")
