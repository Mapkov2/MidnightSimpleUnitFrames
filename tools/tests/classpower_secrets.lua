-- classpower_secrets.lua -- secret values as strict as the 12.x client.
--
-- The shared stubs model a secret as a plain table that issecretvalue() knows.
-- That is more lenient than the client in two ways that let real bugs pass:
--   * type(secret) is "table", so a `type(v) == "number"` guard never lets a
--     secret through, while the client answers "number" (or "string");
--   * comparing it is silent, while the client raises.
-- This helper closes both gaps for a ClassPower smoke:
--   local Secrets = assert(loadfile(root .. "/tools/tests/classpower_secrets.lua"))()
--   World.Start(..., { beforeLoad = function() Secrets.Install() end })
--   local hp = Secrets.New("number")
-- After Install(), type() reports a secret's kind, issecretvalue() recognises
-- it, tonumber()/tostring() pass it through, and arithmetic, ordering,
-- concatenation, length, indexing, calling and secret == secret raise.
--
-- Lua 5.1 never calls __eq when one side is nil, a number or a string, so a
-- `secret == nil` or `secret == ""` stays silent at the VM level. Watch(path)
-- closes that gap with a line hook: whenever a line of that file runs while a
-- local named on it holds a secret, and the line compares that name with == or
-- ~= or truth-tests it with not, the line is recorded as a violation. A line
-- that calls issecretvalue(name) first is a guarded short-circuit and passes.
--
-- Plain Lua 5.1.

local Secrets = {}

local rawtype, rawtonumber, rawtostring = type, tonumber, tostring
local kinds = setmetatable({}, { __mode = "k" })

local function Raise(operation)
    error("attempt to " .. operation .. " a secret value", 3)
end

local meta = {
    __eq = function() Raise("compare") end,
    __lt = function() Raise("compare") end,
    __le = function() Raise("compare") end,
    __add = function() Raise("perform arithmetic on") end,
    __sub = function() Raise("perform arithmetic on") end,
    __mul = function() Raise("perform arithmetic on") end,
    __div = function() Raise("perform arithmetic on") end,
    __mod = function() Raise("perform arithmetic on") end,
    __pow = function() Raise("perform arithmetic on") end,
    __unm = function() Raise("perform arithmetic on") end,
    __concat = function() Raise("concatenate") end,
    __len = function() Raise("get the length of") end,
    __index = function() Raise("index") end,
    __newindex = function() Raise("index") end,
    __call = function() Raise("call") end,
    __tostring = function() return "<secret>" end,
}

--- A new secret of the given Lua kind ("number" by default, or "string").
function Secrets.New(kind)
    local value = setmetatable({}, meta)
    kinds[value] = kind or "number"
    return value
end

function Secrets.IsSecret(value)
    return kinds[value] ~= nil
end

--- Swaps the client-facing globals. Call before the addon files load: files
--- capture type/issecretvalue/tonumber/tostring as locals.
function Secrets.Install()
    _G.type = function(value)
        local kind = kinds[value]
        if kind then return kind end
        return rawtype(value)
    end
    _G.issecretvalue = function(value) return kinds[value] ~= nil end
    _G.tonumber = function(value, base)
        if kinds[value] then return value end
        return rawtonumber(value, base)
    end
    _G.tostring = function(value)
        if kinds[value] then return Secrets.New("string") end
        return rawtostring(value)
    end
end

local function SourceLines(path)
    local file = assert(io.open(path, "rb"), "missing source: " .. path)
    local raw = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local lines = {}
    for line in (raw .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    return lines
end

local function Escape(name) return (name:gsub("%W", "%%%0")) end

local function Misuses(line, name)
    local n = Escape(name)
    if line:find("issecretvalue%(%s*" .. n .. "%s*%)") then return false end
    return line:find("%f[%w_]" .. n .. "%s*[=~]=") ~= nil
        or line:find("[=~]=%s*" .. n .. "%f[^%w_]") ~= nil
        or line:find("%f[%w_]not%s+" .. n .. "%f[^%w_]") ~= nil
end

--- Records every executed line of `path` that compares or truth-tests a local
--- holding a secret. Returns stop(): it removes the hook and returns the
--- violations as "file:line: text" strings.
function Secrets.Watch(path)
    local lines = SourceLines(path)
    local wanted = "@" .. path
    local violations, seen = {}, {}
    debug.sethook(function(_, lineNumber)
        local info = debug.getinfo(2, "S")
        if not info or (info.source ~= wanted and info.source:gsub("\\", "/") ~= wanted:gsub("\\", "/")) then return end
        local text = lines[lineNumber]
        if not text then return end
        local index = 1
        while true do
            local name, value = debug.getlocal(2, index)
            if not name then break end
            if kinds[value] and Misuses(text, name) and not seen[lineNumber] then
                seen[lineNumber] = true
                violations[#violations + 1] = ("%s:%d: %s"):format(path:match("[^/\\]+$"), lineNumber, text:match("^%s*(.-)%s*$"))
            end
            index = index + 1
        end
    end, "l")
    return function()
        debug.sethook()
        return violations
    end
end

return Secrets
