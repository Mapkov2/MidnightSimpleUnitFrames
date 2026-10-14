-- welcome_release_summary_smoke.lua <repoRoot>
-- Login keeps title, client patch and menu hint, with no release-count line.
-- The optional greeting toggle and old-preview compatibility warning retain
-- their independent behavior.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function Load(interface, version, enabled)
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
    local messages = {}
    local env = setmetatable({}, { __index = _G })
    env._G, env.CreateFrame = env, false
    env.MSUF_DB = { general = { showWelcomeMessage = enabled } }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_WelcomeMessage.lua"))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", ns)
    return ns.WelcomeMessage, messages
end

local function NoCounts(lines, label)
    for _, line in ipairs(lines) do
        for _, key in ipairs({ "New features & changes", "Bug fixes", "Performance improvements" }) do
            Check(not line:find(key, 1, true), label .. ": unwanted release counts: " .. line)
        end
    end
end

for _, version in ipairs({ "6.50", "6.501" }) do
    for _, case in ipairs({
        { 120007, "12.0.7" }, { 120100, "12.1" }, { 120105, "12.1.5" }, { 120200, "12.2" },
        { 16001, "1.60" }, { 11509, "1.15" }, { 20506, "2.5" }, { 50504, "5.5" },
    }) do
        local label = version .. "/" .. case[1]
        local welcome = Load(case[1], version, true)
        local lines = welcome.GetLines(false)
        Check(#lines == 3, label .. ": expected title, patch and /msuf lines only")
        Check(lines[1]:find("v" .. version, 1, true) and not lines[1]:lower():find("beta", 1, true),
            label .. ": release title changed")
        Check(lines[2]:find("Welcome to Patch " .. case[2] .. "|r", 1, true),
            label .. ": client patch changed")
        Check(lines[3] and lines[3]:find("/msuf", 1, true), label .. ": menu hint missing")
        Check(welcome.GetReleaseSummaryLine == nil, label .. ": removed summary helper remains")
        NoCounts(lines, label)
        NoCounts(welcome.GetLines(true), label .. "/warning-only")
        local muted, messages = Load(case[1], version, false)
        Check(muted.IsEnabled() == false and muted.Show() == false and #messages == 0,
            label .. ": disabled welcome printed")
        Check(muted.Show(true) == true and #messages == 3, label .. ": forced replay failed")
        NoCounts(messages, label .. "/forced")
    end
end

local unknown = Load(nil, "6.501", true)
Check(#unknown.GetLines(false) == 3, "unknown client lost ordinary greeting")
NoCounts(unknown.GetLines(false), "unknown client")

local preview, messages = Load(120007, "6.0 RC18", false)
Check(preview.IsEnabled() == false and preview.IsPreviewWarningRequired() == true,
    "old-client preview warning was tied to the optional greeting")
Check(preview.Show() == true and #messages == 2, "old-client preview warning was hidden")
Check(messages[2] and messages[2]:find("Built for WoW 12.1 PTR.", 1, true)
    and messages[2]:find("Blizzard's native 12.1 system.", 1, true), "preview compatibility text changed")
NoCounts(messages, "preview warning")
local fullPreview = Load(120007, "6.0 RC18", true).GetLines(false)
Check(#fullPreview == 4 and fullPreview[3]:find("Thanks for testing!", 1, true)
    and fullPreview[4]:find("/msuf", 1, true), "enabled preview greeting changed")
local currentPreview, currentMessages = Load(120100, "6.0 RC18", false)
Check(currentPreview.IsPreviewWarningRequired() == false
    and currentPreview.Show() == false and #currentMessages == 0,
    "compatible preview ignored the disabled greeting")

if #failures > 0 then
    error("welcome_release_summary_smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("welcome_release_summary_smoke: ok (6.50/6.501 without counts on all clients; toggle and preview warnings preserved)")
