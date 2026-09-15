--- Client flavor detection shared by Retail and the supported Classic clients.
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
Client.SupportsEllesmereEditMode = isRetail
Client.SupportsBlizzardEditMode = type(_G.Enum) == "table" and type(_G.Enum.EditModeSystem) == "table"
Client.IsSupported = isRetail or isVanilla or isMists or isTBC
Client.TOCFlavor = tocFlavor
Client.ProjectIDRecognized = isRetail or projectIsVanilla or projectIsMists or projectIsTBC
-- Capability fact only. Never define a global issecretvalue fallback here:
-- other addons probe that global to detect the secret-value API.
Client.HasSecretValueAPI = type(_G.issecretvalue) == "function"
-- Placeholder until Blizzard publishes a real Forever client fact. Never invent
-- a Forever project ID, interface number or TOC suffix.
Client.IsForever = false

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

-- Arena opponent slots are a client fact, published as Client.MaxArenaOpponents
-- and _G.MSUF_MAX_ARENA_FRAMES: 3 on Mainline (MSUF keeps 3 arena frames there
-- even though Retail's Blizzard_ArenaUI defines MAX_ARENA_ENEMIES = 5), 5 on TBC
-- and Mists, none on Classic Era (no arena units), and none on an Unknown
-- client, the most conservative answer.
-- The MAX_ARENA_ENEMIES read is defensive only. Blizzard_ArenaUI is LoadOnDemand
-- and this file loads near the top of every TOC, before it, so in game the
-- global is always nil here and TBC/Mists always get 5. It only matters on a
-- client that defines the global up front; the detection smoke cases that
-- preset it pin that defensive branch.
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

-- Short aliases match the style used by ElvUI's shared client initializer and
-- make future client splits cheap without introducing per-frame checks.
MSUF.Retail = Client.IsRetail
MSUF.Vanilla = Client.IsVanilla
MSUF.Era = Client.IsEra
MSUF.Mists = Client.IsMists
MSUF.TBC = Client.IsTBC
MSUF.Classic = Client.IsClassic

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
