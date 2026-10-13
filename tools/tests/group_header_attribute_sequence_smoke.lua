-- Pin every ordered attribute write the secure group headers receive.
--
-- The pin is compact. For each layout and each header the fixture holds the write count, a three-modulus
-- hash (75 bits) of the exact ordered "key<TAB>value" sequence and a checkpoint hash after every STEP writes.
-- tools/fixtures/group_header_attributes/<client>.tsv; Vanilla, TBC and Mists share Classic.tsv.
--
-- A mismatch names the layout and the header and prints the actual writes of the first window that differs,
-- so a swapped pair fails at its own position. The full expected/actual diff comes from a checkout of the
-- commit that last recorded the pin (git log -1 --format=%h -- tools/fixtures/group_header_attributes):
--   lua tools/tests/group_header_attribute_sequence_smoke.lua <root> <client> against <baselineRoot>
-- After a deliberate behaviour change re-record the pin (Vanilla records the shared Classic file;
-- "record own" writes <client>.tsv for a client that must diverge from the shared pin):
--   lua tools/tests/group_header_attribute_sequence_smoke.lua <root> <client> record [own]
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local mode, baselineRoot = arg[3], arg[4]
local STEP = 8
local MODULI = { 33554393, 33554383, 33554371 }
local BASES = { 16777619, 12582917, 25165843 }
local SEEDS = { 1, 7, 13 }
local CLASSIC = { Vanilla = true, TBC = true, Mists = true }
local fixtureDir = root .. "/tools/fixtures/group_header_attributes/"
local fmod, byte, format = math.fmod, string.byte, string.format

-- Booting the whole load graph for each of the 44 layouts is almost entirely compile time: compile once.
local plainLoadfile, compiled = loadfile, {}
function loadfile(path)
    local dump = compiled[path]
    if dump then return loadstring(dump, "@" .. path) end
    local chunk, message = plainLoadfile(path)
    if chunk then compiled[path] = string.dump(chunk) end
    return chunk, message
end

local function Encode(value)
    return type(value) .. ":" .. tostring(value):gsub("\\", "\\\\"):gsub("\t", "\\t")
        :gsub("\r", "\\r"):gsub("\n", "\\n")
end

