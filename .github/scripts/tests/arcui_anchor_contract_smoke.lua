local root = assert(arg[1], "usage: lua arcui_anchor_contract_smoke.lua <repo-root>")

local function read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local integration = read("MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua")
local runtime = read("MidnightSimpleUnitFrames/Runtime/MSUF_BarBackgroundRuntime.lua")
local toc = read("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc")

assert(toc:find("Integrations\\MSUF_Integration_ThirdPartyAnchors.lua", 1, true))
assert(integration:find('getAnchor("Essential")', 1, true), "ArcUI Essential anchor is not resolved")
assert(integration:find('groupName == "Essential"', 1, true), "ArcUI event is not group-scoped")
assert(integration:find("arcUIRefreshAfterCombat", 1, true), "ArcUI acquisition is not combat-deferred")
assert(not integration:find("ArcUI_CDMGroups_NS", 1, true)
    and not integration:find("ReapplyAll", 1, true)
    and not integration:find("RegisterFrame", 1, true), "ArcUI private/ownership API leaked into MSUF")

local arcRefresh = assert(integration:match(
    "(refreshArcUIAnchor = function.-)\nrefreshSkironAnchorProxy = function"
), "ArcUI refresh block is missing")
assert(arcRefresh:find("local source = arcUIAnchor or ResolveArcUIAnchorSource()", 1, true))
assert(arcRefresh:find("local acquired = not arcUIAnchor", 1, true))
assert(arcRefresh:find('RefreshEssentialCooldownAnchorConsumers("acquired")', 1, true))
assert(not arcRefresh:find("OnUpdate", 1, true)
    and not arcRefresh:find("NewTicker", 1, true)
    and not arcRefresh:find("C_Timer.After", 1, true), "ArcUI path adds recurring or retry work")

local arcPos = assert(runtime:find("local getArcUIAnchor", 1, true))
local skironPos = assert(runtime:find("local getSkironProxy", 1, true))
assert(arcPos < skironPos, "ArcUI provider does not win while active")

local callbacks, frames = {}, {}
local rebinds, observerScans, widthRefreshes = 0, 0, 0
local Frame = {}
Frame.__index = Frame
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:IsShown() return true end
function Frame:IsForbidden() return false end
function Frame:IsProtected() return false end
function Frame:SetPoint() end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:SetScript(script, fn) self.scripts[script] = fn end

local function newFrame(width, height)
    local frame = setmetatable({ width = width or 1, height = height or 1, events = {}, scripts = {} }, Frame)
    frames[#frames + 1] = frame
    return frame
end

_G.UIParent, _G.WorldFrame = newFrame(1920, 1080), newFrame(1920, 1080)
_G.CreateFrame = function() return newFrame() end
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function(_, fn) fn() end }
_G.C_AddOns = { IsAddOnLoaded = function(name) return name == "ArcUI" end }
_G.EventRegistry = { RegisterCallback = function(_, event, fn) callbacks[event] = fn end }

local anchor = newFrame(240, 32)
_G.ArcUI_Public = {
    ANCHOR_CHANGED_EVENT = "ArcUI.AnchorProxy.SizeChanged",
    GetGroupAnchor = function(name)
        assert(name == "Essential")
        return anchor
    end,
}
_G.MSUF_DB = {}
_G.MSUF_EnsureCooldownWidthObservers = function() observerScans = observerScans + 1 end
_G.MSUF_ScheduleCooldownWidthRefresh = function() widthRefreshes = widthRefreshes + 1 end

local MSUF = { UF = { Factory = { RefreshExternalAnchor = function(name)
    assert(name == "EssentialCooldownViewer")
    rebinds = rebinds + 1
end } } }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua"))(
    "MidnightSimpleUnitFrames", MSUF
)
assert(_G.MSUF_GetArcUICooldownAnchor() == anchor, "ArcUI anchor was not cached")
assert(rebinds == 1 and observerScans == 1 and widthRefreshes == 1,
    "ArcUI acquisition did not initialize consumers exactly once")

callbacks["ArcUI.AnchorProxy.SizeChanged"](nil, "Essential", anchor)
assert(rebinds == 1 and observerScans == 1 and widthRefreshes == 2,
    "same-identity ArcUI reflow rebound unitframes or missed width refresh")
callbacks["ArcUI.AnchorProxy.SizeChanged"](nil, "Utility", newFrame(100, 20))
assert(rebinds == 1 and widthRefreshes == 2, "non-Essential ArcUI event reached consumers")

print("arcui_anchor_contract_smoke: OK")
