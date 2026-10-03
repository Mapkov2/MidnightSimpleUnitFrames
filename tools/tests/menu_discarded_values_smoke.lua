-- menu_discarded_values_smoke.lua <repoRoot>
--
-- A `local` declaration with more values than names drops the extra values
-- without a word from the compiler. The guard-removal pass of the Retail
-- port (da36c0a5) left one such line in the history castbar fallback
-- (re-review R7, P3):
--     local did = true, _G.MSUF_UpdateCastbarVisuals()
--         _G.MSUF_UpdateBossCastbarPreview()
--     did = true
-- The original asked both castbar owners and returned whether one ran. This
-- smoke pins two things:
--   1. no Lua file of the Options addon declares more values than names on
--      one line (strings and comments are blanked first, so their text never
--      counts, and a line whose expression continues on the next line or holds
--      a function body is skipped);
--   2. the history castbar fallback, reached when neither ApplyService nor the
--      general apply is published, calls both castbar owners once and reports
--      that it applied.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local OPTIONS = "MidnightSimpleUnitFrames_Options"

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Read(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

-- Blank the contents of strings and comments, keep the line breaks.
local function Blank(source)
    local out, i, n = {}, 1, #source
    local function Keep(text) out[#out + 1] = text end
    local function Mask(text) Keep((text:gsub("[^\n]", " "))) end
    while i <= n do
        local c = source:sub(i, i)
        local long = source:match("^%[(=*)%[", i)
        if source:sub(i, i + 1) == "--" then
            local level = source:match("^%-%-%[(=*)%[", i)
            local stop
            if level then
                local _, close = source:find("]" .. level .. "]", i, true)
                stop = close or n
            else
                stop = (source:find("\n", i, true) or (n + 1)) - 1
            end
            Mask(source:sub(i, stop))
            i = stop + 1
        elseif long then
            local _, close = source:find("]" .. long .. "]", i, true)
            close = close or n
            Keep('"'); Mask(source:sub(i + 1, close - 1)); Keep('"')
            i = close + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n do
                local d = source:sub(j, j)
                if d == "\\" then j = j + 2
                elseif d == c or d == "\n" then break
                else j = j + 1 end
            end
            Keep(c); Mask(source:sub(i + 1, j - 1)); Keep(c)
            i = j + 1
        else
            Keep(c)
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Top-level comma count of a one-line expression list, or nil when the list
-- continues on the next line or holds a function body.
local function ExpressionCount(rhs)
    if rhs:find("%f[%w_]function%f[^%w_]") then return nil end
    local depth, count = 0, 1
    for k = 1, #rhs do
        local c = rhs:sub(k, k)
        if c == "(" or c == "{" or c == "[" then depth = depth + 1
        elseif c == ")" or c == "}" or c == "]" then depth = depth - 1
        elseif c == "," and depth == 0 then count = count + 1 end
    end
    if depth ~= 0 then return nil end
    local tail = rhs:gsub("%s+$", "")
    if tail == "" or tail:find("[,%+%-%*/%^%%<>=~%.]$") or tail:find("%f[%w_]and$")
        or tail:find("%f[%w_]or$") or tail:find("%f[%w_]not$") then return nil end
    return count
end

local function Files()
    local list = {}
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- "' .. OPTIONS .. '/*.lua"'))
    for line in pipe:lines() do list[#list + 1] = line end
    pipe:close()
    return list
end

local files = Files()
Check(#files > 100, "the Options addon lists only " .. #files .. " Lua files")
local scanned = 0
for _, path in ipairs(files) do
    local lineNo = 0
    for line in (Blank(Read(path)) .. "\n"):gmatch("([^\n]*)\n") do
        lineNo = lineNo + 1
        local names, rhs = line:match("^%s*local%s+([%a_][%w_]*[%w_%s,]*)=%s*(.-)%s*$")
        if names and not line:find("^%s*local%s+function") and not rhs:find("^=") then
            local _, commas = names:gsub(",", "")
            local values = ExpressionCount(rhs)
            if values and values > commas + 1 then
                Check(false, path .. ":" .. lineNo .. ": local declares " .. (commas + 1) .. " name(s) but "
                    .. values .. " values; the extra values are dropped")
            end
        end
    end
    scanned = scanned + 1
end

-- 2. The history castbar fallback calls both castbar owners.
do
    local source = Read(OPTIONS .. "/Shell/Menu2/MSUF_Menu2_Bindings_History.lua")
    local body = source:match("\n(local function ApplyScopedFeatureRuntime%(.-\nend)\n")
    if Check(body, "ApplyScopedFeatureRuntime is gone from the history bindings; update this smoke") then
        local castbar = body:match('if kind == "castbar" then\n(.-)\n    end\n')
        if Check(castbar, "the castbar branch of ApplyScopedFeatureRuntime is gone; update this smoke") then
            local calls = {}
            local env = setmetatable({
                ApplyService = {},
                M = {},
                _G = {
                    MSUF_UpdateCastbarVisuals = function() calls[#calls + 1] = "visuals" end,
                    MSUF_UpdateBossCastbarPreview = function() calls[#calls + 1] = "boss" end,
                },
            }, { __index = _G })
            local chunk = assert(loadstring("return function(kind, reason)\n" .. castbar .. "\nend", "=castbar-fallback"))
            setfenv(chunk, env)
            local applied = chunk()("castbar", "smoke")
            Check(applied == true, "the castbar fallback returned " .. tostring(applied) .. ", not true")
            Check(table.concat(calls, ",") == "visuals,boss",
                "the castbar fallback called " .. table.concat(calls, ",") .. ", not visuals,boss")
            Check(not castbar:find("\ndid = true", 1, true) and not castbar:find("= true, _G.", 1, true),
                "the castbar fallback still carries the mangled guard-removal lines")
        end
    end
end

if #failures > 0 then
    error("menu_discarded_values_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("menu_discarded_values_smoke: ok (" .. scanned .. " Options files; history castbar fallback asks both owners)")
