-- global_links_smoke.lua <repoRoot> [--list]
--
-- MSUF publishes most cross-file API as _G.MSUF_* globals that call sites
-- resolve late. A guard such as `if type(_G.MSUF_X) == "function" then` cannot
-- tell an optional collaborator from a provider that was renamed or deleted:
-- both do nothing, silently. The 2026-10-01 review found at least nine guarded
-- names that no file defines, each a feature that quietly stopped working.
--
-- This smoke reads every tracked Lua and XML file of the three addons
-- (core, Options, Assistant) and collects:
--   reads        _G.MSUF_X, _G["MSUF_X"], rawget(_G, "MSUF_X"),
--                type(MSUF_X) on a bare global, MSUF.Require/Optional("MSUF_X")
--   definitions  _G.MSUF_X = / _G["MSUF_X"] = / rawset(_G, "MSUF_X", ...),
--                a global `MSUF_X =` or `function MSUF_X(`, an export call
--                ("MSUF_X" as the first argument of an *Export*/*Publish*
--                function that publishes a global), a named frame
--                (CreateFrame(..., "MSUF_X") or an XML name="MSUF_X"), and the
--                TOC SavedVariables.
-- A name that is read but defined nowhere is a dead link. It fails the smoke
-- unless tools/global-links-ledger.tsv records it with its owner and reason;
-- a ledger row whose name is no longer a dead link fails too, so the ledger
-- only shrinks. Pass --list to print every dead link with its read sites.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local listMode = arg[2] == "--list"

local ADDONS = { "MidnightSimpleUnitFrames", "MidnightSimpleUnitFrames_Options", "MidnightSimpleUnitFrames_Assistant" }
local PREFIX = "^MSUF_"

local function ReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

---------------------------------------------------------------------------
-- Tokenizer (Lua 5.1 lexical grammar; comments dropped, strings kept)
---------------------------------------------------------------------------
local function Tokenize(src)
    local tokens, n = {}, 0
    local i, len, line = 1, #src, 1
    local function push(kind, value)
        n = n + 1
        tokens[n] = { kind = kind, value = value, line = line }
    end
    local function longBracket(at)
        local eq = src:match("^%[(=*)%[", at)
        if not eq then return nil end
        local close = "]" .. eq .. "]"
        local s = at + #eq + 2
        local e = src:find(close, s, true)
        if not e then e = len + 1 end
        return s, e - 1, e + #close
    end
    while i <= len do
        local c = src:sub(i, i)
        if c == "\n" then
            line = line + 1
            i = i + 1
        elseif c:match("%s") then
            i = i + 1
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            local s, e, nextAt = longBracket(i + 2)
            if s then
                local body = src:sub(i, nextAt - 1)
                for _ in body:gmatch("\n") do line = line + 1 end
                i = nextAt
            else
                local stop = src:find("\n", i, true) or (len + 1)
                i = stop
            end
        elseif c == "[" and src:match("^%[=*%[", i) then
            local s, e, nextAt = longBracket(i)
            local body = src:sub(s, e)
            push("string", body)
            for _ in src:sub(i, nextAt - 1):gmatch("\n") do line = line + 1 end
            i = nextAt
        elseif c == '"' or c == "'" then
            local j = i + 1
            local buf = {}
            while j <= len do
                local d = src:sub(j, j)
                if d == "\\" then
                    buf[#buf + 1] = src:sub(j, j + 1)
                    if src:sub(j + 1, j + 1) == "\n" then line = line + 1 end
                    j = j + 2
                elseif d == c then
                    break
                elseif d == "\n" then
                    break
                else
                    buf[#buf + 1] = d
                    j = j + 1
                end
            end
            push("string", table.concat(buf))
            i = j + 1
        elseif c:match("[%a_]") then
            local word = src:match("^[%w_]+", i)
            push("name", word)
            i = i + #word
        elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
            local num = src:match("^0[xX]%x+", i) or src:match("^%d*%.?%d*[eE][%+%-]?%d+", i) or src:match("^%d*%.?%d*", i)
            push("number", num)
            i = i + math.max(#num, 1)
        else
            local three = src:sub(i, i + 2)
            local two = src:sub(i, i + 1)
            if three == "..." then
                push("op", three); i = i + 3
            elseif two == "==" or two == "~=" or two == "<=" or two == ">=" or two == ".." or two == "::" then
                push("op", two); i = i + 2
            else
                push("op", c); i = i + 1
            end
        end
    end
    return tokens, n
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------
local reads = {}        -- name -> { "file:line", ... }
local defined = {}      -- name -> "file:line"
local function AddRead(name, where)
    if not name:match(PREFIX) then return end
    local list = reads[name]
    if not list then list = {}; reads[name] = list end
    list[#list + 1] = where
end
local function AddDef(name, where)
    if not name:match(PREFIX) then return end
    defined[name] = defined[name] or where
end

local function IsExportCall(name)
    return name:find("Export", 1, true) or name:find("Publish", 1, true)
end

-- Index of the closing parenthesis of the call whose "(" is at open, and the
-- start of every top-level argument.
local function CallArgs(tokens, open, n)
    local depth, args = 0, { open + 1 }
    for k = open, n do
        local t = tokens[k]
        if t.kind == "op" then
            if t.value == "(" or t.value == "{" or t.value == "[" then depth = depth + 1
            elseif t.value == ")" or t.value == "}" or t.value == "]" then
                depth = depth - 1
                if depth == 0 then return k, args end
            elseif t.value == "," and depth == 1 then
                args[#args + 1] = k + 1
            end
        end
    end
    return n, args
end

local function ScanLua(relative, src)
    local tokens, n = Tokenize(src)
    -- Locals: a name declared local anywhere in the file never counts as a
    -- global there (approximation: Lua scopes are not tracked).
    local locals = {}
    for k = 1, n do
        local t = tokens[k]
        if t.kind == "name" and t.value == "local" then
            local j = k + 1
            if tokens[j] and tokens[j].value == "function" then
                if tokens[j + 1] then locals[tokens[j + 1].value] = true end
            else
                while tokens[j] and tokens[j].kind == "name" do
                    locals[tokens[j].value] = true
                    if tokens[j + 1] and tokens[j + 1].value == "," then j = j + 2 else break end
                end
            end
        elseif t.kind == "name" and t.value == "function" then
            -- parameters
            local j = k + 1
            while tokens[j] and tokens[j].value ~= "(" and j < k + 8 do j = j + 1 end
            if tokens[j] and tokens[j].value == "(" then
                j = j + 1
                while tokens[j] and tokens[j].value ~= ")" do
                    if tokens[j].kind == "name" then locals[tokens[j].value] = true end
                    j = j + 1
                end
            end
        elseif t.kind == "name" and t.value == "for" then
            local j = k + 1
            while tokens[j] and tokens[j].kind == "name" and tokens[j].value ~= "in" do
                locals[tokens[j].value] = true
                if tokens[j + 1] and tokens[j + 1].value == "," then j = j + 2 else break end
            end
        end
    end
    -- Aliases of the global table: `local G = _G` (and `_G` itself).
    local globalTable = { _G = true }
    for k = 1, n - 3 do
        local t = tokens[k]
        if t.value == "local" and tokens[k + 1].kind == "name" and tokens[k + 2].value == "="
            and tokens[k + 3].value == "_G" and not (tokens[k + 4] and (tokens[k + 4].value == "." or tokens[k + 4].value == "[")) then
            globalTable[tokens[k + 1].value] = true
        end
    end
    local function where(t) return relative .. ":" .. t.line end
    for k = 1, n do
        local t = tokens[k]
        local nx, nx2, prev = tokens[k + 1], tokens[k + 2], tokens[k - 1]
        local isGlobalTable = t.kind == "name" and globalTable[t.value] and not (prev and (prev.value == "." or prev.value == ":"))
        if isGlobalTable and prev and prev.value == "function" and nx and nx.value == "." and nx2 and nx2.kind == "name" then
            AddDef(nx2.value, where(t))
        elseif isGlobalTable and nx and nx.value == "." and nx2 and nx2.kind == "name" then
            local after = tokens[k + 3]
            if after and after.value == "=" then AddDef(nx2.value, where(t))
            else AddRead(nx2.value, where(t)) end
        elseif isGlobalTable and nx and nx.value == "[" and nx2 and nx2.kind == "string"
            and tokens[k + 3] and tokens[k + 3].value == "]" then
            local after = tokens[k + 4]
            if after and after.value == "=" then AddDef(nx2.value, where(t))
            else AddRead(nx2.value, where(t)) end
        elseif t.kind == "name" and (t.value == "rawget" or t.value == "rawset") and nx and nx.value == "("
            and nx2 and globalTable[nx2.value] and tokens[k + 3] and tokens[k + 3].value == ","
            and tokens[k + 4] and tokens[k + 4].kind == "string" then
            if t.value == "rawset" then AddDef(tokens[k + 4].value, where(t)) else AddRead(tokens[k + 4].value, where(t)) end
        elseif t.kind == "name" and t.value == "type" and nx and nx.value == "(" and nx2 and nx2.kind == "name"
            and tokens[k + 3] and tokens[k + 3].value == ")" and not locals[nx2.value]
            and not (prev and (prev.value == "." or prev.value == ":")) then
            AddRead(nx2.value, where(t))
        elseif t.kind == "name" and (t.value == "Require" or t.value == "Optional") and prev and prev.value == "."
            and nx and nx.value == "(" and nx2 and nx2.kind == "string" then
            AddRead(nx2.value, where(t))
        elseif t.kind == "name" and t.value == "function" and nx and nx.kind == "name" and nx.value:match(PREFIX)
            and nx2 and nx2.value == "(" and not (prev and prev.value == "local") then
            AddDef(nx.value, where(t))
        elseif t.kind == "name" and t.value:match(PREFIX) and nx and nx.value == "=" and not locals[t.value]
            and not (prev and (prev.value == "." or prev.value == ":" or prev.value == "local" or prev.value == ",")) then
            AddDef(t.value, where(t))
        elseif t.kind == "name" and IsExportCall(t.value) and nx and nx.value == "(" and nx2 and nx2.kind == "string" then
            local close, args = CallArgs(tokens, k + 1, n)
            -- ExportPublic(name, value, false) records the API without a global.
            local third = args[3] and tokens[args[3]]
            local noGlobal = third and third.value == "false" and (args[3] + 1 == close)
            if not noGlobal then AddDef(nx2.value, where(t)) end
        elseif t.kind == "name" and t.value == "CreateFrame" and nx and nx.value == "(" then
            local close, args = CallArgs(tokens, k + 1, n)
            local second = args[2] and tokens[args[2]]
            if second and second.kind == "string" and args[2] + 1 <= close then AddDef(second.value, where(t)) end
        end
    end
end

local function ScanXML(relative, src)
    local line = 1
    for chunk in (src .. "\n"):gmatch("([^\n]*)\n") do
        for name in chunk:gmatch('[%s<]name%s*=%s*"([%w_]+)"') do AddDef(name, relative .. ":" .. line) end
        line = line + 1
    end
end

local function ScanTOC(relative, src)
    for list in src:gmatch("##%s*SavedVariables[%w]*:%s*([^\n]+)") do
        for name in list:gmatch("[%w_]+") do AddDef(name, relative) end
    end
end

local command = 'git -C "' .. root .. '" ls-files -- ' .. table.concat(ADDONS, " ")
local pipe = assert(io.popen(command, "r"), "cannot enumerate tracked addon files")
local scanned = 0
for relative in pipe:lines() do
    relative = relative:gsub("\\", "/")
    local lower = relative:lower()
    if lower:match("%.lua$") or lower:match("%.xml$") or lower:match("%.toc$") then
        local src = ReadFile(root .. "/" .. relative)
        if src then
            if lower:match("%.lua$") then ScanLua(relative, src)
            elseif lower:match("%.xml$") then ScanXML(relative, src)
            else ScanTOC(relative, src) end
            scanned = scanned + 1
        end
    end
end
local pipeOk, _, pipeCode = pipe:close()
assert(pipeOk or pipeCode == 0, "git ls-files failed: " .. tostring(pipeCode))
assert(scanned >= 400, "only " .. scanned .. " addon files were scanned; git ls-files likely failed")

---------------------------------------------------------------------------
-- Ledger
---------------------------------------------------------------------------
-- Name<TAB>Kind<TAB>Owner<TAB>Evidence<TAB>Reason, one row per name that is
-- read but has no static definition:
--   dynamic   defined at run time in a way this scan cannot see (a name built
--             from a list or a concatenation, a flag written through _G[key]).
--             Evidence is "path::literal": the tracked file must still contain
--             the literal, so deleting the provider turns the row red.
--   external  provided by another addon on purpose (Evidence "-").
--   dead      a real dead link that its owning package still has to fix
--             (Evidence "-"). Rows only ever leave this list.
local ledgerPath = root .. "/tools/global-links-ledger.tsv"
local ledger, ledgerOrder = {}, {}
local ledgerText = ReadFile(ledgerPath) or ""
local lineNo = 0
local KINDS = { dynamic = true, external = true, dead = true }
for row in (ledgerText .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    if row ~= "" and not row:match("^#") and not row:match("^Name\t") then
        local name, kind, owner, evidence, reason = row:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$")
        assert(name and reason ~= "", "global-links-ledger.tsv:" .. lineNo .. ": expected Name, Kind, Owner, Evidence, Reason")
        assert(KINDS[kind], "global-links-ledger.tsv:" .. lineNo .. ": unknown kind " .. tostring(kind))
        assert(not ledger[name], "global-links-ledger.tsv: duplicate row for " .. name)
        ledger[name] = { kind = kind, owner = owner, evidence = evidence, reason = reason, line = lineNo }
        ledgerOrder[#ledgerOrder + 1] = name
    end
end

local dead = {}
for name in pairs(reads) do
    if not defined[name] then dead[#dead + 1] = name end
end
table.sort(dead)

if listMode then
    for _, name in ipairs(dead) do
        local sites = reads[name]
        print(name .. "\t" .. #sites .. "\t" .. table.concat(sites, " "))
    end
    print(("%d files scanned, %d names read, %d dead links"):format(scanned, (function()
        local c = 0; for _ in pairs(reads) do c = c + 1 end; return c end)(), #dead))
    return
end

local problems = {}
for _, name in ipairs(dead) do
    if not ledger[name] then
        problems[#problems + 1] = ("%s is read but defined nowhere: %s"):format(name, table.concat(reads[name], ", "))
    end
end
for _, name in ipairs(ledgerOrder) do
    local row = ledger[name]
    if reads[name] == nil or defined[name] then
        problems[#problems + 1] = ("ledger row %s is no dead link any more (%s); drop the row"):format(name,
            reads[name] == nil and "nothing reads it" or ("defined at " .. defined[name]))
    elseif row.kind == "dynamic" then
        local path, literal = row.evidence:match("^(.-)::(.+)$")
        local text = path and ReadFile(root .. "/" .. path)
        if not (text and text:find(literal, 1, true)) then
            problems[#problems + 1] = ("ledger row %s (dynamic): the evidence %s no longer holds; is the provider gone?"):format(
                name, row.evidence)
        end
    elseif row.evidence ~= "-" then
        problems[#problems + 1] = ("ledger row %s (%s) must use evidence \"-\""):format(name, row.kind)
    end
end
if #problems > 0 then
    error("global_links_smoke: " .. #problems .. " problem(s):\n  " .. table.concat(problems, "\n  "), 0)
end
local counts = { dynamic = 0, external = 0, dead = 0 }
for _, name in ipairs(dead) do counts[ledger[name].kind] = counts[ledger[name].kind] + 1 end
print(("global_links_smoke: ok (%d files; %d unresolved names: %d dynamic, %d external, %d dead links owned by other packages)"):format(
    scanned, #dead, counts.dynamic, counts.external, counts.dead))
