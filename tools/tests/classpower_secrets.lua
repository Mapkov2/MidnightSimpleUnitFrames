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
-- ~= or truth-tests it with not, the line is recorded as a violation, unless
-- the text before the use short-circuits it while the value is secret: a
-- secret predicate on the same name joined the right way round
-- (`NotSecret(v) and v ~= nil`, `not NotSecret(v) or v == nil`,
-- `not CanAccessTableValue(t) or #t == 0`, `issecretvalue(v) or ...`), or a
-- plain local flag (`maxSecret or cache ~= maxValue`, `curSafe and v == nil`,
-- `not curSecret and v == nil`). An `or` after an `and` guard, or a
-- parenthesis group closing around the guard, makes the use reachable again.
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

-- Short-circuit guards. A use of a secret local is safe when the text before
-- it on the line makes the rest of the expression unreachable while the value
-- is secret: a secret predicate on the same name (NotSecret, CanAccess*,
-- issecretvalue) or a plain local flag, joined by `and` / `or` the right way
-- round, with no `or` cutting an `and` guard off (`a and x or use` reaches
-- use) and no parenthesis group closing around the guard before the use.
-- Each entry: pattern (%s is the escaped name), the joining operator, and
-- whether the pattern starts with `not`.
local SECRET_GUARDS = {
    { "%%f[%%w_]NotSecret%%(%%s*%s%%s*%%)%%s+and%%f[^%%w_]", "and" },
    { "%%f[%%w_]CanAccess[%%w_]*%%(%%s*%s%%s*%%)%%s+and%%f[^%%w_]", "and" },
    { "%%f[%%w_]not%%s+issecretvalue%%(%%s*%s%%s*%%)%%s+and%%f[^%%w_]", "and", true },
    { "%%f[%%w_]not%%s+NotSecret%%(%%s*%s%%s*%%)%%s+or%%f[^%%w_]", "or", true },
    { "%%f[%%w_]NotSecret%%(%%s*%s%%s*%%)%%s*==%%s*false%%s+or%%f[^%%w_]", "or" },
    { "%%f[%%w_]not%%s+CanAccess[%%w_]*%%(%%s*%s%%s*%%)%%s+or%%f[^%%w_]", "or", true },
    { "%%f[%%w_]issecretvalue%%(%%s*%s%%s*%%)%%s+or%%f[^%%w_]", "or" },
    { "%%f[%%w_]issecretvalue%%(%%s*%s%%s*%%)%%s*~=%%s*true%%s+and%%f[^%%w_]", "and" },
    { "%%f[%%w_]issecretvalue%%(%%s*%s%%s*%%)%%s*==%%s*false%%s+and%%f[^%%w_]", "and" },
    { "%%f[%%w_]issecretvalue%%(%%s*%s%%s*%%)%%s*==%%s*true%%s+or%%f[^%%w_]", "or" },
    { "%%f[%%w_]NotSecret%%(%%s*%s%%s*%%)%%s*==%%s*true%%s+and%%f[^%%w_]", "and" },
    { "%%f[%%w_]NotSecret%%(%%s*%s%%s*%%)%%s*~=%%s*false%%s+and%%f[^%%w_]", "and" },
}

local KEYWORDS = { ["and"] = true, ["or"] = true, ["not"] = true, ["if"] = true, ["then"] = true,
    ["elseif"] = true, ["return"] = true, ["local"] = true, ["while"] = true, ["do"] = true,
    ["until"] = true, ["true"] = true, ["false"] = true, ["nil"] = true }

local function ParenDepth(text)
    local depth = 0
    for c in text:gmatch("[()]") do depth = depth + (c == "(" and 1 or -1) end
    return depth
end

