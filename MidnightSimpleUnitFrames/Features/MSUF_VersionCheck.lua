-- MSUF_VersionCheck.lua
-- Midnight Simple Unit Frames (MSUF)
-- Peer-to-peer version check via addon messaging (like DBM/BigWigs).
--
-- How it works:
--   1. On login, broadcast our version to Guild + Group (once).
--   2. Listen for other MSUF clients' version broadcasts.
--   3. If a higher version is detected, print a one-shot chat message.
--
-- Secret-safe: All values are addon-generated strings/numbers, never game
-- API return values. No comparisons on secret/protected data.
--
-- Performance: Near-zero overhead. Single broadcast at login, passive
-- listener on CHAT_MSG_ADDON. No combat paths, no OnUpdate.
--
-- Debug: /msuf versiontest  — simulates an update notification.

local addonName, ns = ...
ns = ns or {}

-- =========================================================================
-- Constants
-- =========================================================================
local MSG_PREFIX = "MSUF" -- 4 chars, well within 16-char limit

-- =========================================================================
-- Perf locals
-- =========================================================================
local type, tonumber, tostring = type, tonumber, tostring
local string_format, string_match = string.format, string.match
local C_ChatInfo = C_ChatInfo
local C_AddOns  = C_AddOns
local IsInGroup, IsInRaid, IsInGuild = IsInGroup, IsInRaid, IsInGuild
local LE_PARTY_CATEGORY_HOME     = LE_PARTY_CATEGORY_HOME
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

-- =========================================================================
-- Version parsing
-- =========================================================================
-- "2.2" / "2.2.1" / "2.10.3" → single integer for fast comparison.
-- Format: major * 10000 + minor * 100 + patch
-- Secret-safe: operates on addon-controlled strings only.
local function VersionToNumber(str)
    if type(str) ~= "string" then return 0 end
    local maj, min, pat = string_match(str, "^(%d+)%.(%d+)%.?(%d*)")
    if not maj then return 0 end
    return (tonumber(maj) or 0) * 10000
         + (tonumber(min) or 0) * 100
         + (tonumber(pat) or 0)
end

local function NumberToVersion(num)
    if type(num) ~= "number" or num <= 0 then return "?" end
    local maj = math.floor(num / 10000)
    local min = math.floor((num % 10000) / 100)
    local pat = num % 100
    if pat > 0 then return string_format("%d.%d.%d", maj, min, pat) end
    return string_format("%d.%d", maj, min)
end

-- =========================================================================
-- State (session-scoped)
-- =========================================================================
local myVersionStr   = nil
local myVersionNum   = 0
local highestSeenNum = 0
local highestSeenStr = nil
local notifiedUser   = false
local prefixOk       = false
local moduleActive   = false  -- true if Init() ran successfully

-- =========================================================================
-- Core
-- =========================================================================
local function ReadMyVersion()
    if myVersionStr then return end
    local ok, ver = pcall(function()
        return C_AddOns and C_AddOns.GetAddOnMetadata
            and C_AddOns.GetAddOnMetadata(addonName, "Version")
    end)
    if ok and type(ver) == "string" and ver ~= "" then
        myVersionStr   = ver
        myVersionNum   = VersionToNumber(ver)
        highestSeenNum = myVersionNum
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
    if not myVersionStr or myVersionNum <= 0 then return end
    if not prefixOk then return end

    local payload = "V:" .. myVersionStr

    -- Guild
    if IsInGuild and IsInGuild() then
        pcall(C_ChatInfo.SendAddonMessage, MSG_PREFIX, payload, "GUILD")
    end

    -- Group / Raid / Instance
    if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        pcall(C_ChatInfo.SendAddonMessage, MSG_PREFIX, payload, "INSTANCE_CHAT")
    elseif IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) then
        if IsInRaid and IsInRaid() then
            pcall(C_ChatInfo.SendAddonMessage, MSG_PREFIX, payload, "RAID")
        else
            pcall(C_ChatInfo.SendAddonMessage, MSG_PREFIX, payload, "PARTY")
        end
    end
end

local function OnAddonMessage(_, prefix, payload, _, _)
    if prefix ~= MSG_PREFIX then return end
    if type(payload) ~= "string" then return end

    local ver = string_match(payload, "^V:(.+)$")
    if not ver then return end

    local num = VersionToNumber(ver)
    if num <= 0 then return end

    -- Secret-safe: comparing addon-generated integers only
    if num > highestSeenNum then
        highestSeenNum = num
        highestSeenStr = ver
        NotifyOnce()
    end
end

-- =========================================================================
-- DB helper
-- =========================================================================
local function IsEnabled()
    local db = _G.MSUF_DB
    if not db or not db.general then return true end -- default: enabled
    return db.general.versionCheckEnabled ~= false
end

-- =========================================================================
-- Event wiring
-- =========================================================================
local KEY = "MSUF_VersionCheck"

local function Init()
    if not IsEnabled() then return end

    ReadMyVersion()

    -- Register prefix (idempotent)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(MSG_PREFIX)
        prefixOk = true
    end

    local bus = ns.MSUF_EventBus or _G.MSUF_EventBus
    if not bus then return end

    -- One-shot broadcast at login (delayed to avoid login storm)
    bus:Register("PLAYER_ENTERING_WORLD", KEY .. "_PEW", function()
        C_Timer.After(5 + math.random() * 5, BroadcastOnce)
    end, nil, true) -- once = true

    -- Passive listener for peer versions (stays registered all session)
    bus:Register("CHAT_MSG_ADDON", KEY .. "_CMA", OnAddonMessage)

    moduleActive = true
end

-- =========================================================================
-- Module registration
-- =========================================================================
ns.MSUF_RegisterModule("VersionCheck", {
    key     = "VersionCheck",
    order   = 999,
    enabled = true,
    Init    = function() Init() end,
})

-- =========================================================================
-- Public API (slash commands, options, debug)
-- =========================================================================
ns.VersionCheck = {
    GetMyVersion = function()
        ReadMyVersion()
        return myVersionStr, myVersionNum
    end,

    GetNewestSeen = function()
        return highestSeenStr or NumberToVersion(highestSeenNum), highestSeenNum, notifiedUser
    end,

    IsActive = function()
        return moduleActive
    end,

    --- Debug: simulate receiving a higher version to preview the notification.
    --- Usage: /msuf versiontest   or   /run MSUF_NS.VersionCheck.DebugFakeUpdate()
    DebugFakeUpdate = function()
        ReadMyVersion()
        if not myVersionStr then
            print("|cff7aa2f7MSUF|r: VersionCheck — could not read own version.")
            return
        end
        local fakeNum = myVersionNum + 100 -- +1 minor
        local fakeStr = NumberToVersion(fakeNum)
        print(string_format(
            "|cff7aa2f7MSUF|r: |cff888888[DEBUG]|r Simulating update from %s → %s",
            tostring(myVersionStr), tostring(fakeStr)
        ))
        PrintUpdateMessage(fakeStr)
    end,
}

-- =========================================================================
-- Slash command: /msuf versiontest
-- Hooks into existing slash handler cleanly via a global the SlashMenu
-- can call, or works standalone via /run.
-- =========================================================================
_G.MSUF_VersionCheck_DebugFakeUpdate = function()
    if ns.VersionCheck and ns.VersionCheck.DebugFakeUpdate then
        ns.VersionCheck.DebugFakeUpdate()
    end
end
