-- Zero-allocation public cleanup and real allocation mutants calibrate heap guards.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local Family = assert(loadfile(root .. "/tools/tests/preview_family_world.lua"))(root, flavor)
local World = Family.New(false)
local env = World.env
assert(env.time() == 1234567890, "clock fixture drift")
assert(env.date() == os.date("%c", 1234567890), "optional date format changed")
assert(env.date("%Y", 0) == os.date("%Y", 0), "explicit timestamp ignored")
assert(env.date("!*t", 0).year == 1970, "table date provider changed")
local dateTable = { year = 2000, month = 1, day = 2, hour = 3, min = 4, sec = 5 }
assert(env.time(dateTable) == os.time(dateTable), "explicit time table ignored")
assert(not pcall(env.date, false) and not pcall(env.date, "%c", false), "invalid date arguments accepted")
local clear = assert(env.MSUF_ClearBossUnitframePreviewForCombat)
local function Sample(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for i = 1, 100 do fn() end
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    return allocated
end
for _, mode in ipairs(arg[3] and { arg[3] } or { "plain", "table", "closure", "string" }) do
    local held, sequence = {}, 0
    for i = 1, 250 do held[i] = false end
    -- The changed function is the actual public cleanup export. It creates
    -- the extra object during the measured operation, after the same native work.
    env.MSUF_ClearBossUnitframePreviewForCombat = function()
        local result = clear()
        sequence = sequence + 1
        if mode == "table" then held[sequence] = {}
        elseif mode == "closure" then held[sequence] = function() return sequence end
        elseif mode == "string" then held[sequence] = string.format("heap-mutant/%07d", sequence) end
        return result
    end
    local one = Sample(env.MSUF_ClearBossUnitframePreviewForCombat)
    local two = Sample(env.MSUF_ClearBossUnitframePreviewForCombat)
    print(string.format("public cleanup %s %s two heap samples %.6f / %.6f KB", flavor, mode, one, two))
    if arg[3] then assert(math.min(one, two) == 0, "public cleanup allocation regression")
    elseif mode == "plain" then assert(one == 0 and two == 0, "unchanged cleanup allocated")
    else assert(one > 0 and two > 0, "real allocation mutant escaped heap guard") end
end
-- Edit Mode transitions copy the whole profile. With the identity-free copy, equal source
-- allocates equal bytes in fresh graphs, and a real allocation added to the same transitions
-- still shows. Both worlds run one complete open, suspend, resume and close per sample.
local function Timers(w)
    local pending, ran = w.widgets.timers, 0
    while #pending > 0 do
        local entry = table.remove(pending, 1)
        if not entry.cancelled and (not entry.timer or entry.timer.iterations == 1) then
            entry.callback()
            ran = ran + 1
            assert(ran < 1000, "unbounded deferred operation")
        end
    end
end
local function EditModeWorld(mode)
    local w = Family.New(false)
    Family.IdentityFreeSnapshots(w)
    local held, sequence, refresh = {}, 0, w.env.MSUF_RefreshAllUnitVisibilityDrivers
    for i = 1, 400 do held[i] = false end
    -- The mutant adds its object to the resume path after the same real work. A string is long
    -- enough to exceed a string-table growth step that lands in one graph only.
    w.env.MSUF_RefreshAllUnitVisibilityDrivers = function(...)
        local result = refresh(...)
        sequence = sequence + 1
        if mode == "table" then held[sequence] = {}
        elseif mode == "closure" then held[sequence] = function() return sequence end
        elseif mode == "string" then held[sequence] = string.rep("m", 256) .. sequence end
        return result
    end
    return function()
        local em = w.core.EditMode
        em.Open("boss", { provider = "ellesmere" })
        Timers(w)
        em.SuspendExternalPreview()
        em.ResumeExternalPreview()
        Timers(w)
        em.Close("family-cost")
        Timers(w)
    end
end
local function EditModeBytes(mode, reverse)
    local plain, changed = EditModeWorld("plain"), EditModeWorld(mode)
    collectgarbage("collect")
    collectgarbage("stop")
    for i = 1, 8 do
        if reverse then changed() plain() else plain() changed() end
    end
    local plainMin, changedMin
    for sample = 1, 2 do
        local plainBytes, changedBytes = 0, 0
        for i = 1, 2 do
            local function Run(fn)
                local before = collectgarbage("count")
                fn()
                return collectgarbage("count") - before
            end
            if reverse then changedBytes = changedBytes + Run(changed) plainBytes = plainBytes + Run(plain)
            else plainBytes = plainBytes + Run(plain) changedBytes = changedBytes + Run(changed) end
        end
        plainMin = not plainMin and plainBytes or math.min(plainMin, plainBytes)
        changedMin = not changedMin and changedBytes or math.min(changedMin, changedBytes)
    end
    collectgarbage("restart")
    return plainMin, changedMin
end
for _, mode in ipairs(arg[3] and { arg[3] } or { "plain", "table", "closure", "string" }) do
    local larger = 0
    for _, reverse in ipairs({ false, true }) do
        local plainBytes, changedBytes = EditModeBytes(mode, reverse)
        print(string.format("edit mode %s %s reverse=%s plain %.6f / changed %.6f KB", flavor, mode,
            tostring(reverse), plainBytes, changedBytes))
        if changedBytes > plainBytes then larger = larger + 1 end
    end
    -- Unrelated identity-keyed visited sets add address-dependent bytes to one order of a pair; equal
    -- code must not allocate more in both, and a real mutant must show in at least one.
    if mode == "plain" or arg[3] then assert(larger < 2, "edit mode transition allocation regression")
    else assert(larger > 0, "edit mode allocation mutant escaped heap guard") end
end
print("PASS public cleanup allocation controls " .. flavor)
