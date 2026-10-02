-- Secret unit answers in the aura files that load on Retail and WoW Forever are
-- assigned first and tested only after issecretvalue says they are plain.
--
-- 12.x returns these APIs' results as secret values for a restricted unit
-- (Blizzard_APIDocumentationGenerated/UnitDocumentation.lua, upstream/live and
-- upstream/forever): UnitPhaseReason, UnitGUID and UnitClass are
-- SecretWhenUnitIdentityRestricted, UnitIsUnit is
-- SecretWhenUnitComparisonRestricted and UnitInRange has SecretReturns.
-- Truth-testing or comparing a secret value raises in game, so a call whose
-- result feeds `and`, `or`, `not`, `if`, `then` or a comparison directly is
-- the bug class this smoke fails on. The Classic clients document none of
-- these as secret, so Game/Classic is out of scope.
-- Re-review 2026-10-02: Runtime_Presence.lua read
-- `type(f) == "function" and UnitPhaseReason(unit) or nil`, whose `or`
-- truth-tests the possibly secret reason before issecretvalue runs.
-- Argument: the repository root.
local root = assert(arg[1], "repository root argument missing")
root = (tostring(root):gsub("\\", "/"):gsub("/+$", ""))

local SECRET_APIS = { "UnitPhaseReason", "UnitGUID", "UnitClass", "UnitIsUnit", "UnitInRange" }
local KEYWORD_AFTER = { ["or"] = true, ["and"] = true, ["then"] = true, ["do"] = true }
local KEYWORD_BEFORE = { ["not"] = true, ["if"] = true, ["elseif"] = true, ["while"] = true,
    ["and"] = false, ["or"] = false }

local function Read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"))
end

