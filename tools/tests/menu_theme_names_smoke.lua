-- menu_theme_names_smoke.lua <repoRoot>
--
-- Review R7 P3: the menu read theme and UI kit fields that nothing ever set,
-- so the branch behind each read was silently dead: T.headingFont (a heading
-- font override no theme provides), T.reduceMotion / T.reducedMotion (a theme
-- motion override; the setting lives in general.reduceMotion) and
-- MSUF.UI.StyleCheckmark (read only by a preview helper without callers).
-- Every field the menu reads from the theme table T or the core UI kit
-- MSUF.UI must have a writer:
--   T:       `T.name = ...`, `function T.name` / `T:name`, or a name list of
--            M.AssignNamedValues(T, ...) or the keys of M.Assign(T, { ... }),
--            anywhere in the menu and shell files;
--   MSUF.UI: `UI.name = ...`, `function UI.name` or `MSUF.UI.name = ...` in
--            the UI kit files (Shell/UI, Kernel).
-- A table named T in another file counts as the theme; that reads stricter,
-- never looser. Comments are ignored.
--
-- Plain Lua 5.1 with the repo root as argument.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local function Files(patterns)
    local list = {}
    local pipe = assert(io.popen('git -C "' .. root .. '" ls-files -- ' .. patterns, "r"), "cannot list files")
    for path in pipe:lines() do list[#list + 1] = path end
    pipe:close()
    assert(#list > 0, "no files matched " .. patterns)
    return list
end
local function Source(path)
    local handle = assert(io.open(root .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    -- Drop long comments first, then line comments.
    return (text:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", ""))
end

local themeReads, themeWrites = {}, {}
local uiReads, uiWrites = {}, {}
local menuFiles = Files('"MidnightSimpleUnitFrames_Options/*.lua" "MidnightSimpleUnitFrames/Shell/*.lua"')
for _, path in ipairs(menuFiles) do
    local text = Source(path)
    for name, tail in text:gmatch("[^%w_%.]T%.([%a_][%w_]*)(%s*=?=?)") do
        if tail:match("^%s*=$") then
            themeWrites[name] = true
        else
            themeReads[name] = themeReads[name] or path
        end
    end
    for name in text:gmatch("function T[%.:]([%a_][%w_]*)") do themeWrites[name] = true end
    for names in text:gmatch('AssignNamedValues%(T,%s*"([^"]*)"') do
        for name in names:gmatch("%S+") do themeWrites[name] = true end
    end
    for names in text:gmatch("AssignNamedValues%(T,%s*%[%[(.-)%]%]") do
        for name in names:gmatch("%S+") do themeWrites[name] = true end
    end
    -- M.Assign(T, { Name = value, ... }) writes each key of its table.
    for block in text:gmatch("Assign%(T,%s*(%b{})") do
        for name in block:gmatch("([%a_][%w_]*)%s*=[^=]") do themeWrites[name] = true end
    end
end
for _, path in ipairs(Files('"MidnightSimpleUnitFrames_Options/*.lua" "MidnightSimpleUnitFrames/*.lua"')) do
    local text = Source(path)
    for name in text:gmatch("MSUF%.UI%.([%a_][%w_]*)") do uiReads[name] = uiReads[name] or path end
    if path:find("/Shell/UI/", 1, true) or path:find("/Kernel/", 1, true) then
        for name in text:gmatch("[^%w_%.]UI%.([%a_][%w_]*)%s*=[^=]") do uiWrites[name] = true end
        for name in text:gmatch("function UI[%.:]([%a_][%w_]*)") do uiWrites[name] = true end
        for name in text:gmatch("MSUF%.UI%.([%a_][%w_]*)%s*=[^=]") do uiWrites[name] = true end
    end
end

local missing = {}
for name, path in pairs(themeReads) do
    if not themeWrites[name] then missing[#missing + 1] = "T." .. name .. " (read in " .. path .. ")" end
end
for name, path in pairs(uiReads) do
    if not uiWrites[name] then missing[#missing + 1] = "MSUF.UI." .. name .. " (read in " .. path .. ")" end
end
table.sort(missing)
local themeCount, uiCount = 0, 0
for _ in pairs(themeReads) do themeCount = themeCount + 1 end
for _ in pairs(uiReads) do uiCount = uiCount + 1 end
assert(themeCount > 80, "only " .. themeCount .. " theme fields read; the scan lost its files")
assert(#missing == 0, #missing .. " menu field(s) read but set nowhere:\n  " .. table.concat(missing, "\n  "))
print(string.format("menu_theme_names_smoke: ok (%d theme and %d UI kit fields read, all set somewhere; %d files)",
    themeCount, uiCount, #menuFiles))
