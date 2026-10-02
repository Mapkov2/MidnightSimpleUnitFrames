-- optional_globals_smoke.lua <repoRoot>
--
-- Cross-file MSUF globals are hard dependencies: callers resolve them through
-- MSUF.Require, which fails loudly when a provider is renamed or dropped. A
-- caller may read one through MSUF.Optional only when its absence is a
-- designed state (load-on-demand options, a module that exports while
-- enabled, an optional module, or a call the core can reach while it is still
-- loading). tools/optional-globals.tsv documents each such name with its kind,
-- the provider file and the reason.
--
-- This smoke reads every tracked Lua file of the core and the options addon
-- and fails when an Optional("MSUF_x") read (MSUF.Optional, a local alias, or
-- a RunOptional-style wrapper) names a global without a row, when a row's
-- kind is unknown, when its evidence file does not name the global, or when a
-- row is no longer read (rows only shrink with the reads).
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")

local function Read(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

local KINDS = { ["lod-options"] = true, ["module-toggle"] = true, ["optional-module"] = true, ["load-order"] = true }

local rows, order = {}, {}
local ledger = assert(Read(root .. "/tools/optional-globals.tsv"), "tools/optional-globals.tsv is missing")
local header = false
for line in ledger:gmatch("[^\n]+") do
    if line:sub(1, 1) ~= "#" then
        if not header then
            assert(line == "Name\tKind\tEvidence\tReason", "unexpected optional-globals header: " .. line)
            header = true
        else
            local name, kind, evidence, reason = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
            assert(name, "malformed optional-globals row: " .. line)
            assert(not rows[name], "duplicate optional-globals row: " .. name)
            assert(KINDS[kind], name .. ": unknown kind " .. kind)
            local source = Read(root .. "/" .. evidence)
            assert(source, name .. ": evidence file " .. evidence .. " is missing")
            assert(source:find(name, 1, true), name .. ": " .. evidence .. " does not name it")
            rows[name] = { kind = kind, reason = reason, reads = 0 }
            order[#order + 1] = name
        end
    end
end

-- Tracked Lua files of the two addons.
local listing = assert(io.popen('git -C "' .. root .. '" ls-files -- "MidnightSimpleUnitFrames/*.lua" "MidnightSimpleUnitFrames_Options/*.lua"'))
local files = {}
for path in listing:lines() do files[#files + 1] = path end
listing:close()
assert(#files > 100, "git ls-files found only " .. #files .. " Lua files")

local unlisted = {}
local reads = 0
for _, path in ipairs(files) do
    local text = Read(root .. "/" .. path)
    if text then
        -- Comments never resolve a global.
        text = text:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
        for name in text:gmatch("Optional%(%s*\"(MSUF[%w_]*)\"") do
            reads = reads + 1
            local row = rows[name]
            if row then
                row.reads = row.reads + 1
            else
                unlisted[#unlisted + 1] = path .. ": " .. name
            end
        end
    end
end

assert(#unlisted == 0, "Optional reads without a tools/optional-globals.tsv row (add one, or Require them):\n  "
    .. table.concat(unlisted, "\n  "))
for _, name in ipairs(order) do
    assert(rows[name].reads > 0, name .. ": stale tools/optional-globals.tsv row, nothing reads it through Optional")
end
print(string.format("optional_globals_smoke: ok (%d documented optional globals, %d reads in %d files)",
    #order, reads, #files))
