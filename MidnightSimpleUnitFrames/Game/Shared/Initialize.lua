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

local function ReadTOCField(field)
    local getMetadata = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    if type(getMetadata) ~= "function" then return nil end
    return getMetadata(addonName, field)
end

local tocFlavor = ReadTOCField("X-MSUF-Client")
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
-- Blizzard calls "Camelot" a placeholder name. When the marker is renamed, the
-- new name goes in front of this list and the old one stays, so both builds
-- keep working; the audit's marker contract names the break.
local FOREVER_MARKERS = { "RegisterCamelotEvents" }
local gameEvent = _G.GameEvent
local foreverMarker
if type(gameEvent) == "table" then
    for i = 1, #FOREVER_MARKERS do
        if type(gameEvent[FOREVER_MARKERS[i]]) == "function" then
            foreverMarker = FOREVER_MARKERS[i]
            break
        end
    end
end
local hasCamelotMarker = foreverMarker ~= nil
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
-- The interface number of the running build, read once above. Nothing else may
-- call GetBuildInfo for it: the value cannot change while the client runs.
Client.Interface = interfaceNumber
Client.Flavor = isVanilla and "Vanilla" or isMists and "Mists" or isTBC and "TBC"
    or isRetail and "Mainline" or "Unknown"
Client.IsRetail = isRetail
Client.IsVanilla = isVanilla
Client.IsMists = isMists
Client.IsTBC = isTBC
Client.IsClassic = isVanilla or isMists or isTBC
-- Hunter pet happiness: Classic Era and TBC through the global GetPetHappiness,
-- WoW Forever through C_PetInfo.GetPetHappiness (Blizzard's Forever pet frame
-- shows it). Cataclysm removed it, so Mists and Midnight have none.
Client.SupportsPetHappiness = isVanilla or isTBC or isForever
-- Mob tagging: the first player to hit a mob owns its loot and experience, and
-- Blizzard grays the target for everyone else (UnitIsTapDenied). Every Classic
-- client and WoW Forever have it; Midnight needs no MSUF handling.
Client.SupportsTapDenied = isVanilla or isMists or isTBC or isForever
-- Threat percentage text on the target, focus and boss frames. Every client has
-- UnitDetailedThreatSituation; the owner offers the text on Classic Era, TBC and
-- WoW Forever (2026-09-19), so Mists and Midnight menus stay unchanged.
Client.SupportsThreatText = isVanilla or isTBC or isForever
-- WoW Forever characters carry a surname next to their first name (Blizzard's
-- Camelot NameUtil). No other client has one.
Client.HasCharacterSurnames = isForever
-- Empowered casts are an Evoker mechanic. WoW Forever has nine classes and no
-- Evoker, and no Classic client has one, so only Midnight offers the controls.
Client.HasEmpoweredCasts = isRetail and not isForever
-- One-time onboarding: the first-start welcome scene and the upgrade highlights.
-- The WoW Forever beta client does not keep SavedVariables between sessions, a
-- Blizzard bug that hits every addon. Both lifecycles live in those variables,
-- so every login reads as a clean install and would greet the player again.
-- Restore this once Forever persists settings.
Client.SupportsOnboardingScenes = not isForever
-- The aura filter that returns the debuffs this player can dispel. Classic Era
-- keeps the original meaning of HARMFUL|RAID, the filter Blizzard's own "show
-- dispellable debuffs" party frames scan there, and does not honour
-- RAID_PLAYER_DISPELLABLE (dispel visuals stayed dark on Era only, in-game
-- report 2026-09-16). TBC, Mists and Mainline use RAID_PLAYER_DISPELLABLE.
Client.DispellableDebuffFilter = isVanilla and "HARMFUL|RAID" or "HARMFUL|RAID_PLAYER_DISPELLABLE"
-- EllesmereUI's Edit Mode runs on both Mainline-family clients, Midnight and
-- WoW Forever (confirmed in game by the owner, 2026-09-19); no Classic client
-- has it, so the Mainline family is the right answer here.
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

-- Whether this client can host Blizzard's Cooldown Manager at all, and with it
-- the Essential Cooldown anchor. The feature belongs to Blizzard_CooldownViewer,
-- whose TOC allows the Mainline game types only (standard, plus camelot on WoW
-- Forever); the C_CooldownViewer namespace, by contrast, lives in the shared
-- engine and exists on Classic Era, TBC and Mists too, so that namespace alone
-- is not a client signal and must never be used as one. The code family answers
-- first, the owning Blizzard addon has to be part of this build, and the engine
-- namespace is the last conjunct so a build without the API still answers no.
-- The addon state can only say no: a client whose addon API cannot be read keeps
-- the family answer instead of losing the anchor. Addons cannot be installed
-- mid-session, so this is a fixed fact, resolved once here rather than probed on
-- every anchor resolve.
local function ShipsBlizzardAddOn(name)
    local addOns = _G.C_AddOns
    local doesAddOnExist = type(addOns) == "table" and addOns.DoesAddOnExist or nil
    if type(doesAddOnExist) ~= "function" then return nil end
    return doesAddOnExist(name) == true
