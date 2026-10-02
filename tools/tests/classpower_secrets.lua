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
-- `secret == nil` or `secret == ""` stays silent at the VM level, and a secret
-- stub is a table, so a boolean test on it (`if v then`, `v or 0`) passes too,
-- where the client raises "attempt to perform boolean test on a secret value".
-- Watch(path [, options]) closes those gaps with a line hook. Whenever a line
-- of a watched file runs, it records the line as a violation when
--   * a local holding a secret is compared (== / ~=) or negated (not v), or
--   * a field holding a secret is boolean-tested through a local table
--     (`t.f or ...`, `t.f and ...`, `if t.f then`, `not t.f`, ...);
--   * with options.strict also when a secret local is boolean-tested in any
--     other way (`v and`, `v or`, `if v then`, `elseif v then`, `while v do`,
--     `and v then`, `or v then`) or a secret field is compared,
-- unless the text before the use short-circuits it while the value is secret:
--   * a secret predicate on the same operand joined the right way round:
--     `NotSecret(v) and v ~= nil`, `not NotSecret(v) or v == nil`,
--     `not CanAccessTableValue(t) or #t == 0`, `issecretvalue(v) or ...`,
--     `IsSecret(v) or ...`. Predicates are known by name, qualified or not
--     (`E.NotSecret`, `_issecretvalue`); Secrets.GUARD_NAMES lists them and a
--     smoke may add its own aliases;
--   * a plain local flag: `maxSecret or cache ~= maxValue`,
--     `curSafe and v == nil`, `not curSecret and v == nil`.
-- An `or` after an `and` guard, or a parenthesis group closing around the
-- guard, makes the use reachable again. A guard on an earlier line of the same
-- expression counts: a line that starts with `and` / `or`, or follows a line
-- ending in `and` / `or` / `(`, is read together with those lines.
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


-- Secret predicates by the last segment of their name. "truthy" answers true
-- while its operand is secret (issecretvalue), "falsy" answers false
-- (NotSecret, CanAccessTableValue). A smoke may add its own aliases.
Secrets.GUARD_NAMES = {
    truthy = { issecretvalue = true, _issecretvalue = true, IsSecret = true, isSecret = true,
        IsSecretValue = true, isSecretValue = true },
    falsy = { NotSecret = true, notSecret = true, IsPlain = true, isPlain = true },
    falsyPrefixes = { "CanAccess", "canAccess", "canaccess" },
}

