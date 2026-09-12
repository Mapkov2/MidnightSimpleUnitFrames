--- Public MSUF Edit Mode API transaction and registration contract.
_G = _G or _ENV

local function ResolvePath(relative)
    local candidates = { "MidnightSimpleUnitFrames/" .. relative, relative }
    for i = 1, #candidates do
        local handle = io.open(candidates[i], "r")
        if handle then handle:close(); return candidates[i] end
    end
    error("cannot locate " .. relative)
end

local registry = {}
local refreshes, historySyncs = 0, 0
local undo = { begin = 0, commit = 0, cancel = 0 }
_G.MSUF_EM2 = {
    Registry = {
        Register = function(config) registry[config.key] = config end,
        Unregister = function(key) registry[key] = nil end,
        Get = function(key) return registry[key] end,
    },
    State = {
        IsActive = function() return true end,
        GetProvider = function() return "msuf" end,
        SetUnitKey = function() end,
    },
    Movers = { SyncAll = function() refreshes = refreshes + 1 end, Remove = function() end },
    HUD = { RefreshControls = function() refreshes = refreshes + 1 end },
    Undo = {
        BeginChange = function() undo.begin = undo.begin + 1; return true end,
        CommitChange = function() undo.commit = undo.commit + 1; return true end,
        CancelChange = function() undo.cancel = undo.cancel + 1; return true end,
    },
    Focus = { NotifyPositionChanged = function() end },
}
_G.InCombatLockdown = function() return false end
_G.UIParent = {
    GetEffectiveScale = function() return 0.8 end,
    GetWidth = function() return 1600 end,
    GetHeight = function() return 900 end,
}
_G.MSUF2 = { SyncExternalHistoryState = function() historySyncs = historySyncs + 1 end }

local MSUF = {}
function MSUF.ExportPublic(name, value) _G[name] = value; return value end
assert(loadfile(ResolvePath("Kernel/MSUF_Boundary.lua")))("MidnightSimpleUnitFrames", MSUF)
local chunk = assert(loadfile(ResolvePath("Shell/EditMode/MSUF_EditMode_PublicAPI.lua")))
chunk("MidnightSimpleUnitFrames", MSUF)

local API = assert(_G.MSUF_EditModeAPI, "public Edit Mode API was not exported")
assert(API.GetVersion() == 1, "unexpected Edit Mode API version")
local caps = API.GetCapabilities()
assert(caps.drag and caps.gridSnap and caps.nudge and caps.undoRedo and caps.saveDiscard,
    "public API capability contract is incomplete")
assert(caps.polling == false, "public API must remain event-driven")

