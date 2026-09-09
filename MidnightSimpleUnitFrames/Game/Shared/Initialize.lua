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
local isVanilla = (vanillaID ~= nil and projectID == vanillaID) or tocFlavor == "vanilla"
local isMists = (mistsID ~= nil and projectID == mistsID) or tocFlavor == "mists"
local isTBC = (tbcID ~= nil and projectID == tbcID) or tocFlavor == "tbc"

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
Client.IsSupported = isRetail or isVanilla or isMists or isTBC

local unsupportedEvents = Client.UnsupportedEvents or {}
Client.UnsupportedEvents = unsupportedEvents
if Client.IsClassic then
    -- Confirmed absent from both Blizzard upstream/classic and
    -- upstream/classic_anniversary API documentation.
    unsupportedEvents.UNIT_POWER_POINT_CHARGE = true
    unsupportedEvents.WAR_MODE_STATUS_UPDATE = true
end

function Client.SupportsEvent(event)
    return type(event) == "string" and event ~= "" and unsupportedEvents[event] ~= true
end

-- Unit tokens that never exist on a client. Classic Era has no focus unit and
-- no boss or arena encounters; TBC has focus and arenas but no boss units.
-- Mirrors the gates ElvUI applies (Focus/Arena `not Classic`, Boss `not
-- (Classic or TBC)`). Menu pages, copy targets and frame compilation consult
-- this instead of repeating client checks.
local unsupportedUnits = Client.UnsupportedUnits or {}
Client.UnsupportedUnits = unsupportedUnits
if isVanilla then
    unsupportedUnits.focus = true
    unsupportedUnits.focustarget = true
    unsupportedUnits.boss = true
    unsupportedUnits.arena = true
elseif isTBC then
    unsupportedUnits.boss = true
end

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
