-- Regression: opening the picker over an unnamed UI tree (Menu2) drops the
-- hover loop into the EnumerateFrames fallback. That scan visits every frame
-- in the UI, so it must (1) NEVER invoke the caller's _isCandidateAllowed
-- during hover - the anchor-dependency walk behind it froze clients at hover
-- cadence, it may only run once on the confirming click, (2) still pick the
-- smallest named frame under the cursor, (3) rescan only every few hover
-- ticks, serving a cached result in between, and (4) keep the picker open
-- with a message when the clicked target is vetoed.
local root = arg and arg[1] or "."

local Widget = {}
Widget.__index = Widget

local function NewWidget(name)
    return setmetatable({ name = name, scripts = {}, shown = false }, Widget)
end

function Widget:SetAllPoints() end
function Widget:SetPoint() end
function Widget:SetSize() end
function Widget:SetWidth() end
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
function Widget:Hide() self.shown = false end
function Widget:Show() self.shown = true end
function Widget:SetScript(kind, callback) self.scripts[kind] = callback end
function Widget:CreateTexture() return NewWidget() end
function Widget:CreateFontString() return NewWidget() end
function Widget:GetEffectiveScale() return 1 end

_G.UIParent = NewWidget("UIParent")
_G.WorldFrame = NewWidget("WorldFrame")
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.CreateFrame = function(_, name) return NewWidget(name) end
_G.GetCursorPosition = function() return 50, 50 end
local ctrlHeld = false
_G.IsControlKeyDown = function() return ctrlHeld end
_G.GetMouseFoci = nil
_G.GetMouseFocus = nil
_G.issecretvalue = function() return false end

local function NewScanFrame(name, l, b, w, h)
    local f = { unitToken = nil }
    function f:IsForbidden() return false end
    function f:IsVisible() return true end
    function f:GetRect() return l, b, w, h end
    function f:GetName() return name end
    return f
end

-- Cursor sits at (50, 50). underBig is enumerated first so an order-based pick
-- would wrongly win over the area-based one; the far frames are valid anchors
-- that must never be evaluated beyond the cheap rect test.
local underBig = NewScanFrame("MSUF_UnderBig", 0, 0, 100, 100)
local underSmall = NewScanFrame("MSUF_UnderSmall", 40, 40, 20, 20)
local frames = { underBig }
for i = 1, 40 do
    frames[#frames + 1] = NewScanFrame("MSUF_Far" .. i, 200, 200, 50, 50)
end
frames[#frames + 1] = underSmall
local throwing = { unitToken = nil }
function throwing:IsForbidden() return false end
function throwing:IsVisible() return true end
function throwing:GetRect()
    error("Attempt to access forbidden object from code tainted by an AddOn")
end
frames[#frames + 1] = throwing

local nextByFrame = {}
for i = 1, #frames do nextByFrame[frames[i]] = frames[i + 1] end

local enumStarts = 0
_G.EnumerateFrames = function(previous)
    if previous == nil then
        enumStarts = enumStarts + 1
        return frames[1]
    end
    return nextByFrame[previous]
end

local MSUF = {}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_AnchorPicker.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local overlay = assert(_G.MSUF_EnsureAnchorPicker)()
assert(overlay and overlay.scripts.OnShow and overlay.scripts.OnUpdate and overlay.scripts.OnEvent,
    "picker scripts were not installed")

local candidateSeen = {}
local vetoSmall = true
overlay._isCandidateAllowed = function(_, name)
    candidateSeen[#candidateSeen + 1] = name
    if vetoSmall and name == "MSUF_UnderSmall" then return false end
    return true
end
local pickedVia
overlay._onPick = function(name) pickedVia = name end

overlay.scripts.OnShow(overlay)
overlay.scripts.OnUpdate(overlay, 0.04)

assert(enumStarts == 1, "expected exactly one enumeration on the first hover tick, got " .. enumStarts)
assert(overlay._pickedName == "MSUF_UnderSmall",
    "expected the smallest named under-cursor frame, got " .. tostring(overlay._pickedName))
assert(#candidateSeen == 0,
    "_isCandidateAllowed ran during hover (" .. #candidateSeen .. " calls) - that is the CPU-freeze path")

-- Ticks 2-4 must serve the cached result without a rescan.
for _ = 1, 3 do
    overlay.scripts.OnUpdate(overlay, 0.04)
    assert(enumStarts == 1, "full-UI scan ran again inside the throttle window")
    assert(overlay._pickedName == "MSUF_UnderSmall", "cached pick was lost inside the throttle window")
end

-- Tick 5 leaves the throttle window and rescans.
overlay.scripts.OnUpdate(overlay, 0.04)
assert(enumStarts == 2, "expected a rescan after the throttle window, got " .. enumStarts .. " scans")
assert(#candidateSeen == 0, "_isCandidateAllowed ran during hover on rescan")

-- Vetoed CTRL+click: exactly one candidate check, picker stays open with a message.
ctrlHeld = true
overlay.shown = true
overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(#candidateSeen == 1 and candidateSeen[1] == "MSUF_UnderSmall",
    "expected exactly one candidate check on click, got " .. #candidateSeen)
assert(pickedVia == nil, "vetoed target was picked anyway")
assert(overlay.shown == true, "picker closed on a vetoed target")
assert(overlay._sub and overlay._sub.text == overlay._lTargetNotAllowed,
    "vetoed click did not surface the not-allowed message")

-- Allowed CTRL+click: pick goes through and the picker closes.
vetoSmall = false
overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(pickedVia == "MSUF_UnderSmall", "allowed target was not picked, got " .. tostring(pickedVia))
assert(overlay.shown == false, "picker did not close after a successful pick")

print("PASS anchor picker scan budget: hover never runs candidate checks, throttled rescan, click-time veto")