local function Feed(state, row)
    local text = row .. "\n"
    local padding = (3 - #text % 3) % 3
    if padding > 0 then text = text .. ("\0"):rep(padding) end
    local h1, h2, h3 = state[1], state[2], state[3]
    for index = 1, #text, 3 do
        local a, b, c = byte(text, index, index + 2)
        local value = a + 256 * b + 65536 * c
        h1 = fmod(h1 * BASES[1] + value, MODULI[1])
        h2 = fmod(h2 * BASES[2] + value, MODULI[2])
        h3 = fmod(h3 * BASES[3] + value, MODULI[3])
    end
    state[1], state[2], state[3] = h1, h2, h3
end

local function Digest(state)
    return format("%07x%07x%07x", state[1], state[2], state[3])
end

-- One header's write list as a fixture record: count, digest over the whole sequence, prefix digests.
local function Summarize(name, rows)
    local state, marks = { SEEDS[1], SEEDS[2], SEEDS[3] }, {}
    for index = 1, #rows do
        Feed(state, rows[index])
        if index % STEP == 0 then marks[#marks + 1] = Digest(state) end
    end
    return { name = name, count = #rows, digest = Digest(state), marks = marks, rows = rows }
end

local function Capture(captureRoot)
    local Harness = dofile(captureRoot .. "/tools/tests/group_header_world.lua")
    local cases = {}
    local function Scenario(kind, count, sort, preserve)
        local writes, names = {}, {}
        local h = Harness.New(captureRoot, flavor, { beforeBoot = function(world)
            local create = world.env.CreateFrame
            world.env.CreateFrame = function(frameType, name, parent, template)
                local frame = create(frameType, name, parent, template)
                if template == "SecureGroupHeaderTemplate" or template == "SecureGroupPetHeaderTemplate" then
                    local rows = {}
                    writes[name], names[#names + 1] = rows, name
                    local set = frame.SetAttribute
                    frame.SetAttribute = function(self, key, value)
                        rows[#rows + 1] = key .. "\t" .. Encode(value)
                        return set(self, key, value)
                    end
                end
                return frame
            end
            world.env.UnitGroupRolesAssigned = function(unit)
                local index = tonumber((unit or ""):match("%d+")) or 0
                return index % 3 == 0 and "HEALER" or index % 3 == 1 and "TANK" or "DAMAGER"
            end
            world.env.GetInstanceInfo = function()
                return "Instance", kind == "mythicraid" and "raid" or "none", kind == "mythicraid" and 16 or 0
            end
        end })
        local GF = h.GF
        GF.EnsureDB()
        local conf = GF.GetConf(kind)
        conf.enabled, conf.showSolo = true, false
        conf.sortMode, conf.preserveRaidGroups = sort, preserve
        conf.playerFirstInRole, conf.sortAlphabeticalWithinRole = true, true
        conf.petsEnabled, conf.petsColumns = true, 3
        if kind == "party" then h:SetRoster({ "player", "party1", "party2", "party3", "party4" })
        else h:SetRaid(count) end
        GF.RefreshHeaderLayout()
        h:RunTimers()
        GF.RefreshAdditionalGroups()
        -- Warm no-op, topology/size changes, native/name-list transitions and reuse.
        GF.RefreshHeaderLayout()
        for _, growth in ipairs({ "UP", "LEFT", "RIGHT", "DOWN" }) do
            conf.growth, conf.width = growth, conf.width + 1
            GF.RefreshHeaderLayout()
        end
        conf.sortMode = "INDEX"
        GF.RefreshHeaderLayout()
        conf.sortMode = sort
        GF.RefreshHeaderLayout()
        GF.SetupPriorityHeader(kind, "Name-raid1,Name-raid2", 2)
        GF.SetupPriorityHeader(kind, "Name-raid1,Name-raid2", 2)
        GF.RetireHeader(kind == "party" and "party" or "raid")
        GF.RefreshHeaderLayout()
        GF.RefreshAdditionalGroups()
        assert(#h.violations == 0, tostring(h.violations[1]))
        assert(#h.callMethodErrors == 0, tostring(h.callMethodErrors[1]))
        table.sort(names)
        local case = { label = table.concat({ kind, count, sort, tostring(preserve) }, "\t"), headers = {}, writes = 0 }
        for _, name in ipairs(names) do
            local header = Summarize(name, writes[name])
            case.headers[#case.headers + 1] = header
            case.writes = case.writes + header.count
        end
        cases[#cases + 1] = case
    end
    for _, sort in ipairs({ "INDEX", "ROLE", "GROUP", "GROUP_ROLE" }) do
        Scenario("party", 5, sort, false)
        for _, count in ipairs({ 10, 20, 25, 40 }) do
            Scenario("raid", count, sort, false)
            Scenario("raid", count, sort, true)
        end
        Scenario("mythicraid", 20, sort, false)
        Scenario("mythicraid", 20, sort, true)
    end
    return cases
end

local function Split(line)
    local fields = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
    return fields
end

local function FixturePath(own)
    local ownPath = fixtureDir .. flavor .. ".tsv"
    if own or not CLASSIC[flavor] then return ownPath end
    local file = io.open(ownPath, "rb")
    if file then
        file:close()
        return ownPath
    end
    return fixtureDir .. "Classic.tsv"
end

local function WriteFixture(path, cases)
    local out = {
        "# Ordered SetAttribute writes of the secure group headers, pinned by hash. Written by",
        "# tools/tests/group_header_attribute_sequence_smoke.lua (record); never edit by hand.",
        "# CASE: kind, size, sort, preserve groups, headers, writes. HEADER: name, writes, digest over the",
        "# whole ordered sequence, then the digest after every " .. STEP .. " writes.",
    }
    for _, case in ipairs(cases) do
        out[#out + 1] = table.concat({ "CASE", case.label, #case.headers, case.writes }, "\t")
        for _, header in ipairs(case.headers) do
            local fields = { "HEADER", header.name, header.count, header.digest }
            for _, mark in ipairs(header.marks) do fields[#fields + 1] = mark end
            out[#out + 1] = table.concat(fields, "\t")
        end
    end
    local file = assert(io.open(path, "wb"))
    file:write(table.concat(out, "\n"), "\n")
    file:close()
end

local function ReadFixture(path)
    local file = assert(io.open(path, "rb"), "header attribute pin is missing: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local cases, byLabel, case = {}, {}, nil
    for line in text:gmatch("[^\n]+") do
        local fields = Split(line)
        if fields[1] == "CASE" then
            case = { label = table.concat(fields, "\t", 2, 5), headerCount = tonumber(fields[6]), writes = tonumber(fields[7]), headers = {} }
            cases[#cases + 1], byLabel[case.label] = case, case
        elseif fields[1] == "HEADER" then
            local header = { name = fields[2], count = tonumber(fields[3]), digest = fields[4], marks = {} }
            for index = 5, #fields do
                if fields[index] ~= "" then header.marks[#header.marks + 1] = fields[index] end
            end
            case.headers[#case.headers + 1] = header
        end
    end
    return cases, byLabel
end

local function Window(rows, first, last)
    local lines = {}
    for index = first, last do lines[#lines + 1] = format("    #%d  %s", index, rows[index]) end
    return table.concat(lines, "\n")
end

-- Where a header's actual writes first stop matching the pinned checkpoints.
local function DescribeHeader(header, want)
    if not want then
        return "  header " .. header.name .. " is not in the pin (" .. header.count .. " writes)"
    end
    if header.count == want.count and header.digest == want.digest then return nil end
    local window = 1
    while header.marks[window] and header.marks[window] == want.marks[window] do window = window + 1 end
    local first = (window - 1) * STEP + 1
    local last = math.min(window * STEP, header.count)
    local text = format("  header %s: pinned %d writes, now %d; first difference in write #%d-#%d", header.name,
        want.count, header.count, first, math.max(first, last))
    if first > header.count then return text .. " (the sequence now ends earlier)" end
    return text .. ", actual writes there:\n" .. Window(header.rows, first, last)
end

local function DescribeCase(case, want)
    if not want then return "layout " .. case.label:gsub("\t", " ") .. " is not in the pin" end
    local lines = {}
    local wanted = {}
    for _, header in ipairs(want.headers) do wanted[header.name] = header end
    for _, header in ipairs(case.headers) do
        local line = DescribeHeader(header, wanted[header.name])
        if line then lines[#lines + 1] = line end
        wanted[header.name] = nil
    end
    for _, header in ipairs(want.headers) do
        if wanted[header.name] then lines[#lines + 1] = "  header " .. header.name .. " is pinned but no longer created" end
    end
    if #lines == 0 then return nil end
    return "layout " .. case.label:gsub("\t", " ") .. ":\n" .. table.concat(lines, "\n")
end

-- Full diff of two captures made from checkouts: the first differing write with its neighbours.
local function CompareCaptures(expected, actual)
    local failures = {}
    for index, case in ipairs(actual) do
        local base = expected[index]
        local problem
        if not base or base.label ~= case.label or #base.headers ~= #case.headers then
            problem = "layouts or header lists differ"
        else
            for position, header in ipairs(case.headers) do
                local old = base.headers[position]
                if old.name ~= header.name then
                    problem = "header " .. old.name .. " became " .. header.name
                    break
                end
                local limit = math.max(#old.rows, #header.rows)
                for row = 1, limit do
                    if old.rows[row] ~= header.rows[row] then
                        problem = format("header %s, write #%d\n    expected %s\n    actual   %s\n  expected neighbours:\n%s\n  actual neighbours:\n%s",
                            header.name, row, tostring(old.rows[row]), tostring(header.rows[row]),
                            Window(old.rows, math.max(1, row - 3), math.min(#old.rows, row + 6)),
                            Window(header.rows, math.max(1, row - 3), math.min(#header.rows, row + 6)))
                        break
                    end
                end
                if problem then break end
            end
        end
        if problem then failures[#failures + 1] = "layout " .. case.label:gsub("\t", " ") .. ": " .. problem end
    end
    return failures
end

local cases = Capture(root)

if mode == "record" then
    local path = FixturePath(arg[4] == "own")
    WriteFixture(path, cases)
    print("group_header_attribute_sequence_smoke: recorded " .. #cases .. " layouts into " .. path)
    return
end

if mode == "against" then
    local failures = CompareCaptures(Capture(assert(baselineRoot, "against needs the baseline checkout root")
        :gsub("\\", "/"):gsub("/$", "")), cases)
    if #failures > 0 then
        error(flavor .. ": " .. #failures .. " of " .. #cases .. " layouts differ from the baseline\n"
            .. table.concat(failures, "\n", 1, math.min(#failures, 3)), 0)
    end
    print("group_header_attribute_sequence_smoke: ok (" .. flavor .. ": identical to the baseline checkout)")
    return
end

local pinned, byLabel = ReadFixture(FixturePath())
local failures, writes = {}, 0
for _, case in ipairs(cases) do
    writes = writes + case.writes
    local want = byLabel[case.label]
    local text = DescribeCase(case, want)
    if want and (want.headerCount ~= #want.headers or want.writes ~= case.writes) and not text then
        text = "layout " .. case.label:gsub("\t", " ") .. ": pin is internally inconsistent"
    end
    if text then failures[#failures + 1] = text end
end
if #pinned ~= #cases then
    failures[#failures + 1] = "the pin lists " .. #pinned .. " layouts, the smoke ran " .. #cases
end
if #failures > 0 then
    error(flavor .. ": header attribute sequence differs in " .. #failures .. " of " .. #cases .. " layouts\n"
        .. table.concat(failures, "\n", 1, math.min(#failures, 3))
        .. "\nFull diff: git worktree add <dir> $(git log -1 --format=%h -- tools/fixtures/group_header_attributes), then run\n"
        .. "  lua tools/tests/group_header_attribute_sequence_smoke.lua <root> " .. flavor .. " against <dir>", 0)
end
print("group_header_attribute_sequence_smoke: ok (" .. flavor .. ": " .. #cases .. " layouts, " .. writes
    .. " ordered writes pinned by hash)")
