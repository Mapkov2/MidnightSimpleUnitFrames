local addonName, MSUF = ...

-- Foreign symbols this file depends on (MiniAuras / MiniCC; undocumented
-- provider API):
--   MiniAurasApi.v1 or MiniCCApi.v1: table whose RegisterFrameProvider(api,
--     provider) accepts MSUF's party/raid frame provider. When neither exists
--     at load, a watcher frame retries on ADDON_LOADED "MiniAuras"/"MiniCC"
--     and gives up at PLAYER_LOGIN; MiniAuras then never sees MSUF's group
--     frames. A registration that raises counts as absent.
--   The refresh callback MiniAuras hands to provider.RegisterRefreshFrames:
--     isolated on every frame-registry change; errors retain the callback stack.

MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local GF = MSUF.GF
if not (GF and type(GF.ForEachFrame) == "function"
    and type(GF.RegisterFrameRegistryObserver) == "function") then return end
-- Failed integration calls are reported while independent addon work continues.
local PROVIDER_NAME = "MidnightSimpleUnitFrames"
local OBSERVER_OWNER = addonName or PROVIDER_NAME
local providerFrames = {}
local refreshFrames
local observerRegistered = false
local registered = false
local loadWatcher

local IsGroupUnit = _G.MSUF_IsGroupUnitToken

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
    if refreshFrames then refreshFrames() end
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
    api:RegisterFrameProvider(provider)
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
