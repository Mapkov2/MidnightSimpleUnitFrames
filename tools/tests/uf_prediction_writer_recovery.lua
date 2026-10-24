-- Real queue bodies, isolated from prediction painters/native health data.
-- arg 2 "budget" measures the healthy path only; arg 3 optionally selects a baseline source.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Prediction.lua"
local file = assert(io.open(arg[3] or path, "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local start = assert(source:find("local predictionQueueA, predictionQueueB", 1, true)
    or source:find("local predictionWriteQueue, predictionReadQueue", 1, true))
local finish = assert(source:find("\nfunction Prediction.UpdateHealthValue", start, true))
local body = source:sub(start, finish - 1)

local function World(persistent)
    local w = { calls = {}, natives = 0, writes = 0, glow = 0 }
    local driver = { shown = false }
    function driver:SetScript(_, fn) self.callback = fn; w.natives = w.natives + 1 end
    if persistent then
        function driver:Show() self.shown = true; w.natives = w.natives + 1 end
        function driver:Hide() self.shown = false; w.natives = w.natives + 1 end
    end
    local function Write(frame, mask)
        w.writes = w.writes + 1
        if not w.measuring then w.calls[#w.calls + 1] = frame.name .. ":" .. mask end
        assert(frame._msufPredictionDirtyMask == nil and frame._msufPredictionQueued == nil,
            "writer ran before dequeue state was committed")
        if frame.fail then error("prediction writer failure") end
        if frame.enqueue then frame.enqueue() end
    end
    local env = setmetatable({
        MSUF = { PublicGlobals = {} },
        CreateFrame = function() return driver end,
        PREDICTION_DATA_EVENT_BITS = { UNIT_HEAL_PREDICTION = 1, UNIT_ABSORB_AMOUNT_CHANGED = 2,
            UNIT_HEAL_ABSORB_AMOUNT_CHANGED = 4 },
        PREDICTION_DIRTY_PLAN_KEYS = { [1] = "heal", [2] = "absorb", [7] = "all" },
        UpdateFull = function(frame, event) w.fallback = event; Write(frame, 7) end,
        UpdateGlowHealthFast = function() w.glow = w.glow + 1 end,
    }, { __index = _G })
    local chunk = assert(loadstring(body .. "\nreturn QueuePredictionDataEvent, CancelQueuedPrediction", "@" .. path))
    setfenv(chunk, env)
    w.queue, w.cancel = chunk()
    function w:Frame(name, fail)
        return { name = name, fail = fail, MSUFUnitKey = name, _msufPredictionFlushData = Write }
    end
    function w:Armed() return driver.callback ~= nil and (not persistent or driver.shown) end
    function w:Tick()
        assert(self:Armed(), "prediction driver stopped with queued frames")
        return pcall(driver.callback)
    end
    w.driver, w.env = driver, env
    return w
end

local function Recovery(persistent)
    local w = World(persistent)
    local first, second = w:Frame("first", true), w:Frame("second")
    w.queue(first, "UNIT_ABSORB_AMOUNT_CHANGED")
    w.queue(second, "UNIT_HEAL_PREDICTION")
    local ok, why = w:Tick()
    assert(not ok and why:find("prediction writer failure", 1, true), "writer error was hidden")
    assert(first._msufPredictionQueued == nil and second._msufPredictionQueued == true)
    w.queue(second, "UNIT_ABSORB_AMOUNT_CHANGED") -- Already queued; cannot repair a lost batch.
    assert(w:Armed(), "writer failure stranded the second frame")
    first.fail = false
    w.queue(first, "UNIT_ABSORB_AMOUNT_CHANGED")
    assert(w:Tick())
    assert(table.concat(w.calls, ",") == "first:2,second:3", "resumed batch lost/replayed an item")
    assert(w:Tick() and w.calls[3] == "first:2", "requeued failed item did not run next tick")
    assert(not w:Armed(), "empty prediction driver remained armed")

    -- Cancellation after an error must not disarm an unfinished read batch.
    local bad, cancelled, survivor = w:Frame("bad", true), w:Frame("cancelled"), w:Frame("survivor")
    w.queue(bad, "UNIT_HEAL_PREDICTION")
    w.queue(cancelled, "UNIT_HEAL_PREDICTION")
    w.queue(survivor, "UNIT_HEAL_PREDICTION")
    assert(not w:Tick())
    assert(w.cancel(cancelled) and w:Armed(), "cancellation disarmed the unfinished read batch")
    assert(w:Tick() and w.calls[#w.calls] == "survivor:1")
    assert(cancelled._msufPredictionQueued == nil and not w:Armed())

    -- A sync takeover of a sealed item consumes its union once, then the read cursor skips its empty mask.
    local syncFirst, syncSecond = w:Frame("syncFirst", true), w:Frame("syncSecond")
    w.queue(syncFirst, "UNIT_HEAL_PREDICTION")
    w.queue(syncSecond, "UNIT_HEAL_PREDICTION")
    assert(not w:Tick())
    w.env.MSUF.PublicGlobals.MSUF_GF_PredictionSync = true
    w.queue(syncSecond, "UNIT_ABSORB_AMOUNT_CHANGED")
    local writes = w.writes
    assert(w.calls[#w.calls] == "syncSecond:3" and w:Tick())
    assert(w.writes == writes and not w:Armed(), "sealed item replayed after synchronous takeover")
    w.env.MSUF.PublicGlobals.MSUF_GF_PredictionSync = false

    -- Work queued by a writer belongs to the next rendered frame.
    local extra, producer = w:Frame("extra"), w:Frame("producer")
    producer.enqueue = function() w.queue(extra, "UNIT_HEAL_PREDICTION") end
    producer._msufPredictionGlowDeferred = true
    w.queue(producer, "UNIT_HEAL_PREDICTION")
    assert(w:Tick() and w.calls[#w.calls] == "producer:1" and w:Armed())
    assert(w.glow == 1 and extra._msufPredictionQueued == true)
    assert(w:Tick() and w.calls[#w.calls] == "extra:1" and not w:Armed())

    -- The missing-plan fallback and single-absorb synchronous path keep their contracts.
    extra._msufPredictionFlushData = nil
    for _, event in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }) do
        w.queue(extra, event)
    end
    assert(w:Tick() and w.fallback == "all")
    producer.enqueue = nil
    producer._msufPredictionSimpleAbsorb = true
    w.queue(producer, "UNIT_ABSORB_AMOUNT_CHANGED")
    assert(not w:Armed() and w.calls[#w.calls] == "producer:2")

    -- A final-item error keeps only one empty cleanup tick, and can be queued anew.
    first.fail = true
    w.queue(first, "UNIT_HEAL_PREDICTION")
    assert(not w:Tick() and w:Armed())
    assert(w:Tick() and not w:Armed(), "last-item failure left the driver running")
    first.fail = false
    w.queue(first, "UNIT_HEAL_PREDICTION")
    assert(w:Tick() and w.calls[#w.calls] == "first:1")

    local noDriver = World(persistent)
    noDriver.env.CreateFrame = nil
    noDriver.queue(noDriver:Frame("synchronous"), "UNIT_HEAL_PREDICTION")
    assert(noDriver.calls[1] == "synchronous:1", "missing-driver synchronous fallback changed")
    print("PASS uf_prediction_writer_recovery " .. (persistent and "persistent" or "script"))
end

-- Keeping the queue within the module's local ceiling must preserve native clamp enums.
local function ClampBinding()
    local first = assert(source:find('local WHITE = ', 1, true))
    local last = assert(source:find('local TEST_MAX = ', first, true))
    local fnStart = assert(source:find('local function ShowProtectedOverAbsorb(', 1, true))
    local fnEnd = assert(source:find('\nlocal function ShowFullHealthStripe(', fnStart, true))
    local mode
    local calc = {
        SetDamageAbsorbClampMode = function(_, value) mode = value end,
        GetDamageAbsorbs = function() return 0, true end,
    }
    local function Noop() end
    local env = setmetatable({
        Enum = { UnitDamageAbsorbClampMode = { MissingHealth = 42, MissingHealthWithoutIncomingHeals = 43 } },
        issecretvalue = function() return false end,
        UnitGetDetailedHealPrediction = Noop,
        CreateUnitHealPredictionCalculator = function() return calc end,
        SetOverAbsorbAlpha = Noop,
    }, { __index = _G })
    local chunk = assert(loadstring(source:sub(first, last - 1) .. source:sub(fnStart, fnEnd - 1)
        .. '\nreturn ShowProtectedOverAbsorb', '@' .. path))
    setfenv(chunk, env)
    local paint = chunk()
    assert(paint({}, { SetShown = Noop, _msufOverAbsorbGlowTexture = { SetAlphaFromBoolean = Noop } }, "target", true))
    assert(mode == 42, "local-ceiling cleanup lost the native MissingHealth clamp binding")
    print("PASS uf_prediction native clamp binding")
end

-- Baseline fe88bbaa5, 32-bit Lua 5.1, instructions per queued frame (queue + drain).
-- Calls/native writes and allocation are also pinned independently of VM cost.
local BASELINE = { [1] = 93.5, [2] = 70.25, [40] = 48.1625 }
local MODE_BASELINE = {
    duplicate = { 88.25, 3, 1, 1 }, coalesced = { 110.25, 4, 1, 1 }, cancel = { 92, 3, 2, 0 },
    sync = { 30, 1, 0, 1 }, simple = { 13, 1, 0, 1 }, reentrant = { 120, 4, 2, 1.5 },
}
local function Budget(size, mode)
    local w, frames = World(true), {}
    for index = 1, size do frames[index] = w:Frame("budget") end
    if mode == "sync" then w.env.MSUF.PublicGlobals.MSUF_GF_PredictionSync = true end
    if mode == "simple" then
        for index = 1, size do frames[index]._msufPredictionSimpleAbsorb = true end
    end
    local extra = w:Frame("extra")
    if mode == "reentrant" then
        frames[1].enqueue = function() w.queue(extra, "UNIT_ABSORB_AMOUNT_CHANGED") end
    end
    w.measuring = true
    local function Batch()
        for index = 1, size do
            local frame = frames[index]
            w.queue(frame, "UNIT_ABSORB_AMOUNT_CHANGED")
            if mode == "duplicate" then w.queue(frame, "UNIT_ABSORB_AMOUNT_CHANGED") end
            if mode == "coalesced" then
                w.queue(frame, "UNIT_HEAL_PREDICTION")
                w.queue(frame, "UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            end
            if mode == "cancel" then w.cancel(frame) end
        end
        if w:Armed() then assert(w:Tick()) end
        if mode == "reentrant" then assert(w:Tick()) end
    end
    for _ = 1, 10 do Batch() end
    w.natives, w.writes = 0, 0
    local instructions, calls = 0, 0
    debug.sethook(function(event)
        if debug.getinfo(2, "S").source == "@" .. path then
            if event == "count" then instructions = instructions + 1 end
            if event == "call" then calls = calls + 1 end
        end
    end, "c", 1)
    for _ = 1, 100 do Batch() end
    debug.sethook()
    local events = size * 100
    local kb = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 100 do Batch() end
        kb = math.min(kb, (collectgarbage("count") - before) / events)
        collectgarbage("restart")
    end
    local vm, addon, natives, writes = instructions / events, calls / events, w.natives / (events * 3), w.writes / (events * 3)
    print(string.format("prediction budget %s n=%d: %.4f instructions, %.3f addon calls, %.3f natives, %.3f writers, %.6f KB/item",
        mode, size, vm, addon, natives, writes, kb))
    if not arg[3] then
        if mode == "queued" then
            assert(vm <= BASELINE[size], "persistent cursor exceeded the original VM instruction budget")
            assert(addon == 1 + 2 / size and natives == 2 / size and writes == 1,
                "persistent cursor added a per-item function/native call")
        else
            local before = assert(MODE_BASELINE[mode])
            assert(vm <= before[1] and addon <= before[2] and natives <= before[3] and writes == before[4],
                mode .. " exceeded original instruction/call/native budgets or changed writer count")
        end
        assert(kb == 0, "queue/drain allocated per item")
    end
end

if arg[2] ~= "budget" then Recovery(true); Recovery(false); ClampBinding() end
for _, size in ipairs({ 1, 2, 40 }) do Budget(size, "queued") end
for _, mode in ipairs({ "duplicate", "coalesced", "cancel", "sync", "simple", "reentrant" }) do Budget(2, mode) end
