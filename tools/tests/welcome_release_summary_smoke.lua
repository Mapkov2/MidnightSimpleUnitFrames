-- welcome_release_summary_smoke.lua <repoRoot>
--
-- The 6.50 login greeting sums up the 6.5 line (CHANGELOG_6.5_DRAFT.md totals)
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
        Client = { Interface = interface },
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

local welcome = Load(120105, "6.50")
local line = Summary(welcome.GetLines(false))
Check(line ~= nil, "12.1.5 with 6.50: the greeting has no release summary")
if line then
    Check(line:find("MSUF 6.50", 1, true) and line:find("New features & changes: 102", 1, true)
        and line:find("Bug fixes: 103", 1, true) and line:find("Performance improvements: 20", 1, true),
        "12.1.5 with 6.50: the summary does not name 6.50 with 102 / 103 / 20: " .. line)
end
Check(#welcome.GetLines(false) == 4, "12.1.5 with 6.50: expected title, patch, summary and /msuf lines")
Check(Summary(welcome.GetLines(true)) == nil, "the warning-only greeting printed the release summary")
Check(Summary(Load(120200, "6.50").GetLines(false)) ~= nil, "12.2 with 6.50: the summary is missing")
Check(Summary(Load(120100, "6.50").GetLines(false)) == nil, "12.1.0 printed the 6.50 summary")
Check(Summary(Load(16001, "6.50").GetLines(false)) == nil, "WoW Forever printed the 12.1.5 summary")
Check(Summary(Load(11509, "6.50").GetLines(false)) == nil, "Classic Era printed the 12.1.5 summary")
Check(Summary(Load(120105, "6.5-beta19").GetLines(false)) == nil, "a beta build printed the 6.50 summary")
Check(Summary(Load(120105, "6.51").GetLines(false)) == nil, "a later version printed the 6.50 totals")
Check(Summary(Load(nil, "6.50").GetLines(false)) == nil, "an unknown interface printed the summary")

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
print("welcome_release_summary_smoke: ok (6.50 summary on 12.1.5+, silent on 12.1.0, Forever, Classic and other versions; 12 locale packs)")
