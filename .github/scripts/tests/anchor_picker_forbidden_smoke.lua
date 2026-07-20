-- Regression: EnumerateFrames may yield a tainted frame whose IsForbidden()
-- reports false while methods such as IsVisible() still throw. The picker must
-- skip that object and continue scanning without producing a Lua error.
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
_G.IsControlKeyDown = function() return false end
_G.GetMouseFoci = nil
_G.GetMouseFocus = nil
_G.issecretvalue = function() return false end

local tainted = { unitToken = nil }
function tainted:IsForbidden() return false end
function tainted:IsVisible()
    error("calling 'IsVisible' on bad self (Attempt to access forbidden object from code tainted by an AddOn)")
end

local safe = { unitToken = nil }
function safe:IsForbidden() return false end
function safe:IsVisible() return true end
function safe:GetName() return "MSUF_TestSafeAnchor" end
function safe:GetRect() return 0, 0, 100, 100 end

_G.EnumerateFrames = function(previous)
    if previous == nil then return tainted end
    if previous == tainted then return safe end
    return nil
end

local MSUF = {}
function MSUF.ExportPublic(name, value)
    _G[name] = value
    return value
end

local chunk = assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/MSUF_AnchorPicker.lua"))
chunk("MidnightSimpleUnitFrames", MSUF)
local overlay = assert(_G.MSUF_EnsureAnchorPicker)()
assert(overlay and overlay.scripts.OnShow and overlay.scripts.OnUpdate, "picker scripts were not installed")
overlay.scripts.OnShow(overlay)
overlay.scripts.OnUpdate(overlay, 0.04)
assert(overlay._pickedFrame == safe and overlay._pickedName == "MSUF_TestSafeAnchor",
    "picker did not skip the tainted frame and continue to the safe anchor")

print("PASS anchor picker forbidden frame: protected calls and continued scan")
