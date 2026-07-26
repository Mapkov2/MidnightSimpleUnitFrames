-- Regression: toggle afterSet callbacks pass true/false into RefreshProxy.
-- Those values must invoke the installed refresh, never replace it.
local root = arg and arg[1] or "."

local MSUF = { MSUF2 = {} }
_G.MSUF2 = MSUF.MSUF2
_G.C_Timer = { After = function() end }
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        UnregisterAllEvents = function() end,
        SetScript = function() end,
    }
end

assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Support.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local proxy = assert(MSUF.MSUF2.RefreshProxy, "RefreshProxy was not exported")()
local calls = 0
local refresh = function() calls = calls + 1 end

assert(proxy(refresh) == refresh, "proxy did not install the refresh function")
proxy(true)
assert(calls == 1, "true toggle value replaced the refresh function")
proxy(false)
assert(calls == 2, "false toggle value did not invoke the refresh function")
proxy()
assert(calls == 3, "plain refresh request did not invoke the refresh function")
proxy(true)
assert(calls == 4, "refresh target was corrupted after a true toggle value")

print("PASS menu refresh proxy: boolean toggle values invoke the installed refresher")
