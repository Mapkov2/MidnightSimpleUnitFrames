local addonName, MSUF = ...

-- Foreign symbols this file depends on (MiniAuras / MiniCC; undocumented
-- provider API):
--   MiniAurasApi.v1 or MiniCCApi.v1: table whose RegisterFrameProvider(api,
--     provider) accepts MSUF's party/raid frame provider. When neither exists
--     at load, a watcher frame retries on ADDON_LOADED "MiniAuras"/"MiniCC"
--     until PLAYER_LOGIN when the API is absent. A throwing API retains the
--     filtered ADDON_LOADED watcher until registration succeeds.
--   The refresh callback MiniAuras hands to provider.RegisterRefreshFrames:
--     quarantined after a failure until MiniAuras registers another callback.

local GF = MSUF.GF
if not (GF and type(GF.ForEachFrame) == "function"
    and type(GF.RegisterFrameRegistryObserver) == "function") then return end
-- Failed integration calls are reported while independent addon work continues.
local PROVIDER_NAME = "MidnightSimpleUnitFrames"
local OBSERVER_OWNER = addonName or PROVIDER_NAME
local providerFrames = {}
local RunIntegrationCall = MSUF.RunIntegrationCall
local refreshState = { label = "MiniAuras refresh" }
local registrationState = { label = "MiniAuras registration" }
local refreshFrames
local observerRegistered = false
local registered = false
local loadWatcher

local IsGroupUnit = MSUF.Require("MSUF_IsGroupUnitToken", "Integrations/MSUF_Integration_MiniAuras.lua")

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
    if refreshFrames and not refreshState.failed then RunIntegrationCall(refreshState, refreshFrames) end
end

local function RegisterRefreshFrames(callback)
    refreshFrames = type(callback) == "function" and callback or nil
    refreshState.failed = nil
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
    local apiRoot = MiniAurasApi or MiniCCApi
    local api = type(apiRoot) == "table" and apiRoot.v1
    if type(api) ~= "table" or type(api.RegisterFrameProvider) ~= "function" then return false end
    if not RunIntegrationCall(registrationState, api.RegisterFrameProvider, api, provider) then return false end
    registered = true
    StopLoadWatcher()
    return true
end

if TryRegister() or type(CreateFrame) ~= "function" then return end

loadWatcher = CreateFrame("Frame")
loadWatcher:RegisterEvent("ADDON_LOADED")
loadWatcher:RegisterEvent("PLAYER_LOGIN")
loadWatcher:SetScript("OnEvent", function(_, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= "MiniAuras" and loadedAddon ~= "MiniCC" then return end
    if TryRegister() then return end
    if event == "PLAYER_LOGIN" then
        if registrationState.failed then loadWatcher:UnregisterEvent("PLAYER_LOGIN")
        else StopLoadWatcher() end
    end
end)
