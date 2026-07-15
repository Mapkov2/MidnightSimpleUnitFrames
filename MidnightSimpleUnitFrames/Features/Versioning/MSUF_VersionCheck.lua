--- MSUF_VersionCheck.lua
--- Midnight Simple Unit Frames (MSUF)
--- Peer-to-peer version check via addon messaging (like DBM/BigWigs).
--- How it works:
--- 1. On login, broadcast our version to Guild + Group (once).
--- 2. Listen for other MSUF clients' version broadcasts.
--- 3. If a higher version is detected, print a one-shot chat message.
--- Secret-safe: All values are addon-generated strings/numbers, never game
--- API return values. No comparisons on secret/protected data.
--- Performance: Near-zero overhead. Single broadcast at login, passive
--- listener on CHAT_MSG_ADDON. No combat paths, no OnUpdate.
--- Debug: /msuf versiontest - simulates an update notification.

local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

--- Constants
local MSG_PREFIX = "MSUF" --- 4 chars, well within 16-char limit

--- Perf locals
local type, tonumber, tostring = type, tonumber, tostring
local string_format, string_match = string.format, string.match
local C_ChatInfo = C_ChatInfo
local C_AddOns  = C_AddOns
local IsInGroup, IsInRaid, IsInGuild = IsInGroup, IsInRaid, IsInGuild
local LE_PARTY_CATEGORY_HOME     = LE_PARTY_CATEGORY_HOME
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

--- Version parsing. The numeric key preserves prerelease ordering while staying
--- below Lua's exact-integer range for bounded components.
--- Secret-safe: operates on addon-controlled strings only.
local function VersionToNumber(str)
    if type(str) ~= "string" then return 0 end
    local value = str:match("^%s*(.-)%s*$")
    if not value or value == "" or #value > 32 then return 0 end
    local maj, min, pat, channel, revisionText = string_match(value:lower(), "^(%d+)%.(%d+)%.?(%d*)%-?([%a]*)(%d*)$")
    local hasSeparator = value:find("-", 1, true) ~= nil
    if channel == "" then
        if hasSeparator or revisionText ~= "" then return 0 end
    elseif not hasSeparator or revisionText == "" then
        return 0
    end
    local revision = tonumber(revisionText) or 0
    maj, min, pat = tonumber(maj), tonumber(min), tonumber(pat) or 0
    if not maj or not min or maj > 999 or min > 999 or pat > 999 or revision > 99999 then return 0 end
    local rank
    if channel == "" then rank = 4
    elseif channel == "alpha" then rank = 1
    elseif channel == "beta" then rank = 2
    elseif channel == "rc" then rank = 3
    else return 0 end
    local normalized = string_format("%d.%d%s%s", maj, min, pat > 0 and ("." .. pat) or "", channel ~= "" and ("-" .. channel .. revision) or "")
    local number = ((((maj * 1000) + min) * 1000 + pat) * 10 + rank) * 100000 + revision
    return number, normalized, { major = maj, minor = min, patch = pat, channel = channel, revision = revision }
end

--- State (session-scoped)
local myVersionStr   = nil
local myVersionNum   = 0
local myVersionParts = nil
local highestSeenNum = 0
local highestSeenStr = nil
local notifiedUser   = false
local prefixOk       = false
local moduleActive   = false  --- true if Init() ran successfully
local broadcastGeneration = 0
local IsEnabled

--- Core
local function ReadMyVersion()
    if myVersionStr then return end
    local ver = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    if type(ver) == "string" and ver ~= "" then
        local number, normalized, parts = VersionToNumber(ver)
        myVersionStr   = normalized or ver
        myVersionNum   = number
        myVersionParts = parts
        highestSeenNum = myVersionNum
        highestSeenStr = myVersionStr
    end
end

local function PrintUpdateMessage(newVer)
    print(string_format(
        "|cff7aa2f7MSUF|r: A newer version (%s%s|r) is available! You have %s%s|r — please update.",
        "|cffffd100", tostring(newVer),
        "|cffffd100", tostring(myVersionStr or "?")
    ))
end

local function NotifyOnce()
    if notifiedUser then return end
    if highestSeenNum <= myVersionNum then return end
    notifiedUser = true
    PrintUpdateMessage(highestSeenStr or NumberToVersion(highestSeenNum))
end