end
Client.HostsCooldownManager = Client.Family == "Mainline"
    and ShipsBlizzardAddOn("Blizzard_CooldownViewer") ~= false
    and type(_G.C_CooldownViewer) == "table"

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

-- Class resource modes implemented by this client's provider. Enum.PowerType
-- alone is not evidence: old clients expose tokens for resources they lack.
-- Sources: upstream/{classic_era,classic_anniversary,classic,forever}
-- Blizzard_UnitFrame TOCs and Game/<Flavor>/ClassPower.lua. Mists' provider
-- owns Chi (all Monk specs), not the separate Blizzard Stagger display.
local classResources = {}
local resourceNames
if isRetail and not isForever then
    resourceNames = "COMBO_POINTS RUNES HOLY_POWER SOUL_SHARDS CHI ARCANE_CHARGES ESSENCE "
        .. "CHARGED SOUL_FRAGMENTS SOUL_FRAGMENTS_META SOUL_FRAGMENTS_VENG MAELSTROM MAELSTROM_ABOVE_5 "
        .. "MAELSTROM_POWER ASTRAL_POWER AP_PREDICTION ECLIPSE_SOLAR ECLIPSE_LUNAR ECLIPSE_CA "
        .. "STAGGER_GREEN STAGGER_YELLOW STAGGER_RED INSANITY WHIRLWIND TIP_OF_THE_SPEAR "
        .. "ICICLES EBON_MIGHT IRONFUR SWEEPING_STRIKES NO_CLASS_BAR MANA RESOURCE_TEXT"
elseif isMists then
    resourceNames = "COMBO_POINTS RUNES HOLY_POWER SOUL_SHARDS CHI ARCANE_CHARGES MISTS_ARCANE_CHARGES "
        .. "SHADOW_ORBS BURNING_EMBERS DEMONIC_FURY ECLIPSE_SOLAR ECLIPSE_LUNAR ECLIPSE_CA MANA RESOURCE_TEXT"
elseif isVanilla or isTBC or isForever then
    resourceNames = "COMBO_POINTS MANA RESOURCE_TEXT"
end
for resource in (resourceNames or ""):gmatch("%S+") do classResources[resource] = true end
function Client.SupportsClassResource(resource)
    return classResources[resource] == true
end
local classResourceSettings = {
    ["bars.showChargedComboPoints"] = "CHARGED",
    ["bars.runeShowTime"] = "RUNES",
    ["bars.showSweepingStrikes"] = "SWEEPING_STRIKES",
    ["bars.showEleMaelstrom"] = "MAELSTROM_POWER",
    ["bars.showEbonMight"] = "EBON_MIGHT",
    ["bars.showShadowMana"] = "INSANITY",
    ["bars.showGuardianIronfur"] = "IRONFUR",
    ["bars.guardianIronfurShowHashLines"] = "IRONFUR",
}
function Client.SupportsClassResourceSetting(settingKey)
    if settingKey == "bars.classPowerAnchorToCooldown" then return Client.HostsCooldownManager == true end
    local resource = classResourceSettings[settingKey]
    return resource == nil or Client.SupportsClassResource(resource)
end

-- The MSUF version of this client, read once here so nothing asks the TOC again.
-- Every client TOC owns its "## Version", so clients can follow their own patch
-- cycle. WoW Forever shares the _Mainline.toc files with Midnight and cannot
-- own that field; its version is the core TOC's "## X-MSUF-Version-Forever".
-- A game mode that shares a TOC later gets its own X-MSUF-Version-<Mode> field.
-- The _Mainline.toc Version lines are conditioned on the game type, so the AddOn
-- list shows the right number too. The Forever field stays the source here, and
-- a condition a client hands back as text is cut off.
local addonVersion = isForever and ReadTOCField("X-MSUF-Version-Forever") or nil
if type(addonVersion) ~= "string" or addonVersion == "" then
    addonVersion = ReadTOCField("Version")
end
if type(addonVersion) == "string" then
    addonVersion = addonVersion:gsub("%s*%[.*$", "")
end
Client.AddonVersion = type(addonVersion) == "string" and addonVersion ~= "" and addonVersion or nil

--- The one MSUF version accessor, for chat lines, tooltips and bug reports.
--- Client.AddonVersion above is resolved once, from the TOC this client loaded,
--- so no other file may ask a TOC again: the Options and Assistant packages
--- carry their own "## Version" field, and a Mainline TOC carries one
--- conditioned line per game type. Returns nil when detection did not run;
--- callers that need a placeholder keep their own.
function MSUF.GetAddonVersion()
    return Client.AddonVersion
