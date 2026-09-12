-- Load the real library adapter and drive its registered media/event callbacks.
local combat, callback = false, nil
local frames, queued, timers, calls = {}, {}, {}, {}
local media = { font = {}, statusbar = {}, background = {}, msuf_statusicon = {} }
local function count(key)
    calls[key] = (calls[key] or 0) + 1
end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local LSM = {}
function LSM:HashTable(kind) return media[kind] end
function LSM:Fetch(kind, key) return media[kind][key] end
function LSM:Register(kind, key, path) media[kind][key] = path end
function LSM.RegisterCallback(_, _, fn) callback = fn end
function LSM.UnregisterCallback() callback = nil end
_G.LibStub = function(name) if name == "LibSharedMedia-3.0" then return LSM end end
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
_G.MSUF_ScheduleOnce = function(key, fn)
    count("schedule")
    assert(not queued[key], "duplicate schedule request")
    queued[key] = fn
end
_G.CreateFrame = function()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    frames[#frames + 1] = f
    return f
end
local function fire(event)
    for i = 1, #frames do
        local f = frames[i]
        if f.events[event] then f.scripts.OnEvent(f, event) end
    end
end
local function flush()
    local fn = assert(queued.LSM_MEDIA_REFRESH, "missing combined media refresh")
    queued.LSM_MEDIA_REFRESH = nil
    fn()
end
local MSUF = { ExportPublic = function(name, value) _G[name] = value; return value end }
MSUF.GF = {
    DIRTY_VISUAL = 32,
    InvalidateConfCache = function() count("invalidate") end,
    RefreshVisuals = function(_, mask) count("group"); calls.mask = mask end,
}
_G.MSUF, _G.MSUF_NS = MSUF, MSUF
_G.MSUF_DB = { general = { fontKey = "Chosen" } }
_G.MSUF_BUNDLED_FONTS_REGISTERED = true
_G.MSUF_UpdateAllBarTextures_Immediate = function() count("bars") end
_G.MSUF_UpdateCastbarTextures_Immediate = function() count("casts") end
_G.MSUF_RefreshStatusIconPacks = function() count("icons") end
_G.MSUF_RequestFontRecovery = function() count("font") end
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Boundary.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua"))("MidnightSimpleUnitFrames", MSUF)
assert(callback, "registration callback missing")
equal(#frames, 1, "library lifecycle listener")
media.font.Chosen = "Interface\\AddOns\\Test\\Chosen.ttf"
callback(nil, "font", "Chosen")
callback(nil, "statusbar", "Bar")
callback(nil, "background", "Icon")
callback(nil, "statusbar", "Other")
equal(calls.schedule, 1, "mixed registration burst")
flush()
for _, key in ipairs({ "font", "bars", "casts", "icons", "invalidate", "group" }) do
    equal(calls[key], 1, "one refresh for " .. key)
end
equal(calls.mask, nil, "statusbars require full group refresh")
equal(#frames, 1, "no unnecessary deferral listener")

-- A queued out-of-combat burst can enter combat before its callback executes.
callback(nil, "background", "Icon2")
combat = true
fire("PLAYER_REGEN_DISABLED")
flush()
equal(calls.icons, 1, "deferred icon work")
equal(#frames, 2, "one lazy media deferral listener")
combat = false
fire("PLAYER_REGEN_ENABLED")
equal(calls.icons, 2, "deferred work resumed")
equal(calls.group, 2, "one deferred group refresh")
equal(calls.mask, MSUF.GF.DIRTY_VISUAL, "icon-only group mask")
equal(frames[2].events.PLAYER_REGEN_ENABLED, nil, "idle listener unregistered")
fire("PLAYER_REGEN_ENABLED")
equal(calls.icons, 2, "idle event cannot replay settled work")

-- Registrations while the library callback is detached are discovered at exit.
combat = true
fire("PLAYER_REGEN_DISABLED")
assert(callback == nil, "callback must be detached in combat")
media.statusbar.Late = "late-bar"
media.font.Late = "late-font"
combat = false
fire("PLAYER_REGEN_ENABLED")
assert(callback, "callback must be reattached")
flush()
equal(calls.font, 2, "combat font registration caught up")
equal(calls.bars, 2, "combat bar registration caught up")
equal(calls.icons, 3, "combat icons caught up")
equal(calls.group, 3, "combat catch-up coalesced")

-- The timer fallback obeys the same burst contract without allocating per call.
_G.MSUF_ScheduleOnce = nil
callback(nil, "statusbar", "TimerBar")
callback(nil, "background", "TimerIcon")
equal(#timers, 1, "one fallback timer")
timers[1]()
equal(calls.group, 4, "fallback group refresh")
equal(calls.icons, 4, "fallback icon refresh")
print("PASS media coalescing: mixed bursts, group masks, combat deferral/catch-up, timer fallback")
