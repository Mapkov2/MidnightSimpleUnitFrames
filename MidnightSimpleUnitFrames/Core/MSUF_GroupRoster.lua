local addonName, ns = ...

local Roster = {}
ns.GroupRoster = Roster
_G.MSUF_GroupRoster = Roster

local listeners = {}
local activeUnits = {}
local unitToButtons = {}
local previewMode = nil
local unitEventFrame
local rosterFrame

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }
local RAID_LIMIT = 40

local function CopyList(src, dest)
    dest = dest or {}
    for i = 1, #src do dest[i] = src[i] end
    for i = #src + 1, #dest do dest[i] = nil end
    return dest
end

local function GetDB()
    local db = _G.MSUF_DB
    if not db and type(_G.EnsureDB) == "function" then
        _G.EnsureDB()
        db = _G.MSUF_DB
    end
    return db
end

local function GetPreviewUnits(kind)
    local out = {}
    if kind == "party" then
        for i = 1, 5 do
            out[i] = "preview_party" .. i
        end
    else
        for i = 1, 20 do
            out[i] = "preview_raid" .. i
        end
    end
    return out
end

local function BuildPartyUnits()
    local out = {}
    local count = 0
    if IsInRaid and IsInRaid() then return out end
    local members = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if members <= 0 then return out end
    for i = 1, #PARTY_UNITS do
        local unit = PARTY_UNITS[i]
        if UnitExists and UnitExists(unit) then
            count = count + 1
            out[count] = unit
        end
    end
    return out
end

local function BuildRaidUnits(maxCount)
    local out = {}
    if not (IsInRaid and IsInRaid()) then return out end
    local members = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if members <= 0 then return out end
    local limit = math.min(maxCount or RAID_LIMIT, members, RAID_LIMIT)
    for i = 1, limit do
        out[i] = "raid" .. i
    end
    return out
end

local function RebuildActiveUnits()
    for unit in pairs(activeUnits) do activeUnits[unit] = nil end

    local party = Roster.GetUnits("party")
    for i = 1, #party do activeUnits[party[i]] = true end

    local raid = Roster.GetUnits("raid")
    for i = 1, #raid do activeUnits[raid[i]] = true end
end

local function RegisterUnitEvents()
    if not unitEventFrame then return end
    unitEventFrame:UnregisterAllEvents()
    for unit in pairs(activeUnits) do
        unitEventFrame:RegisterUnitEvent("UNIT_HEALTH", unit)
        unitEventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
        unitEventFrame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
        unitEventFrame:RegisterUnitEvent("UNIT_CONNECTION", unit)
        unitEventFrame:RegisterUnitEvent("UNIT_FLAGS", unit)
        unitEventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
    end
end

local function Notify(event, payload)
    for i = 1, #listeners do
        local fn = listeners[i]
        if type(fn) == "function" then
            pcall(fn, event, payload)
        end
    end
end

function Roster.RegisterListener(fn)
    if type(fn) ~= "function" then return end
    listeners[#listeners + 1] = fn
end

function Roster.SetPreviewMode(mode)
    if mode ~= "party" and mode ~= "raid" then mode = nil end
    if previewMode == mode then return end
    previewMode = mode
    RebuildActiveUnits()
    RegisterUnitEvents()
    Notify("preview", mode)
    Notify("roster")
end

function Roster.GetPreviewMode()
    return previewMode
end

function Roster.GetUnits(kind)
    if previewMode == kind then
        return GetPreviewUnits(kind)
    end
    if kind == "party" then
        return BuildPartyUnits()
    end
    local db = GetDB()
    local gf = db and db.groupFrames and db.groupFrames.raid
    local maxCount = (gf and gf.maxFrames) or RAID_LIMIT
    return BuildRaidUnits(maxCount)
end

function Roster.RegisterButton(unit, button)
    if not unit or not button then return end
    local list = unitToButtons[unit]
    if not list then
        list = {}
        unitToButtons[unit] = list
    end
    list[#list + 1] = button
end

function Roster.ClearButtonMap(button)
    for unit, list in pairs(unitToButtons) do
        local n = 0
        for i = 1, #list do
            if list[i] ~= button then
                n = n + 1
                list[n] = list[i]
            end
        end
        for i = n + 1, #list do list[i] = nil end
        if n == 0 then unitToButtons[unit] = nil end
    end
end

function Roster.IterButtons(unit)
    return unitToButtons[unit]
end

function Roster.Refresh()
    RebuildActiveUnits()
    RegisterUnitEvents()
    Notify("roster")
end

local function OnUnitEvent(_, event, unit)
    local buttons = unit and unitToButtons[unit]
    if buttons and #buttons > 0 then
        Notify("unit", unit)
    else
        Notify("unit", unit)
    end
end

local function OnRosterEvent(_, event)
    if event == "PLAYER_LOGIN" then
        rosterFrame:UnregisterEvent("PLAYER_LOGIN")
    end
    Roster.Refresh()
end

function Roster.Ensure()
    if rosterFrame then return end

    rosterFrame = CreateFrame("Frame", "MSUF_GroupRosterFrame")
    rosterFrame:RegisterEvent("PLAYER_LOGIN")
    rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterFrame:SetScript("OnEvent", OnRosterEvent)

    unitEventFrame = CreateFrame("Frame", "MSUF_GroupRosterUnitFrame")
    unitEventFrame:SetScript("OnEvent", OnUnitEvent)
end

Roster.Ensure()
