_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {},
    bars = {},
    gameplay = {},
    player = {},
    target = { powerBarDetached = true },
    focus = {},
    pet = {},
    units = {
        player = {},
        target = { powerBarDetached = true },
        focus = {},
        pet = {},
    },
    groups = {
        party = {},
        raid = {},
        mythicraid = {},
    },
}

local runtimeLoaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(runtimeLoaderPath)
RuntimeManifest.LoadAssistantRuntime(MSUF)

local A = assert(MSUF.Assistant, "Assistant namespace missing")
A.GetContext = A.GetContext or function() return {} end

-- These fixed-family movement commands must not cold-build the broad exact
-- alias and registry-candidate indices. They are common first prompts and are
-- intentionally measured before any warm-up below.
do
    local parser = assert(A.Parser, "Assistant parser missing")
    local coldCases = {
        { text = "move boss castbar down 5", path = { "general", "bossCastbarOffsetY" }, expected = -5 },
        { text = "lower target power text by 5", path = { "target", "powerOffsetY" }, expected = -1 },
        { text = "raise target power text by 5", path = { "target", "powerOffsetY" }, expected = 4 },
    }
    for i = 1, #coldCases do
        local case = coldCases[i]
        local started = os.clock()
        local result = A.Submit(case.text)
        local elapsedMs = (os.clock() - started) * 1000
        local status = result and (result.status or result.result)
        assert(status == "applied" or status == "changed", case.text .. ": expected applied result, got " .. tostring(status))
        local value = _G.MSUF_DB
        for j = 1, #case.path do value = type(value) == "table" and value[case.path[j]] or nil end
        assert(value == case.expected, case.text .. ": expected " .. tostring(case.expected) .. ", got " .. tostring(value))
        assert(elapsedMs <= 50, string.format("%s: cold route %.3f ms exceeds 50 ms", case.text, elapsedMs))
        io.write(string.format("%.3f ms cold <= 50.000 | %s\n", elapsedMs, case.text))
    end
    assert(parser._registryExactAliasIndex == nil, "cold fixed-family movement built the exact-alias index")
    assert(parser._registryCandidateIndexByToken == nil, "cold fixed-family movement built the registry candidate index")
end

local cases = {
    {
        label = "group aura exact cooldown anchor",
        text = "set party buff cooldown anchor to top left",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "group aura filter",
        text = "set raid buff filter to raid",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "unit aura stack offset",
        text = "set target buff stack x offset to 5",
        kind = "changes",
        maxAvgMs = 12,
    },
    {
        label = "shared aura icon size",
        text = "set all aura icon size to 24",
        kind = "changes",
        maxAvgMs = 8,
    },
    {
        label = "compound numeric boolean chain",
        text = "set player width 300 height 45 target width 250 height 40 names off",
        kind = "changes",
        maxAvgMs = 15,
    },
    {
        label = "compound repeated attribute list",
        text = "set player width height 300 45 target width height 250 40 names off",
        kind = "changes",
        maxAvgMs = 15,
    },
    {
        label = "compound multi-scope booleans",
        text = "turn off player target focus names and portraits but keep power bars on",
        kind = "changes",
        maxAvgMs = 15,
    },
    {
        label = "portrait compound",
        text = "set player portrait shape rounded border thickness 6 background on",
        kind = "changes",
        maxAvgMs = 18,
    },
    {
        label = "detached powerbar generic move",
        text = "move target powerbar to the left",
        kind = "changes",
        maxAvgMs = 6,
    },
    {
        label = "classpower width mode exact alias",
        text = "set class resources width to essential cooldowns",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower root exact alias",
        text = "turn on class resources",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower size exact alias",
        text = "make combo points wider",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower fill direction exact alias",
        text = "make class resource fill right to left",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower visibility exact alias",
        text = "hide class resource out of combat",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower gap exact alias",
        text = "increase class resource spacing",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower text size exact alias",
        text = "make class resource text bigger",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower separator exact alias",
        text = "make combo point separators wider",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower background exact alias",
        text = "show class resource background",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower move exact alias",
        text = "move class resource down 5",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower placement exact alias",
        text = "move class resource under player frame",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower display exact alias",
        text = "show class resources as text",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower anchor exact alias",
        text = "anchor class resources to essential cooldownmanager",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower preview exact alias",
        text = "preview class resource mage arcane",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower preview action alias",
        text = "start class resource preview animation",
        kind = "action",
        summary = "Changes the Class Resources inline preview animation.",
        maxAvgMs = 5,
    },
    {
        label = "classpower color exact alias",
        text = "make combo points blue",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "classpower background color exact alias",
        text = "make holy power background black",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "aura workflow action",
        text = "set aura editing scope to target",
        kind = "changes",
        maxAvgMs = 5,
    },
    {
        label = "aura reset action",
        text = "reset target aura scope",
        kind = "action",
        maxAvgMs = 5,
    },
    {
        label = "knowledge/location fast path",
        text = "where is castbar texture",
        kind = "action",
        maxAvgMs = 8,
    },
}

local iterations = tonumber(arg and arg[1]) or 80
local warmups = tonumber(arg and arg[2]) or 10
local multiplier = tonumber(os.getenv("MSUF_ASSISTANT_PERF_BUDGET_MULTIPLIER") or "1") or 1
local failures = {}

local function fail(message)
    failures[#failures + 1] = message
end

for i = 1, #cases do
    local case = cases[i]
    for _ = 1, warmups do A.Parse(case.text) end

    local started = os.clock()
    local last
    for _ = 1, iterations do
        last = A.Parse(case.text)
    end
    local elapsedMs = (os.clock() - started) * 1000
    local avgMs = elapsedMs / iterations
    local budget = case.maxAvgMs * multiplier
    local kind = last and last.kind or "nil"
    local summary = last and last.summary or ""
    local changes = last and last.changes and #last.changes or 0

    io.write(string.format(
        "%.3f ms avg <= %.3f | %-34s | %s | changes=%d | %s\n",
        avgMs,
        budget,
        case.label,
        tostring(kind),
        changes,
        case.text
    ))

    if kind ~= case.kind then
        fail(string.format("%s: expected kind %s, got %s", case.label, tostring(case.kind), tostring(kind)))
    end
    if case.summary and summary ~= case.summary then
        fail(string.format("%s: expected summary %q, got %q", case.label, case.summary, summary))
    end
    if avgMs > budget then
        fail(string.format("%s: %.3f ms avg exceeds %.3f ms budget", case.label, avgMs, budget))
    end
end

if #failures > 0 then
    io.write("\nassistant_perf_budget_smoke: failed\n")
    for i = 1, #failures do io.write("- " .. failures[i] .. "\n") end
    os.exit(1)
end

io.write(string.format(
    "\nassistant_perf_budget_smoke: ok cases=%d iterations=%d warmups=%d multiplier=%.2f\n",
    #cases,
    iterations,
    warmups,
    multiplier
))
