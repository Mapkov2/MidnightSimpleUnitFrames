-- The exported status updater retains the original callable guard and warm cost.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = dofile(root .. "/tools/tests/client_world.lua")
local caps = {
    ["boss1"] = { 6500, 4700 }, ["boss8"] = { 6500, 4700 },
    ["target"] = { 4300, 4100 }, ["false"] = { 3700, 3500 },
}
local cases = {
    { "boss1", 1 }, { "boss8", 8 }, { "target", false }, { false, false },
}
local errors = {}
for _, provider in ipairs({ "native", "absent", "malformed" }) do
    local w = World.New(root, flavor)
    w:Boot()
    assert(not w:FirstFailure(), flavor .. ": graph did not boot")
    local frame = w.env.CreateFrame("Frame", nil, w.env.UIParent)
    frame.bossNumberText = frame:CreateFontString()
    local fs, update = frame.bossNumberText, w.core.UFStatusRuntime.UpdateBossNumber
    for i = 1, 60 do
        local name = debug.getupvalue(update, i)
        if not name then break end
        if name == "GetBossIndexFromToken" then
            if provider == "absent" then debug.setupvalue(update, i, nil) end
            if provider == "malformed" then debug.setupvalue(update, i, {}) end
        end
    end
    local writes, shown = 0, nil
    fs.SetText = function(_, text) writes = writes + 1; fs.text = text end
    fs.SetShown = function(_, value) writes = writes + 1; shown = value end
    for _, case in ipairs(cases) do
        for _, enabled in ipairs({ true, false }) do
            frame.MSUFUnitKey = case[1] or nil
            local status = { bossNumber = { enabled = enabled } }
            update(frame, status)
            local expected = provider == "native" and enabled and case[2] or false
            assert(shown == (expected ~= false), "boss-number visibility changed")
            if expected then assert(fs.text == tostring(expected), "boss index changed") end
            local work = 0
            writes = 0
            debug.sethook(function()
                if debug.getinfo(2, "S").source:find("/MidnightSimpleUnitFrames/", 1, true) then work = work + 1 end
            end, "", 1)
            for i = 1, 100 do update(frame, status) end
            debug.sethook()
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for i = 1, 1000 do update(frame, status) end
            local allocated = collectgarbage("count") - before
            collectgarbage("restart")
            local label = provider .. ":" .. tostring(case[1]) .. ":" .. tostring(enabled)
            print(label, work, writes, allocated)
            local cap = provider == "native" and caps[tostring(case[1])][enabled and 1 or 2] or (enabled and 2700 or 2500)
            local allocationCap = provider == "native" and case[1] == "target" and 21 / 1024 or 0
            if work > cap or writes ~= 0 or allocated > allocationCap then
                errors[#errors + 1] = label .. ": " .. work .. " VM, " .. writes .. " natives, " .. allocated .. " KiB"
            end
        end
    end
end
assert(#errors == 0, flavor .. ": warm boss-number regression:\n" .. table.concat(errors, "\n"))
print("boss_number_warm_update_smoke: ok (" .. flavor .. ": index/fallback, enabled/disabled, natives and allocation)")