local function GuardKind(callee)
    local name = callee:match("([%a_][%w_]*)$")
    if not name then return nil end
    local names = Secrets.GUARD_NAMES
    if names.truthy[name] then return true end
    if names.falsy[name] then return false end
    for _, prefix in ipairs(names.falsyPrefixes) do
        if name:sub(1, #prefix) == prefix then return false end
    end
    return nil
end

local KEYWORDS = { ["and"] = true, ["or"] = true, ["not"] = true, ["if"] = true, ["then"] = true,
    ["elseif"] = true, ["return"] = true, ["local"] = true, ["while"] = true, ["do"] = true,
    ["until"] = true, ["true"] = true, ["false"] = true, ["nil"] = true }

local function ParenDepth(text)
    local depth = 0
    for c in text:gmatch("[()]") do depth = depth + (c == "(" and 1 or -1) end
    return depth
end

-- True when a guard spanning prefix[start .. finish] still governs the end of
-- prefix (where the use starts): no parenthesis group around the guard closes
-- first, and no `or` cuts an `and` guard off.
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

-- A secret predicate call on the operand (pattern n), possibly negated and
-- compared with true/false, joined to the rest by and/or the short-circuiting
-- way round.
local function PredicateGuard(prefix, n)
    for start, callee, after in prefix:gmatch("()([%a_][%w_%.:]*)%(%s*" .. n .. "%s*%)()") do
        local value = GuardKind(callee)
        if value ~= nil then
            local guardStart = start
            local negation = prefix:sub(1, start - 1):find("%f[%w_]not%s+$")
            if negation then
                value = not value
                guardStart = negation
            end
            local position = after
            local _, compareEnd, compareOp, literal = prefix:find("^%s*([=~]=)%s*(%a+)", position)
            if compareOp and (literal == "true" or literal == "false") then
                local equal = value == (literal == "true")
                value = (compareOp == "==") == equal
                position = compareEnd + 1
            end
            local _, opEnd, operator = prefix:find("^%s+(%a+)%f[^%w_]", position)
            if (operator == "and" and not value) or (operator == "or" and value) then
                if Reaches(prefix, guardStart, opEnd, operator) then return true end
            end
        end
    end
    return false
end

-- A plain local flag joined by and/or the short-circuiting way round.
local function FlagGuard(prefix, locals, known)
    for start, flag, flagEnd in prefix:gmatch("()([%a_][%w_]*)()") do
        local _, opEnd, operator = prefix:find("^%s+(%a+)%f[^%w_]", flagEnd)
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

local function Guarded(prefix, n, locals, known)
    return PredicateGuard(prefix, n) or FlagGuard(prefix, locals, known)
end

-- The ways of comparing or boolean-testing an operand (pattern n); the ()
-- capture marks where the operand starts.
local function ComparePatterns(n)
    return { "()" .. n .. "%s*[=~]=", "[=~]=%s*()" .. n }
end

local function TruthPatterns(n)
    return {
        "%f[%w_]not%s+()" .. n,
        "()" .. n .. "%s+and%f[^%w_]",
        "()" .. n .. "%s+or%f[^%w_]",
        "%f[%w_]if%s+()" .. n .. "%s+then%f[^%w_]",
        "%f[%w_]elseif%s+()" .. n .. "%s+then%f[^%w_]",
        "%f[%w_]while%s+()" .. n .. "%s+do%f[^%w_]",
        "%f[%w_]and%s+()" .. n .. "%s+then%f[^%w_]",
        "%f[%w_]or%s+()" .. n .. "%s+then%f[^%w_]",
    }
end

-- What Watch records for each operand kind. Default: a secret local compared
-- or negated, a secret field boolean-tested. Strict (Watch option): any
-- boolean test of a secret local and any comparison of a secret field too.
local function UsePatterns(n, field, strict)
    local patterns = {}
    if not field or strict then
        for _, pattern in ipairs(ComparePatterns(n)) do patterns[#patterns + 1] = pattern end
    end
    if field or strict then
        for _, pattern in ipairs(TruthPatterns(n)) do patterns[#patterns + 1] = pattern end
    else
        patterns[#patterns + 1] = "%f[%w_]not%s+()" .. n
    end
    return patterns
end

-- True when text uses the operand (pattern n, plain length len) at or after
-- position from without a guard before it.
local function Misused(text, from, n, len, locals, known, field, strict)
    local patterns = UsePatterns(n, field, strict)
    for i = 1, #patterns do
        local init = 1
        while true do
            local start, finish, operandStart = text:find(patterns[i], init)
            if not start then break end
            init = start + 1
            local before = text:sub(operandStart - 1, operandStart - 1)
            local after = text:sub(operandStart + len, operandStart + len)
            if operandStart >= from and not before:find("[%w_%.:]") and not after:find("[%w_%.:%(%[]")
                and not Guarded(text:sub(1, operandStart - 1), n, locals, known) then
                return true
            end
        end
    end
    return false
end

local function StripComment(line)
    return (line:gsub("%-%-.*$", ""))
end

-- The current line, preceded by the earlier lines of the same expression.
local function ExpressionText(lines, lineNumber)
    local current = StripComment(lines[lineNumber])
    local text, index = current, lineNumber
    while index > 1 and lineNumber - index < 4 do
        local previous = StripComment(lines[index - 1]):match("^%s*(.-)%s*$")
        local head = StripComment(lines[index]):match("^%s*(.-)%s*$")
        local continues = head:find("^and%f[^%w_]") or head:find("^or%f[^%w_]")
            or previous:find("%f[%w_]and$") or previous:find("%f[%w_]or$") or previous:find("%($")
        if not continues then break end
        text = previous .. " " .. text
        index = index - 1
    end
    return text, #text - #current + 1
end

--- Records every executed line of `path` that compares or negates a secret
--- local, or boolean-tests a secret field of a local table. With
--- options.strict it also records any boolean test of a secret local
--- (`v or 0`, `if v then`) and any comparison of a secret field. `path` may
--- also be a list of paths: one hook watches them all (debug.sethook keeps a
--- single hook). Returns stop(): it removes the hook and returns the
--- violations as "file:line: text" strings.
function Secrets.Watch(path, options)
    local strict = options and options.strict == true
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
        local line = lines[lineNumber]
        if not line or seen[lineNumber] then return end
        -- Later locals shadow earlier ones of the same name.
        local locals, known, index = {}, {}, 1
        while true do
            local name, value = debug.getlocal(2, index)
            if not name then break end
            locals[name], known[name] = value, true
            index = index + 1
        end
        local text, from
        local function Record()
            seen[lineNumber] = true
            violations[#violations + 1] = ("%s:%d: %s"):format(entry.name, lineNumber, line:match("^%s*(.-)%s*$"))
        end
        for name, value in pairs(locals) do
            if kinds[value] then
                if not text then text, from = ExpressionText(lines, lineNumber) end
                if Misused(text, from, Escape(name), #name, locals, known, false, strict) then return Record() end
            end
        end
        for tableName, field in line:gmatch("([%a_][%w_]*)%.([%a_][%w_]*)") do
            local tbl = locals[tableName]
            if rawtype(tbl) == "table" and not kinds[tbl] and kinds[rawget(tbl, field)] then
                if not text then text, from = ExpressionText(lines, lineNumber) end
                local operand = tableName .. "." .. field
                if Misused(text, from, Escape(operand), #operand, locals, known, true, strict) then
                    return Record()
                end
            end
        end
    end, "l")
    return function()
        debug.sethook()
        return violations
    end
end

return Secrets
