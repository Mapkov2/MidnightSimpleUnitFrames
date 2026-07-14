local function bomLoadfile(path)
    local handle, openError = io.open(path, "rb")
    if not handle then return nil, openError end
    local source = handle:read("*a")
    handle:close()
    if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end
    local compile = loadstring or load
    return compile(source, "@" .. tostring(path))
end

loadfile = bomLoadfile
dofile = function(path)
    local chunk, err = bomLoadfile(path)
    assert(chunk, err)
    return chunk()
end

-- Desktop harnesses are shared with newer Lua runtimes, while WoW still uses
-- the Lua 5.1 global unpack.  Provide the compatibility alias centrally so a
-- product audit does not fail before it reaches the code under test.
table.unpack = table.unpack or unpack

local original = assert(arg, "usage: lua51_bom_runner.lua <script.lua> [args...]")
local target = assert(original[1], "usage: lua51_bom_runner.lua <script.lua> [args...]")
local forwarded = { [0] = target }
for i = 2, #original do forwarded[i - 1] = original[i] end
arg = forwarded
local chunk, err = bomLoadfile(target)
assert(chunk, err)
return chunk()
