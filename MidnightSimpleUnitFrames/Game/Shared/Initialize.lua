--- Client detection shared by Retail and the supported Classic clients: code
--- family, flavor and game mode.
---
--- This file intentionally loads before Kernel/MSUF_Bootstrap.lua.  Keep it
--- dependency-free: its job is to establish stable client flags that later
--- modules can branch on without repeating WOW_PROJECT_ID checks.

local addonName, MSUF = ...
local _G = _G
local type = type
local tonumber = tonumber
local select = select

MSUF = type(MSUF) == "table" and MSUF or _G.MSUF or _G.MSUF_NS or {}
_G.MSUF = MSUF
_G.MSUF_NS = MSUF

local projectID = _G.WOW_PROJECT_ID
local mainlineID = _G.WOW_PROJECT_MAINLINE
local vanillaID = _G.WOW_PROJECT_CLASSIC
local mistsID = _G.WOW_PROJECT_MISTS_CLASSIC
local tbcID = _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC

local function ReadTOCFlavor()
    local getMetadata = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    if type(getMetadata) ~= "function" then return nil end
    return getMetadata(addonName, "X-MSUF-Client")
end

local tocFlavor = ReadTOCFlavor()
tocFlavor = type(tocFlavor) == "string"
    and tocFlavor:lower():gsub("^%s+", ""):gsub("%s+$", "") or nil
local isRetail = mainlineID ~= nil and projectID == mainlineID
-- The project match and the TOC tag match stay separate so a client that is
-- placed only by its X-MSUF-Client tag can be reported below.
local projectIsVanilla = vanillaID ~= nil and projectID == vanillaID
local projectIsMists = mistsID ~= nil and projectID == mistsID
local projectIsTBC = tbcID ~= nil and projectID == tbcID
local isVanilla = projectIsVanilla or tocFlavor == "vanilla"
local isMists = projectIsMists or tocFlavor == "mists"
local isTBC = projectIsTBC or tocFlavor == "tbc"
local projectIsMainline = isRetail

-- WoW Forever runs Blizzard's Mainline code under its own TOC game type
-- (camelot in the 1.60.1 beta). It reads the _Mainline.toc files and reports
-- the Standard game mode, so neither tells it apart from Midnight. Blizzard_Game
-- is a LoadFirst Blizzard addon whose camelot-only file defines
-- GameEvent.RegisterCamelotEvents, so that function exists before any addon
-- loads, and only on Forever. An untagged (Mainline) TOC with the marker places
-- the Mainline build whatever project ID the client reports; a Classic
-- X-MSUF-Client tag always wins.
local gameEvent = _G.GameEvent
local hasCamelotMarker = type(gameEvent) == "table" and type(gameEvent.RegisterCamelotEvents) == "function"
local isForever = hasCamelotMarker and (tocFlavor == nil or tocFlavor == "")
if isForever then
    isRetail, isVanilla, isMists, isTBC = true, false, false, false
end

local interfaceNumber
if type(_G.GetBuildInfo) == "function" then
    interfaceNumber = tonumber((select(4, _G.GetBuildInfo())))
end

local Client = MSUF.Client or {}
MSUF.Client = Client
Client.ProjectID = projectID
Client.Interface = interfaceNumber
Client.Flavor = isVanilla and "Vanilla" or isMists and "Mists" or isTBC and "TBC"
    or isRetail and "Mainline" or "Unknown"
Client.IsRetail = isRetail
Client.IsVanilla = isVanilla
Client.IsEra = isVanilla
Client.IsMists = isMists
Client.IsTBC = isTBC
Client.IsClassic = isVanilla or isMists or isTBC
Client.SupportsPetHappiness = isVanilla or isTBC
-- The aura filter that returns the debuffs this player can dispel. Classic Era
-- keeps the original meaning of HARMFUL|RAID, the filter Blizzard's own "show
-- dispellable debuffs" party frames scan there, and does not honour
-- RAID_PLAYER_DISPELLABLE (dispel visuals stayed dark on Era only, in-game
-- report 2026-09-16). TBC, Mists and Mainline use RAID_PLAYER_DISPELLABLE.
Client.DispellableDebuffFilter = isVanilla and "HARMFUL|RAID" or "HARMFUL|RAID_PLAYER_DISPELLABLE"
Client.SupportsEllesmereEditMode = isRetail
Client.SupportsBlizzardEditMode = type(_G.Enum) == "table" and type(_G.Enum.EditModeSystem) == "table"
Client.IsSupported = isRetail or isVanilla or isMists or isTBC
Client.TOCFlavor = tocFlavor
Client.ProjectIDRecognized = projectIsMainline
    or (not isForever and (projectIsVanilla or projectIsMists or projectIsTBC))