-- True when a guard spanning prefix[start .. finish] still governs the end of
-- prefix (where the use starts).
local function Reaches(prefix, start, finish, operator)
    local guardDepth = ParenDepth(prefix:sub(1, start - 1))
    local depth, rest = guardDepth, prefix:sub(finish + 1)
    local index = 1
    while index <= #rest do
        local c = rest:sub(index, index)
        if c == "(" then
            depth = depth + 1
        elseif c == ")" then
            depth = depth - 1
            if depth < guardDepth then return false end
        elseif operator == "and" and depth <= guardDepth and rest:find("^or%f[^%w_]", index)
            and (index == 1 or not rest:sub(index - 1, index - 1):find("[%w_]")) then
            return false
        end
        index = index + 1
    end
    return true
end

local function Guarded(prefix, name, locals, known)
    local n = Escape(name)
    for i = 1, #SECRET_GUARDS do
        local entry = SECRET_GUARDS[i]
        local pattern, operator, negated = entry[1]:format(n), entry[2], entry[3]
        local position = 1
        while true do
            local start, finish = prefix:find(pattern, position)
            if not start then break end
            local before = prefix:sub(1, start - 1)
            if (negated or not before:find("%f[%w_]not%s*$")) and Reaches(prefix, start, finish, operator) then
                return true
            end
            position = start + 1
        end
    end
    for start, flag, flagEnd in prefix:gmatch("()([%a_][%w_]*)()") do
        local opStart, opEnd, operator = prefix:find("^%s+(%a+)%f[^%w_]", flagEnd)
        if (operator == "and" or operator == "or") and known[flag] and not KEYWORDS[flag]
            and not kinds[locals[flag]] then
            local before = prefix:sub(1, start - 1)
            if not before:find("[%.:]%s*$") then
                local truthy = locals[flag] ~= nil and locals[flag] ~= false
                local guardStart = start
                local negation = before:find("%f[%w_]not%s+$")
                if negation then
                    truthy = not truthy
                    guardStart = negation
                end
                local short = (operator == "or" and truthy) or (operator == "and" and not truthy)
                if short and Reaches(prefix, guardStart, opEnd, operator) then return true end
            end
        end
    end
    return false
end

local USE_PATTERNS = { "%%f[%%w_]%s%%s*[=~]=", "[=~]=%%s*%s%%f[^%%w_]", "%%f[%%w_]not%%s+%s%%f[^%%w_]" }

local function Misuses(line, name, locals, known)
    local n = Escape(name)
    for i = 1, #USE_PATTERNS do
        local start = line:find(USE_PATTERNS[i]:format(n))
        if start and not Guarded(line:sub(1, start - 1), name, locals, known) then return true end
    end
    return false
end

--- Records every executed line of `path` that compares or truth-tests a local
--- holding a secret. `path` may also be a list of paths: one hook watches them
--- all (debug.sethook keeps a single hook). Returns stop(): it removes the hook
--- and returns the violations as "file:line: text" strings.
function Secrets.Watch(path)
    local watched = {}
    for _, file in ipairs(type(path) == "table" and path or { path }) do
        local key = ("@" .. file):gsub("\\", "/")
        watched[key] = { lines = SourceLines(file), name = file:match("[^/\\]+$"), seen = {} }
    end
    local violations = {}
    debug.sethook(function(_, lineNumber)
        local info = debug.getinfo(2, "S")
        local entry = info and (watched[info.source] or watched[(info.source:gsub("\\", "/"))])
        if not entry then return end
        local lines, seen = entry.lines, entry.seen
        local text = lines[lineNumber]
        if not text or seen[lineNumber] then return end
        -- Later locals shadow earlier ones of the same name.
        local locals, known, index = {}, {}, 1
        while true do
            local name, value = debug.getlocal(2, index)
            if not name then break end
            locals[name], known[name] = value, true
            index = index + 1
        end
        for name, value in pairs(locals) do
            if kinds[value] and Misuses(text, name, locals, known) then
                seen[lineNumber] = true
                violations[#violations + 1] = ("%s:%d: %s"):format(entry.name, lineNumber, text:match("^%s*(.-)%s*$"))
                break
            end
        end
    end, "l")
    return function()
        debug.sethook()
        return violations
    end
end

return Secrets
