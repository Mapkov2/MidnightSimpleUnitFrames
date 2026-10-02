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
--      tooltip/status words come out of the German pack.
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
Check(env.BINDING_NAME_MSUF_TOGGLE_OPTIONS == De("Toggle MSUF Options")
    and env.BINDING_NAME_MSUF_TOGGLE_EDITMODE == De("Toggle MSUF Edit Mode"),
    "deDE: the options and Edit Mode binding labels stayed English")
for _, key in ipairs({ "Level %d", "Level %d (%s)", "Elite", "Rare", "Rare Elite", "PvP", "AFK", "DND",
    "DEAD", "GHOST", "OFFLINE" }) do
    ns.Translate(key)
    Check(ns.L[key] ~= nil, "deDE: the pack has no entry for " .. key)
end
print("engine_chat_locale_smoke: ok (" .. scanned .. " files scanned, " .. #DIAGNOSTICS .. " diagnostic rows)")
