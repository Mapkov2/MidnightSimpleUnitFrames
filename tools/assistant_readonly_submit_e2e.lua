_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local M = assert(_G.MSUF2, "Menu namespace missing after dashboard smoke")
M.frame = M.frame or { IsShown = function() return true end }
local menuRoot = "MidnightSimpleUnitFrames_Assistant/"
if not exists(menuRoot .. "MSUF_Menu2_AssistantDialogLocale_Data.lua") then menuRoot = "../MidnightSimpleUnitFrames_Assistant/" end
for _, name in ipairs({ "MSUF_Menu2_AssistantDialogLocale_Data.lua", "MSUF_Menu2_AssistantDialogLocale.lua" }) do
    local chunk, err = loadfile(menuRoot .. name)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", _G.MSUF_NS)
end
local reportOnly = type(arg) == "table" and arg[1] == "--report-only"

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end
    return out
end

local function scalar(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local function collectDiffs(before, after, path, out, seen)
    path = path or "MSUF_DB"
    out = out or {}
    seen = seen or {}
    if type(before) ~= type(after) then
        out[#out + 1] = path .. ": " .. scalar(before) .. " -> " .. scalar(after)
        return out
    end
    if type(before) ~= "table" then
        if before ~= after then out[#out + 1] = path .. ": " .. scalar(before) .. " -> " .. scalar(after) end
        return out
    end
    if seen[before] and seen[before] == after then return out end
    seen[before] = after
    local keys = {}
    for key in pairs(before) do keys[key] = true end
    for key in pairs(after) do keys[key] = true end
    local ordered = {}
    for key in pairs(keys) do ordered[#ordered + 1] = key end
    table.sort(ordered, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(ordered) do
        local childPath = path .. "." .. tostring(key)
        if before[key] == nil and after[key] ~= nil then
            out[#out + 1] = childPath .. ": <nil> -> " .. scalar(after[key])
        elseif before[key] ~= nil and after[key] == nil then
            out[#out + 1] = childPath .. ": " .. scalar(before[key]) .. " -> <nil>"
        else
            collectDiffs(before[key], after[key], childPath, out, seen)
        end
    end
    return out
end

local function settingsSnapshot()
    local snapshot = copy(_G.MSUF_DB or {})
    -- Chat history and conversational context are expected to change on every
    -- answer; the invariant below covers profile/setting data.
    snapshot.assistant = nil
    return snapshot
end

-- In the client, profile defaults are materialized by normal menu use. Prime
-- readers once so lazy default tables are not counted as user setting edits.
for _, setting in ipairs((A.Registry and A.Registry:AllSettings()) or {}) do
    if type(setting.get) == "function" then pcall(setting.get) end
end

local function clearPendingState()
    if type(A.RouterClearPendingResultsForRoute) == "function" then A.RouterClearPendingResultsForRoute() end
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    A.pendingSelectedResult = nil
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
    local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
end

local acceptance = {
    { input = "what is target frame width", all = { "target", "width" } },
    { input = "where is raid ready check", all = { "raid", "ready" } },
    { input = "what depends on target buffs", all = { "target", "buff" }, any = { "depend", "relationship", "requires", "controls" } },
    { input = "why is player power text hidden", all = { "player", "power", "text" }, any = { "hidden", "visibility", "show" } },
    { input = "how do profiles work", all = { "profile" } },
    { input = "explain class resource width mode", all = { "class", "resource", "width" } },
    { input = "where can I change castbar texture", all = { "cast", "texture" } },
    { input = "why are party frames missing", all = { "party", "frame" }, any = { "missing", "hidden", "show", "visibility" } },
    { input = "what are your limits", all = { "limit" } },
    { input = "answer in German what is aura filtering", all = { "aura", "filter" }, language = "de", germanOutput = true },
}

local extraReadOnly = {
    { input = "what other addons work well with msuf?", all = { "msuf", "clique", "betterfriendlist", "eqol" }, none = { "i found this in msuf", "group layout" } },
    { input = "Can I use EQoL with MSUF?", all = { "msuf", "enhance qol", "unit frames" }, none = { "copy party", "confirmation", "i found this in msuf" } },
    { input = "what is aura filtering", all = { "aura", "filter" } },
    { input = "answer in English what is aura filtering", all = { "aura", "filter" }, language = "en" },
    { input = "wie kann ich die target breite aendern", all = { "target" } },
    { input = "wo kann ich target buffs ausblenden", all = { "target", "buff" } },
    { input = "how do I hide player name", all = { "player", "name" } },
    { input = "which setting controls raid spacing", all = { "raid", "spacing" } },
    { input = "list settings related to castbar texture", all = { "cast", "texture" } },
    { input = "set target width", all = { "target", "width" } },
    { input = "show me where target buffs are configured", all = { "target", "buff" } },
    { input = "can you show me where target buffs are configured", all = { "target", "buff" } },
    { input = "show me target buff settings", all = { "target", "buff", "current" }, none = { "couldn't find", "target width", "target height" } },
}

local failures = {}
local timings = {}
local acceptanceTimings = {}

local function fail(message)
    failures[#failures + 1] = message
    io.write("FAIL " .. message .. "\n")
end

local function checkCase(case, label, index)
    clearPendingState()
    local before = settingsSnapshot()
    local started = os.clock()
    local result = A.Submit(case.input)
    local elapsedMs = (os.clock() - started) * 1000
    timings[#timings + 1] = elapsedMs
    if label == "A" then acceptanceTimings[#acceptanceTimings + 1] = elapsedMs end
    local diffs = collectDiffs(before, settingsSnapshot())
    local status = type(result) == "table" and (result.status or result.result) or nil
    local output = type(result) == "table" and tostring(result.text or "") or ""
    local lower = output:lower()
    local preview = output:gsub("[%c]+", " "):sub(1, 220)
    io.write(string.format("CASE %s%02d %.3fms status=%s diffs=%d input=%s\n", label, index, elapsedMs, tostring(status), #diffs, case.input))
    io.write("  output=" .. preview .. "\n")
    for _, diff in ipairs(diffs) do io.write("  diff=" .. diff .. "\n") end

    if type(result) ~= "table" then fail(case.input .. ": missing result") end
    if status == "applied" or status == "changed" then fail(case.input .. ": read-only request returned mutation status " .. tostring(status)) end
    if #diffs > 0 then fail(case.input .. ": changed MSUF_DB") end
    for _, term in ipairs(case.all or {}) do
        if not lower:find(term, 1, true) then fail(case.input .. ": missing topic term " .. term) end
    end
    for _, term in ipairs(case.none or {}) do
        if lower:find(term, 1, true) then fail(case.input .. ": contained forbidden term " .. term) end
    end
    if type(case.any) == "table" then
        local found = false
        for _, term in ipairs(case.any) do
            if lower:find(term, 1, true) then found = true; break end
        end
        if not found then fail(case.input .. ": missing all expected relation/diagnostic terms") end
    end
    if case.language and A.DialogLocale and type(A.DialogLocale.GetLanguage) == "function" then
        local actualLanguage = A.DialogLocale.GetLanguage()
        if actualLanguage ~= case.language then fail(case.input .. ": expected response language " .. case.language .. ", got " .. tostring(actualLanguage)) end
    end
    if case.germanOutput and not (lower:find("hier ist", 1, true)
        or lower:find("hilfe:", 1, true)
        or lower:find("technische details", 1, true))
    then
        fail(case.input .. ": German response contains no localized visible wording")
    end
end

for index, case in ipairs(acceptance) do checkCase(case, "A", index) end
for index, case in ipairs(extraReadOnly) do checkCase(case, "R", index) end

do
    clearPendingState()
    local setting = assert(A.Registry and A.Registry:GetSetting("target.width"), "target.width setting missing")
    local before = setting.get()
    local requested = tonumber(before) == 321 and 322 or 321
    local changed = A.Submit("can you set target width to " .. tostring(requested))
    local changedStatus = changed and (changed.status or changed.result)
    if changedStatus ~= "applied" or tonumber(setting.get()) ~= requested then
        fail("explicit can-you mutation was blocked or applied the wrong target width")
    end
    local undone = A.Submit("undo")
    local undoStatus = undone and (undone.status or undone.result)
    if undoStatus ~= "applied" or setting.get() ~= before then fail("explicit mutation undo did not restore target.width") end
    io.write(string.format("MUTATION explicit=can-you status=%s undo=%s restored=%s\n",
        tostring(changedStatus), tostring(undoStatus), tostring(setting.get() == before)))
end

do
    clearPendingState()
    local setting = assert(A.Registry and A.Registry:GetSetting("target.showPowerText"), "target.showPowerText setting missing")
    setting.set(true)
    local before = setting.get()
    local command = "hide target power text"
    local changed = A.Submit(command)
    local changedStatus = changed and (changed.status or changed.result)
    if changedStatus ~= "applied" or setting.get() == before then fail("explicit boolean imperative was blocked") end
    local undone = A.Submit("undo")
    local undoStatus = undone and (undone.status or undone.result)
    if undoStatus ~= "applied" or setting.get() ~= before then fail("boolean imperative undo did not restore target.showPowerText") end
    io.write(string.format("MUTATION explicit=boolean status=%s undo=%s restored=%s\n",
        tostring(changedStatus), tostring(undoStatus), tostring(setting.get() == before)))
end

do
    clearPendingState()
    local target = assert(A.Registry and A.Registry:GetSetting("target.width"), "target.width setting missing")
    local focus = assert(A.Registry and A.Registry:GetSetting("focus.width"), "focus.width setting missing")
    local targetBefore, focusBefore = target.get(), focus.get()
    local targetValue = tonumber(targetBefore) == 331 and 332 or 331
    local focusValue = tonumber(focusBefore) == 341 and 342 or 341
    local changed = A.Submit("set target width to " .. targetValue .. " and set focus width to " .. focusValue)
    local changedStatus = changed and (changed.status or changed.result)
    if changedStatus ~= "applied" or tonumber(target.get()) ~= targetValue or tonumber(focus.get()) ~= focusValue then
        fail("explicit atomic batch was blocked or partially applied")
    end
    local undone = A.Submit("undo")
    local undoStatus = undone and (undone.status or undone.result)
    if undoStatus ~= "applied" or target.get() ~= targetBefore or focus.get() ~= focusBefore then
        fail("atomic batch undo did not restore both widths")
    end
    io.write(string.format("MUTATION explicit=batch status=%s undo=%s restored=%s\n",
        tostring(changedStatus), tostring(undoStatus), tostring(target.get() == targetBefore and focus.get() == focusBefore)))
end

table.sort(timings)
table.sort(acceptanceTimings)
local function percentile(values, fraction)
    local count = #values
    if count == 0 then return 0 end
    local index = math.max(1, math.min(count, math.ceil(count * fraction)))
    return values[index]
end
local sum = 0
for _, value in ipairs(timings) do sum = sum + value end
local acceptanceSum = 0
for _, value in ipairs(acceptanceTimings) do acceptanceSum = acceptanceSum + value end
-- With ten acceptance cases a "p95" is arithmetically just the slowest sample,
-- so asserting on it measured one scheduling outlier rather than felt latency
-- and flipped between runs on an otherwise idle machine. Bound the two things
-- that actually matter instead: the median, which is what a user experiences
-- per request, and an absolute ceiling for the worst sample. Both budgets are
-- tighter than the ceiling they replace.
local acceptanceP50 = percentile(acceptanceTimings, 0.50)
local acceptanceP95 = percentile(acceptanceTimings, 0.95)
local acceptanceMax = acceptanceTimings[#acceptanceTimings] or 0
io.write(string.format("ACCEPTANCE cases=%d avg=%.3fms p50=%.3fms p95=%.3fms max=%.3fms slo=%s\n",
    #acceptanceTimings, acceptanceSum / math.max(1, #acceptanceTimings), acceptanceP50,
    acceptanceP95, acceptanceMax, (acceptanceP50 <= 25 and acceptanceMax <= 80) and "PASS" or "FAIL"))
if acceptanceP50 > 25 then fail(string.format("interactive acceptance median %.3fms exceeds 25ms", acceptanceP50)) end
if acceptanceMax > 80 then fail(string.format("interactive acceptance max %.3fms exceeds 80ms", acceptanceMax)) end
io.write(string.format("SUMMARY cases=%d failures=%d avg=%.3fms p50=%.3fms p95=%.3fms max=%.3fms\n",
    #timings, #failures, sum / math.max(1, #timings), percentile(timings, 0.50), percentile(timings, 0.95), timings[#timings] or 0))

if #failures > 0 and not reportOnly then error("assistant_readonly_submit_e2e: " .. tostring(#failures) .. " failures", 0) end
io.write("assistant_readonly_submit_e2e: " .. (#failures == 0 and "ok" or "report-only") .. "\n")
