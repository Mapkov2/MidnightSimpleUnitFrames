-- Heavy preview work is fair and bounded without changing ordinary next-frame work.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = arg[2] or root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Scheduler.lua"
local function Run(withBoundary)
    local frame, errors, output = nil, {}, {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.C_Timer = { After = function() end }
    env.TimerUtil = nil
    env.CreateFrame = function()
        frame = {}
        function frame:SetScript(_, fn) self.update = fn end
        return frame
    end
    if withBoundary then
        env.secureexecuterange = function(list, fn, ...)
            for i = 1, #list do
                local ok, err = pcall(fn, i, list[i], ...)
                if not ok then errors[#errors + 1] = tostring(err) end
            end
        end
    else
        env.secureexecuterange = false
    end
    local ns = { ExportPublic = function() end }
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)("MidnightSimpleUnitFrames", ns)
    local scheduler = ns.Scheduler
    assert(type(scheduler.RunWorkNextFrame) == "function", "heavy work API missing")
    local function Flush()
        assert(frame.update, "expected an armed frame")
        local ok, err = pcall(frame.update)
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    local function Mark(name) return function() output[#output + 1] = name end end
    local a, b = Mark("a"), Mark("b")
    scheduler.RunWorkNextFrame(a)
    scheduler.RunWorkNextFrame(a)
    scheduler.RunWorkNextFrame(b)
    scheduler.RunNextFrame(Mark("ordinary1"))
    scheduler.RunNextFrame(Mark("ordinary2"))
    Flush()
    assert(table.concat(output, ",") == "a,ordinary1,ordinary2", "ordinary and heavy queues interfered")
    Flush()
    assert(table.concat(output, ",") == "a,ordinary1,ordinary2,b", "duplicate or lost heavy work")
    assert(frame.update == nil, "drained driver stayed active")
    output = {}
    local turns, again = 0
    again = function()
        output[#output + 1] = "again"
        turns = turns + 1
        if turns < 2 then scheduler.RunWorkNextFrame(again) end
    end
    scheduler.RunWorkNextFrame(again)
    scheduler.RunWorkNextFrame(b)
    Flush(); assert(table.concat(output, ",") == "again")
    Flush(); assert(table.concat(output, ",") == "again,b", "reentrant owner overtook another owner")
    Flush(); assert(table.concat(output, ",") == "again,b,again", "reentrant owner was lost")
    assert(frame.update == nil)
    output = {}
    scheduler.RunNextFrame(function() scheduler.RunWorkNextFrame(a) end)
    Flush(); assert(#output == 0, "new heavy work ran in the same ordinary callback turn")
    Flush(); assert(output[1] == "a")
    output = {}
    scheduler.RunWorkNextFrame(function() error("expected isolated work failure") end)
    scheduler.RunWorkNextFrame(a)
    scheduler.RunWorkNextFrame(b)
    Flush(); assert(#errors == 1 and #output == 0)
    Flush(); assert(table.concat(output, ",") == "a", "failed work stranded next owner")
    Flush(); assert(table.concat(output, ",") == "a,b", "failed work stranded final owner")
    assert(frame.update == nil)
    output = {}
    local owner = {}
    scheduler.RunWorkNextFrame(Mark("old"), owner)
    scheduler.RunWorkNextFrame(b)
    scheduler.RunWorkNextFrame(Mark("new"), owner)
    Flush(); assert(table.concat(output, ",") == "new", "stable owner did not replace its pending callback")
    Flush(); assert(table.concat(output, ",") == "new,b", "replacement changed FIFO position or duplicated owner")
    assert(frame.update == nil)
    output = {}
    scheduler.RunWorkNextFrame(function()
        output[#output + 1] = "owner"
        scheduler.RunWorkNextFrame(Mark("owner-next"), owner)
    end, owner)
    scheduler.RunWorkNextFrame(b)
    Flush(); assert(table.concat(output, ",") == "owner")
    Flush(); assert(table.concat(output, ",") == "owner,b")
    Flush(); assert(table.concat(output, ",") == "owner,b,owner-next", "owner requeue was not fair")
    assert(frame.update == nil)
    local ok = pcall(scheduler.RunWorkNextFrame, false)
    assert(not ok, "invalid callback accepted")
    assert(not scheduler.nextFrameActive, "work left the scheduler busy")
end
Run(true)
Run(false)
print("PASS scheduler_work_queue_smoke: FIFO, dedup, owner replacement, one work per frame, reentrancy, ordinary isolation, errors")
