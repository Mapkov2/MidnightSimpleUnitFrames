-- Raw WOW_PROJECT_* reads belong in Game/Shared/Initialize.lua, which turns them
-- into MSUF.Client facts. Classic-owned and reviewed override files may keep only
-- the reads listed in ALLOWED, each with the reason it is still raw. Byte-identical
-- Retail copies are Retail's to change until the single-repo cutover, so they are
-- not checked here and a Retail sync never fails on them. Plain Lua 5.1; arg[1]
-- is the repo root.
local repo = assert(arg[1], "repo root required")

local function ReadText(relative)
    local handle = assert(io.open(repo .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

-- Every project global the client model owns. Detection reads them once, in the
-- source of truth; anywhere else they are a client check that skipped the model.
local PROJECT_GLOBALS = { "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
    "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC" }

--- Drops Lua comments so a project global named in prose does not count as a
--- read: the old substring count made every explanatory comment a "read" and
--- turned the allowance numbers into noise. Block comments (`--[[ ]]`) exist
--- only in the vendored Libs, which this smoke never scans, and are handled
--- anyway. Strings are left alone on purpose: a project global spelled out in
--- a string is still something a reviewer should see.
local function StripComments(source)
    local kept, blockClose = {}, nil
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        if blockClose then
            local stop = line:find(blockClose, 1, true)
            if stop then
                line, blockClose = line:sub(stop + #blockClose), nil
            else
                line = ""
            end
        end
        if not blockClose then
            local open, level = line:match("()%-%-%[(=*)%[")
            if open then
                local close = "]" .. level .. "]"
                local head, rest = line:sub(1, open - 1), line:sub(open)
                local stop = rest:find(close, 1, true)
                if stop then
                    line = head .. rest:sub(stop + #close)
                else
                    line, blockClose = head, close
                end
            end
        end
        kept[#kept + 1] = (line:gsub("%-%-.*$", ""))
    end
    return table.concat(kept, "\n")
end

--- Reads of the project globals in code, counted as whole identifiers so
--- WOW_PROJECT_ID is never also counted inside WOW_PROJECT_IDX.
local function CountProjectReads(source)
    local code = StripComments(source)
    local total = 0
    for i = 1, #PROJECT_GLOBALS do
        local name = PROJECT_GLOBALS[i]
        for _ in (" " .. code .. " "):gmatch("[^%w_]" .. name .. "[^%w_]") do
            total = total + 1
        end
    end
    return total
end

-- Self-test: the detector has to see a real read and ignore a documented one,
-- otherwise this smoke would pass by failing to look.
do
    local sample = [[
-- WOW_PROJECT_ID is explained here and must not count.
--- Neither does WOW_PROJECT_MAINLINE in a doc comment.
local id = _G.WOW_PROJECT_ID
local wide = WOW_PROJECT_IDX
local both = _G.WOW_PROJECT_ID == _G.WOW_PROJECT_MAINLINE -- WOW_PROJECT_CLASSIC
]]
    assert(CountProjectReads(sample) == 3,
        "the project-read detector is broken: expected 3 reads, got " .. CountProjectReads(sample))
    assert(CountProjectReads("-- WOW_PROJECT_ID\n") == 0, "a commented project global was counted as a read")
end

local reviewed = {}
for line in ReadText("tools/classic-owned-addon-paths.txt"):gmatch("[^\n]+") do
    local path = line:match("^%s*(.-)%s*$")
    if path ~= "" then reviewed[path] = "owned" end
end
for line in ReadText("tools/classic-retail-overrides.tsv"):gmatch("[^\n]+") do
    local path = line:match("^([^\t]+)\t")
    if path then reviewed[path] = "override" end
end

local SOURCE_OF_TRUTH = "MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"
-- path = { reads, reason }. Empty on purpose since 2026-09-19: every owned and
-- overridden file now branches on MSUF.Client. A new entry needs a reason that
-- says why the model cannot answer, not just that the code predates it.
local ALLOWED = {}

-- All three addons: the Assistant decides by client family too, so its reviewed
-- overrides answer to the same rule as the menu they mirror.
local command = 'git -C "' .. repo .. '" ls-files -- MidnightSimpleUnitFrames MidnightSimpleUnitFrames_Options MidnightSimpleUnitFrames_Assistant'
local pipe = assert(io.popen(command, "r"), "cannot enumerate tracked addon files")
local scanned, failures, seen = 0, {}, {}
for path in pipe:lines() do
    if path:match("%.lua$") and reviewed[path] and path ~= SOURCE_OF_TRUTH then
        scanned = scanned + 1
        local reads = CountProjectReads(ReadText(path))
        local allowed = ALLOWED[path]
        if reads > 0 or allowed then
            seen[path] = true
            local expected = allowed and allowed[1] or 0
            if reads ~= expected then
                failures[#failures + 1] = string.format(
                    "%s (%s) reads a WOW_PROJECT_* global %d times, allowed %d. Route client checks through MSUF.Client (%s), or update ALLOWED with the reason.",
                    path, reviewed[path], reads, expected, SOURCE_OF_TRUTH)
            end
        end
    end
end
local pipeOk, pipeReason, pipeCode = pipe:close()
assert(pipeOk or pipeCode == 0, "git ls-files failed: " .. tostring(pipeReason or pipeCode))
assert(scanned >= 100, "only " .. scanned .. " owned or override Lua files were scanned; git ls-files likely failed")
-- The source of truth must keep reading them: it is the only file that may.
assert(CountProjectReads(ReadText(SOURCE_OF_TRUTH)) > 0,
    SOURCE_OF_TRUTH .. " no longer reads any project global; client detection cannot work")
for path in pairs(ALLOWED) do
    assert(reviewed[path], "ALLOWED names a file that is neither owned nor overridden: " .. path)
    assert(seen[path], "ALLOWED names a file that git does not track: " .. path)
end
assert(#failures == 0, table.concat(failures, "\n"))
print("classic project ID reads smoke passed: " .. scanned .. " owned or override Lua files")
