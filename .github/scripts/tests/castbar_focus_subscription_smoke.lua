local subscriber
local subscribed = false
local engine = {}
function engine:Subscribe(key, callback)
    assert(key == "focus")
    subscriber = callback
    subscribed = true
    return true
end
function engine:Unsubscribe(key, callback)
    assert(key == "focus" and callback == subscriber)
    subscribed = false
    subscriber = nil
    return true
end

local source = { alpha = 1 }
function source:SetAlpha(value) self.alpha = value end

local applied = {}
local applyCalls = 0
local lastApplied
local initialized = 0
_G.MSUF_DB = {
    general = { enableFocusKickIcon = true, castbarFocusBackend = "MSUF" },
    focus = { enabled = true },
}
_G.MSUF_FocusCastbar = source
_G.MSUF_ShouldUseMSUFCastbar = function() return true end
_G.MSUF_InitFocusKickIcon = function() initialized = initialized + 1 end
_G.MSUF_FocusKick_ApplyCastState = function(state)
    applyCalls = applyCalls + 1
    lastApplied = state
    if state then applied[#applied + 1] = state end
end
_G.MSUF_BuildCastState = function()
    return { active = true, spellName = "Initial", durationObj = {} }
end
_G.C_Timer = { After = function(_, callback) callback() end }
_G.CreateFrame = function() error("focus-kick subscriber created a duplicate event frame") end

local ns = { MSUF_CastbarEngine = engine }
assert(loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_FocusKick_StateDriver.lua"))("MSUF", ns)
assert(subscribed and initialized == 1, "enabled focus-kick did not subscribe and initialize")
assert(source.alpha == 0 and applied[#applied].spellName == "Initial")

local update = { active = true, spellName = "Updated", durationObj = {} }
subscriber(update, "UNIT_SPELLCAST_DELAYED")
assert(applied[#applied] == update, "canonical focus state was not forwarded")

_G.MSUF_DB.general.enableFocusKickIcon = false
_G.MSUF_FocusKickDriver_ForceUpdate()
assert(not subscribed, "disabled focus-kick retained its state subscription")
assert(source.alpha == 1 and lastApplied == nil and applyCalls >= 3,
    "disabled focus-kick did not restore source ownership")

print("castbar focus subscription smoke: ok")
