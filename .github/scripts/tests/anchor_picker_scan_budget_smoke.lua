-- Regression: the anchor picker must use WoW's mouse-focus stack for hover
-- and confirmation. A global EnumerateFrames geometry scan is both inaccurate
-- and catastrophic in a Perfy build, so it may never run from this picker.
local root = arg and arg[1] or "."

local Widget = {}
Widget.__index = Widget

local function NewWidget(name, parent)
    return setmetatable({
        name = name,
        parent = parent,
        scripts = {},
        shown = false,
        rect = { 0, 0, 10, 10 },
    }, Widget)
end

function Widget:SetAllPoints() end
function Widget:SetPoint(point, relative, relativePoint, x, y)
    self.point, self.relative, self.relativePoint = point, relative, relativePoint
    self.pointX, self.pointY = x, y
end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetFrameStrata() end
function Widget:SetFrameLevel() end
function Widget:EnableMouse() end
function Widget:EnableKeyboard() end
function Widget:SetPropagateKeyboardInput() end
function Widget:SetBackdrop() end
function Widget:SetBackdropColor() end
function Widget:SetBackdropBorderColor() end
function Widget:SetColorTexture() end
function Widget:SetFont() end
function Widget:SetJustifyH() end
function Widget:SetTextColor() end
function Widget:SetShadowColor() end
function Widget:SetShadowOffset() end
function Widget:SetText(text) self.text = text end
function Widget:ClearAllPoints() end
function Widget:RegisterEvent() end
function Widget:UnregisterEvent() end
function Widget:SetScript(kind, callback) self.scripts[kind] = callback end
function Widget:CreateTexture() return NewWidget(nil, self) end
function Widget:CreateFontString() return NewWidget(nil, self) end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetName() return self.name end
function Widget:GetParent() return self.parent end
function Widget:GetRect() return unpack(self.rect) end
function Widget:IsForbidden() return false end
function Widget:Hide()
    local changed = self.shown
    self.shown = false
    if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:Show()
    local changed = not self.shown
    self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
end

_G.UIParent = NewWidget("UIParent")
_G.WorldFrame = NewWidget("WorldFrame")
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateFrame = function(_, name, parent) return NewWidget(name, parent) end
_G.IsControlKeyDown = function() return false end
_G.issecretvalue = function() return false end

local named = NewWidget("MSUF_FocusAnchor", UIParent)
named.rect = { 10, 20, 100, 40 }
local anonymousChild = NewWidget(nil, named)
local currentFoci = { anonymousChild }
local focusCalls = 0
_G.GetMouseFoci = function()
    focusCalls = focusCalls + 1
    return currentFoci
end
_G.GetMouseFocus = nil

local enumStarts = 0
_G.EnumerateFrames = function()
    enumStarts = enumStarts + 1
    error("anchor picker must never enumerate the full UI")
end

local MSUF = {}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_AnchorPicker.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local overlay = assert(_G.MSUF_EnsureAnchorPicker)()
assert(overlay and overlay.scripts.OnShow and overlay.scripts.OnHide and overlay.scripts.OnEvent,
    "picker lifecycle scripts were not installed")
assert(overlay.scripts.OnUpdate == nil, "hidden picker retained an OnUpdate handler")

local function Pulse(elapsed)
    if overlay.shown and overlay.scripts.OnUpdate then
        overlay.scripts.OnUpdate(overlay, elapsed)
    end
end

