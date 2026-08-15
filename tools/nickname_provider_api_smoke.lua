-- Public nickname-provider API contract: deterministic providers, cached
-- resolution, and strictly deferred combat changes without provider calls or
-- frame refreshes.
_G = _G or _ENV

local function ResolvePath(relative)
    local candidates = { "MidnightSimpleUnitFrames/" .. relative, relative }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "r")
        if handle then handle:close(); return candidates[i] end
    end
    error("cannot locate " .. relative)
end

local function Read(relative)
    local handle = assert(io.open(ResolvePath(relative), "rb"))
    local source = handle:read("*a")
    handle:close()
    return source
end

local function Check(condition, message)
    if not condition then error(message, 2) end
end

local combat = false
local names = {
    player = { "Native", "Realm" },
    target = { "Native", "Realm" },
    party1 = { "Other", "Realm" },
    npc = { "Creature", nil },
}
local fullNameReads, isPlayerReads = 0, 0
local eventFrame
local unitRefreshes, groupRefreshes = 0, 0
local lastGroupRefreshUnit
local refreshedGroupUnits = {}
local activeResolver

_G.InCombatLockdown = function() return combat end
_G.UnitName = function(unit)
    local entry = names[unit]
    return entry and entry[1] or nil
end
_G.UnitFullName = function(unit)
    fullNameReads = fullNameReads + 1
    local entry = names[unit]
    return entry and entry[1] or nil, entry and entry[2] or nil
end
_G.UnitIsPlayer = function(unit)
    isPlayerReads = isPlayerReads + 1
    return unit ~= "npc"
end
_G.GetNormalizedRealmName = function() return "Realm" end
_G.issecretvalue = function() return false end
_G.geterrorhandler = function() return function(message) error(message, 0) end end
_G.CreateFrame = function()
    local frame = { events = {} }
    function frame:SetScript(_, callback) self.callback = callback end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    eventFrame = frame
    return frame
end

local unitFrame = {
    MSUFUnitKey = "player",
    _msufActiveElements = { NameText = true, Text = true },
}
local otherUnitFrame = {
    MSUFUnitKey = "party1",
    _msufActiveElements = { NameText = true, Text = true },
}
local aliasUnitFrame = {
    MSUFUnitKey = "target",
    _msufActiveElements = { NameText = true, Text = true },
}
local Text = {
    UnitName = _G.UnitName,
    CreateFrame = _G.CreateFrame,
    InCombatLockdown = _G.InCombatLockdown,
}
function Text.SetDisplayNameResolver(resolver) activeResolver = resolver or _G.UnitName end

local MSUF = {
    API = {},
    Public = {},
    UFText = Text,
    UFTextRuntime = {
        UpdateName = function() unitRefreshes = unitRefreshes + 1 end,
        UpdateInline = function() unitRefreshes = unitRefreshes + 1 end,
    },
    UF = {
        ForEachFrame = function(callback, runtime, targetUnit, targetFullName)
            callback(unitFrame, nil, runtime, targetUnit, targetFullName)
            callback(aliasUnitFrame, nil, runtime, targetUnit, targetFullName)
            callback(otherUnitFrame, nil, runtime, targetUnit, targetFullName)
            return true
        end,
    },
    GF = {
        ForEachFrame = function(callback, includeHidden, a, b, c)
            callback({}, "player", nil, a, b, c)
            callback({}, "target", nil, a, b, c)
            callback({}, "party1", nil, a, b, c)
            return true
        end,
        RefreshGroupNames = function(unit)
            groupRefreshes = groupRefreshes + 1
            lastGroupRefreshUnit = unit
            if unit then
                refreshedGroupUnits[unit] = (refreshedGroupUnits[unit] or 0) + 1
            end
            return true
        end,
    },
}

_G.MSUF_DB = { general = {} }

local chunk = assert(loadfile(ResolvePath("Integrations/MSUF_Integration_NicknameProviders.lua")))
chunk("MidnightSimpleUnitFrames", MSUF)

local API = assert(MSUF.API.Nicknames, "scoped nickname API was not published")
Check(API == MSUF.Public.Nicknames, "public and API nickname facades must match")
Check(API.GetVersion() == 1, "unexpected nickname API version")
local capabilities = API.GetCapabilities()
Check(capabilities.eventDriven and capabilities.cached and capabilities.multipleProviders,
    "nickname API capabilities missing")
Check(capabilities.targetedUpdates == true, "targeted update capability missing")
Check(capabilities.playerOnlyProviders == true, "player-only provider fastpath missing")
Check(capabilities.combatUpdates == false and capabilities.polling == false,
    "combat/polling capability boundary drifted")

local lowCalls, highCalls = 0, 0
local currentNickname = "First"
local ok, reason = API.RegisterProvider("Low", function()
    lowCalls = lowCalls + 1
    return "LowName"
end, 10)
Check(ok and reason == nil, "low-priority provider registration failed")