end

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
-- An unplaced client gets no arena slots below, so the unit answer must agree:
-- arena frames without castbars or trinkets would be half a feature.
if Client.Flavor == "Unknown" then unsupportedUnits.arena = true end

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

-- The Mythic Raid scope belongs to Midnight's fixed 20-player Mythic difficulty.
-- The Classic clients have no such difficulty, and WoW Forever has only
-- 5-player groups and raids, so they keep Party and Raid.
function Client.SupportsGroupKind(kind)
    return kind ~= "mythicraid" or (Client.IsRetail == true and not isForever)
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
        .. "; MSUF " .. tostring(Client.AddonVersion)
    local liveEvent = _G.GameEvent
    local classOrder = _G.CLASS_SORT_ORDER
    local markerNow = false
    if type(liveEvent) == "table" then
        for i = 1, #FOREVER_MARKERS do
            if type(liveEvent[FOREVER_MARKERS[i]]) == "function" then markerNow = true break end
        end
    end
    lines[#lines + 1] = "Forever marker GameEvent." .. (foreverMarker or FOREVER_MARKERS[1])
        .. " at load " .. tostring(hasCamelotMarker) .. ", now " .. tostring(markerNow)
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

    -- WoW Forever has its own pet happiness API and character surnames. The report
    -- names what exists and never prints a name. Both functions take no arguments.
    local petInfo, playerInfo, constants = _G.C_PetInfo, _G.C_PlayerInfo, _G.Constants
    local function Presence(value) return type(value) == "function" and "present" or "missing" end
    local function Flag(fn) return type(fn) == "function" and tostring(fn() == true) or "missing" end
    local function Quoted(value) return value ~= nil and ('"' .. tostring(value) .. '"') or "missing" end
    lines[#lines + 1] = "Pet happiness " .. (Client.SupportsPetHappiness and "supported" or "not supported")
        .. "; C_PetInfo.GetPetHappiness " .. Presence(type(petInfo) == "table" and petInfo.GetPetHappiness)
        .. ", GetPetHappiness " .. Presence(_G.GetPetHappiness)
    local secondName = "unavailable"
    if type(_G.UnitName) == "function" then
        local _, second = _G.UnitName("player")
        local isSecret = _G.issecretvalue
        if type(isSecret) == "function" and isSecret(second) then
            secondName = "secret"
        elseif second == nil then
            secondName = "nil"
        else
            secondName = second == "" and "empty" or "present"
        end
    end
    local separators = type(constants) == "table" and constants.CharacterNameSeparatorConsts
    if type(separators) ~= "table" then separators = nil end
    lines[#lines + 1] = "Names: RegionalUniqueNamesEnabled " .. Flag(_G.RegionalUniqueNamesEnabled)
        .. ", C_PlayerInfo.ShouldDisplaySurname "
        .. Flag(type(playerInfo) == "table" and playerInfo.ShouldDisplaySurname)
        .. ", surname separator " .. Quoted(separators and separators.CHARACTERNAME_SURNAME_SEPARATOR)
        .. ", realm separator " .. Quoted(separators and separators.CHARACTERNAME_REALMNAME_SEPARATOR)
        .. ", UnitName(player) second return " .. secondName

    local addOnStates = {}
    for i = 1, #REPORTED_ADDONS do
        addOnStates[i] = REPORTED_ADDONS[i] .. " " .. DescribeAddOn(REPORTED_ADDONS[i])
    end
    lines[#lines + 1] = "Blizzard addons: " .. table.concat(addOnStates, ", ")
    lines[#lines + 1] = "Login diagnostic: " .. (Client.Diagnostic or "none")
    return lines
end

-- MSUF.Client is the single client surface. The short MSUF.Retail/Vanilla/Era/
-- Mists/TBC/Classic/Forever aliases and the MSUF.Compat.Client bridge that used
-- to sit here had no reader in any of the three addons and were removed; new
-- code branches on Client.Is* or, better, on a named capability above.

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
    elseif Client.Family == "Mainline" and not isForever
        and interfaceNumber ~= nil and interfaceNumber < 100000 then
        -- Midnight interface numbers start at 120000; WoW Forever reports 16001.
        -- A Mainline client below that range without the marker is most likely
        -- Forever after Blizzard renamed the marker. Detection never keys on the
        -- interface number, so behaviour stays Midnight; the line only makes the
        -- miss visible from the first login instead of failing silently.
        diagnostic = "MSUF: Mainline client with interface " .. tostring(interfaceNumber)
            .. " but without the WoW Forever marker (" .. ClientDetails() .. "); running the Midnight build."
            .. " Please report /msuf clientinfo."
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