local candidateSeen = {}
local veto = true
local pickedVia
overlay._isCandidateAllowed = function(_, name)
    candidateSeen[#candidateSeen + 1] = name
    return not veto
end
overlay._onPick = function(name) pickedVia = name end

overlay:Show()
assert(type(overlay.scripts.OnUpdate) == "function", "OnShow did not install the hover driver")
Pulse(0.04)
assert(overlay._pickedFrame == named and overlay._pickedName == "MSUF_FocusAnchor",
    "anonymous focus child did not resolve to its named parent")
assert(overlay._highlight.shown == true, "focused anchor was not highlighted")
assert(overlay._highlight.width == 100 and overlay._highlight.height == 40,
    "highlight did not use the focused anchor rectangle")
assert(overlay._highlight.point == "BOTTOMLEFT" and overlay._highlight.relative == UIParent
    and overlay._highlight.relativePoint == "BOTTOMLEFT"
    and overlay._highlight.pointX == 10 and overlay._highlight.pointY == 20,
    "highlight did not use the focused anchor position")
assert(enumStarts == 0, "focus hover unexpectedly enumerated the full UI")
assert(#candidateSeen == 0, "_isCandidateAllowed ran during hover")

for _ = 1, 250 do Pulse(0.04) end
assert(enumStarts == 0, "repeated hover ticks enumerated the full UI")
assert(#candidateSeen == 0, "_isCandidateAllowed ran during repeated hover")

currentFoci = {}
Pulse(0.04)
assert(overlay._pickedName == nil and overlay._highlight.shown == false
    and overlay._hover.text == overlay._lHoverNone,
    "empty focus kept a stale highlighted candidate")
currentFoci = { anonymousChild }
Pulse(0.04)
assert(overlay._pickedFrame == named, "focus candidate did not recover after an empty tick")

overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(#candidateSeen == 0 and pickedVia == nil,
    "click without CTRL evaluated or selected an anchor")
assert(enumStarts == 0, "click without CTRL enumerated the full UI")

local freshNamed = NewWidget("MSUF_FreshClickAnchor", UIParent)
local freshChild = NewWidget(nil, freshNamed)
currentFoci = { freshChild }
local candidateFrames = {}
candidateSeen = {}
overlay._isCandidateAllowed = function(frame, name)
    candidateFrames[#candidateFrames + 1] = frame
    candidateSeen[#candidateSeen + 1] = name
    return not veto
end
_G.IsControlKeyDown = function() return true end
overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(#candidateSeen == 1 and candidateSeen[1] == "MSUF_FreshClickAnchor"
    and candidateFrames[1] == freshNamed,
    "vetoed click reused the stale hover sample instead of the fresh focus")
assert(pickedVia == nil and overlay.shown == true, "vetoed target closed or completed the picker")
assert(overlay._sub.text == overlay._lTargetNotAllowed,
    "vetoed click did not show the target-not-allowed message")

veto = false
overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(#candidateSeen == 2 and candidateFrames[2] == freshNamed
    and pickedVia == "MSUF_FreshClickAnchor",
    "allowed fresh-click target was not selected")
assert(overlay.shown == false, "successful pick did not close the picker")
assert(overlay.scripts.OnUpdate == nil, "OnHide did not remove the hover driver")
assert(enumStarts == 0, "confirming a focused target enumerated the full UI")

local callsAfterHide = focusCalls
for _ = 1, 250 do Pulse(0.04) end
assert(focusCalls == callsAfterHide, "hidden picker continued polling mouse focus")

currentFoci = {}
pickedVia = nil
candidateSeen = {}
overlay._isCandidateAllowed = function(_, name)
    candidateSeen[#candidateSeen + 1] = name
    return true
end
overlay._onPick = function(name) pickedVia = name end
overlay:Show()
assert(type(overlay.scripts.OnUpdate) == "function", "reopen did not restore the hover driver")
for _ = 1, 250 do Pulse(0.04) end
assert(overlay._pickedName == nil and enumStarts == 0,
    "empty focus stack produced a candidate or triggered a full scan")
overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(pickedVia == nil and #candidateSeen == 0 and overlay.shown == true,
    "empty focus stack selected a stale or scanned candidate")
assert(overlay._sub.text == overlay._lNoNamedFrame,
    "empty focus confirmation did not show the no-frame message")
overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "RightButton")
assert(overlay.shown == false and overlay.scripts.OnUpdate == nil,
    "right-click did not fully stop the picker")
assert(enumStarts == 0, "anchor picker called EnumerateFrames")

print("PASS anchor picker focus budget: zero full scans, focus selection, click veto, dormant lifecycle")