local function BroadcastOnce()
    if not moduleActive or not IsEnabled() then return end
    if not myVersionStr or myVersionNum <= 0 then return end
    if not prefixOk then return end

    local payload = "V:" .. myVersionStr

    --- Guild
    if IsInGuild and IsInGuild() then
        C_ChatInfo.SendAddonMessage(MSG_PREFIX, payload, "GUILD")
    end

    --- Group / Raid / Instance
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        C_ChatInfo.SendAddonMessage(MSG_PREFIX, payload, "INSTANCE_CHAT")
    elseif IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
        if IsInRaid and IsInRaid() then
            C_ChatInfo.SendAddonMessage(MSG_PREFIX, payload, "RAID")
        else
            C_ChatInfo.SendAddonMessage(MSG_PREFIX, payload, "PARTY")
        end
    end
end

local VALID_VERSION_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local function OnAddonMessage(_, prefix, payload, channel)
    if prefix ~= MSG_PREFIX then return end
    if type(payload) ~= "string" or #payload > 40 or not VALID_VERSION_CHANNELS[channel] then return end

    local ver = string_match(payload, "^V:(.+)$")
    if not ver then return end

    local num, normalized = VersionToNumber(ver)
    if num <= 0 then return end

    --- Secret-safe: comparing addon-generated integers only
    if num > highestSeenNum then
        highestSeenNum = num
        highestSeenStr = normalized
        NotifyOnce()
    end
end

--- DB helper
IsEnabled = function()
    local db = _G.MSUF_DB
    if not db or not db.general then return true end --- default: enabled
    return db.general.versionCheckEnabled ~= false
end

--- Event wiring
local KEY = "MSUF_VersionCheck"

local function Enable()
    if moduleActive or not IsEnabled() then return end
    ReadMyVersion()

    --- Register prefix (idempotent)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(MSG_PREFIX)
        prefixOk = true
    end

    local bus = MSUF.MSUF_EventBus or _G.MSUF_EventBus
    if not bus then return end

    --- One-shot broadcast at login (delayed to avoid login storm)
    bus:Register("PLAYER_ENTERING_WORLD", KEY .. "_PEW", function()
        local generation = broadcastGeneration
        C_Timer.After(5 + math.random() * 5, function()
            if generation == broadcastGeneration then BroadcastOnce() end
        end)
    end, nil, true) --- once = true

    --- Passive listener for peer versions (stays registered all session)
    bus:Register("CHAT_MSG_ADDON", KEY .. "_CMA", OnAddonMessage)

    moduleActive = true
end

local function Disable()
    broadcastGeneration = broadcastGeneration + 1
    local bus = MSUF.MSUF_EventBus or _G.MSUF_EventBus
    if bus then
        bus:Unregister("PLAYER_ENTERING_WORLD", KEY .. "_PEW")
        bus:Unregister("CHAT_MSG_ADDON", KEY .. "_CMA")
    end
    moduleActive = false
end

--- Module registration
MSUF.MSUF_RegisterModule("VersionCheck", {
    key     = "VersionCheck",
    order   = 999,
    IsEnabled = IsEnabled,
    Enable = Enable,
    Disable = Disable,
    Shutdown = Disable,
})

--- Public API (slash commands, options, debug)
MSUF.VersionCheck = {
    GetMyVersion = function()
        ReadMyVersion()
        return myVersionStr, myVersionNum
    end,

    GetNewestSeen = function()
        return highestSeenStr or myVersionStr or "?", highestSeenNum, notifiedUser
    end,

    IsActive = function()
        return moduleActive
    end,

    --- Debug: simulate receiving a higher version to preview the notification.
    --- Usage: /msuf versiontest or /run MSUF_NS.VersionCheck.DebugFakeUpdate()
    DebugFakeUpdate = function()
        ReadMyVersion()
        if not myVersionStr then
            print("|cff7aa2f7MSUF|r: VersionCheck — could not read own version.")
            return
        end
        local parts = myVersionParts or {}
        local fakeStr
        if parts.channel and parts.channel ~= "" then
            fakeStr = string_format("%d.%d%s-%s%d", parts.major, parts.minor,
                parts.patch > 0 and ("." .. parts.patch) or "", parts.channel, parts.revision + 1)
        else
            fakeStr = string_format("%d.%d.%d", parts.major or 0, parts.minor or 0, (parts.patch or 0) + 1)
        end
        print(string_format(
            "|cff7aa2f7MSUF|r: |cff888888[DEBUG]|r Simulating update from %s → %s",
            tostring(myVersionStr), tostring(fakeStr)
        ))
        PrintUpdateMessage(fakeStr)
    end,
}

--- Slash command: /msuf versiontest
--- Hooks into existing slash handler cleanly via a global the SlashMenu
--- can call, or works standalone via /run.
ExportPublic("MSUF_VersionCheck_DebugFakeUpdate", function()
    if MSUF.VersionCheck and MSUF.VersionCheck.DebugFakeUpdate then
        MSUF.VersionCheck.DebugFakeUpdate()
    end
end)
