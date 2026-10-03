-- engine_chat_locale_smoke.lua <repoRoot>
--
-- Chat lines, key binding labels, the unit info tooltip and the status text of
-- the engine and state files are translated: the sentence goes through the
-- language pack first and is formatted after, never concatenated first.
--
--   1. Source: no print()/AddMessage() line in Kernel/, State/, Runtime/,
--      UnitFrames/ (engine), Features/, Integrations/ or Libs/MSUFUnitFrames
--      carries an English sentence outside a translate call, except the
--      developer diagnostics listed in DIAGNOSTICS (English on purpose, each
--      row must still match a line). The tooltip and status words are wrapped.
--   2. A German client: profile commands, the key binding labels and the
--      tooltip/status words come out of the German pack, and every fixed
--      import failure reason prints one translated full sentence.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Check(condition, message)
    if not condition then error(message, 2) end
end

-- Developer diagnostics: printed in English on purpose (bug reports, profiler
-- notes). Path, a literal the line carries, and why.
local DIAGNOSTICS = {
    { "Features/Diagnostics/", nil, "developer probes (/msufgp, /msufdbgpos, the aura layer probe)" },
    { "Runtime/MSUF_SlashCommands.lua", "keyboard diagnostics", "/msuf input: stuck-keybind report" },
    { "Runtime/MSUF_SlashCommands.lua", "Bindings: W=", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", "Keyboard focus: ", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", "MSUF edit: active=", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", "EnumerateFrames unavailable.", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", "%02d %s shown=%s", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", "No shown keyboard-enabled frames found.", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", " more keyboard-enabled frames hidden.", "/msuf input" },
    { "Runtime/MSUF_SlashCommands.lua", "client info", "/msuf clientinfo: English bug-report facts by design" },
    { "Runtime/MSUF_SlashCommands.lua", "  /msuf fullreset", "a command to type, not a sentence" },
    { "Runtime/MSUF_SlashCommands.lua", "Group-frame hover debug is", "/msuf gfhoverdebug status line" },
    { "Features/Versioning/MSUF_VersionCheck.lua", "could not read own version", "/msuf versiontest debug hook" },
}

local DIRS = { "Kernel", "State", "Runtime", "UnitFrames/Engine", "UnitFrames/Effects", "UnitFrames/Range",
    "Features", "Integrations", "Libs/MSUFUnitFrames" }

