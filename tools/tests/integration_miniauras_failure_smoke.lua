-- Third-party registration/refresh failures stay isolated and retryable.
local root = assert(arg[1])
local function Run(mode)
local frames, reports, calls, observer, supplied = {}, {}, 0
local env = setmetatable({}, { __index = _G })
env._G = env
env.geterrorhandler = function() return function(message)
    reports[#reports + 1] = message
    if env.reportThrows then error("reporter failed") end
end end
local ns = { ExportPublic = function() end }
ns.Require = function() return function(unit) return unit == "party1" end end
ns.GF = { ForEachFrame = function(callback) callback({}, "party1") end,
    RegisterFrameRegistryObserver = function(_, callback) observer = callback; return true end }
env.CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, callback) self.callback = callback end
    frames[#frames + 1] = frame
    return frame
end
local function Load(path)
    local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))
    setfenv(chunk, env)("MidnightSimpleUnitFrames", ns)
end
Load("Kernel/MSUF_Boundary.lua")
env.MiniAurasApi = { v1 = { RegisterFrameProvider = function(_, provider)
    calls = calls + 1
    if calls == 1 or (mode == "after-login" and calls == 2) then error("foreign registration failed") end
    supplied = provider
end } }
if mode == "absent" then env.MiniAurasApi = nil end
env.reportThrows = true
local ok, err = pcall(Load, "Integrations/MSUF_Integration_MiniAuras.lua")
assert(ok, "foreign registration escaped boundary: " .. tostring(err))
if mode == "absent" then
    local watcher = assert(frames[1], "absent API has no discovery watcher")
    watcher.callback(watcher, "PLAYER_LOGIN")
    assert(watcher.callback == nil and not watcher.events.ADDON_LOADED and not watcher.events.PLAYER_LOGIN,
        "absent API discovery did not stop at login")
    return
end
assert(calls == 1 and #reports == 1, "registration failure not reported once")
local watcher = assert(frames[1], "failed registration left no retry watcher")
assert(watcher.events.ADDON_LOADED and watcher.events.PLAYER_LOGIN)
watcher.callback(watcher, "ADDON_LOADED", "Unrelated")
assert(calls == 1, "unrelated load retried integration")
if mode == "after-login" then
    watcher.callback(watcher, "PLAYER_LOGIN")
    assert(calls == 2 and watcher.callback and watcher.events.ADDON_LOADED and not watcher.events.PLAYER_LOGIN,
        "login registration failure permanently removed retry watcher")
end
local registrationCalls = mode == "after-login" and 3 or 2
local registrationReports = registrationCalls - 1
watcher.callback(watcher, "ADDON_LOADED", "MiniAuras")
assert(calls == registrationCalls and supplied and watcher.callback == nil, "registration did not recover")
local refreshCalls = 0
supplied.RegisterRefreshFrames(function() refreshCalls = refreshCalls + 1; error("foreign refresh failed") end)
assert(refreshCalls == 1 and #reports == registrationReports + 1, "refresh failure escaped or was not reported")
observer()
observer()
assert(refreshCalls == 1 and #reports == registrationReports + 1, "failed refresh was not quarantined")
supplied.RegisterRefreshFrames(function() refreshCalls = refreshCalls + 1 end)
observer()
assert(refreshCalls == 3, "refresh re-registration did not recover")
end
Run("before-login")
Run("after-login")
Run("absent")
print("PASS integration_miniauras_failure_smoke")
