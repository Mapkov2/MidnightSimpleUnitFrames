-- A translated language pack must keep MSUF's slash commands typeable (review
-- F19). Machine translation turned "/msuf tour" into "/msuf 游览" and
-- "Visita /msuf", "/msuf reset" into "restablecer /msuf" and "/msuf locale"
-- into "comando local /msuf": a player who types what the text says lands in
-- the menu search instead of the command. Every "/msuf <word>" in an English
-- key whose word the slash handler answers to must appear unchanged in the
-- translation, as must argument choices such as on|off|status, and a help
-- line keeps its aligned command column.
-- Usage: lua tools/tests/locale_slash_tokens_smoke.lua <repoRoot>
local repo = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local PACKS = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }

local function Read(path)
    local file = assert(io.open(repo .. "/" .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end

-- The words /msuf answers to: registered command names and aliases, and the
-- menu page aliases its fallback opens.
local WORDS = {}
for _, path in ipairs({
    "MidnightSimpleUnitFrames/Runtime/MSUF_SlashCommands.lua",
    "MidnightSimpleUnitFrames/Kernel/MSUF_OptionsLoader.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_API.lua",
}) do
    local source = Read(path)
    for word in source:gmatch("\n%s*name = \"([%l%d]+)\"") do WORDS[word] = true end
    for list in source:gmatch("\n%s*aliases = (%b{})") do
        for word in list:gmatch("\"([%l%d]+)\"") do WORDS[word] = true end
    end
end
local rows = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Navigation.lua"):match("M%.ALIASES = AliasRows %[%[\n(.-)%]%]")
assert(rows, "menu page aliases not found")
for keys in rows:gmatch("=([^\n]+)") do
    for word in keys:gmatch("[^|]+") do
        if word:match("^[%l%d]+$") then WORDS[word] = true end
    end
end
for _, word in ipairs({ "help", "reset", "fullreset", "tour", "locale", "firstload", "options" }) do
    assert(WORDS[word], "slash word missing from the source scan: " .. word)
end

local function Commands(key)
    local list = {}
    for word in key:gmatch("/msuf (%l[%l%d]*)") do
        if WORDS[word] then list[#list + 1] = "/msuf " .. word end
    end
    for word in key:gmatch("/msuf(%l[%l%d]*)") do list[#list + 1] = "/msuf" .. word end
    return list
end

local function Contains(text, command)
    local init = 1
    while true do
        local first, last = text:find(command, init, true)
        if not first then return false end
        if not text:sub(last + 1, last + 1):match("[%w_]") then return true end
        init = last + 1
    end
end

local failures, checked = {}, 0
for _, pack in ipairs(PACKS) do
    local store = {}
    local L = setmetatable({}, { __index = store, __newindex = function(_, key, value) store[key] = value end })
    local namespace = { L = L, LOCALE = pack }
    namespace.RegisterLocale = function() return L end
    namespace.RegisterLocaleLoader = function(_, loader) loader() end
    local previousNS, previousMSUF = _G.MSUF_NS, _G.MSUF
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Locales/" .. pack .. ".lua"))("MidnightSimpleUnitFrames", namespace)
    _G.MSUF_NS, _G.MSUF = previousNS, previousMSUF
    for key, value in pairs(store) do
        if type(key) == "string" and type(value) == "string" and key:find("/msuf", 1, true) then
            checked = checked + 1
            for _, command in ipairs(Commands(key)) do
                if not Contains(value, command) then
                    failures[#failures + 1] = string.format("%s: %q lost %q: %q", pack, key, command, value)
                end
            end
            -- Argument choices such as fresh|upgrade|status are typed as well.
            local plain = key:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for choices in plain:gmatch("%l+|[%l|]*%l") do
                if not value:find(choices, 1, true) then
                    failures[#failures + 1] = string.format("%s: %q lost the choices %q: %q", pack, key, choices, value)
                end
            end
            local column = key:match("^(%s+/msuf.- %- )")
            if column and value:sub(1, #column) ~= column then
                failures[#failures + 1] = string.format("%s: help line %q lost its command column: %q", pack, key, value)
            end
        end
    end
end
table.sort(failures)
if #failures > 0 then error("locale_slash_tokens_smoke:\n  " .. table.concat(failures, "\n  "), 0) end
print("locale_slash_tokens_smoke: OK (" .. checked .. " translated lines with /msuf)")
