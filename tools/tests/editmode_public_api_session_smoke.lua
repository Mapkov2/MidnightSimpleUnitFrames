-- Review F12: the public Edit Mode API session stays consistent when an owner
-- callback raises. Errors keep the client's normal Lua error path (no
-- protected calls in addon code), but
--   * a captureState that raises while a session starts leaves no half-filled
--     entry snapshot behind: the next start captures every element, so Cancel
--     All (discard) restores all of them;
--   * MSUF's own session listeners (owner "MSUF.*", e.g. the Blizzard adapter's
--     tooltip container and layout snapshot) are notified before any other
--     addon's callback, so a raising third-party callback cannot skip them.
-- Real MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_PublicAPI.lua.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local registry = {}
_G.MSUF_EM2 = {
    Util = {},
    Registry = {
        Register = function(cfg) registry[cfg.key] = cfg end,
        Unregister = function(key) registry[key] = nil end,
        Get = function(key) return registry[key] end,
    },
}
local ns = {
    ExportPublic = function(name, value) _G[name] = value; return value end,
    ReportError = function() end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_PublicAPI.lua"))("MidnightSimpleUnitFrames", ns)
local API, External = assert(_G.MSUF_EditModeAPI), assert(_G.MSUF_EM2.ExternalElements)

local function Element(id, state, opts)
    opts = opts or {}
    return {
        id = id, label = id,
        getFrame = function() return {} end,
        captureState = function()
            if opts.raiseCapture and opts.raiseCapture() then error("capture failed: " .. id) end
            return { x = state.x, y = state.y }
        end,
        restoreState = function(saved) state.x, state.y = saved.x, saved.y; return true end,
        movePosition = function() return true end,
        onSessionChanged = opts.onSessionChanged,
    }
end

-- A capture that raises once while the session starts.
local brokenState, fineState = { x = 1, y = 1 }, { x = 2, y = 2 }
local raiseOnce = true
assert(API.RegisterElement("Third.Party", Element("broken", brokenState, {
    raiseCapture = function() local raise = raiseOnce; raiseOnce = false; return raise end,
})))
assert(API.RegisterElement("Third.Party", Element("fine", fineState)))
local started = pcall(External.BeginSession)
Check(not started, "the raising capture did not surface")
Check(External.BeginSession() == true, "the session did not start after the raising capture")
brokenState.x, fineState.x = 50, 60
Check(External.EndSession("discard") == true, "discard did not end the session")
Check(brokenState.x == 1 and fineState.x == 2, "discard after a raising capture restored only part of the elements ("
    .. brokenState.x .. ", " .. fineState.x .. ")")
API.UnregisterOwner("Third.Party")

-- A third-party session callback that raises.
local msufHeard = {}
assert(API.RegisterSessionListener("MSUF.Blizzard", function(enabled, reason) msufHeard[#msufHeard + 1] = { enabled, reason } end))
assert(API.RegisterElement("Third.Party", Element("noisy", { x = 0, y = 0 }, {
    onSessionChanged = function(enabled) if not enabled then error("third-party session callback failed") end end,
})))
Check(External.BeginSession() == true, "the session did not start")
local ended = pcall(External.EndSession, "save")
Check(not ended, "the raising third-party callback did not surface")
local last = msufHeard[#msufHeard]
Check(last and last[1] == false and last[2] == "save",
    "a raising third-party session callback kept MSUF's own adapter from hearing the session end")
Check(External.BeginSession() == true, "a new session did not start after the raising session end")

if #failures > 0 then
    error("editmode_public_api_session_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_public_api_session_smoke: ok (complete entry snapshot, own listeners first)")
