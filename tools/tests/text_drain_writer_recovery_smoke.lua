-- A native ticker survives a callback error; the persistent queue must survive it too.
local root = assert(arg[1])
local ns, tickers, attached, calls = {}, {}, {}, {}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Drain.lua"))("MSUF", ns)
local timer = {}
function timer.NewTicker(delay, callback)
    assert(delay == 0.25)
    local ticker = { callback = callback, armed = true }
    function ticker:Cancel() self.armed = false end
    tickers[#tickers + 1] = ticker
    return ticker
end
local function Tick(ticker)
    assert(ticker.armed, "ticker stopped with queued frames")
    return pcall(ticker.callback)
end
local function Write(frame)
    calls[#calls + 1] = frame.unit
    if frame.fail then error("writer failure") end
    if frame.enqueue then frame.enqueue() end
end
local cancel, _, _, markHealth, markPower = ns.UFModuleFactories.TextDrain(
    timer, nil, false, { attachedFrames = attached }, Write, Write, function() return false end, type,
    function(frame) return frame.visible ~= false end)
local function Frame(unit, fail)
    local frame = { unit = unit, fail = fail, _msufActiveElements = { HealthText = true, PowerText = true },
        _msufTextRuntime = { healthSlotCount = 1, powerSlotCount = 1 } }
    attached[frame] = true
    return frame
end
local first, second, third = Frame("first", true), Frame("second", true), Frame("third")
markHealth(first)
markHealth(second)
markPower(third)
assert(#tickers == 1, "queue created multiple tickers")
local ticker = tickers[1]
local ok, why = Tick(ticker)
assert(not ok and why:find("writer failure", 1, true), "first writer did not fail")
assert(first._msufTextDirtyQueued == nil and second._msufTextDirtyQueued == true, "failing item did not detach")
markHealth(second) -- Already queued: this cannot repair a lost batch.
ok, why = Tick(ticker)
assert(not ok and why:find("writer failure", 1, true), "second writer was stranded after the first error")
assert(second._msufTextDirtyQueued == nil and third._msufTextDirtyQueued == true, "second error lost remaining work")
first.fail = false
markHealth(first) -- Requeue the failed item into the next batch.
assert(Tick(ticker))
assert(table.concat(calls, ",") == "first,second,third", "surviving item order differs")
assert(third._msufTextDirtyQueued == nil)
assert(Tick(ticker))
assert(table.concat(calls, ",") == "first,second,third,first", "requeued failed item was lost/replayed")
assert(Tick(ticker) and not ticker.armed, "empty drain did not cancel")
-- Writer-enqueued work stays in the next batch, including after a resumed batch.
local extra, producer, cancelled, hidden = Frame("extra"), Frame("producer"), Frame("cancelled"), Frame("hidden")
producer.enqueue = function() markPower(extra) end
hidden.visible = false
markHealth(producer)
markHealth(cancelled)
markHealth(hidden)
cancel(cancelled)
local nextTicker = tickers[2]
assert(nextTicker and Tick(nextTicker))
assert(calls[#calls] == "producer" and extra._msufTextDirtyQueued == true, "writer work ran in the same batch")
assert(cancelled._msufTextDirtyQueued == nil and hidden._msufTextDirtyQueued == nil, "skipped item remained queued")
assert(Tick(nextTicker) and calls[#calls] == "extra", "writer-enqueued work was lost")
assert(Tick(nextTicker) and not nextTicker.armed)
print("PASS text_drain_writer_recovery_smoke")