local function Files()
    local list = {}
    for _, path in ipairs(World.Graph(root, World.CoreTOC("Mainline"), "enUS")) do
        local relative = path:sub(#root + 2):gsub("^MidnightSimpleUnitFrames/", "")
        for _, dir in ipairs(DIRS) do
            if relative:sub(1, #dir + 1) == dir .. "/" and not relative:find("/Group/", 1, true) then
                list[#list + 1] = relative
            end
        end
    end
    return list
end

local function StripComments(text)
    text = text:gsub("%-%-%[(=*)%[.-%]%1%]", function(c) return (c:gsub("[^\n]", "")) end)
    return (text:gsub("%-%-[^\n]*", ""))
end

local used = {}
local function Allowed(file, line)
    for index, row in ipairs(DIAGNOSTICS) do
        local path, literal = row[1], row[2]
        if file:sub(1, #path) == path and (literal == nil or line:find(literal, 1, true)) then
            used[index] = true
            return true
        end
    end
    return false
end

-- 1. source
local TYPE_NAMES = { ["function"] = true, table = true, string = true, number = true, boolean = true }
local violations, scanned = {}, 0
for _, file in ipairs(Files()) do
    scanned = scanned + 1
    local text = StripComments(World.Read(root .. "/MidnightSimpleUnitFrames/" .. file))
    local number = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        number = number + 1
        if line:find("print%s*%(") or line:find("AddMessage%s*%(") then
            local bare = line:gsub("[Tt]ranslate%s*%(%s*\"[^\"]*\"%s*%)", "T"):gsub("Tr%s*%(%s*\"[^\"]*\"%s*%)", "T")
            for literal in bare:gmatch("\"([^\"]*)\"") do
                local words = literal:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("MSUF:?", "")
                -- A sentence has a lower-case word; ON/OFF state tokens and type names do not count.
                if words:find("%l%l") and not TYPE_NAMES[literal] and not Allowed(file, line) then
                    violations[#violations + 1] = file .. ":" .. number .. ": " .. line:gsub("^%s+", "")
                    break
                end
            end
        end
    end
end
Check(#violations == 0, "untranslated chat lines:\n  " .. table.concat(violations, "\n  "))
for index, row in ipairs(DIAGNOSTICS) do
    Check(used[index], "diagnostics row matches no line any more, delete it: " .. row[1] .. " " .. tostring(row[2]))
end

local function Code(file) return StripComments(World.Read(root .. "/MidnightSimpleUnitFrames/" .. file)) end
local tooltip = Code("Runtime/MSUF_UnitTooltips.lua")
for _, raw in ipairs({ 'format("Level %d', '" <AFK>"', '" <DND>"', 'return "Elite"', 'return "Rare"',
    'return "Rare Elite"', 'return "Boss"', '"  PvP"', 'text = "PvP"' }) do
    Check(not tooltip:find(raw, 1, true), "Runtime/MSUF_UnitTooltips.lua still writes an English " .. raw)
end
Check(Code("UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"):find("SetText(fs, MSUF.Translate(text))", 1, true),
    "the status text (DEAD, GHOST, OFFLINE, AFK, DND) reaches its font string untranslated")
-- Chat wrappers whose call sites pass English sentences translate inside.
for _, file in ipairs({ "Runtime/MSUF_UIScaleRuntime.lua", "Features/Telemetry/MSUF_Analytics.lua" }) do
    local body = Code(file):match("local function Print%b()(.-)\nend")
    Check(body and body:find("MSUF.Translate(text)", 1, true), file .. ": its chat wrapper prints the English sentence")
end
local keybinds = Code("Kernel/MSUF_Keybinds.lua")
Check(not keybinds:find('BINDING_NAME_MSUF_TOGGLE_OPTIONS = "', 1, true)
    and not keybinds:find('BINDING_NAME_MSUF_TOGGLE_EDITMODE = "', 1, true),
    "Kernel/MSUF_Keybinds.lua assigns an English binding label")

-- 2. a German client
local world = World.New(root, "Mainline", { locale = "deDE" })
world:Boot()
local failure = world:FirstFailure()
Check(failure == nil, "deDE: load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
world:LoadSavedVariables("MidnightSimpleUnitFrames", {})
local env, ns = world.env, world.core
Check(ns.LOCALE == "deDE", "the German pack did not load: " .. tostring(ns.LOCALE))
local function De(key)
    local value = ns.Translate(key)
    Check(value ~= key, "deDE: no German text for " .. key)
    return value
end
local before = #world.prints
env.MSUF_SwitchProfile("Nirgendwo")
local line = world.prints[before + 1]
Check(line == "|cffff0000MSUF:|r " .. De("Unknown profile: %s"):format("Nirgendwo"),
    "deDE: an unknown profile prints " .. tostring(line))
-- A compact string that fails to decode: the whole sentence is translated
-- before the prefix goes in, so no English reason is left in the German line.
before = #world.prints
local imported, importWhy = env.MSUF_ImportFromString("MSUF4:@@@@")
line = world.prints[before + 1]
Check(imported == false and importWhy == "could not decode compact profile string (MSUF4)",
    "deDE: the compact decode failure did not reach its branch: " .. tostring(importWhy))
Check(line == "|cffff0000MSUF:|r "
    .. De("Import failed: could not decode compact profile string (%s)."):format("MSUF4"),
    "deDE: a failed compact import prints " .. tostring(line))
Check(not line:find("could not decode", 1, true), "deDE: the compact import line keeps English words: " .. line)

-- Every fixed import failure reason the chat path prints, driven in the German
-- client: the line is the translated full sentence (a frame key or a value
-- type goes in after), no English word of the sentence is left, and callers
-- still receive the English reason. Each sentence State/MSUF_Profiles.lua
-- lists must have a case here.
local profilesSource = World.Read(root .. "/MidnightSimpleUnitFrames/State/MSUF_Profiles.lua"):gsub("\r\n", "\n")
local listBody = assert(profilesSource:match("for _, sentence in ipairs%((%b{})%) do IMPORT_FAILED_SENTENCES"),
    "the import failure sentence list in State/MSUF_Profiles.lua moved")
local listed, driven = {}, {}
for sentence in listBody:gmatch('\n%s*"([^"\n]+)",') do listed[sentence] = true end
local fixture
local decode = env.MSUF_TryDecodeCompactString
env.MSUF_TryDecodeCompactString = function(str)
    if str == "fixture" then return fixture end
    if decode then return decode(str) end
end
local function Snapshot(kind, payload) return { addon = "MSUF", fmt = 2, schema = 600, kind = kind, payload = payload } end
local function Full(value) return { _msufProfileSchema = 600, general = {}, extra = value } end
local function Nested(depth)
    local value = {}
    for _ = 1, depth do value = { value } end
    return value
end
local many = {}
for index = 1, 125001 do many["k" .. index] = 1 end
local huge = string.rep("x", 32 * 1024 * 1024 + 1)
local function Fn() end
local shared = {}
local cyclic = {}
cyclic.self = cyclic
local colors = "{ addon = 'MSUF', fmt = 2, schema = 600, kind = 'colors', payload = {} }"
local function LiveBad(value)
    return function() env.MSUF_DB.msufSmokeBad = value end, function() env.MSUF_DB.msufSmokeBad = nil end
end
local function Unsupported(unit)
    local saved = ns.Client.SupportsUnit
    return function() ns.Client.SupportsUnit = function(key) return key ~= unit end end,
        function() ns.Client.SupportsUnit = saved end
end
local function ExternalFails()
    local saved = ns.ProfileFields.CaptureExternal
    return function() ns.ProfileFields.CaptureExternal = function() return false end end,
        function() ns.ProfileFields.CaptureExternal = saved end
end
local A, P = "Import failed: ", "Profile import failed: "
-- { sentence, import string or "fixture", decoded fixture, inserted text, setup, teardown }
local cases = {
    { A .. "could not decode compact profile string (%s).", "MSUF4:@@@@", nil, "MSUF4" },
    { A .. "profile import is too large", "{" .. string.rep(" ", 8 * 1024 * 1024) },
    { A .. "unterminated comment", "--[[ open" },
    { A .. "profile table has too many values", "{" .. string.rep("1,", 250000) .. "}" },
    { A .. "unterminated string", "{ 'open" },
    { A .. "unterminated escape", "{ 'open\\" },
    { A .. "invalid decimal escape", "{ '\\300' }" },
    { A .. "unsupported string escape", "{ '\\q' }" },
    { A .. "invalid number", "{ 1e999 }" },
    { A .. "profile table is too deep", string.rep("{", 70) },
    { A .. "unterminated table", "{ 1," },
    { A .. "unsupported table key", "{ [true] = 1 }" },
    { A .. "unsupported value", "{ x }" },
    { A .. "profile import must contain a table", "return 5" },
    { A .. "MSUF 6.x profile required (schema 600).", "{ _msufProfileSchema = 577 }" },
    { A .. "unknown kind", "{ addon = 'MSUF', fmt = 2, schema = 600, kind = 'bogus', payload = {} }" },
    { A .. "profile has too many values", "fixture", Snapshot("colors", many) },
    { P .. "profile has too many values", "fixture", Full(many) },
    { A .. "profile strings are too large", "fixture", Snapshot("colors", { text = huge }) },
    { P .. "profile strings are too large", "fixture", Full(huge) },
    { A .. "profile contains an invalid number", "fixture", Snapshot("colors", { value = 0 / 0 }) },
    { P .. "profile contains an invalid number", "fixture", Full(0 / 0) },
    { A .. "profile contains unsupported %s", "fixture", Snapshot("colors", { value = Fn }), "function" },
    { P .. "profile contains unsupported %s", "fixture", Full(Fn), "function" },
    { A .. "profile is too deep", "fixture", Snapshot("colors", Nested(70)) },
    { P .. "profile is too deep", "fixture", Full(Nested(70)) },
    { A .. "profile contains a cyclic or shared table", "fixture", Snapshot("colors", { a = shared, b = shared }) },
    { P .. "profile contains a cyclic or shared table", "fixture", Full({ a = shared, b = shared }) },
    { A .. "profile contains an unsupported table key", "fixture", Snapshot("colors", { [true] = 1 }) },
    { P .. "profile contains an unsupported table key", "fixture", Full({ [true] = 1 }) },
    { A .. "unsupported unitframe: %s.", "fixture", Snapshot("unitselection", { arena = {} }), "arena",
        Unsupported("arena") },
    { A .. "invalid unitframe: %s.", "fixture", Snapshot("unitselection", { player = 5 }), "player" },
    { A .. "unexpected selected-frame setting: %s.", "fixture",
        Snapshot("unitselection", { player = {}, bogus = {} }), "bogus" },
    { A .. "invalid selected-frame settings: %s.", "fixture",
        Snapshot("unitselection", { player = {}, general = 5 }), "general" },
    { A .. "select at least one unitframe.", "fixture", Snapshot("unitselection", {}) },
    { A .. "setting outside selected unitframes: %s.", "fixture",
        Snapshot("unitselection", { player = {}, general = { bogusKey = 1 } }), "bogusKey" },
    { A .. "aura settings outside selected unitframes: %s.", "fixture",
        Snapshot("unitselection", { player = {}, auras3 = { perUnit = { target = {} } } }), "target" },
    { A .. "unexpected selected-frame aura setting: %s.", "fixture",
        Snapshot("unitselection", { player = {}, auras3 = { bogus = true } }), "bogus" },
    { A .. "profile contains an invalid number", colors, nil, nil, LiveBad(0 / 0) },
    { A .. "profile contains a value that cannot be saved", colors, nil, nil, LiveBad(Fn) },
    { A .. "profile contains a table that refers to itself", colors, nil, nil, LiveBad(cyclic) },
    { A .. "profile exceeds snapshot limits", colors, nil, nil, LiveBad(Nested(40)) },
    { A .. "an add-on part of the profile could not be copied", colors, nil, nil, ExternalFails() },
}
for _, case in ipairs(cases) do
    local sentence, input, decoded, inserted, setup, teardown = case[1], case[2], case[3], case[4], case[5], case[6]
    Check(listed[sentence], "deDE: the import sentence list has no " .. sentence)
    driven[sentence] = true
    local reason = sentence:gsub("^Profile import failed: ", ""):gsub("^Import failed: ", ""):gsub("%.$", "")
    local expected = inserted and reason:format(inserted) or reason
    fixture = decoded
    if setup then setup() end
    before = #world.prints
    local ok, why = env.MSUF_ImportFromString(input)
    line = world.prints[before + 1]
    if teardown then teardown() end
    fixture = nil
    Check(ok == false and why == expected, "deDE: " .. sentence .. " was not the rejection: " .. tostring(why))
    local german = De(sentence)
    Check(line == "|cffff0000MSUF:|r " .. (inserted and german:format(inserted) or german),
        "deDE: " .. sentence .. " prints " .. tostring(line))
    for word in ("failed " .. reason):gmatch("%f[%a]%l%l%l+%f[%A]") do
        Check(not line:find("%f[%a]" .. word .. "%f[%A]"), "deDE: " .. sentence .. " keeps the English word '"
            .. word .. "': " .. line)
    end
end
for sentence in pairs(listed) do
    Check(driven[sentence], "deDE: no case drives the listed import sentence " .. sentence)
end
env.MSUF_TryDecodeCompactString = decode
Check(env.BINDING_NAME_MSUF_TOGGLE_OPTIONS == De("Toggle MSUF Options")
    and env.BINDING_NAME_MSUF_TOGGLE_EDITMODE == De("Toggle MSUF Edit Mode"),
    "deDE: the options and Edit Mode binding labels stayed English")
for _, key in ipairs({ "Level %d", "Level %d (%s)", "Elite", "Rare", "Rare Elite", "PvP", "AFK", "DND",
    "DEAD", "GHOST", "OFFLINE" }) do
    ns.Translate(key)
    Check(ns.L[key] ~= nil, "deDE: the pack has no entry for " .. key)
end
print("engine_chat_locale_smoke: ok (" .. scanned .. " files scanned, " .. #DIAGNOSTICS .. " diagnostic rows, "
    .. #cases .. " German import failure lines)")
