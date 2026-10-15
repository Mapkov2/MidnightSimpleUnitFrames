-- Edit Mode preview behaviour against values frozen from the pre-service parent (7.0-main ec077fd9).
-- The cost smokes run the same Edit Mode code on both sides; this one compares with recorded results.
-- Regenerate only from a parent tree: lua <this file> <package root> <Flavor> write <parent root> > fixture
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local write = arg[3] == "write"
local source = write and assert(arg[4]):gsub("\\", "/"):gsub("/$", "") or root
local Family = assert(loadfile(root .. "/tools/tests/preview_family_world.lua"))(root, flavor, source)
local w = Family.New(false)
local env, em = w.env, w.core.EditMode
local MIRRORS = { "MSUF_UnitEditModeActive", "MSUF_PreviewTestMode", "MSUF_BossTestMode", "MSUF_ArenaTestMode",
    "MSUF2_BossUnitframePreviewActive", "MSUF2_ArenaUnitframePreviewActive", "MSUF_UnitPreviewActive" }
local function Timers()
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
-- Frame state as one number: every recorded boss and arena frame field, in key order.
local function Fingerprint()
    local snapshot, keys, hash = Family.Snapshot(w), {}, 7
    for key in pairs(snapshot) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local text = key .. "=" .. tostring(snapshot[key])
        for i = 1, #text do hash = (hash * 31 + text:byte(i)) % 2147483629 end
    end
    return hash
end
local lines = {}
local function Record(name)
    Timers()
    local row = { name }
    for _, mirror in ipairs(MIRRORS) do row[#row + 1] = tostring(env[mirror]) end
    row[#row + 1] = tostring(em.IsActive()) .. "/" .. tostring(env.MSUF_CurrentEditUnitKey)
    row[#row + 1] = tostring(Fingerprint())
    lines[#lines + 1] = table.concat(row, "\t")
end
local function Step(name, fn)
    fn()
    Record(name)
end
local pages = env.MSUF2.UnitPage
Record("start")
for _, unit in ipairs({ "boss", "arena" }) do
    Step(unit .. " open", function() em.Open(unit) end)
    Step(unit .. " reopen target", function() em.Open("target") end)
    Step(unit .. " sync", function() env.MSUF_SyncAllUnitPreviews() end)
    Step(unit .. " close", function() em.Close("trace") end)
    Step(unit .. " ellesmere open", function() em.Open(unit, { provider = "ellesmere" }) end)
    Step(unit .. " suspend", function() em.SuspendExternalPreview() end)
    Step(unit .. " resume", function() em.ResumeExternalPreview() end)
    Step(unit .. " combat", function() w:EnterCombat() end)
    Step(unit .. " combat end", function() w:LeaveCombat() end)
    Step(unit .. " ellesmere close", function() em.Close("trace") end)
    Step(unit .. " open for cancel", function() em.Open(unit) end)
    Step(unit .. " cancel all", function() env.MSUF_EM2.State.CancelAll() end)
    local setPage = pages[unit == "boss" and "SetBossPagePreviewActive" or "SetArenaPagePreviewActive"]
    Step(unit .. " page on", function() setPage(true) end)
    Step(unit .. " page edit open", function() em.Open(unit) end)
    Step(unit .. " page off", function() setPage(false) end)
    Step(unit .. " page edit close", function() em.Close("trace") end)
end
local failure = w:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
if write then
    print(table.concat(lines, "\n"))
    return
end
local path = root .. "/tools/fixtures/preview/EditModeTrace." .. flavor .. ".tsv"
local file = assert(io.open(path, "rb"), "missing frozen trace " .. path)
local expected = {}
for line in file:read("*a"):gsub("\r\n", "\n"):gmatch("[^\n]+") do expected[#expected + 1] = line end
file:close()
assert(#expected == #lines, flavor .. ": frozen trace has " .. #expected .. " rows, package " .. #lines)
for i = 1, #lines do
    assert(lines[i] == expected[i], flavor .. ": Edit Mode preview behaviour drifted from the frozen parent at row " .. i
        .. "\nfrozen: " .. expected[i]:gsub("\t", " | ") .. "\npackage: " .. lines[i]:gsub("\t", " | "))
end
print("PASS Edit Mode preview behaviour equals the frozen parent " .. flavor .. ": " .. #lines .. " steps")