-- Capability fact only. Never define a global issecretvalue fallback here:
-- other addons probe that global to detect the secret-value API.
Client.HasSecretValueAPI = type(_G.issecretvalue) == "function"
-- The code family decides which build runs: Mainline loads the Retail tree plus
-- Game/Shared, Classic adds Game/Classic and its flavor folder.
Client.Family = Client.Flavor == "Mainline" and "Mainline" or Client.IsClassic and "Classic" or "Unknown"

-- Game mode, one level below the family. C_GameRules.GetActiveGameMode exists on
-- every current client and is final before addons load: Blizzard_SharedXML reads
-- it at file scope. Enum.GameMode keys are not TOC game types: Classic clients
-- run Standard, and Plunderstorm ships its own TOC suffix.
local KNOWN_GAME_MODES = { Standard = true, Plunderstorm = true, WoWHack = true }
local gameModeEnum = type(_G.Enum) == "table" and type(_G.Enum.GameMode) == "table" and _G.Enum.GameMode or nil

local function ReadActiveGameMode()
    local gameRules = _G.C_GameRules
    local getActiveGameMode = type(gameRules) == "table" and gameRules.GetActiveGameMode or nil
    if type(getActiveGameMode) ~= "function" then return nil end
    return getActiveGameMode()
end

-- Keys are visited in sorted order so the answer stays stable if two keys ever
-- share a value.
local function GameModeKey(mode)
    if mode == nil or not gameModeEnum then return nil end
    local keys = {}
    for key, value in pairs(gameModeEnum) do
        if value == mode and type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys[1]
end

local gameMode = ReadActiveGameMode()
local gameModeName = GameModeKey(gameMode)
local standardGameMode = gameModeEnum and gameModeEnum.Standard
Client.GameMode = gameMode
Client.GameModeName = gameModeName
-- Without the API or the Standard key there is nothing to compare, so the
-- client counts as Standard, which every client ran before game modes existed.
Client.IsStandardGameMode = gameMode == nil or standardGameMode == nil or gameMode == standardGameMode
Client.GameModeRecognized = Client.IsStandardGameMode or KNOWN_GAME_MODES[gameModeName] == true
-- WoW Forever, from the Blizzard_Game marker above. Never key it on a guessed
-- Forever project ID, interface number, TOC suffix or Enum.GameMode key.
Client.IsForever = isForever

local unsupportedEvents = Client.UnsupportedEvents or {}
Client.UnsupportedEvents = unsupportedEvents
if Client.IsClassic then
    -- Confirmed absent from both Blizzard upstream/classic and
    -- upstream/classic_anniversary API documentation.
    unsupportedEvents.UNIT_POWER_POINT_CHARGE = true
    unsupportedEvents.WAR_MODE_STATUS_UPDATE = true
    -- Exists only in upstream/live API documentation.
    unsupportedEvents.PVP_MATCH_STATE_CHANGED = true
end

-- Answers from C_EventUtils.IsEventValid, cached per event name. The client's
-- event set cannot change while it runs, so each name is asked at most once.
local eventValidity = {}

function Client.SupportsEvent(event)
    if type(event) ~= "string" or event == "" or unsupportedEvents[event] == true then
        return false
    end
    local valid = eventValidity[event]
    if valid ~= nil then return valid end
    local eventUtils = _G.C_EventUtils
    local isEventValid = type(eventUtils) == "table" and eventUtils.IsEventValid or nil
    if type(isEventValid) ~= "function" then return true end
    valid = isEventValid(event) == true
    eventValidity[event] = valid
    return valid
