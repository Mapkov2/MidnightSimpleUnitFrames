-- Version check ranking across release lines (review F3). The minor is a
-- decimal fraction: 6.5 is newer than 6.20, so a 6.5 user is never told to
-- "update" to 6.20 or 6.21. Peers broadcast an explicit release epoch (V2) and
-- keep the legacy V: line for older clients, whose integer minor reads a
-- two-digit 6.50 correctly where it read 6.5 as older than 6.20.
-- Usage: lua tools/tests/version_check_epoch_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local path = repo .. "/MidnightSimpleUnitFrames/Features/Versioning/MSUF_VersionCheck.lua"

local function Boot(myVersion)
    local world = { sent = {}, prints = {}, handlers = {}, timers = {} }
    local env = setmetatable({}, { __index = _G })
    env.print = function(text) world.prints[#world.prints + 1] = tostring(text) end
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, payload, channel) world.sent[#world.sent + 1] = channel .. " " .. payload end,
    }
    env.C_AddOns = {}
    env.IsInGuild = function() return true end
    env.IsInGroup = function(category) return category == 1 end
    env.IsInRaid = function() return false end
    env.LE_PARTY_CATEGORY_HOME, env.LE_PARTY_CATEGORY_INSTANCE = 1, 2
    env.C_Timer = { After = function(_, fn) world.timers[#world.timers + 1] = fn end }
    env.MSUF_DB = { general = {} }
    local ns = {
        ExportPublic = function() end,
        GetAddonVersion = function() return myVersion end,
        MSUF_RegisterModule = function(_, spec) world.module = spec end,
        MSUF_EventBus = { Register = function(_, event, _, fn) world.handlers[event] = fn end, Unregister = function() end },
    }
    local chunk = assert(loadfile(path))
    setfenv(chunk, env)
    chunk("MidnightSimpleUnitFrames", ns)
    world.module.Enable()
    return world
end
local function Receive(world, payload)
    world.handlers.CHAT_MSG_ADDON("CHAT_MSG_ADDON", "MSUF", payload, "GUILD", "Peer")
end
local function Notified(world)
    for _, line in ipairs(world.prints) do if line:find("A newer version", 1, true) then return line end end
end

-- A 6.5 beta client hears older Retail and Classic lines without a prompt.
for _, payload in ipairs({ "V:6.20", "V:6.21", "V:6.16", "V:6.5-beta11", "V:6.09" }) do
    local w = Boot("6.5-beta12")
    Receive(w, payload)
    assert(not Notified(w), "6.5-beta12 was told to update by " .. payload)
end
-- Newer versions still prompt, from either message form.
for _, case in ipairs({
    { "V:6.5-beta13", "6.5-beta13" }, { "V:6.50-rc1", "6.50-rc1" }, { "V:6.6", "6.6" },
    { "V2:6500000300001:6.5-rc1", "6.5-rc1" }, { "V2:7000000400000:7.0", "7.0" },
}) do
    local w = Boot("6.5-beta12")
    Receive(w, case[1])
    local line = Notified(w)
    assert(line and line:find(case[2], 1, true), "6.5-beta12 missed the newer " .. case[1])
end
-- A Retail 6.21 client hears 6.5 as newer.
local retail = Boot("6.21")
Receive(retail, "V:6.5")
assert(Notified(retail), "6.21 did not hear about 6.5")
-- A hostile label never reaches chat as markup; an oversized epoch is ignored.
local w = Boot("6.5-beta12")
Receive(w, "V2:9000000000000:|cffff0000x|r")
Receive(w, "V2:99999999999999999999:9.9")
assert(not Notified(w), "a malformed V2 message prompted an update")

-- Broadcast: the epoch line plus the legacy line older clients rank right.
local sender = Boot("6.5-beta12")
sender.handlers.PLAYER_ENTERING_WORLD()
assert(#sender.timers == 1, "no delayed broadcast was scheduled")
sender.timers[1]()
local sent = table.concat(sender.sent, "\n")
assert(sent:find("GUILD V2:6500000200012:6.5-beta12", 1, true), "the epoch line was not broadcast:\n" .. sent)
assert(sent:find("GUILD V:6.50-beta12", 1, true), "the legacy line was not broadcast in two-digit form:\n" .. sent)
-- The legacy reader of older clients (integer minor) ranks the two-digit line
-- above 6.21 and above older 6.5 betas.
local function OldRank(version)
    local maj, min, pat, channel, rev = version:lower():match("^(%d+)%.(%d+)%.?(%d*)%-?([%a]*)(%d*)$")
    local rank = ({ [""] = 4, alpha = 1, beta = 2, rc = 3 })[channel]
    return ((((tonumber(maj) * 1000) + tonumber(min)) * 1000 + (tonumber(pat) or 0)) * 10 + rank) * 100000 + (tonumber(rev) or 0)
end
assert(OldRank("6.50-beta12") > OldRank("6.21") and OldRank("6.50-beta12") > OldRank("6.5-beta11"),
    "older clients still rank the legacy line below their own version")
print("version_check_epoch_smoke: OK")
