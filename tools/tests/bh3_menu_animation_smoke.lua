-- Probe C24: T.PlayAlphaScale creates a new AnimationGroup per call (popupIn profile),
-- reached by MSUF.UI.FadeIn (Shell/UI/MSUF_Widgets.lua:396) for every Edit Mode popup open.
local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/"
local function load(path, ns) return assert(loadfile(ROOT .. path))("MidnightSimpleUnitFrames", ns) end
IsLoggedIn = function() return true end
MSUF_DB = { general = {} }
MSUF_EnsureDB = function() return MSUF_DB end
local ns = { Translate = function(s) return s end, GetEffectiveLocale = function() return "enUS" end,
    Client = { IsForever = false } }
ns.MSUF2 = {
    Assign = function(t, v) for k, x in pairs(v) do t[k] = x end return t end,
    WordList = function(s) local t = {} for v in s:gmatch("%S+") do t[#t + 1] = v end return t end,
    Lines = function(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end,
}
load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Forever.lua", ns)
load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua", ns)
load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua", ns)
local T = ns.MSUF2.Theme

-- A frame whose animation groups persist for its lifetime (WoW never frees them).
local groupsCreated, animsCreated = 0, 0
local function NewAnim()
    animsCreated = animsCreated + 1
    local a = {}
    for _, m in ipairs({ "SetFromAlpha", "SetToAlpha", "SetDuration", "SetOrder", "SetSmoothing",
        "SetScaleFrom", "SetScaleTo", "SetOrigin" }) do a[m] = function() end end
    return a
end
local popup = { alpha = 1, groups = {} }
function popup:SetAlpha(a) self.alpha = a end
function popup:GetAlpha() return self.alpha end
function popup:Show() end
function popup:CreateAnimationGroup()
    groupsCreated = groupsCreated + 1
    local g = { scripts = {} }
    function g:CreateAnimation() return NewAnim() end
    function g:SetScript(k, v) self.scripts[k] = v end
    function g:Stop() end
    function g:Play() if self.scripts.OnFinished then self.scripts.OnFinished() end end
    self.groups[#self.groups + 1] = g
    return g
end

-- UI.FadeIn(frame, 0.12, 0.86, 1) -> theme.PlayMotion(frame, "popupIn", {...})
for i = 1, 200 do
    T.PlayMotion(popup, "popupIn", { duration = 0.12, fromAlpha = 0.86, toAlpha = 1 })
end
print("popup opens: 200  AnimationGroups created on the one popup frame:", groupsCreated,
    " Animations:", animsCreated)
local tracked = 0
for _ in pairs(T._menuAnimationGroups) do tracked = tracked + 1 end
print("groups tracked (and iterated by every StopAllMenuAnimations):", tracked)
print("expected: 1 group reused (as T.PlayAlpha does at Theme.lua:765-776)")

assert(groupsCreated == 1 and animsCreated == 2 and tracked == 1, "popup motion retains native animation groups")
