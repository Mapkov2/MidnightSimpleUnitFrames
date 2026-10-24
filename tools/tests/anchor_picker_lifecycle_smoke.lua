-- The real picker keeps its singleton, visual layout and open/close lifecycle.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local env = world.env
if arg[3] then
    local load = world.LoadFile
    world.LoadFile = function(self, path, addon, namespace)
        if path:match("/Shell/UI/MSUF_AnchorPicker.lua$") then path = arg[3] end
        return load(self, path, addon, namespace)
    end
end
local held, blocked, focus = false, false, {}
env.UIParent.IsForbidden = function(self) return self.forbidden == true end
env.GetMouseFoci = function() return focus end
env.IsControlKeyDown = function() return held end
local create = env.CreateFrame
local function EnableKeyboard(self, value) self.keyboardEnabled = value end
local function PropagateKeyboard(self, value) self.propagateKeyboard = value end
env.CreateFrame = function(...)
    local frame = create(...)
    frame.EnableKeyboard = EnableKeyboard
    frame.SetPropagateKeyboardInput = PropagateKeyboard
    return frame
end
world:Boot()
assert(not world:FirstFailure(), "whole client graph did not load")
env.MSUF_BlockConfigCombatLocked = function() return blocked end
local messages = 0
env.MSUF_ShowConfigCombatLockMessage = function() messages = messages + 1 end
local ensure = assert(world.core.PublicGlobals.MSUF_EnsureAnchorPicker)
local picker = assert(ensure())
-- Shared widget stubs keep visibility flags; deliver native visibility scripts here.
local show, hide = picker.Show, picker.Hide
picker.Show = function(self)
    local changed = not self:IsShown()
    show(self)
    if changed and self:GetScript("OnShow") then self:GetScript("OnShow")(self) end
end
picker.Hide = function(self)
    local changed = self:IsShown()
    hide(self)
    if changed and self:GetScript("OnHide") then self:GetScript("OnHide")(self) end
end
assert(ensure() == picker, "picker singleton changed")
assert(picker:GetFrameStrata() == "FULLSCREEN_DIALOG" and picker:GetFrameLevel() == 100, "overlay layer changed")
assert(picker:IsMouseEnabled() == false and not picker:IsShown(), "overlay initial mouse/visibility changed")
assert(picker._topPanel:GetWidth() == 760 and picker._topPanel:GetHeight() == 60, "panel size changed")
local point, relative, relativePoint, x, y = picker._topPanel:GetPoint()
assert(point == "TOP" and relative == picker and relativePoint == "TOP" and x == 0 and y == -92, "panel anchor changed")
assert(picker._sub:GetWidth() == 720 and picker._info and picker._hover and picker._ctrlHint, "text surfaces missing")
assert(not picker._highlight:IsShown() and picker:GetScript("OnUpdate") == nil, "closed picker has active hover work")
local function Event(event, button)
    picker:GetScript("OnEvent")(picker, event, button)
end
local function Open()
    picker:Show()
    assert(picker:IsEventRegistered("GLOBAL_MOUSE_DOWN") and picker:IsEventRegistered("PLAYER_REGEN_DISABLED"),
        "open picker has no confirmation/combat events")
    assert(picker:GetScript("OnUpdate"), "open picker has no hover callback")
end
local function Closed()
    assert(not picker:IsShown() and picker:GetScript("OnUpdate") == nil, "close left hover work running")
    assert(not picker:IsEventRegistered("GLOBAL_MOUSE_DOWN") and not picker:IsEventRegistered("PLAYER_REGEN_DISABLED"),
        "close retained registered events")
    assert(picker._pickedFrame == nil and picker._pickedName == nil and picker._onPick == nil
        and picker._isCandidateAllowed == nil and not picker._highlight:IsShown(), "close retained a pick or highlight")
end
Open()
Event("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(picker:IsShown() and picker._sub:GetText() == picker._lCtrlRequired, "unmodified left click was accepted")
held = true
Event("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(picker:IsShown() and picker._sub:GetText() == picker._lNoNamedFrame, "empty focus was accepted")
local a = env.CreateFrame("Frame", "AnchorLifecycleA", env.UIParent)
local b = env.CreateFrame("Frame", "AnchorLifecycleB", env.UIParent)
a.left, a.bottom, a.width, a.height = 10, 20, 200, 40
b.left, b.bottom, b.width, b.height = 30, 40, 250, 50
focus[1] = a
local update = picker:GetScript("OnUpdate")
update(picker, 0.01)
assert(picker._pickedFrame == nil, "hover throttle changed")
update(picker, 0.03)
assert(picker._pickedFrame == a and picker._pickedName == "AnchorLifecycleA", "hover did not use current focus")
assert(picker._highlight:IsShown() and picker._highlight:GetWidth() == 200
    and picker._highlight:GetHeight() == 40, "hover highlight geometry changed")
local picked
picker._onPick = function(name) picked = name end
picker._isCandidateAllowed = function(_, name) return name ~= "AnchorLifecycleB" end
focus[1] = b
Event("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(picked == nil and picker:IsShown() and picker._sub:GetText() == picker._lTargetNotAllowed,
    "confirmation used a stale hover target or ignored candidate veto")
picker._isCandidateAllowed = function() return true end
Event("GLOBAL_MOUSE_DOWN", "LeftButton")
assert(picked == "AnchorLifecycleB", "confirmation did not pick the fresh focus")
Closed()
Open()
Event("GLOBAL_MOUSE_DOWN", "RightButton")
Closed()
Open()
picker:GetScript("OnKeyDown")(picker, "ESCAPE")
Closed()
Open()
Event("PLAYER_REGEN_DISABLED")
assert(messages == 1, "combat close lost its message")
Closed()
blocked = true
picker:Show()
Closed()
assert(ensure() == picker, "singleton changed across repeated sessions")
print("anchor_picker_lifecycle_smoke: ok (" .. flavor .. ")")
