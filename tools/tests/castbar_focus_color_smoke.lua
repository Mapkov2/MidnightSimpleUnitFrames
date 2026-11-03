-- Separate focus colors must retain semantic tinting and reuse native colors.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
world:Boot()
local failed = world:FirstFailure()
assert(not failed, failed and failed.message)
local core, env = world.core, world.env
core.Require("MSUF_EnsureDB", "focus color smoke")()
local C, general = core.Castbars, env.MSUF_DB.general
C.Backend.Set("focus", "MSUF", general)
C.Backend.Set("target", "MSUF", general)
general.kickReadyShowFocus, general.kickReadyShowTarget = false, false
general.castbarInterruptibleR, general.castbarInterruptibleG, general.castbarInterruptibleB = .2, .4, .8
general.castbarNonInterruptibleR, general.castbarNonInterruptibleG, general.castbarNonInterruptibleB = .9, .1, .1
local focus = C.Driver.CastbarDriver_ApplyBackendState("focus")
local target = C.Driver.CastbarDriver_ApplyBackendState("target")
local function Paint(frame, raw)
    local saved, result = frame.statusBar
    local texture = { SetVertexColorFromBoolean = function(_, value, yes, no)
        result = { (value == true and yes or no):GetRGBA() }
    end }
    frame.statusBar = { GetStatusBarTexture = function() return texture end,
        SetStatusBarColor = function(_, r, g, b, a) result = { r, g, b, a } end }
    frame.isNotInterruptible, frame._msufApiNotInterruptibleRaw = raw == true, raw
    frame:UpdateColorForInterruptible()
    frame.statusBar = saved
    return assert(result, "no focus color painted")
end
local function Check(actual, r, g, b, reason)
    assert(math.abs(actual[1] - r) < .0001 and math.abs(actual[2] - g) < .0001
        and math.abs(actual[3] - b) < .0001 and actual[4] == 1, reason)
end
general.focusCastbarOverrideEnabled = nil
C.Config.Invalidate()
Check(Paint(focus, false), .2, .4, .8, "legacy focus color changed")
general.focusCastbarOverrideEnabled = true
general.focusCastbarOverrideColor = { .58, .52, 1 }
C.Config.Invalidate()
Check(Paint(focus, false), .58, .52, 1, "focus does not use its own color")
Check(Paint(target, false), .2, .4, .8, "focus override changed target")
Check(Paint(focus, true), .9, .1, .1, "focus override hid non-interruptible warning")
general.focusCastbarOverrideColor = { .17, .29, .43 }
C.Config.Invalidate()
Check(Paint(focus, false), .17, .29, .43, "focus color did not refresh")
Paint(target, false)
local create, allocations = env.CreateColor, 0
env.CreateColor = function(...)
    allocations = allocations + 1
    return create(...)
end
for _ = 1, 100 do Paint(focus, false) Paint(target, false) end
env.CreateColor = create
assert(allocations == 0, "alternating focus/target colors allocated ColorObjects")
general.focusCastbarOverrideEnabled = false
C.Config.Invalidate()
Check(Paint(focus, false), .2, .4, .8, "disabled focus override did not restore shared color")
print("PASS focus castbar colors " .. flavor .. ": legacy, override, refresh, warning and native color reuse")
