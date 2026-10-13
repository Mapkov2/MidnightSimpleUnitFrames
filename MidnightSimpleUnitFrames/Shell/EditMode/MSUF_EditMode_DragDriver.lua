-- One dormant driver for Edit Mode drag strategies and their input capture.
-- Subscription changes copy the list; a running tick retains its original list.
local _, MSUF = ...
local Driver = {}
MSUF.EditModeDragDriver = Driver
local frame
local listeners, owners = {}, {}
local RunEach = secureexecuterange
if type(RunEach) ~= "function" then
    RunEach = function(list, callback, ...)
        for i = 1, #list do MSUF.RunHostAPIStep("EditMode.Drag", callback, i, list[i], ...) end
    end
end
local Refresh, HasVisibleOwner
local hookedOwners = setmetatable({}, { __mode = "k" })

local function OwnerVisible(owner)
    if owner.IsVisible then return owner:IsVisible() end
    return not owner.IsShown or owner:IsShown()
end

-- The client isolates each owner, reports a raise, and resumes the range.
-- No mutable dispatch depth spans owner code; tombstones cancel old records.
local function Deliver(_, record, elapsed)
    local owner = record.owner
    if not record.active then return end
    if OwnerVisible(owner) then
        record.callback(owner, elapsed)
    elseif not HasVisibleOwner() then
        -- Parent visibility may change without an owner OnHide notification.
        Refresh()
    end
end

local function OnUpdate(_, elapsed)
    RunEach(listeners, Deliver, elapsed)
end

function Driver.GetFrame()
    if not frame then
        local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/EditMode/MSUF_EditMode_DragDriver.lua")
        frame = PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_TickerFrame", UIParent))
        frame:Hide()
    end
    return frame
end

HasVisibleOwner = function()
    for i = 1, #listeners do
        local owner = listeners[i].owner
        if owner == frame or OwnerVisible(owner) then return true end
    end
    return false
end

Refresh = function()
    if not frame then return end
    if not HasVisibleOwner() then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    else
        frame:SetScript("OnUpdate", OnUpdate)
        frame:Show()
    end
end

function Driver.Detach(owner)
    local record = owners[owner]
    if not record then return end
    record.active = false
    owners[owner] = nil
    local nextList = {}
    for i = 1, #listeners do
        if listeners[i].active then nextList[#nextList + 1] = listeners[i] end
    end
    listeners = nextList
    Refresh()
end

function Driver.Attach(owner, callback)
    Driver.GetFrame()
    Driver.Detach(owner)
    if owner ~= frame and owner.HookScript and not hookedOwners[owner] then
        hookedOwners[owner] = true
        owner:HookScript("OnShow", Refresh)
        owner:HookScript("OnHide", Refresh)
    end
    local record = { owner = owner, callback = callback, active = true }
    local nextList = {}
    for i = 1, #listeners do nextList[i] = listeners[i] end
    nextList[#nextList + 1] = record
    listeners, owners[owner] = nextList, record
    Refresh()
end

function Driver.Clear()
    for i = 1, #listeners do listeners[i].active = false end
    listeners, owners = {}, {}
    Refresh()
end

function Driver.IsRunning()
    return frame ~= nil and frame:GetScript("OnUpdate") ~= nil
end