--- Blanks comments and string contents so a match is always code.
local function CodeOnly(source)
    local out, i, n = {}, 1, #source
    while i <= n do
        local nextSpecial = source:find("[%-\"']", i)
        if not nextSpecial then
            out[#out + 1] = source:sub(i)
            break
        end
        if nextSpecial > i then
            out[#out + 1] = source:sub(i, nextSpecial - 1)
            i = nextSpecial
        end
        local c = source:sub(i, i)
        if c == "-" and source:sub(i + 1, i + 1) == "-" then
            local eq = source:match("^%[(=*)%[", i + 2)
            local stop
            if eq then
                local _, close = source:find("]" .. eq .. "]", i + 4 + #eq, true)
                stop = close or n
            else
                stop = (source:find("\n", i, true) or (n + 1)) - 1
            end
            out[#out + 1] = source:sub(i, stop):gsub("[^\n]", " ")
            i = stop + 1
        elseif c == '"' or c == "'" then
            local stopSet = c == '"' and '[\\\n"]' or "[\\\n']"
            local j = i + 1
            while j <= n do
                j = source:find(stopSet, j) or (n + 1)
                if source:sub(j, j) ~= "\\" then break end
                j = j + 2
            end
            out[#out + 1] = c .. string.rep(" ", math.max(0, j - i - 1)) .. c
            i = j + 1
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return table.concat(out)
end

--- The 1-based line number and the trimmed source text of a position.
local function LineAt(source, position)
    local _, count = source:sub(1, position):gsub("\n", "")
    local lineStart = 1
    for _ = 1, count do lineStart = source:find("\n", lineStart, true) + 1 end
    return count + 1, (source:match("[^\n]*", lineStart):gsub("^%s+", ""))
end

--- Returns "file:line: text" for every call of a secret API (or a local alias
--- of one) whose result is truth-tested or compared directly.
local function Violations(path, source)
    local mentions = false
    for i = 1, #SECRET_APIS do
        if source:find(SECRET_APIS[i], 1, true) then mentions = true break end
    end
    if not mentions then return {} end
    local code = CodeOnly(source)
    local names = {}
    for i = 1, #SECRET_APIS do
        local api = SECRET_APIS[i]
        names[api] = api
        names["_G." .. api] = api
    end
    -- local x = _G.Api / local x = Api, including multiple assignment.
    for lhs, rhs in code:gmatch("local[ \t]+([%w_, \t]-)[ \t]*=[ \t]*([^\n]+)") do
        local left, right = {}, {}
        for name in lhs:gmatch("[%w_]+") do left[#left + 1] = name end
        for expr in rhs:gmatch("[^,]+") do right[#right + 1] = (expr:gsub("^%s+", ""):gsub("%s+$", "")) end
        for i = 1, #left do
            local expr = right[i] and right[i]:gsub("^_G%.", "")
            for j = 1, #SECRET_APIS do
                if expr == SECRET_APIS[j] then names[left[i]] = SECRET_APIS[j] end
            end
        end
    end
    local found = {}
    for name, api in pairs(names) do
        local pattern = "%f[%w_%.]" .. name:gsub("%.", "%%.") .. "%s*%b()"
        local start = 1
        while true do
            local s, e = code:find(pattern, start)
            if not s then break end
            start = e + 1
            local tail = code:sub(e + 1, e + 40)
            local after = tail:match("^%s*([%a_]+)") or ""
            local afterOp = tail:match("^%s*([=~<>]=?)") or ""
            local window = code:sub(math.max(1, s - 40), s - 1)
            local before = window:match("([%a_]+)%s*$") or ""
            local beforeOp = window:match("([=~<>]=?)%s*$") or ""
            if KEYWORD_AFTER[after] or KEYWORD_BEFORE[before] == true
                or afterOp == "==" or afterOp == "~=" or afterOp == "<" or afterOp == ">"
                or afterOp == "<=" or afterOp == ">="
                or beforeOp == "==" or beforeOp == "~=" then
                local line, text = LineAt(source, s)
                found[#found + 1] = path .. ":" .. line .. ": " .. api .. " result tested before issecretvalue: " .. text
            end
        end
    end
    table.sort(found)
    return found
end

-- The lint finds the shape it exists for, and accepts assign-then-guard.
do
    local planted = Violations("planted.lua", table.concat({
        "local unitPhaseReason = _G.UnitPhaseReason",
        "local reason = type(unitPhaseReason) == \"function\" and unitPhaseReason(unit) or nil",
        "local a, guidOf = 1, UnitGUID",
        "if guidOf(unit) == old then end",
        "if not UnitIsUnit(\"player\", unit) then end",
    }, "\n"))
    assert(#planted == 3, "the lint missed a planted secret truth test (" .. #planted .. " of 3)")
    local clean = Violations("clean.lua", table.concat({
        "local unitPhaseReason = _G.UnitPhaseReason",
        "local reason = nil",
        "if type(unitPhaseReason) == \"function\" then reason = unitPhaseReason(unit) end",
        "-- UnitGUID(unit) or nil in a comment",
        "local text = \"UnitGUID(unit) or nil\"",
        "if issecretvalue(reason) ~= true then state = reason ~= nil end",
    }, "\n"))
    assert(#clean == 0, "the lint flagged assign-then-guard code: " .. tostring(clean[1]))
end

local function ListLua(directory)
    local files = {}
    local command = 'git -C "' .. root .. '" ls-files -- "' .. directory .. '"'
    local pipe = assert(io.popen(command), "git ls-files failed")
    for line in pipe:lines() do
        if line:match("%.lua$") then files[#files + 1] = line end
    end
    pipe:close()
    return files
end

local files = {}
for _, directory in ipairs({ "MidnightSimpleUnitFrames/Auras3", "MidnightSimpleUnitFrames/Game/Forever/Auras" }) do
    for _, path in ipairs(ListLua(directory)) do files[#files + 1] = path end
end
assert(#files > 40, "the aura file list is incomplete (" .. #files .. " files)")
local all = {}
for i = 1, #files do
    local found = Violations(files[i], Read(root .. "/" .. files[i]))
    for j = 1, #found do all[#all + 1] = found[j] end
end
if #all > 0 then
    error("secret unit answers truth-tested before issecretvalue:\n  " .. table.concat(all, "\n  "), 0)
end
print("aura secret truth-test smoke: OK (" .. #files .. " files)")