ok, reason = API.RegisterProvider("High", function(unit, nativeName, fullName)
    highCalls = highCalls + 1
    if unit == "player" then
        Check(nativeName == "Native", "provider did not receive native name")
        Check(fullName == "Native-Realm", "provider did not receive full name")
        return currentNickname
    end
    Check(unit == "party1" and nativeName == "Other" and fullName == "Other-Realm",
        "provider did not receive the targeted secondary identity")
    return "OtherNick"
end, 50)
Check(ok and reason == nil, "high-priority provider registration failed")
Check(type(activeResolver) == "function", "nickname resolver was not installed")

local resolved = activeResolver("player")
Check(resolved == "First", "highest-priority nickname was not selected")
Check(highCalls == 1 and lowCalls == 0, "provider priority order was not respected")
Check(activeResolver("player") == "First" and highCalls == 1,
    "resolved nickname was not cached")
Check(activeResolver("party1") == "OtherNick" and highCalls == 2,
    "secondary nickname was not cached")

local beforeTargetedUnitRefreshes = unitRefreshes
local beforeTargetedGroupRefreshes = groupRefreshes
currentNickname = "Targeted"
refreshedGroupUnits = {}
ok, reason = API.NotifyChanged("High", "player")
Check(ok and reason == nil, "targeted nickname change failed")
Check(unitRefreshes == beforeTargetedUnitRefreshes + 4,
    "targeted change did not refresh every unit-frame alias of the identity")
Check(groupRefreshes == beforeTargetedGroupRefreshes + 2
    and refreshedGroupUnits.player == 1 and refreshedGroupUnits.target == 1
    and refreshedGroupUnits.party1 == nil,
    "targeted change did not fan out to exactly the matching group-frame aliases")
Check(activeResolver("player") == "Targeted" and highCalls == 3,
    "targeted change did not invalidate only the unit cache")
Check(activeResolver("target") == "Targeted" and highCalls == 3,
    "targeted change did not rebuild the shared identity cache for an alias")
Check(activeResolver("party1") == "OtherNick" and highCalls == 3,
    "targeted change invalidated an unrelated unit cache")

ok, reason = API.NotifyChanged("High", {})
Check(not ok and reason == "invalid_unit", "invalid targeted unit was accepted")

local beforeCombatUnitRefreshes = unitRefreshes
local beforeCombatGroupRefreshes = groupRefreshes
currentNickname = "Second"
combat = true
ok, reason = API.NotifyChanged("High", "player")
Check(ok and reason == "deferred_combat", "combat change was not deferred")
ok, reason = API.NotifyChanged("High", "player")
Check(ok and reason == "deferred_combat", "duplicate combat unit change was not coalesced")
Check(eventFrame and eventFrame.events.PLAYER_REGEN_ENABLED,
    "deferred change did not request the one-shot post-combat event")
Check(unitRefreshes == beforeCombatUnitRefreshes and groupRefreshes == beforeCombatGroupRefreshes,
    "nickname frames refreshed in combat")
Check(activeResolver("player") == "Targeted", "combat did not preserve the frozen nickname")
Check(highCalls == 3 and lowCalls == 0, "a nickname provider ran in combat")

eventFrame.callback(eventFrame, "PLAYER_REGEN_ENABLED")
Check(unitRefreshes == beforeCombatUnitRefreshes and groupRefreshes == beforeCombatGroupRefreshes,
    "regen event refreshed while combat lockdown was still active")
Check(highCalls == 3, "regen event called a provider while still in combat")

combat = false
eventFrame.callback(eventFrame, "PLAYER_REGEN_ENABLED")
Check(not eventFrame.events.PLAYER_REGEN_ENABLED,
    "post-combat event was not unregistered after the deferred flush")
Check(unitRefreshes == beforeCombatUnitRefreshes + 4,
    "unit and inline names for every identity alias were not refreshed exactly once after combat")
Check(groupRefreshes == beforeCombatGroupRefreshes + 2,
    "group-frame identity aliases were not refreshed exactly once after combat")
Check(activeResolver("player") == "Second", "post-combat nickname was not applied")
Check(highCalls == 4 and lowCalls == 0, "post-combat resolution did not use one cached provider call")

combat = true
beforeCombatUnitRefreshes = unitRefreshes
beforeCombatGroupRefreshes = groupRefreshes
ok, reason = API.UnregisterProvider("High")
Check(ok and reason == "deferred_combat", "combat unregister was not deferred")
Check(activeResolver("player") == "Second", "combat unregister changed the frozen display")
Check(unitRefreshes == beforeCombatUnitRefreshes and groupRefreshes == beforeCombatGroupRefreshes,
    "combat unregister refreshed frames")