end

-- Unit tokens that never exist on a client. Classic Era has no focus unit and
-- no boss or arena encounters; TBC has focus and arenas but no boss units.
-- Mirrors the gates ElvUI applies (Focus/Arena `not Classic`, Boss `not
-- (Classic or TBC)`). Menu pages, copy targets and frame compilation consult
-- this instead of repeating client checks.
local UNSUPPORTED_UNITS_BY_FLAVOR = {
    Vanilla = { "focus", "focustarget", "boss", "arena" },
    TBC = { "boss" },
}
local unsupportedUnits = Client.UnsupportedUnits or {}
Client.UnsupportedUnits = unsupportedUnits
local flavorUnsupportedUnits = UNSUPPORTED_UNITS_BY_FLAVOR[Client.Flavor]
if flavorUnsupportedUnits then
    for i = 1, #flavorUnsupportedUnits do
        unsupportedUnits[flavorUnsupportedUnits[i]] = true
    end
end
-- WoW Forever ships no arena UI: Blizzard excludes Blizzard_PVPUI and
-- CompactArenaFrame for its camelot game type. Focus and boss units stay.
if isForever then unsupportedUnits.arena = true end

-- Arena opponent slots are a client fact, published as Client.MaxArenaOpponents
-- and _G.MSUF_MAX_ARENA_FRAMES: 3 on Mainline, whatever MAX_ARENA_ENEMIES says
-- there, 5 on TBC and Mists, none on Classic Era (no arena units), and none on
-- an Unknown client, the most conservative answer. Mainline never reads the
-- global; its Blizzard_Deprecated_ArenaUI defines it before addons load.
-- On TBC and Mists the MAX_ARENA_ENEMIES read is defensive only. Their
-- Blizzard_ArenaUI is LoadOnDemand and this file loads near the top of every
-- TOC, before it, so in game the global is nil here and they get 5. It only
-- matters on a client that defines the global up front; the detection smoke
-- cases that preset it pin that defensive branch.
local arenaSlots = 0
if unsupportedUnits.arena == true then
    arenaSlots = 0
elseif Client.IsClassic then
    local blizzardSlots = tonumber(_G.MAX_ARENA_ENEMIES)
    arenaSlots = (blizzardSlots and blizzardSlots >= 1) and math.min(math.floor(blizzardSlots), 5) or 5
elseif Client.IsRetail then
    arenaSlots = 3
end
Client.MaxArenaOpponents = arenaSlots
_G.MSUF_MAX_ARENA_FRAMES = arenaSlots

function Client.SupportsUnit(unit)
    if type(unit) ~= "string" or unit == "" then return false end
    local base = unit:match("^(%a+)%d+$") or unit
    return unsupportedUnits[base] ~= true
end

function Client.SupportsGroupKind(kind)
    return kind ~= "mythicraid" or Client.IsRetail == true
end

-- Game rules are Blizzard's switches for what a game mode allows, such as
-- EditModeDisabled or TargetFrameDisabled. Returns true or false, or nil when
-- this client has no such rule or no C_GameRules API. Rule keys differ between
-- clients, so a rule is looked up by key instead of being assumed.
function Client.IsGameRuleActive(ruleKey)
    local enum = _G.Enum
    local rules = type(enum) == "table" and enum.GameRule or nil
    local rule = type(rules) == "table" and type(ruleKey) == "string" and rules[ruleKey] or nil
    local gameRules = _G.C_GameRules
    local isGameRuleActive = type(gameRules) == "table" and gameRules.IsGameRuleActive or nil
    if rule == nil or type(isGameRuleActive) ~= "function" then return nil end
    return isGameRuleActive(rule) == true
end

-- English report lines for /msuf clientinfo, built only when the command runs.
-- Everything here is plain client metadata, never unit data or a secret value.
-- Only the no-argument mode predicates are called; every other C_GameRules Is*
-- function is listed by name, so a new game mode shows up without guessing its
-- API.
local PROJECT_GLOBALS = { "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
    "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC" }
