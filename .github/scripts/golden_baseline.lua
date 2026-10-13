-- Golden baselines for the parity smokes.
--
-- A parity smoke used to replay the current source and a Retail reference checkout side by side.
-- The reference is frozen, so its observable behavior is recorded once into
-- .github/scripts/golden/<smoke>.golden and the smoke compares the current source with that file.
-- Logs are stored as chunk digests (a mismatch names the first differing chunk), counters as numbers.
--
-- Plain Lua 5.1, no dependencies. Each smoke loads it from its repository root:
--   local Golden = assert(loadfile(root .. "/.github/scripts/golden_baseline.lua"))()
local Golden = {}

local MODULUS = 4294967296
local CHUNK_LINES = 2000

local lineA, lineB = {}, {}

-- The C runtime spells non-finite numbers differently (Windows: 1.#INF, -1.#IND, 1.#INF0000;
-- glibc: inf, -nan). A golden file recorded on one platform must hold on the other.
local function Canonical(line)
    if not (line:find("#", 1, true) or line:find("nan", 1, true)) then return line end
    line = line:gsub("(%-?)1%.#INF%d*", "%1inf")
    line = line:gsub("%-?1%.#IND%d*", "nan")
    line = line:gsub("%-?1%.#QNAN%d*", "nan")
    line = line:gsub("%-nan%(ind%)", "nan")
    line = line:gsub("%-nan", "nan")
    return line
end

-- Two independent 32-bit polynomial hashes of one line, memoized: logs repeat the same few
-- hundred distinct lines millions of times.
local function LineHash(line)
    local a = lineA[line]
    if a then return a, lineB[line] end
    local ha, hb = 5381, 52711
    local byte = string.byte
    local canonical = Canonical(line)
    for index = 1, #canonical do
        local value = byte(canonical, index)
        ha = (ha * 31 + value) % MODULUS
        hb = (hb * 33 + value * 7 + 1) % MODULUS
    end
    lineA[line], lineB[line] = ha, hb
    return ha, hb
end

local blockA, blockB, blockLines = {}, {}, {}

-- Hash of a block of lines, memoized by the exact text.
local function BlockHash(text)
    local a = blockA[text]
    if a then return a, blockB[text], blockLines[text] end
    local ha, hb, count = 17, 31, 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local la, lb = LineHash(line)
        ha = (ha * 1000003 + la + 1) % MODULUS
        hb = (hb * 1048573 + lb + 7) % MODULUS
        count = count + 1
    end
    blockA[text], blockB[text], blockLines[text] = ha, hb, count
    return ha, hb, count
end

local Digest = {}
Digest.__index = Digest

-- A running digest over a sequence of text blocks (one per case, say).
function Golden.Digest()
    return setmetatable({ a = 7, b = 11, blocks = 0, lines = 0 }, Digest)
end

function Digest:Add(text)
    local ha, hb, count = BlockHash(text)
    self.a = (self.a * 1000003 + ha + 1) % MODULUS
    self.b = (self.b * 1048573 + hb + 3) % MODULUS
    self.blocks = self.blocks + 1
    self.lines = self.lines + count
end

function Digest:Value()
    return string.format("%08x%08x:%d:%d", self.a, self.b, self.blocks, self.lines)
end

local function SplitLines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

-- Digests of consecutive CHUNK_LINES-line chunks of a log, and the log's line count.
local function ChunkDigests(lines)
    local digests = {}
    for first = 1, #lines, CHUNK_LINES do
        local ha, hb = 13, 29
        for index = first, math.min(first + CHUNK_LINES - 1, #lines) do
            local la, lb = LineHash(lines[index])
            ha = (ha * 1000003 + la + 1) % MODULUS
            hb = (hb * 1048573 + lb + 5) % MODULUS
        end
        digests[#digests + 1] = string.format("%08x%08x", ha, hb)
    end
    return digests
end

-- Appends the entries that describe a log: its line count and one digest per chunk.
function Golden.AddLog(entries, name, text)
    local lines = SplitLines(text)
    entries[#entries + 1] = { name .. ".lines", tostring(#lines) }
    for index, digest in ipairs(ChunkDigests(lines)) do
        entries[#entries + 1] = { string.format("%s.chunk.%04d", name, index), digest }
    end
end

-- nil when `expected` (a map from Golden.Read) records exactly this log, otherwise a message
-- that names the first chunk that differs and shows the current lines of that chunk.
function Golden.LogDiff(expected, name, text)
    local lines = SplitLines(text)
    local digests = ChunkDigests(lines)
    local recordedLines = tonumber(expected[name .. ".lines"])
    if not recordedLines then return name .. ": the golden file has no record of this log" end
    for index, digest in ipairs(digests) do
        local recorded = expected[string.format("%s.chunk.%04d", name, index)]
        if recorded ~= digest then
            local first = (index - 1) * CHUNK_LINES + 1
            local shown = {}
            for line = first, math.min(first + 5, #lines) do shown[#shown + 1] = "    " .. lines[line] end
            return string.format("%s differs from the golden baseline in lines %d-%d of %d (recorded %d lines); current lines from %d:\n%s",
                name, first, math.min(first + CHUNK_LINES - 1, #lines), #lines, recordedLines, first, table.concat(shown, "\n"))
        end
    end
    if recordedLines ~= #lines then
        return string.format("%s has %d lines, the golden baseline records %d", name, #lines, recordedLines)
    end
    return nil
end

-- The fixture is "key value" lines; '#' starts a comment. Values are numbers or digests.
function Golden.Read(path)
    local handle = io.open(path, "rb")
    if not handle then
        error("golden baseline missing: " .. path .. " (record it from the reference source: see the smoke header)", 0)
    end
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    local map = {}
    for line in text:gmatch("[^\n]+") do
        if line:sub(1, 1) ~= "#" then
            local key, value = line:match("^(%S+) (.+)$")
            if not key then error("malformed golden line in " .. path .. ": " .. line, 0) end
            map[key] = value
        end
    end
    return map
end

function Golden.Write(path, header, entries)
    local handle = assert(io.open(path, "wb"))
    for _, line in ipairs(header) do handle:write("# ", line, "\n") end
    for _, entry in ipairs(entries) do handle:write(entry[1], " ", entry[2], "\n") end
    handle:close()
end

-- Numbers keep 17 significant digits so a float counter survives the round trip exactly.
function Golden.Number(value)
    return string.format("%.17g", value)
end

-- The location of a smoke's fixture inside the repository under test.
function Golden.Path(root, smoke)
    return root .. "/.github/scripts/golden/" .. smoke .. ".golden"
end

-- Smoke command line: <root> [baseline source root | -] [parity-only] [record [label]]
-- Returns baselineRoot (nil = compare with the golden file), record (bool), label.
function Golden.Mode(argv)
    local baseline = argv and argv[2]
    if baseline == "-" or baseline == "" or baseline == "parity-only" or baseline == "golden" then baseline = nil end
    local record, label = false, nil
    for index = 2, (argv and #argv or 0) do
        if argv[index] == "record" then
            record, label = true, argv[index + 1]
        end
    end
    if record and not baseline then error("record needs the reference source root as the second argument", 0) end
    return baseline, record, label
end

function Golden.Header(smoke, label)
    return {
        "Golden baseline of .github/scripts/" .. smoke .. ".lua.",
        "Source: " .. (label or "the baseline source root passed to the smoke") .. ".",
        "Record: lua .github/scripts/auras3_test_driver.lua .github/scripts/" .. smoke .. ".lua <repo> <baseline source root> record \"<source label>\"",
        "The smoke compares the current source with these values; it never rewrites them.",
    }
end

return Golden
