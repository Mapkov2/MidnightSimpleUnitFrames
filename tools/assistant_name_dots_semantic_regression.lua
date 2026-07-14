_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local A, Registry
local status, findChange, assertNoWrongPartyMutation

local function runExtendedSuite()
local extendedFailures = {}

local function runExtendedCase(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        extendedFailures[#extendedFailures + 1] = label .. ": " .. tostring(err)
    end
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copy
end

local function displayValue(value)
    if type(value) == "string" then return string.format("%q", value) end
    return tostring(value)
end

local function firstDifference(actual, expected, path)
    path = path or "value"
    if type(actual) ~= type(expected) then
        return path .. " type was " .. type(actual) .. ", expected " .. type(expected)
    end
    if type(actual) ~= "table" then
        if actual ~= expected then
            return path .. " was " .. displayValue(actual) .. ", expected " .. displayValue(expected)
        end
        return nil
    end
    for key, expectedValue in pairs(expected) do
        local difference = firstDifference(actual[key], expectedValue, path .. "." .. tostring(key))
        if difference then return difference end
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            return path .. "." .. tostring(key) .. " unexpectedly exists with " .. displayValue(actual[key])
        end
    end
    return nil
end

local function assertRawEquals(actual, expected, label)
    local difference = firstDifference(actual, expected, label)
    assert(not difference, difference)
end

local function beginNameDotsCase(opts)
    opts = opts or {}
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
    local db = _G.MSUF_DB
    db.general = type(db.general) == "table" and db.general or {}
    db.shortenNames = opts.enabled ~= false
    db.general.shortenNameMaxChars = opts.maxChars or 12
    db.general.shortenNameClipSide = opts.clipSide or "LEFT"
    db.general.shortenNameShowDots = opts.showDots ~= false
    db.target = deepCopy(opts.target or { fontOverride = false })
    db.focus = deepCopy(opts.focus or { fontOverride = false })
    db.gf_party = deepCopy(opts.party or { fontOverride = false })
    db.gf_raid = deepCopy(opts.raid or { fontOverride = false })
    db.gf_mythicraid = deepCopy(opts.mythicraid or { fontOverride = false })
    return db
end

local function assertApplied(result, label)
    assert(status(result) == "applied", label .. ": expected applied, got "
        .. tostring(status(result)) .. " (" .. tostring(result and result.text) .. ")")
end

local function assertNameDotValue(plan, key, expected, label)
    assert(plan and plan.kind == "changes", label .. ": expected changes, got " .. tostring(plan and plan.kind))
    local change = assert(findChange(plan, key), label .. ": missing " .. key)
    assert(change.value == expected, label .. ": " .. key .. " was " .. tostring(change.value)
        .. ", expected " .. tostring(expected))
end

local function assertNoNameDotMutation(plan, label)
    for i = 1, #(plan and plan.changes or {}) do
        local key = tostring(plan.changes[i].setting and plan.changes[i].setting.key or "")
        assert(not key:find("nameNoEllipsis", 1, true)
            and not key:find("shortenNameNoEllipsis", 1, true)
            and not key:find("shortenNameShowDots", 1, true),
            label .. ": unexpectedly changed " .. key)
    end
end

local function assertExactNameDotKeys(plan, expectedKeys, label)
    assert(plan and plan.kind == "changes", label .. ": expected changes, got " .. tostring(plan and plan.kind))
    local expected = {}
    for i = 1, #expectedKeys do expected[expectedKeys[i]] = true end
    local actual = {}
    for i = 1, #(plan.changes or {}) do
        local key = tostring(plan.changes[i].setting and plan.changes[i].setting.key or "")
        if key:find("nameNoEllipsis", 1, true) or key:find("shortenNameNoEllipsis", 1, true) then
            actual[key] = true
            assert(plan.changes[i].value == true, label .. ": " .. key .. " used the wrong hide-dots polarity")
        end
    end
    assertRawEquals(actual, expected, label .. " name-dot keys")
end

runExtendedCase("stale unit override seeds Shared state and round-trips raw data", function()
    local db = beginNameDotsCase({
        enabled = true,
        maxChars = 12,
        clipSide = "LEFT",
        showDots = true,
        target = {
            fontOverride = false,
            shortenNames = false,
            shortenNameMaxChars = 4,
            shortenNameClipSide = "RIGHT",
            shortenNameShowDots = false,
            regressionMarker = "stale-target",
        },
    })
    local before = deepCopy(db.target)
    local sharedBefore = {
        shortenNames = db.shortenNames,
        shortenNameMaxChars = db.general.shortenNameMaxChars,
        shortenNameClipSide = db.general.shortenNameClipSide,
        shortenNameShowDots = db.general.shortenNameShowDots,
    }
    local result = A.Submit("turn off the dots on shortened target names")
    assertApplied(result, "stale target")
    assert(db.target.fontOverride == true, "stale target: font override was not enabled")
    assert(db.target.shortenNames == true, "stale target: stale shortening enablement was resurrected")
    assert(db.target.shortenNameMaxChars == 12, "stale target: stale shortening length was resurrected")
    assert(db.target.shortenNameClipSide == "LEFT", "stale target: stale clipping side was resurrected")
    assert(db.target.shortenNameShowDots == false, "stale target: dots were not hidden")
    assertRawEquals({
        shortenNames = db.shortenNames,
        shortenNameMaxChars = db.general.shortenNameMaxChars,
        shortenNameClipSide = db.general.shortenNameClipSide,
        shortenNameShowDots = db.general.shortenNameShowDots,
    }, sharedBefore, "stale target Shared values")
    local appliedRaw = deepCopy(db.target)
    assert(A.UndoLast() == true, "stale target: undo failed")
    assertRawEquals(db.target, before, "stale target after undo")
    assert(A.RedoLast() == true, "stale target: redo failed")
    assertRawEquals(db.target, appliedRaw, "stale target after redo")
end)

runExtendedCase("sparse unit override receives a complete effective snapshot", function()
    local db = beginNameDotsCase({
        enabled = true,
        maxChars = 17,
        clipSide = "LEFT",
        showDots = true,
        target = { fontOverride = false, regressionMarker = "sparse-target" },
    })
    local before = deepCopy(db.target)
    local result = A.Submit("hide the ellipsis on shortened target names")
    assertApplied(result, "sparse target")
    assert(db.target.fontOverride == true, "sparse target: font override was not enabled")
    assert(db.target.shortenNames == true, "sparse target: raw shortening enablement was not seeded")
    assert(db.target.shortenNameMaxChars == 17, "sparse target: raw shortening length was not seeded")
    assert(db.target.shortenNameClipSide == "LEFT", "sparse target: raw clipping side was not seeded")
    assert(db.target.shortenNameShowDots == false, "sparse target: raw dots value was not written")
    local appliedRaw = deepCopy(db.target)
    assert(A.UndoLast() == true, "sparse target: undo failed")
    assertRawEquals(db.target, before, "sparse target after undo")
    assert(A.RedoLast() == true, "sparse target: redo failed")
    assertRawEquals(db.target, appliedRaw, "sparse target after redo")
end)

runExtendedCase("stale group override seeds Shared state and round-trips raw data", function()
    local db = beginNameDotsCase({
        enabled = true,
        maxChars = 14,
        clipSide = "LEFT",
        showDots = true,
        party = {
            fontOverride = false,
            nameShortenEnabled = false,
            nameMaxChars = 4,
            nameClipSide = "RIGHT",
            nameNoEllipsis = true,
            regressionMarker = "stale-party",
        },
    })
    local before = deepCopy(db.gf_party)
    local result = A.Submit("turn off the dots on shortened party names")
    assertApplied(result, "stale Party")
    assert(db.gf_party.fontOverride == true, "stale Party: font override was not enabled")
    assert(db.gf_party.nameShortenEnabled == true, "stale Party: stale shortening enablement was resurrected")
    assert(db.gf_party.nameMaxChars == 14, "stale Party: stale shortening length was resurrected")
    assert(db.gf_party.nameClipSide == "LEFT", "stale Party: stale clipping side was resurrected")
    assert(db.gf_party.nameNoEllipsis == true, "stale Party: dots were not hidden")
    local appliedRaw = deepCopy(db.gf_party)
    assert(A.UndoLast() == true, "stale Party: undo failed")
    assertRawEquals(db.gf_party, before, "stale Party after undo")
    assert(A.RedoLast() == true, "stale Party: redo failed")
    assertRawEquals(db.gf_party, appliedRaw, "stale Party after redo")
end)

runExtendedCase("sparse group override receives a complete effective snapshot", function()
    local db = beginNameDotsCase({
        enabled = true,
        maxChars = 19,
        clipSide = "RIGHT",
        showDots = true,
        party = { fontOverride = false, regressionMarker = "sparse-party" },
    })
    local before = deepCopy(db.gf_party)
    local result = A.Submit("remove the ellipsis from shortened party names")
    assertApplied(result, "sparse Party")
    assert(db.gf_party.fontOverride == true, "sparse Party: font override was not enabled")
    assert(db.gf_party.nameShortenEnabled == true, "sparse Party: raw shortening enablement was not seeded")
    assert(db.gf_party.nameMaxChars == 19, "sparse Party: raw shortening length was not seeded")
    assert(db.gf_party.nameClipSide == "RIGHT", "sparse Party: raw clipping side was not seeded")
    assert(db.gf_party.nameNoEllipsis == true, "sparse Party: raw No Ellipsis value was not written")
    local appliedRaw = deepCopy(db.gf_party)
    assert(A.UndoLast() == true, "sparse Party: undo failed")
    assertRawEquals(db.gf_party, before, "sparse Party after undo")
    assert(A.RedoLast() == true, "sparse Party: redo failed")
    assertRawEquals(db.gf_party, appliedRaw, "sparse Party after redo")
end)

runExtendedCase("Raid dots do not mutate Mythic Raid", function()
    local db = beginNameDotsCase({
        enabled = true,
        maxChars = 11,
        clipSide = "LEFT",
        showDots = true,
        raid = { fontOverride = false, regressionMarker = "raid" },
        mythicraid = {
            fontOverride = true,
            nameShortenEnabled = false,
            nameMaxChars = 7,
            nameClipSide = "RIGHT",
            nameNoEllipsis = false,
            regressionMarker = "mythic-must-not-change",
        },
    })
    local raidBefore = deepCopy(db.gf_raid)
    local mythicBefore = deepCopy(db.gf_mythicraid)
    local result = A.Submit("turn off the dots on shortened raid names")
    assertApplied(result, "Raid isolation")
    assert(db.gf_raid.fontOverride == true and db.gf_raid.nameNoEllipsis == true,
        "Raid isolation: Raid dots were not hidden")
    assertRawEquals(db.gf_mythicraid, mythicBefore, "Mythic Raid after Raid apply")
    local raidApplied = deepCopy(db.gf_raid)
    assert(A.UndoLast() == true, "Raid isolation: undo failed")
    assertRawEquals(db.gf_raid, raidBefore, "Raid after undo")
    assertRawEquals(db.gf_mythicraid, mythicBefore, "Mythic Raid after Raid undo")
    assert(A.RedoLast() == true, "Raid isolation: redo failed")
    assertRawEquals(db.gf_raid, raidApplied, "Raid after redo")
    assertRawEquals(db.gf_mythicraid, mythicBefore, "Mythic Raid after Raid redo")
end)

runExtendedCase("Mythic Raid dots are isolated and undo exactly", function()
    local db = beginNameDotsCase({
        enabled = true,
        maxChars = 16,
        clipSide = "RIGHT",
        showDots = true,
        raid = {
            fontOverride = true,
            nameShortenEnabled = true,
            nameMaxChars = 8,
            nameClipSide = "LEFT",
            nameNoEllipsis = false,
            regressionMarker = "raid-must-not-change",
        },
        mythicraid = {
            fontOverride = false,
            nameShortenEnabled = false,
            nameMaxChars = 5,
            nameClipSide = "LEFT",
            nameNoEllipsis = false,
            regressionMarker = "stale-mythic",
        },
    })
    local raidBefore = deepCopy(db.gf_raid)
    local mythicBefore = deepCopy(db.gf_mythicraid)
    local result = A.Submit("turn off the dots on shortened mythic raid names")
    assertApplied(result, "Mythic Raid isolation")
    assertRawEquals(db.gf_raid, raidBefore, "Raid after Mythic Raid apply")
    assert(db.gf_mythicraid.fontOverride == true, "Mythic Raid: font override was not enabled")
    assert(db.gf_mythicraid.nameShortenEnabled == true, "Mythic Raid: Shared shortening enablement was not seeded")
    assert(db.gf_mythicraid.nameMaxChars == 16, "Mythic Raid: Shared shortening length was not seeded")
    assert(db.gf_mythicraid.nameClipSide == "RIGHT", "Mythic Raid: Shared clipping side was not seeded")
    assert(db.gf_mythicraid.nameNoEllipsis == true, "Mythic Raid: dots were not hidden")
    local mythicApplied = deepCopy(db.gf_mythicraid)
    assert(A.UndoLast() == true, "Mythic Raid: undo failed")
    assertRawEquals(db.gf_mythicraid, mythicBefore, "Mythic Raid after undo")
    assertRawEquals(db.gf_raid, raidBefore, "Raid after Mythic Raid undo")
    assert(A.RedoLast() == true, "Mythic Raid: redo failed")
    assertRawEquals(db.gf_mythicraid, mythicApplied, "Mythic Raid after redo")
    assertRawEquals(db.gf_raid, raidBefore, "Raid after Mythic Raid redo")
end)

do
    local unicodeEllipsis = string.char(0xE2, 0x80, 0xA6)
    local prompts = {
        "turn off party frame..",
        "turn off party frame...",
        "turn off party frame" .. unicodeEllipsis,
    }
    for i = 1, #prompts do
        local prompt = prompts[i]
        runExtendedCase("sentence-ending punctuation: " .. prompt, function()
            beginNameDotsCase({ enabled = true, showDots = true })
            local plan = A.Parse(prompt)
            assert(plan.kind == "changes", prompt .. ": expected the normal Party frame toggle, got " .. tostring(plan.kind))
            local enabled = assert(findChange(plan, "gf_party.enabled"), prompt .. ": did not preserve the Party frame toggle")
            assert(enabled.value == false, prompt .. ": Party frame toggle used the wrong value")
            assertNoNameDotMutation(plan, prompt)
        end)
    end
end

do
    local cases = {
        { "set party name no ellipsis to false", false },
        { "set party name no ellipsis false", false },
        { "set party name no ellipsis off", false },
        { "disable party name no ellipsis", false },
        { "set party name no ellipsis to true", true },
        { "set party name no ellipsis true", true },
        { "set party name no ellipsis on", true },
        { "enable party name no ellipsis", true },
    }
    for i = 1, #cases do
        local prompt, expected = cases[i][1], cases[i][2]
        runExtendedCase("No Ellipsis polarity: " .. prompt, function()
            beginNameDotsCase({ enabled = true, showDots = true })
            assertNameDotValue(A.Parse(prompt), "gf_party.nameNoEllipsis", expected, prompt)
        end)
    end
end

do
    local prompts = {
        "keep the dots off on shortened party names",
        "keep shortened party name dots off",
        "keep the trailing dots off for party names",
    }
    for i = 1, #prompts do
        local prompt = prompts[i]
        runExtendedCase("keep dots off: " .. prompt, function()
            beginNameDotsCase({ enabled = true, showDots = true })
            assertNameDotValue(A.Parse(prompt), "gf_party.nameNoEllipsis", true, prompt)
        end)
    end
end

do
    local prompts = {
        "do not hide the dots on shortened party names",
        "don't hide the dots on shortened party names",
        "do not remove the ellipsis from shortened party names",
        "do not show the dots on shortened party names",
    }
    for i = 1, #prompts do
        local prompt = prompts[i]
        runExtendedCase("negated dots action: " .. prompt, function()
            local db = beginNameDotsCase({
                enabled = true,
                showDots = true,
                party = { fontOverride = false, regressionMarker = "negated-action" },
            })
            local before = deepCopy(db.gf_party)
            local plan = A.Parse(prompt)
            assert(plan.kind == "ambiguous", prompt .. ": expected clarification, got " .. tostring(plan.kind))
            assert(#(plan.choices or {}) >= 2, prompt .. ": clarification did not provide options")
            assertNoNameDotMutation(plan, prompt)
            local result = A.Submit(prompt)
            assert(status(result) == "ambiguous", prompt .. ": submit did not fail closed")
            assertRawEquals(db.gf_party, before, prompt .. " raw Party state")
        end)
    end
end

do
    local prompts = {
        "turn off the DOTS on party frame",
        "remove the DOTS from shortened party names",
    }
    for i = 1, #prompts do
        local prompt = prompts[i]
        runExtendedCase("uppercase DOTS: " .. prompt, function()
            beginNameDotsCase({ enabled = true, showDots = true })
            assertNameDotValue(A.Parse(prompt), "gf_party.nameNoEllipsis", true, prompt)
        end)
    end
end

runExtendedCase("Party and Raid dots are a two-scope transaction", function()
    local db = beginNameDotsCase({
        enabled = true,
        showDots = true,
        party = { fontOverride = false, regressionMarker = "multi-party" },
        raid = { fontOverride = false, regressionMarker = "multi-raid" },
        mythicraid = { fontOverride = false, regressionMarker = "multi-mythic-untouched" },
    })
    local prompt = "remove the trailing dots from shortened party and raid names"
    assertExactNameDotKeys(A.Parse(prompt), {
        "gf_party.nameNoEllipsis",
        "gf_raid.nameNoEllipsis",
    }, prompt)
    local before = {
        party = deepCopy(db.gf_party),
        raid = deepCopy(db.gf_raid),
        mythicraid = deepCopy(db.gf_mythicraid),
    }
    assertApplied(A.Submit(prompt), prompt)
    assert(db.gf_party.fontOverride == true and db.gf_party.nameNoEllipsis == true,
        prompt .. ": Party dots were not hidden")
    assert(db.gf_raid.fontOverride == true and db.gf_raid.nameNoEllipsis == true,
        prompt .. ": Raid dots were not hidden")
    assertRawEquals(db.gf_mythicraid, before.mythicraid, prompt .. " Mythic Raid after apply")
    local applied = {
        party = deepCopy(db.gf_party),
        raid = deepCopy(db.gf_raid),
        mythicraid = deepCopy(db.gf_mythicraid),
    }
    assert(A.UndoLast() == true, prompt .. ": undo failed")
    assertRawEquals({ party = db.gf_party, raid = db.gf_raid, mythicraid = db.gf_mythicraid },
        before, prompt .. " after undo")
    assert(A.RedoLast() == true, prompt .. ": redo failed")
    assertRawEquals({ party = db.gf_party, raid = db.gf_raid, mythicraid = db.gf_mythicraid },
        applied, prompt .. " after redo")
end)

runExtendedCase("Target and Focus dots are a two-scope transaction", function()
    local db = beginNameDotsCase({
        enabled = true,
        showDots = true,
        target = { fontOverride = false, regressionMarker = "multi-target" },
        focus = { fontOverride = false, regressionMarker = "multi-focus" },
    })
    local prompt = "remove the trailing dots from shortened target and focus names"
    assertExactNameDotKeys(A.Parse(prompt), {
        "fontScope.target.shortenNameNoEllipsis",
        "fontScope.focus.shortenNameNoEllipsis",
    }, prompt)
    local before = { target = deepCopy(db.target), focus = deepCopy(db.focus) }
    assertApplied(A.Submit(prompt), prompt)
    assert(db.target.fontOverride == true and db.target.shortenNameShowDots == false,
        prompt .. ": Target dots were not hidden")
    assert(db.focus.fontOverride == true and db.focus.shortenNameShowDots == false,
        prompt .. ": Focus dots were not hidden")
    local applied = { target = deepCopy(db.target), focus = deepCopy(db.focus) }
    assert(A.UndoLast() == true, prompt .. ": undo failed")
    assertRawEquals({ target = db.target, focus = db.focus }, before, prompt .. " after undo")
    assert(A.RedoLast() == true, prompt .. ": redo failed")
    assertRawEquals({ target = db.target, focus = db.focus }, applied, prompt .. " after redo")
end)

runExtendedCase("mixed Party and Target dots are a two-scope transaction", function()
    local db = beginNameDotsCase({
        enabled = true,
        showDots = true,
        party = { fontOverride = false, regressionMarker = "mixed-party" },
        target = { fontOverride = false, regressionMarker = "mixed-target" },
    })
    local prompt = "remove the trailing dots from shortened party and target names"
    assertExactNameDotKeys(A.Parse(prompt), {
        "gf_party.nameNoEllipsis",
        "fontScope.target.shortenNameNoEllipsis",
    }, prompt)
    local before = { party = deepCopy(db.gf_party), target = deepCopy(db.target) }
    assertApplied(A.Submit(prompt), prompt)
    assert(db.gf_party.fontOverride == true and db.gf_party.nameNoEllipsis == true,
        prompt .. ": Party dots were not hidden")
    assert(db.target.fontOverride == true and db.target.shortenNameShowDots == false,
        prompt .. ": Target dots were not hidden")
    local applied = { party = deepCopy(db.gf_party), target = deepCopy(db.target) }
    assert(A.UndoLast() == true, prompt .. ": undo failed")
    assertRawEquals({ party = db.gf_party, target = db.target }, before, prompt .. " after undo")
    assert(A.RedoLast() == true, prompt .. ": redo failed")
    assertRawEquals({ party = db.gf_party, target = db.target }, applied, prompt .. " after redo")
end)

do
    local db = beginNameDotsCase({
        enabled = true,
        showDots = true,
        target = {
            fontOverride = true,
            shortenNames = true,
            shortenNameMaxChars = 9,
            shortenNameClipSide = "RIGHT",
            shortenNameShowDots = true,
        },
        party = {
            fontOverride = true,
            nameShortenEnabled = true,
            nameMaxChars = 10,
            nameClipSide = "LEFT",
            nameNoEllipsis = false,
        },
    })
    local before = {
        shared = {
            shortenNames = db.shortenNames,
            shortenNameShowDots = db.general.shortenNameShowDots,
        },
        target = deepCopy(db.target),
        party = deepCopy(db.gf_party),
    }
    local prompts = {
        "turn off the dots on all frames",
        "remove the trailing dots from all unit frames",
    }
    for i = 1, #prompts do
        local prompt = prompts[i]
        runExtendedCase("all frames clarification: " .. prompt, function()
            A.StartNewTask()
            A.undoStack = {}
            A.redoStack = {}
            local plan = A.Parse(prompt)
            assert(plan.kind == "ambiguous", prompt .. ": expected Shared-vs-overrides clarification, got " .. tostring(plan.kind))
            assert(#(plan.choices or {}) >= 2, prompt .. ": clarification did not provide options")
            assertNoNameDotMutation(plan, prompt)
            local result = A.Submit(prompt)
            assert(status(result) == "ambiguous", prompt .. ": submit did not remain a clarification")
            assertRawEquals({
                shared = {
                    shortenNames = db.shortenNames,
                    shortenNameShowDots = db.general.shortenNameShowDots,
                },
                target = db.target,
                party = db.gf_party,
            }, before, prompt .. " raw state")
        end)
    end
end

if #extendedFailures > 0 then
    io.stderr:write("assistant_name_dots_semantic_regression: " .. tostring(#extendedFailures)
        .. " extended failure(s)\n")
    for i = 1, #extendedFailures do
        io.stderr:write(tostring(i) .. ") " .. extendedFailures[i] .. "\n")
    end
    error("assistant_name_dots_semantic_regression extended cases failed", 0)
end

io.write("assistant_name_dots_semantic_regression: ok\n")
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
Registry = assert(A.Registry, "Assistant registry missing")

status = function(result)
    return result and (result.status or result.result)
end

findChange = function(plan, key)
    for i = 1, #(plan and plan.changes or {}) do
        local change = plan.changes[i]
        if change.setting and change.setting.key == key then return change end
    end
    return nil
end

assertNoWrongPartyMutation = function(plan, label)
    for i = 1, #(plan and plan.changes or {}) do
        local key = tostring(plan.changes[i].setting and plan.changes[i].setting.key or "")
        assert(key ~= "gf_party.x", label .. ": routed to Party X Position")
        assert(key ~= "gf_party.showName", label .. ": routed to Party name visibility")
        assert(key ~= "gf_party.enabled", label .. ": routed to Party frame visibility")
        assert(key ~= "gf_party.nameShortenEnabled", label .. ": changed name shortening itself")
    end
end

local function resetParty(shorteningEnabled, showDots)
    A.StartNewTask()
    A.undoStack = {}
    A.redoStack = {}
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    _G.MSUF_DB.shortenNames = shorteningEnabled == true
    _G.MSUF_DB.general.shortenNameMaxChars = 6
    _G.MSUF_DB.general.shortenNameClipSide = "LEFT"
    _G.MSUF_DB.general.shortenNameShowDots = showDots ~= false
    _G.MSUF_DB.gf_party = {
        fontOverride = false,
        x = 27,
        showName = true,
        enabled = true,
    }
end

local EXTENDED_ONLY = type(arg) == "table" and arg[1] == "--extended-only"

if not EXTENDED_ONLY then
resetParty(true, true)
local parsed = A.Parse("turn off the dots on party frame")
assert(parsed.kind == "changes", "exact screenshot prompt did not become a concrete change: " .. tostring(parsed.kind))
assert(#(parsed.changes or {}) == 1, "exact screenshot prompt should keep a leaf-only semantic plan")
assert(not findChange(parsed, "fontScope.gf_party.override"),
    "Party override mechanics leaked into the semantic plan")
local dots = assert(findChange(parsed, "gf_party.nameNoEllipsis"), "Party No Ellipsis change missing")
assert(dots.value == true, "turn off dots used the wrong No Ellipsis polarity")
assertNoWrongPartyMutation(parsed, "exact screenshot prompt")

local applied = A.Submit("turn off the dots on party frame")
assert(status(applied) == "applied", "exact screenshot prompt was not applied: " .. tostring(applied and applied.text))
assert(_G.MSUF_DB.gf_party.fontOverride == true, "Party font override was not enabled")
assert(_G.MSUF_DB.gf_party.nameNoEllipsis == true, "Party dots remained enabled")
assert(_G.MSUF_DB.gf_party.nameShortenEnabled == true, "inherited name shortening was lost")
assert(_G.MSUF_DB.gf_party.nameMaxChars == 6, "inherited shortening length was lost")
assert(_G.MSUF_DB.gf_party.nameClipSide == "LEFT", "inherited shortening side was lost")
assert(_G.MSUF_DB.gf_party.x == 27 and _G.MSUF_DB.gf_party.showName == true and _G.MSUF_DB.gf_party.enabled == true,
    "an unrelated Party frame setting changed")
assert(tostring(applied.text):find("shortened names no longer show trailing dots", 1, true),
    "success response did not explain the visible result")
local partyTransaction = assert(A.undoStack and A.undoStack[#A.undoStack],
    "Party dots change did not create an undo transaction")
assert(type(partyTransaction.beforeNameShorteningStates) == "table"
        and partyTransaction.beforeNameShorteningStates[1]
        and partyTransaction.beforeNameShorteningStates[1].scope == "gf_party",
    "Party dots transaction did not capture the raw pre-change name-shortening state")
assert(type(partyTransaction.afterNameShorteningStates) == "table"
        and partyTransaction.afterNameShorteningStates[1]
        and partyTransaction.afterNameShorteningStates[1].scope == "gf_party",
    "Party dots transaction did not capture the raw post-change name-shortening state")

local undoOK = A.UndoLast()
assert(undoOK == true, "undo failed")
assert(_G.MSUF_DB.gf_party.fontOverride == false, "undo did not restore Shared inheritance")
assert(Registry:GetSetting("gf_party.nameNoEllipsis").get() == false,
    "undo failed to restore a false No Ellipsis value")
local redoOK = A.RedoLast()
assert(redoOK == true, "redo failed")
assert(_G.MSUF_DB.gf_party.fontOverride == true and _G.MSUF_DB.gf_party.nameNoEllipsis == true,
    "redo failed to reapply Party No Ellipsis")

local polarityCases = {
    { "show the dots on shortened party names", false },
    { "turn on party name ellipsis", false },
    { "turn on party name no ellipsis", true },
    { "turn off party name no ellipsis", false },
    { "remove the trailing dots from party names", true },
    { "turn off .. on party names", true },
    { "turn off ... on party names", true },
    { "turn off … on party names", true },
}
for i = 1, #polarityCases do
    A.StartNewTask()
    local prompt, expected = polarityCases[i][1], polarityCases[i][2]
    local plan = A.Parse(prompt)
    assert(plan.kind == "changes", prompt .. ": expected changes, got " .. tostring(plan.kind))
    local change = assert(findChange(plan, "gf_party.nameNoEllipsis"), prompt .. ": wrong setting")
    assert(change.value == expected, prompt .. ": wrong polarity")
    assertNoWrongPartyMutation(plan, prompt)
end

A.StartNewTask()
local location = A.Parse("where do I turn off name dots on party frames")
assert(location.kind == "action", "location request did not navigate")
assert(location.action and location.action.key == "open_setting_control", "location request used the wrong action")
assert(location.args and location.args.settingKey == "gf_party.nameNoEllipsis", "location request used the wrong setting")
assert(location.args.page == "opt_fonts", "location request did not open Fonts")

resetParty(false, true)
local uncertain = A.Parse("turn off the dots on party frame")
assert(uncertain.kind == "ambiguous" and #(uncertain.choices or {}) >= 2,
    "weak dots wording without shortening evidence did not offer choices")
assertNoWrongPartyMutation(uncertain, "uncertain dots prompt")

local xBefore = _G.MSUF_DB.gf_party.x
local rawDoT = A.Submit("turn off DoTs on party frames")
assert(status(rawDoT) == "ambiguous", "DoT request did not ask which meaning: " .. tostring(rawDoT and rawDoT.text))
assert(_G.MSUF_DB.gf_party.x == xBefore and _G.MSUF_DB.gf_party.fontOverride == false,
    "DoT clarification mutated Party settings")

local otherDomainCases = {
    "turn off corner dots on party frames",
    "turn off status dots on party frames",
    "turn off combo point dots",
    "turn off debuff dots on party frames",
}
for i = 1, #otherDomainCases do
    A.StartNewTask()
    local prompt = otherDomainCases[i]
    local plan = A.Parse(prompt)
    assert(not findChange(plan, "gf_party.nameNoEllipsis"), prompt .. ": hijacked by name ellipsis")
    assertNoWrongPartyMutation(plan, prompt)
end

resetParty(true, true)
local setup = A.Submit("shorten party names to 6 letters and keep the end")
assert(status(setup) == "applied" or status(setup) == "unchanged", "context setup failed")
local followup = A.Parse("and remove the dots")
assert(followup.kind == "changes", "follow-up did not reuse the Party shortening context")
assert(findChange(followup, "gf_party.nameNoEllipsis"), "follow-up lost the Party scope")
assertNoWrongPartyMutation(followup, "context follow-up")

end

runExtendedSuite()