local MODE_PREDICATES = { "IsStandard", "IsPlunderstorm", "IsWoWHack" }
local REPORTED_GAME_RULES = { "EditModeDisabled", "PlayerFrameDisabled", "TargetFrameDisabled",
    "UnitFramePvPContextualDisabled" }
local REPORTED_ADDONS = { "Blizzard_AuraContainer", "Blizzard_CooldownViewer", "Blizzard_EditMode",
    "Blizzard_CompactRaidFrames", "Blizzard_ArenaUI", "Blizzard_PVPUI", "Blizzard_SwingTimer" }

local function JoinOr(list, empty)
    return #list > 0 and table.concat(list, " ") or empty
end

-- DoesAddOnExist comes first: GetAddOnInfo is only asked about an addon this
-- client actually ships.
local function DescribeAddOn(name)
    local addOns = _G.C_AddOns
    local doesAddOnExist = type(addOns) == "table" and addOns.DoesAddOnExist or nil
    if type(doesAddOnExist) ~= "function" then return "unknown" end
    if doesAddOnExist(name) ~= true then return "absent" end
    local isAddOnLoaded = addOns.IsAddOnLoaded
    if type(isAddOnLoaded) == "function" and isAddOnLoaded(name) then return "loaded" end
    local getAddOnInfo = addOns.GetAddOnInfo
    if type(getAddOnInfo) ~= "function" then return "present" end
    local _, _, _, loadable, reason = getAddOnInfo(name)
    return loadable and "loadable" or ("not loadable (" .. tostring(reason) .. ")")
end

