-- welcome_release_summary_smoke.lua <repoRoot>
--
-- The 7.0-alpha1 login greeting sums up the 7.0-alpha1 release (CHANGELOG.md totals)
-- on WoW 12.1.5 and newer only: not on 12.1.0, not on WoW Forever or the
-- Classic clients, not for another version, and not when only the preview
-- warning is printed. Every locale pack translates the three labels with
-- exactly one %d each.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Load(interface, version)
    local ns = {
        ExportPublic = function() end,
        Translate = function(text) return text end,
        GetAddonVersion = function() return version end,
        Client = {
            Interface = interface,
            IsRetail = interface == 16001 or (interface and interface >= 100000) or false,
            IsForever = interface == 16001,
        },
    }
    local env = setmetatable({}, { __index = _G })
    env.CreateFrame = nil
    env.MSUF_DB = { general = {} }
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_WelcomeMessage.lua"))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", ns)
    return ns.WelcomeMessage
end

local function Summary(lines)
    for i = 1, #lines do
        if lines[i]:find("New features & changes", 1, true) then return lines[i] end
    end
end

local welcome = Load(120105, "7.0-alpha1")
local greeting = welcome.GetLines(false)
Check(greeting[1]:find("v7.0-alpha1", 1, true) and greeting[1]:find("alpha1", 1, true),
    "Retail release title must show v7.0-alpha1 with alpha1")
for _, case in ipairs({
    { 120007, "12.0.7" }, { 120100, "12.1" }, { 120105, "12.1.5" }, { 120200, "12.2" },
    { 16001, "1.60" }, { 11509, "1.15" }, { 20506, "2.5" }, { 50504, "5.5" },
}) do
    local lines = Load(case[1], "7.0-alpha1").GetLines(false)
    Check(lines[2]:find("Welcome to Patch " .. case[2] .. "|r", 1, true),
        "wrong welcome patch for interface " .. case[1] .. ": " .. lines[2])
end
local line = Summary(welcome.GetLines(false))
Check(line ~= nil, "12.1.5 with 7.0-alpha1: the greeting has no release summary")
if line then
    Check(line:find("MSUF 7.0-alpha1", 1, true) and line:find("New features & changes: 2", 1, true)
        and line:find("Bug fixes: 6", 1, true) and line:find("Performance improvements: 2", 1, true),
        "12.1.5 with 7.0-alpha1: the summary does not name 7.0-alpha1 with 2 / 6 / 2: " .. line)
end
Check(#welcome.GetLines(false) == 4, "12.1.5 with 7.0-alpha1: expected title, patch, summary and /msuf lines")
Check(Summary(welcome.GetLines(true)) == nil, "the warning-only greeting printed the release summary")
Check(Summary(Load(120200, "7.0-alpha1").GetLines(false)) ~= nil, "12.2 with 7.0-alpha1: the summary is missing")
Check(Summary(Load(120100, "7.0-alpha1").GetLines(false)) == nil, "12.1.0 printed the 7.0-alpha1 summary")
Check(Summary(Load(16001, "7.0-alpha1").GetLines(false)) == nil, "WoW Forever printed the 12.1.5 summary")
Check(Summary(Load(11509, "7.0-alpha1").GetLines(false)) == nil, "Classic Era printed the 12.1.5 summary")
Check(Summary(Load(120105, "6.5-beta19").GetLines(false)) == nil, "an older beta build printed the 7.0-alpha1 summary")
Check(Summary(Load(120105, "7.0-alpha2").GetLines(false)) == nil, "a later version printed the 7.0-alpha1 totals")
Check(Summary(Load(nil, "7.0-alpha1").GetLines(false)) == nil, "an unknown interface printed the summary")

local KEYS = { "New features & changes: %d", "Bug fixes: %d", "Performance improvements: %d" }
local LOCALES = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
for _, locale in ipairs(LOCALES) do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    for _, key in ipairs(KEYS) do
        local escaped = key:gsub("[%%%.%-%+%*%?%[%]%^%$%(%)]", "%%%0")
        local value = text:match('L%["' .. escaped .. '"%]%s*=%s*"([^"\r\n]*)"')
        if Check(value ~= nil, locale .. " lacks " .. key) then
            local _, count = value:gsub("%%d", "")
            Check(count == 1 and not value:find("%%[^d]"), locale .. " " .. key .. " needs exactly one %d: " .. value)
            if locale ~= "enUS" and locale ~= "enGB" then
                Check(value ~= key, locale .. " leaves " .. key .. " untranslated")
            end
        end
    end
end

if #failures > 0 then
    error("welcome_release_summary_smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("welcome_release_summary_smoke: ok (7.0-alpha1 summary on 12.1.5+, silent on 12.1.0, Forever, Classic and other versions; 12 locale packs)")
