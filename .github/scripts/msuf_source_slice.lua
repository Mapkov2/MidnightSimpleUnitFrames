-- Shared source slicer for the contract smokes.
--
-- A dozen smokes compile one function out of a shipped file so they can call it
-- offline. Every one of them used to cut the slice at a marker naming whatever
-- came next in the file -- the next function's name, or even the doc comment
-- above it. Those boundaries are not boundaries: rename or reorder the next
-- function and the slice silently grows, shrinks or stops matching, and the
-- smoke fails for a non-bug (or, worse, passes on the wrong text).
--
-- Slice.Function() ends the slice at the function's own matching `end`, found by
-- counting block keywords with a Lua lexer that skips strings and comments. It
-- needs no knowledge of what follows. A miss is always fatal and always names
-- the file and the declaration.
--
--     local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
--     local body = Slice.Function(source, "local function ClampBoxAxis", path)
--
-- Usage note: `declaration` is the literal text that opens the function, up to
-- but not including its parameter list -- "local function Foo",
-- "function A3.Bar", "M.Format = function". Pass the file path so a miss can
-- name it.

local Slice = {}

local function Fail(message)
    error("msuf_source_slice: " .. message, 3)
end

function Slice.Read(path)
    local file = io.open(path, "rb")
    if file == nil then Fail("cannot read " .. tostring(path)) end
    local text = file:read("*a")
    file:close()
    -- The worktree is CRLF; every caller matches "\n" patterns.
    return (text:gsub("\r\n", "\n"))
end

local KEYWORD = {
    ["function"] = 1, ["if"] = 1, ["do"] = 1, ["repeat"] = 1,
    ["end"] = -1, ["until"] = -1,
}

