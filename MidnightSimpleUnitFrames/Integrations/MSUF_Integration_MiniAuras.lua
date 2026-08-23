local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local GF = MSUF.GF
if not (GF and type(GF.ForEachFrame) == "function"
    and type(GF.RegisterFrameRegistryObserver) == "function") then return end

local PROVIDER_NAME = "MidnightSimpleUnitFrames"
local OBSERVER_OWNER = addonName or PROVIDER_NAME
local providerFrames = {}
local refreshFrames
local observerRegistered = false
local registered = false
local loadWatcher

local function IsGroupUnit(unit)
    return type(unit) == "string"
        and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
end

local function CollectFrame(frame, unit)
    if frame and frame._msufGFIsPreviewFrame ~= true and IsGroupUnit(unit) then
        providerFrames[#providerFrames + 1] = frame
    end
end

local function GetFrames()
    for i = #providerFrames, 1, -1 do providerFrames[i] = nil end
    GF.ForEachFrame(CollectFrame, true)
    return providerFrames
end

local function RequestRefresh()
    if refreshFrames then pcall(refreshFrames) end
end

local function RegisterRefreshFrames(callback)
    refreshFrames = type(callback) == "function" and callback or nil
    if not observerRegistered then
        observerRegistered = GF.RegisterFrameRegistryObserver(OBSERVER_OWNER, RequestRefresh) == true
    end
    RequestRefresh()
end

local provider = {
    Name = PROVIDER_NAME,
    GetFrames = GetFrames,
    RegisterRefreshFrames = RegisterRefreshFrames,
}

local function StopLoadWatcher()
    if not loadWatcher then return end
    loadWatcher:UnregisterEvent("ADDON_LOADED")
    loadWatcher:UnregisterEvent("PLAYER_LOGIN")
    loadWatcher:SetScript("OnEvent", nil)
    loadWatcher = nil
end

local function TryRegister()
    if registered then return true end
    local apiRoot = _G.MiniAurasApi or _G.MiniCCApi
    local api = type(apiRoot) == "table" and apiRoot.v1
    if type(api) ~= "table" or type(api.RegisterFrameProvider) ~= "function" then return false end
    if not pcall(api.RegisterFrameProvider, api, provider) then return false end
    registered = true
    StopLoadWatcher()
    return true
end

if TryRegister() or type(_G.CreateFrame) ~= "function" then return end

loadWatcher = _G.CreateFrame("Frame")
loadWatcher:RegisterEvent("ADDON_LOADED")
loadWatcher:RegisterEvent("PLAYER_LOGIN")
loadWatcher:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= "MiniAuras" and loadedAddon ~= "MiniCC" then return end
    if TryRegister() or event == "PLAYER_LOGIN" then StopLoadWatcher() end
end)
