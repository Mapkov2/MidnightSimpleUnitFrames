local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local registered = {}
local module
local bus = {}
function bus:Register(event, key, callback)
    registered[event .. "|" .. key] = callback
end
function bus:Unregister(event, key)
    registered[event .. "|" .. key] = nil
end

_G.MSUF_DB = { general = { versionCheckEnabled = true } }
_G.C_AddOns = { GetAddOnMetadata = function() return "6.0-beta17" end }
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function() end,
}
_G.C_Timer = { After = function() end }
_G.IsInGuild = function() return false end
_G.IsInGroup = function() return false end
_G.IsInRaid = function() return false end
_G.LE_PARTY_CATEGORY_HOME = 1
_G.LE_PARTY_CATEGORY_INSTANCE = 2

local ns = { MSUF_EventBus = bus }
function ns.MSUF_RegisterModule(name, value)
    Check(name == "VersionCheck", "unexpected module registration")
    module = value
end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Features/Versioning/MSUF_VersionCheck.lua"))
chunk("MidnightSimpleUnitFrames", ns)
Check(module and type(module.Enable) == "function", "version module was not registered")
module.Enable()

local receive = registered["CHAT_MSG_ADDON|MSUF_VersionCheck_CMA"]
Check(type(receive) == "function", "version listener was not registered")
local ownString, ownNumber = ns.VersionCheck.GetMyVersion()
Check(ownString == "6.0-beta17" and ownNumber > 0, "own prerelease version was not normalized")

local function NewestIs(expected, message)
    local value = ns.VersionCheck.GetNewestSeen()
    Check(value == expected, message .. ": got " .. tostring(value))
end

receive(nil, "MSUF", "V:6.0-beta99999|Hitem:19019|h", "GUILD")
NewestIs("6.0-beta17", "malicious version suffix was accepted")
receive(nil, "MSUF", "V:6.0-18", "GUILD")
NewestIs("6.0-beta17", "stable version with a fake revision was accepted")
receive(nil, "MSUF", "V:6.0beta18", "GUILD")
NewestIs("6.0-beta17", "prerelease without a separator was accepted")
receive(nil, "MSUF", "V:6.0-beta", "GUILD")
NewestIs("6.0-beta17", "prerelease without a numeric revision was accepted")
receive(nil, "MSUF", "V:6.0-beta18", "WHISPER")
NewestIs("6.0-beta17", "untrusted addon-message channel was accepted")
receive(nil, "MSUF", "V:6.0-beta16", "GUILD")
NewestIs("6.0-beta17", "older prerelease replaced the current version")
receive(nil, "MSUF", "V:6.0-beta18", "GUILD")
NewestIs("6.0-beta18", "newer beta revision was not detected")
local _, betaNumber, notified = ns.VersionCheck.GetNewestSeen()
Check(betaNumber > ownNumber and notified == true, "newer beta did not trigger the one-shot notification")
receive(nil, "MSUF", "V:6.0", "RAID")
NewestIs("6.0", "stable release did not sort after its prereleases")
local _, stableNumber = ns.VersionCheck.GetNewestSeen()
Check(stableNumber > betaNumber, "stable release numeric order is not above beta")
receive(nil, "MSUF", "V:" .. string.rep("9", 41), "GUILD")
NewestIs("6.0", "oversized payload was accepted")

print("PASS version check prerelease: bounded grammar, trusted channels, beta ordering, stable ordering")