-- Skip a long bracket ("[[", "[=[", ...) that starts at `position`.
-- Returns the position after the closing bracket, or nil when this is not one.
local function SkipLongBracket(source, position)
    local equals = source:match("^%[(=*)%[", position)
    if equals == nil then return nil end
    local close = "]" .. equals .. "]"
    local _, stop = source:find(close, position + #equals + 2, true)
    return (stop or #source) + 1
end

-- Position just past the `end` that closes the block opened at `position`
-- (which must sit on the opening keyword's block, depth already 1).
local function FindBlockEnd(source, position, path, declaration)
    local depth = 1
    local length = #source
    while position <= length do
        local char = source:sub(position, position)
        if char == "-" and source:sub(position + 1, position + 1) == "-" then
            local afterLong = SkipLongBracket(source, position + 2)
            if afterLong then
                position = afterLong
            else
                position = (source:find("\n", position, true) or length) + 1
            end
        elseif char == '"' or char == "'" then
            local quote, scan = char, position + 1
            while scan <= length do
                local inner = source:sub(scan, scan)
                if inner == "\\" then scan = scan + 2
                elseif inner == quote then scan = scan + 1; break
                else scan = scan + 1 end
            end
            position = scan
        elseif char == "[" then
            position = SkipLongBracket(source, position) or (position + 1)
        elseif char:match("[%a_]") then
            local word = source:match("^[%w_]+", position)
            local step = KEYWORD[word]
            if step then
                depth = depth + step
                if depth == 0 then return position + #word end
            end
            position = position + #word
        elseif char:match("%d") then
            position = position + #source:match("^[%w%.]+", position)
        else
            position = position + 1
        end
    end
    Fail("no matching `end` for " .. declaration .. " in " .. tostring(path)
        .. " (the slice ran off the end of the file)")
end

-- Every position where `declaration` opens a function: the parameter list has
-- to follow, so "function Apply.Text" never matches "function Apply.Texture".
local function Declarations(source, declaration)
    local found, from = {}, 1
    while true do
        local first = source:find(declaration, from, true)
        if first == nil then return found end
        local after = first + #declaration
        if source:match("^[ \t]*%(", after) then found[#found + 1] = first end
        from = after
    end
end

-- The text of one function, from its declaration through its own `end`.
function Slice.Function(source, declaration, path)
    local found = Declarations(source, declaration)
    if #found == 0 then
        Fail("no `" .. declaration .. "(` in " .. tostring(path)
            .. "; the function was renamed, moved or removed, so this contract now covers nothing")
    end
    if #found > 1 then
        Fail("`" .. declaration .. "(` is declared " .. #found .. " times in " .. tostring(path)
            .. "; the slice would be ambiguous")
    end
    local first = found[1]
    -- The parameter list is balanced, so %b() walks past any parenthesised
    -- expression inside it.
    local _, afterParams = source:find("%b()", first + #declaration - 1)
    if afterParams == nil then
        Fail("no parameter list after `" .. declaration .. "` in " .. tostring(path))
    end
    local stop = FindBlockEnd(source, afterParams + 1, path, declaration)
    return source:sub(first, stop - 1)
end

-- One table constructor, from its declaration through its balanced `}`.
-- `declaration` is the text up to but not including the `{`, for example
-- "local MSUF_SCALE_FRAME_GLOBALS =".
function Slice.Table(source, declaration, path)
    local first = source:find(declaration, 1, true)
    if first == nil then
        Fail("no `" .. declaration .. "` in " .. tostring(path)
            .. "; the table was renamed, moved or removed, so this contract now covers nothing")
    end
    if source:find(declaration, first + #declaration, true) ~= nil then
        Fail("`" .. declaration .. "` appears more than once in " .. tostring(path)
            .. "; the slice would be ambiguous")
    end
    local open = source:find("{", first + #declaration - 1, true)
    if open == nil then Fail("no table constructor after `" .. declaration .. "` in " .. tostring(path)) end
    local _, stop = source:find("%b{}", open)
    if stop == nil then Fail("unbalanced table constructor after `" .. declaration .. "` in " .. tostring(path)) end
    return source:sub(first, stop)
end

-- True while the statement collected so far cannot be the whole statement:
-- an unclosed bracket, or a trailing/leading binary operator. Lets a slice
-- follow an expression that production later wrapped over several lines,
-- which is a formatting change, not a behaviour change.
local CONTINUES = { "and", "or", "not", "%.%.", "==", "~=", "<=", ">=", "<", ">",
    "%+", "%-", "%*", "/", "%%", "%^", "," }
local function StatementIncomplete(text, nextLine)
    local depth = 0
    for char in text:gmatch("[%(%)%[%]{}]") do
        if char == "(" or char == "[" or char == "{" then depth = depth + 1
        else depth = depth - 1 end
    end
    if depth > 0 then return true end
    local tail = text:match("([^\r\n]-)%s*$")
    for index = 1, #CONTINUES do
        if tail:match(CONTINUES[index] .. "$") then return true end
    end
    if nextLine == nil then return false end
    local head = nextLine:match("^%s*(%S+)")
    if head == nil then return false end
    for index = 1, #CONTINUES do
        if head:match("^" .. CONTINUES[index]) then return true end
    end
    return false
end

-- One assignment statement, from its declaration to the end of its expression
-- (following the expression across lines when it is wrapped). Lets a harness
-- read a constant or a gate expression out of the shipped file instead of
-- re-declaring it, so the harness cannot keep asserting against a value or a
-- rule production has changed.
function Slice.Constant(source, declaration, path)
    local first = source:find(declaration, 1, true)
    if first == nil then
        Fail("no `" .. declaration .. "` in " .. tostring(path)
            .. "; the constant was renamed, moved or removed")
    end
    if source:find(declaration, first + #declaration, true) ~= nil then
        Fail("`" .. declaration .. "` appears more than once in " .. tostring(path))
    end
    local rest = source:sub(first)
    local lines = {}
    for line in rest:gmatch("([^\n]*)\n?") do
        lines[#lines + 1] = line
        if #lines > 64 then break end
    end
    if lines[1]:find("function", 1, true) then
        Fail("`" .. declaration .. "` in " .. tostring(path)
            .. " declares a function; use Slice.Function")
    end
    if lines[1]:find("{", 1, true) then
        Fail("`" .. declaration .. "` in " .. tostring(path)
            .. " declares a table; use Slice.Table")
    end
    local statement = lines[1]
    local index = 1
    while StatementIncomplete(statement, lines[index + 1]) do
        index = index + 1
        if lines[index] == nil then
            Fail("`" .. declaration .. "` in " .. tostring(path) .. " never finishes its expression")
        end
        statement = statement .. "\n" .. lines[index]
    end
    return statement
end

-- One declaration of any of the three kinds above, picked from the
-- declaration text: "... function" is a function, an `=` followed by `{` is a
-- table, anything else is a scalar constant.
function Slice.Declaration(source, declaration, path)
    if declaration:find("function", 1, true) then
        return Slice.Function(source, declaration, path)
    end
    local first = source:find(declaration, 1, true)
    if first == nil then
        Fail("no `" .. declaration .. "` in " .. tostring(path)
            .. "; it was renamed, moved or removed, so this contract now covers nothing")
    end
    local line = source:match("^[^\r\n]*", first)
    if line:find("{", 1, true) then return Slice.Table(source, declaration, path) end
    return Slice.Constant(source, declaration, path)
end

-- A run of declarations a harness needs together, each cut at its own
-- structural boundary and joined in the order given. This replaces "slice from
-- the first one to whatever is declared after the last one": the run is stated
-- here instead of being whatever the shipped file happens to hold in between.
function Slice.Declarations(source, declarations, path)
    local parts = {}
    for index = 1, #declarations do
        parts[index] = Slice.Declaration(source, declarations[index], path)
    end
    -- Trailing newline: callers concatenate this straight onto a harness
    -- preamble or epilogue, and a slice that ends on `end` would glue.
    return table.concat(parts, "\n") .. "\n"
end

-- A slice that is not a function, a table or a constant: an export block, a
-- run of statements. Both markers are required, and a miss names the file and
-- the marker. Prefer the kinds above; this one has no structural boundary.
function Slice.Block(source, startMarker, endMarker, path)
    local first = source:find(startMarker, 1, true)
    if first == nil then
        Fail("no start marker `" .. startMarker .. "` in " .. tostring(path))
    end
    local last = source:find(endMarker, first + #startMarker, true)
    if last == nil then
        Fail("no end marker `" .. endMarker .. "` after `" .. startMarker .. "` in " .. tostring(path))
    end
    return source:sub(first, last - 1)
end

return Slice