combat = false
eventFrame.callback(eventFrame, "PLAYER_REGEN_ENABLED")
Check(activeResolver("player") == "LowName", "remaining provider did not take ownership")
Check(lowCalls == 1, "remaining provider was not resolved exactly once")

ok, reason = API.UnregisterProvider("Low")
Check(ok and reason == nil, "final provider unregister failed")
Check(activeResolver == _G.UnitName, "native UnitName resolver was not restored")

-- The bundled NSRT adapter must use the same registry instead of replacing the
-- central resolver. Its own combat callback also keeps the NSRT cache frozen.
local nsrtCallbacks = {}
_G.NSRT = {
    Settings = { GlobalNickNames = true },
    NickNames = { ["Native-Realm"] = "NSRTFirst" },
}
_G.NSAPI = {
    RegisterCallback = function(_, event, callback)
        nsrtCallbacks[event] = callback
    end,
}

chunk = assert(loadfile(ResolvePath("Integrations/MSUF_Integration_NSRTNicknames.lua")))
chunk("MidnightSimpleUnitFrames", MSUF)
Check(API.IsProviderRegistered("NorthernSkyRaidTools"),
    "bundled NSRT adapter did not register as a nickname provider")
Check(activeResolver("player") == "NSRTFirst", "NSRT nickname was not resolved")
Check(type(nsrtCallbacks.NSRT_NICKNAME_UPDATED) == "function",
    "NSRT nickname callback was not registered")
local fullNameReadsBeforeNPC = fullNameReads
local isPlayerReadsBeforeNPC = isPlayerReads
Check(activeResolver("npc") == "Creature", "player-only provider changed an NPC name")
Check(fullNameReads == fullNameReadsBeforeNPC
    and isPlayerReads == isPlayerReadsBeforeNPC + 1,
    "player-only provider performed a full-name/provider lookup for an NPC")

_G.MSUF_DB.general.nsrtNicknameIntegration = false
Check(type(_G.MSUF_NSRTNicknames_ApplySetting) == "function",
    "NSRT setting apply hook was not exported")
_G.MSUF_NSRTNicknames_ApplySetting()
Check(not API.IsProviderRegistered("NorthernSkyRaidTools"),
    "disabling the MSUF NSRT integration did not unregister the provider")
Check(activeResolver("player") == "Native",
    "disabling the MSUF NSRT integration did not restore the character name")

_G.MSUF_DB.general.nsrtNicknameIntegration = true
_G.MSUF_NSRTNicknames_ApplySetting()
Check(API.IsProviderRegistered("NorthernSkyRaidTools"),
    "re-enabling the MSUF NSRT integration did not restore the provider")
Check(activeResolver("player") == "NSRTFirst",
    "re-enabling the MSUF NSRT integration did not restore the nickname")

combat = true
beforeCombatUnitRefreshes = unitRefreshes
beforeCombatGroupRefreshes = groupRefreshes
_G.NSRT.NickNames["Native-Realm"] = "NSRTSecond"
nsrtCallbacks.NSRT_NICKNAME_UPDATED()
Check(activeResolver("player") == "NSRTFirst", "NSRT cache changed in combat")
Check(unitRefreshes == beforeCombatUnitRefreshes and groupRefreshes == beforeCombatGroupRefreshes,
    "NSRT callback refreshed names in combat")
Check(eventFrame and eventFrame.events.PLAYER_REGEN_ENABLED,
    "NSRT callback did not request its post-combat refresh")

combat = false
eventFrame.callback(eventFrame, "PLAYER_REGEN_ENABLED")
Check(activeResolver("player") == "NSRTSecond",
    "NSRT nickname was not rebuilt after combat")
Check(unitRefreshes == beforeCombatUnitRefreshes + 6,
    "NSRT post-combat unit/inline refresh count drifted")
Check(groupRefreshes == beforeCombatGroupRefreshes + 1,
    "NSRT post-combat group refresh count drifted")

local source = Read("Integrations/MSUF_Integration_NicknameProviders.lua")
Check(not source:find("OnUpdate", 1, true), "nickname API must not install OnUpdate work")
Check(not source:find("NewTicker", 1, true), "nickname API must not install a ticker")
Check(not source:find("C_Timer", 1, true), "nickname API must not schedule timers")

local toc = Read("MidnightSimpleUnitFrames.toc")
local apiPos = assert(toc:find("Integrations\\MSUF_Integration_NicknameProviders.lua", 1, true),
    "nickname provider API missing from TOC")
local nsrtPos = assert(toc:find("Integrations\\MSUF_Integration_NSRTNicknames.lua", 1, true),
    "NSRT nickname adapter missing from TOC")
Check(apiPos < nsrtPos, "nickname provider API must load before the NSRT adapter")

print("nickname_provider_api_smoke: ok")
