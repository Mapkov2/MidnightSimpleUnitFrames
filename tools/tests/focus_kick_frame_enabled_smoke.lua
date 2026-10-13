-- Both tracker consumers retain the focus-frame switch without changing backend ownership.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local consumer = assert(arg[2], "state or icon consumer required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, "Mainline", { page = "home", keepFlush = true })
local env, castbars = mw.env, mw.core.Castbars
local general = env.MSUF_DB.general
general.castbarFocusBackend = "MSUF"
general.enableFocusCastbar = true
general.enableFocusKickIcon = true
general.focusKickShowCastbar = false
env.MSUF_DB.focus.enabled = true
env.MSUF_Castbars_OnSettingsChanged("focus gate")
local focus = assert(castbars.Frames.Get("focus"), "focus castbar missing")
castbars.FocusKick.InitFocusKickIcon()
local icon = assert(castbars.Frames.Get("focusKick"), "focus icon missing")
local state = { active = true, name = "Cast", icon = 123, castGUID = "gate", startTime = 0, endTime = 10 }
local function Observe(enabled)
    env.MSUF_DB.focus.enabled = enabled
    env.MSUF_Castbars_OnSettingsChanged("focus gate")
    assert(castbars.Config.Read("focus").enabled, "frame switch changed independent backend ownership")
    if consumer == "state" then
        env.MSUF_FocusKickDriver_ForceUpdate()
        return focus._msufFocusKickSuppressed == true
    end
    assert(consumer == "icon", "unknown consumer")
    -- Direct canonical state delivery isolates the icon's own guard from StateDriver.
    castbars.FocusKick.FocusKick_ApplyCastState(state)
    return icon:IsShown()
end
assert(Observe(true), consumer .. ": positive tracker control failed")
assert(not Observe(false), consumer .. ": disabled focus still activates tracker")
assert(Observe(nil), consumer .. ": nil focus switch no longer enables tracker")
assert(Observe(true), consumer .. ": re-enable failed")
general.castbarFocusBackend = "HIDE"
env.MSUF_Castbars_OnSettingsChanged("focus gate")
if consumer == "state" then
    env.MSUF_FocusKickDriver_ForceUpdate()
    assert(focus._msufFocusKickSuppressed ~= true, "hidden backend still suppresses focus")
else
    castbars.FocusKick.FocusKick_ApplyCastState(state)
    assert(not icon:IsShown(), "hidden backend still shows icon")
end
assert(mw.core.KickReady == env.MSUF_HostAPI.GetKickReady(), "public readiness consumer identity changed")
print("focus frame enabled smoke: " .. consumer .. " ok (true/false/nil/re-enable/backend)")