function Client.DescribeLines()
    local lines = {}
    local projectName = "unrecognized"
    for i = 1, #PROJECT_GLOBALS do
        local id = _G[PROJECT_GLOBALS[i]]
        if id ~= nil and id == projectID then
            projectName = PROJECT_GLOBALS[i]
            break
        end
    end
    local version, build
    if type(_G.GetBuildInfo) == "function" then
        version, build = _G.GetBuildInfo()
    end
    lines[#lines + 1] = "Project " .. tostring(projectID) .. " (" .. projectName .. "), build "
        .. tostring(version) .. " (" .. tostring(build) .. "), interface " .. tostring(interfaceNumber)
    lines[#lines + 1] = "TOC X-MSUF-Client " .. ((tocFlavor ~= nil and tocFlavor ~= "") and tocFlavor or "none")
        .. "; family " .. Client.Family .. ", flavor " .. Client.Flavor
        .. (Client.IsForever and ", WoW Forever" or "")
        .. (Client.IsSupported and "" or " (not supported)")
    local liveEvent = _G.GameEvent
    local classOrder = _G.CLASS_SORT_ORDER
    lines[#lines + 1] = "Forever marker GameEvent.RegisterCamelotEvents at load " .. tostring(hasCamelotMarker)
        .. ", now " .. tostring(type(liveEvent) == "table" and type(liveEvent.RegisterCamelotEvents) == "function")
        .. "; CLASS_SORT_ORDER " .. (type(classOrder) == "table" and (#classOrder .. " classes") or "missing")

    local gameRules = _G.C_GameRules
    local liveMode
    if type(gameRules) == "table" and type(gameRules.GetActiveGameMode) == "function" then
        liveMode = gameRules.GetActiveGameMode()
    end
    lines[#lines + 1] = "Game mode " .. tostring(gameModeName or "?") .. " (" .. tostring(gameMode) .. ") at load, "
        .. tostring(GameModeKey(liveMode) or "?") .. " (" .. tostring(liveMode) .. ") now"
        .. (Client.GameModeRecognized and "" or "; not recognized")

    if type(gameRules) == "table" then
        local predicates, others, called = {}, {}, {}
        for i = 1, #MODE_PREDICATES do
            local name = MODE_PREDICATES[i]
            called[name] = true
            if type(gameRules[name]) == "function" then
                predicates[#predicates + 1] = name .. "=" .. tostring(gameRules[name]() == true)
            end
        end
        for name, value in pairs(gameRules) do
            if type(name) == "string" and type(value) == "function" and name:find("^Is") and not called[name] then
                others[#others + 1] = name
            end
        end
        table.sort(others)
        lines[#lines + 1] = "C_GameRules " .. JoinOr(predicates, "has no mode predicates")
            .. "; other Is functions: " .. JoinOr(others, "none")
    else
        lines[#lines + 1] = "C_GameRules is missing"
    end

    local rules = {}
    for i = 1, #REPORTED_GAME_RULES do
        local active = Client.IsGameRuleActive(REPORTED_GAME_RULES[i])
        if active ~= nil then rules[#rules + 1] = REPORTED_GAME_RULES[i] .. "=" .. tostring(active) end
    end
    lines[#lines + 1] = "Game rules: " .. JoinOr(rules, "none of the reported rules exist")

    local units = {}
    for unit in pairs(unsupportedUnits) do units[#units + 1] = unit end
    table.sort(units)
    lines[#lines + 1] = "issecretvalue " .. (Client.HasSecretValueAPI and "present" or "missing")
        .. "; arena slots " .. tostring(Client.MaxArenaOpponents)
        .. "; unsupported units: " .. JoinOr(units, "none")

    local addOnStates = {}
    for i = 1, #REPORTED_ADDONS do
        addOnStates[i] = REPORTED_ADDONS[i] .. " " .. DescribeAddOn(REPORTED_ADDONS[i])
    end
    lines[#lines + 1] = "Blizzard addons: " .. table.concat(addOnStates, ", ")
    lines[#lines + 1] = "Login diagnostic: " .. (Client.Diagnostic or "none")
    return lines
end

-- Short aliases match the style used by ElvUI's shared client initializer and
-- make future client splits cheap without introducing per-frame checks.
MSUF.Retail = Client.IsRetail
MSUF.Vanilla = Client.IsVanilla
MSUF.Era = Client.IsEra
MSUF.Mists = Client.IsMists
MSUF.TBC = Client.IsTBC
MSUF.Classic = Client.IsClassic
MSUF.Forever = Client.IsForever

MSUF.Compat = MSUF.Compat or {}
MSUF.Compat.Client = Client

-- One English chat line for a client the detection above cannot fully place.
-- Known clients build no text and create no frame. This file loads before the
-- Kernel, so the EventBus is not available and a single raw frame is used.
do
    local function ClientDetails()
        return "project " .. tostring(projectID) .. ", interface " .. tostring(interfaceNumber)
            .. ", X-MSUF-Client " .. ((tocFlavor ~= nil and tocFlavor ~= "") and tocFlavor or "none")
    end

    local diagnostic
    if not Client.IsSupported then
        diagnostic = "MSUF: unrecognized client (" .. ClientDetails() .. "); no client flavor is active."
    elseif not Client.ProjectIDRecognized then
        diagnostic = "MSUF: unrecognized project ID (" .. ClientDetails() .. "); using the "
            .. Client.Flavor .. " TOC build."
    elseif Client.Family == "Mainline" and not Client.GameModeRecognized then
        -- A new Mainline game mode keeps full Mainline behaviour; the line only
        -- makes the mode visible in bug reports from its first login.
        diagnostic = "MSUF: game mode " .. tostring(gameModeName or "?") .. " (" .. tostring(gameMode)
            .. ") is not recognized (" .. ClientDetails() .. "); running the Mainline build."
            .. " Please report /msuf clientinfo."
    end
    if not Client.HasSecretValueAPI then
        diagnostic = (diagnostic or ("MSUF: " .. Client.Flavor .. " client (" .. ClientDetails() .. ")."))
            .. " The secret-value API (issecretvalue) is missing; unit frames will raise errors."
    end
    Client.Diagnostic = diagnostic

    if diagnostic and type(_G.CreateFrame) == "function" then
        local diagnosticFrame = _G.CreateFrame("Frame")
        diagnosticFrame:RegisterEvent("PLAYER_LOGIN")
        diagnosticFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_LOGIN")
            self:SetScript("OnEvent", nil)
            _G.print(diagnostic)
        end)
    end
end
