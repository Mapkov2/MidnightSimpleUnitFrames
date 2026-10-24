-- Exercise actual cached compilation with fresh chunks, environments and executions.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local source = (arg[2] or root):gsub("\\", "/")
local parses, stdinCalls = {}, 0
local fixture = [[
local count = 0
return { items = {}, next = function() count = count + 1 return count end,
    environment = function() return FIXTURE_ENV end }, nil, "tail"
]]
local loader = assert(loadfile(source .. "/tools/tests/responsibility_route_loader.lua"))
setfenv(loader, setmetatable({
    loadfile = function(path)
        parses[path] = (parses[path] or 0) + 1
        if path == "missing" then return nil, "missing fixture" end
        return loadstring(path == "runtime-error" and 'error("fixture execution failed")' or fixture, "@" .. path)
    end,
    dofile = function() stdinCalls = stdinCalls + 1 return "stdin", nil, "tail" end,
}, { __index = _G }))
local compile, execute = loader()
assert(type(execute) == "function", "dofile compilation cache absent")
local first, second = assert(compile("fixture")), assert(compile("fixture"))
assert(first ~= second and parses.fixture == 1, "compilation cache reused a chunk or parsed twice")
assert(debug.getinfo(first, "S").source == "@fixture", "cached source identity changed")
setfenv(first, { FIXTURE_ENV = "first" })
setfenv(second, { FIXTURE_ENV = "second" })
local a, hole, tail = first()
local b = second()
assert(hole == nil and tail == "tail", "chunk return arity changed")
assert(a ~= b and a.items ~= b.items and a.next ~= b.next, "module state or closures shared")
assert(a.next() == 1 and a.next() == 2 and b.next() == 1, "module locals shared")
assert(a.environment() == "first" and b.environment() == "second", "chunk environments shared")
local c, blank, ending = execute("fixture")
local d = execute("fixture")
assert(c ~= d and c.next() == 1 and d.next() == 1 and parses.fixture == 1, "dofile cached execution")
assert(blank == nil and ending == "tail", "dofile return arity changed")
assert(compile("other") and parses.other == 1, "distinct source paths merged")
for i = 1, 2 do
    local chunk, message = compile("missing")
    assert(chunk == nil and message == "missing fixture", "compile error changed")
end
assert(parses.missing == 2, "failed compilation cached")
local ok, message = pcall(execute, "missing")
assert(not ok and message:find("missing fixture", 1, true), "dofile compile error swallowed")
for i = 1, 2 do
    ok, message = pcall(execute, "runtime-error")
    assert(not ok and message:find("fixture execution failed", 1, true), "dofile execution error swallowed")
end
assert(parses["runtime-error"] == 1, "throwing chunk reparsed")
local value, empty, last = execute()
assert(value == "stdin" and empty == nil and last == "tail" and stdinCalls == 1, "stdin fallback changed")
print("fixture_compilation_cache_smoke: ok")
