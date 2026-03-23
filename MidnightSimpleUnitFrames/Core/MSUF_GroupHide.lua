local addonName, ns = ...
ns = ns or {}
ns.Group = ns.Group or {}

local hiddenFrames = {
    "PartyFrame",
    "CompactPartyFrame",
    "CompactRaidFrameContainer",
    "CompactRaidFrameManager",
}

local hiddenMembers = {
    "CompactPartyFrameMember",
    "CompactRaidFrame",
}

local blizzardHidden = false
local pendingSync = false

local function GetGroupDB()
    local db = _G.MSUF_DB
    return db and db.group
end

local function ShouldHideBlizzard()
    local groupDB = GetGroupDB()
    if not groupDB then return false end
    if groupDB.enabled == false then return false end
    return groupDB.hideBlizzard ~= false
end

local function HideFrame(frame)
    if not frame then return end
    frame:Hide()
    if not frame._msufGroupHideHooked then
        frame._msufGroupHideHooked = true
        hooksecurefunc(frame, "Show", function(self)
            if ShouldHideBlizzard() then
                self:Hide()
            end
        end)
        if frame.SetShown then
            hooksecurefunc(frame, "SetShown", function(self, shown)
                if shown and ShouldHideBlizzard() then
                    self:Hide()
                end
            end)
        end
    end
end

local function RestoreFrame(frame)
    if not frame then return end
    frame:Show()
end

local function ForEachBlizzardGroupFrame(fn)
    for i = 1, #hiddenFrames do
        fn(_G[hiddenFrames[i]])
    end
    for i = 1, 4 do
        fn(_G[hiddenMembers[1] .. i])
    end
    for i = 1, 40 do
        fn(_G[hiddenMembers[2] .. i])
    end
end

local function ApplySync()
    pendingSync = false
    local shouldHide = ShouldHideBlizzard()
    if shouldHide then
        ForEachBlizzardGroupFrame(HideFrame)
        blizzardHidden = true
    elseif blizzardHidden then
        ForEachBlizzardGroupFrame(RestoreFrame)
        if type(_G.CompactRaidFrameManager_UpdateShown) == "function" then
            pcall(_G.CompactRaidFrameManager_UpdateShown, _G.CompactRaidFrameManager)
        end
        blizzardHidden = false
    end
end

function _G.MSUF_SyncBlizzardGroupFrames()
    if InCombatLockdown and InCombatLockdown() then
        pendingSync = true
        return
    end
    ApplySync()
end

local function SyncLater()
    C_Timer.After(0.5, function()
        _G.MSUF_SyncBlizzardGroupFrames()
    end)
end

if type(_G.MSUF_EventBus_Register) == "function" then
    _G.MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_GROUP_HIDE_LOGIN", SyncLater)
    _G.MSUF_EventBus_Register("PLAYER_ENTERING_WORLD", "MSUF_GROUP_HIDE_WORLD", SyncLater)
    _G.MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_GROUP_HIDE_REGEN", function()
        if pendingSync then
            ApplySync()
        end
    end)
end
