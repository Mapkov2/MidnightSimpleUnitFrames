local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local Group = ns.Group
local pairs = pairs
local UnitInRange = UnitInRange
local issecretvalue = _G.issecretvalue
local ticker
local owner = {}

local function Shared()
    local db = _G.MSUF_DB and _G.MSUF_DB.group and _G.MSUF_DB.group.shared
    return db or {}
end

local function ApplyRange(unit)
    local frame = Group.activeFrames and Group.activeFrames[unit]
    if not frame then return end
    local sh = Shared()
    if sh.rangeFade == false then
        frame:SetAlpha(1)
        return
    end
    local inRange, checked
    if UnitInRange then
        inRange, checked = UnitInRange(unit)
    end
    if issecretvalue and ((inRange ~= nil and issecretvalue(inRange)) or (checked ~= nil and issecretvalue(checked))) then
        inRange = nil
    end
    local alpha = (inRange == false) and (sh.rangeFadeAlpha or 0.4) or 1
    if frame._lastRangeAlpha ~= alpha then
        frame._lastRangeAlpha = alpha
        frame:SetAlpha(alpha)
    end
end

local function UnitHandler(_, event, unit)
    ApplyRange(unit)
end

function _G.MSUF_GroupRange_RefreshAll()
    if not Group.activeFrames then return end
    for unit in pairs(Group.activeFrames) do
        ApplyRange(unit)
    end
end

local function EnsureTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(0.5, function()
        local roster = Group.roster or {}
        if roster.type == "raid" then
            _G.MSUF_GroupRange_RefreshAll()
        end
    end)
end

EnsureTicker()
Group.AddUnitEvent(owner, "UNIT_IN_RANGE_UPDATE", UnitHandler)
