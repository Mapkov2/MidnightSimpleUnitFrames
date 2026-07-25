-- Regression: mouse focus may contain tainted regions whose methods throw.
-- The picker must skip them through per-method protected calls, continue to a
-- safe focused anchor and never reintroduce an instrumented Lua pcall boundary
-- like pcall(EvaluateFrameUnderCursor, ...), which corrupts Perfy's stack.
local root = arg and arg[1] or "."

assert(debug and type(debug.getinfo) == "function",
    "debug.getinfo is required for the protected-boundary regression check")
local realPcall = pcall
local failedPickerTargets = {}
local function Pack(...)
    return { n = select("#", ...), ... }
end
_G.pcall = function(fn, ...)
    local result = Pack(realPcall(fn, ...))
    if result[1] == false and debug and debug.getinfo then
        local info = debug.getinfo(fn, "S")
        local source = info and info.source or ""
        if type(source) == "string" and source:find("MSUF_AnchorPicker.lua", 1, true) then
            failedPickerTargets[#failedPickerTargets + 1] = source
        end
    end
    return unpack(result, 1, result.n)
end

local Widget = {}
Widget.__index = Widget

local function NewWidget(name, parent)
    return setmetatable({
        name = name,
        parent = parent,
        scripts = {},
        shown = false,
        rect = { 0, 0, 100, 100 },
    }, Widget)
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
function Widget:SetScript(kind, callback) self.scripts[kind] = callback end
function Widget:CreateTexture() return NewWidget(nil, self) end
function Widget:CreateFontString() return NewWidget(nil, self) end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetName()
    if self.throwName then error("calling 'GetName' on bad self") end
    return self.name
end
function Widget:GetParent()
    if self.throwParent then error("calling 'GetParent' on bad self") end
    return self.parent
end
function Widget:GetRect()
    if self.throwRect then error("calling 'GetRect' on bad self") end
    return unpack(self.rect)
end
function Widget:IsForbidden()
    if self.throwForbidden then
        error("Attempt to access forbidden object from code tainted by an AddOn")
    end
    return false
end
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
_G.IsControlKeyDown = function() return true end
_G.issecretvalue = function() return false end

local badName = NewWidget(nil, nil)
badName.throwName = true

local badForbidden = NewWidget("MSUF_TaintedCandidate", nil)
badForbidden.throwForbidden = true

local badParent = NewWidget(nil, nil)
badParent.throwParent = true

local safe = NewWidget("MSUF_TestSafeAnchor", UIParent)
safe.throwRect = true
_G.GetMouseFoci = function()
    return { badName, badForbidden, badParent, safe }
end
_G.GetMouseFocus = nil

local enumCalls = 0
_G.EnumerateFrames = function()
    enumCalls = enumCalls + 1
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
assert(overlay and overlay.scripts.OnShow and overlay.scripts.OnEvent,
    "picker scripts were not installed")

local pickedVia
overlay._isCandidateAllowed = function(frame, name)
    return frame == safe and name == "MSUF_TestSafeAnchor"
end
overlay._onPick = function(name) pickedVia = name end

overlay:Show()
assert(type(overlay.scripts.OnUpdate) == "function", "OnShow did not install OnUpdate")
overlay.scripts.OnUpdate(overlay, 0.04)
assert(overlay._pickedFrame == safe and overlay._pickedName == "MSUF_TestSafeAnchor",
    "picker did not skip tainted focus regions and continue to the safe anchor")
assert(overlay._highlight.shown == false,
    "throwing GetRect did not safely suppress the highlight")
assert(enumCalls == 0, "tainted focus handling fell back to a full UI scan")

overlay.scripts.OnEvent(overlay, "GLOBAL_MOUSE_DOWN", "LeftButton")
assert(pickedVia == "MSUF_TestSafeAnchor", "safe focused anchor was not confirmed")
assert(overlay.shown == false and overlay.scripts.OnUpdate == nil,
    "successful confirmation did not fully stop the picker")
assert(enumCalls == 0, "confirmation enumerated the full UI")
assert(#failedPickerTargets == 0,
    "a failed pcall escaped an instrumented AnchorPicker Lua function")

_G.pcall = realPcall
print("PASS anchor picker forbidden focus: tainted methods contained, protected boundaries, zero full scans")