local position = { x = 20, y = -10, width = 180, height = 40 }
local sessionCalls = {}
local settingsCalls = 0
local frame = {
    GetLeft = function() return 100.2 end,
    GetRight = function() return 300.8 end,
    GetBottom = function() return 400.2 end,
    GetTop = function() return 500.4 end,
    GetEffectiveScale = function() return 0.8 end,
}
local element = {
    id = "frame_1",
    label = "Test Frame",
    getFrame = function() return frame end,
    captureState = function()
        return { x = position.x, y = position.y, width = position.width, height = position.height }
    end,
    restoreState = function(state) position.x, position.y = state.x, state.y; return true end,
    movePosition = function(request)
        position.x = request.state.x + request.deltaX
        position.y = request.state.y + request.deltaY
        return true
    end,
    resetPosition = function() position.x, position.y = 0, 0; return true end,
    openSettings = function() settingsCalls = settingsCalls + 1; return true end,
    onSessionChanged = function(enabled, reason) sessionCalls[#sessionCalls + 1] = { enabled, reason } end,
}

assert(API.RegisterElement("TestOwner", element) == true, "valid element registration failed")
local key = "external:testowner:frame_1"
assert(registry[key] and registry[key].externalPublicElement == true,
    "registered element did not enter the native registry")
assert(historySyncs == 1 and refreshes > 0, "registration did not refresh native history/shell state")
local elementCaps = assert(API.GetElementCapabilities("TestOwner", "frame_1"))
assert(elementCaps.settings and elementCaps.reset and elementCaps.inspector and not elementCaps.resize,
    "per-element capabilities are incomplete")
local label, x, y, width, height = _G.MSUF_EM2.ExternalElements.GetInspectorValues(key)
assert(label == "Test Frame" and x == -499 and y == 50 and width == 201 and height == 100,
    "external inspector values must use the mirrored center-gap contract of MSUF's own frames")

assert(API._BeginSession() == true, "external session did not begin")
assert(API.OpenSettings("TestOwner", "frame_1") and settingsCalls == 1,
    "settings callback did not use the protected public boundary")
assert(sessionCalls[1][1] == true and sessionCalls[1][2] == "enter",
    "element did not receive session entry")
local initial = assert(_G.MSUF_EM2.ExternalElements.CaptureState(key))
assert(_G.MSUF_EM2.ExternalElements.ApplyMove(key, initial, 7, -4, nil, nil, "preview"))
assert(position.x == 27 and position.y == -14, "preview movement callback drifted")

assert(_G.MSUF_EM2.ExternalElements.Nudge(key, 3, 2), "external nudge failed")
assert(position.x == 30 and position.y == -12, "external nudge did not commit")
assert(undo.begin == 1 and undo.commit == 1 and undo.cancel == 0,
    "external nudge did not use native undo ownership")

local history = assert(API._CaptureHistorySnapshot())
position.x, position.y = 500, 600
assert(API._RestoreHistorySnapshot(history, "history"))
assert(position.x == 30 and position.y == -12, "history restore did not restore provider state")

position.x, position.y = 90, 80
assert(API._EndSession("discard") == true, "external discard failed")
assert(position.x == 20 and position.y == -10, "session discard did not restore entry state")
assert(sessionCalls[#sessionCalls][1] == false and sessionCalls[#sessionCalls][2] == "discard",
    "element did not receive discard exit")

local ok, reason = API.RegisterElement("BrokenOwner", {
    id = "broken", label = "Broken", getFrame = function() return frame end,
})
assert(ok == false and reason == "capture_restore_or_get_set_required",
    "invalid providers must fail closed with a stable reason")

assert(API.UnregisterOwner("TestOwner") == true and registry[key] == nil,
    "owner unregister did not remove the native registry entry")

local reports, survivorCalls, originalPresent = {}, 0, false
local function FailingListener() error("session listener failure") end
_G.geterrorhandler = function()
    return function(message)
        reports[#reports + 1] = message
        for depth = 2, 35 do
            local info = debug.getinfo(depth, "f")
            if not info then break end
            if info.func == FailingListener then originalPresent = true end
        end
    end
end
assert(API.RegisterSessionListener("FailingOwner", FailingListener))
assert(API.RegisterSessionListener("SurvivingOwner", function() survivorCalls = survivorCalls + 1 end))
local ok, failure = pcall(API._BeginSession)
assert(not ok and tostring(failure):find("session listener failure", 1, true), "listener exception was hidden")
assert(#reports == 0, "listener was intercepted instead of propagating")
API.UnregisterSessionListener("FailingOwner")
local before = survivorCalls
API._EndSession("save")
API._BeginSession()
API._EndSession("save")
assert(survivorCalls == before + 3, "listener exception stranded the session lifecycle")
API.UnregisterSessionListener("SurvivingOwner")

local handle = assert(io.open(ResolvePath("Shell/EditMode/MSUF_EditMode_PublicAPI.lua"), "rb"))
local source = handle:read("*a")
handle:close()
assert(not source:find("OnUpdate", 1, true) and not source:find("NewTicker", 1, true),
    "public API must not add idle polling")

print("editmode_public_api_smoke: ok")
