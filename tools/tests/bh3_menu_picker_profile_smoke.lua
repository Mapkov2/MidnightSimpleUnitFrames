local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, arg[2] or "Mainline")
world.env.MAX_BOSS_FRAMES = 5
world:Boot()
assert(not world:FirstFailure(), "client boot failed")
local env, core = world.env, world.core
local M = core.MSUF2
local function Upvalue(fn, wanted, replace)
    for i = 1, 60 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then
            if replace then debug.setupvalue(fn, i, replace) end
            return value
        end
        if not name then break end
    end
    error("missing fixture seam " .. wanted)
end
local Picker = Upvalue(M.OpenColorContextPicker, "Picker")
local panel = env.CreateFrame("Frame", nil, env.UIParent)
panel.title = panel:CreateFontString()
panel.infoButton = env.CreateFrame("Button", nil, panel)
panel.blocker = env.CreateFrame("Frame", nil, panel)
local function Noop() end
for _, name in ipairs({ "SetContextListShown", "RestorePosition", "Layout", "Refresh", "ClampPosition",
    "RefreshColorReadout", "RefreshOpacity", "NotifyLiveChange" }) do panel[name] = Noop end
M.Theme.RefreshMenuFonts, M.ApplyPopupFramePriority, M.RefreshWindowControls = Noop, Noop, Noop
Upvalue(Picker.Ensure, "picker", panel)
Picker.DefineSession(panel)
panel:Hide()
local a = M.EnsureDB()
M.EnsureDB = function() return env.MSUF_DB end
M.GetGeneralDB = function() return env.MSUF_DB.general end
a.general.testPickerColor = 0.2
local owner = {}
function owner:GetRGB() local v = env.MSUF_DB.general.testPickerColor; return v, v, v end
function owner:SetRGB(v) env.MSUF_DB.general.testPickerColor = v end
local commits, finishes = 0, 0
owner._msuf2CommitColorInteraction = function() commits = commits + 1 end
panel:Open("Colors", { owner }, nil, nil, function() finishes = finishes + 1 end)
panel:Apply(0.4, 0.4, 0.4)
assert(a.general.testPickerColor == 0.4)
-- A raw external replacement may bypass the normal pre-mutation callback.
local b = core.ProfileFields.CopySnapshot(a)
b.general.testPickerColor = 0.8
env.MSUF_DB, env.MSUF_ActiveProfile = b, "Other"
panel:Finish(true)
assert(b.general.testPickerColor == 0.8, "old picker Cancel wrote into the replacement profile")
assert(commits == 0 and finishes == 0, "stale picker committed callbacks to the replacement profile")
env.MSUF_DB, env.MSUF_ActiveProfile = a, "Original"
panel:Open("Colors", { owner })
panel:Apply(0.6, 0.6, 0.6)
assert(M.CloseColorPickerForProfileChange, "profile mutation close entry point missing")
M.CloseColorPickerForProfileChange()
assert(a.general.testPickerColor == 0.4 and not panel:IsShown(), "pre-mutation close did not cancel against the original profile")
panel:Open("Colors", { owner })
env.MSUF_DB, env.MSUF_ActiveProfile = b, "Other"
panel:Apply(0.1, 0.1, 0.1)
assert(b.general.testPickerColor == 0.8 and not panel:IsShown(), "stale live edit wrote into another profile")
print("picker profile identity: PASS")
