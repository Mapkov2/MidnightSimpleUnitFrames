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
local ns={}
assert(loadfile(root.."/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"))("MSUF",ns)
local scheduler=ns.Scheduler
local survived,deferred=0,0
OriginalCallback=function()
  scheduler.ScheduleOnce("deferred",function() deferred=deferred+1 end)
  error("intentional callback failure")
end
scheduler.ScheduleOnce("failing",OriginalCallback)
scheduler.ScheduleOnce("survivor",function() survived=survived+1 end)
driver.tick()
assert(#reported==1 and callbackPresent,"original error stack was unwound before reporting")
assert(survived==1 and deferred==0 and driver.tick,"failure stranded work or ran newly queued work immediately")
driver.tick()
assert(deferred==1 and not driver.tick,"next-frame work was lost or scheduler stayed armed")
assert(scheduler.head==1 and scheduler.tail==0 and next(scheduler.pending)==nil,"queue state leaked after error")
_G.geterrorhandler=function() return function() error("broken third-party handler") end end
scheduler.ScheduleOnce("handler_failure",function() error("still report original failure") end)
scheduler.ScheduleOnce("survivor2",function() survived=survived+1 end)
driver.tick()
assert(survived==2 and #prints==1 and prints[1]:find("still report original failure",1,true),"broken handler stranded queue or lost fallback report")
assert(not driver.tick and next(scheduler.pending)==nil,"handler error left queue armed")
_G.print=nativePrint
print("Scheduler traceback: original callback retained; errors isolated; nested work deferred; broken error handler handled")
