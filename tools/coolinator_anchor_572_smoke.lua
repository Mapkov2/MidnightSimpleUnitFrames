local ROOT = assert(arg[1], "usage: lua tools/coolinator_anchor_572_smoke.lua <repo-root>")

local function Join(...)
    local parts = { ... }
    return table.concat(parts, "/"):gsub("\\", "/")
end

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local addonRoot = Join(ROOT, "MidnightSimpleUnitFrames")
local integrationPath = Join(addonRoot, "Integrations/MSUF_Integration_ThirdPartyAnchors.lua")
local mainSource = Read(Join(addonRoot, "MidnightSimpleUnitFrames.lua"))
local runtimeSource = Read(Join(addonRoot, "Core/MSUF_BarBackgroundRuntime.lua"))
local editModeLayoutSource = Read(Join(addonRoot, "EditMode2/MSUF_EM2_Layout.lua"))
local tocSource = Read(Join(addonRoot, "MidnightSimpleUnitFrames.toc"))
local integrationSource = Read(integrationPath)

assert(tocSource:find("Integrations\\MSUF_Integration_ThirdPartyAnchors.lua", 1, true),
    "third-party integration is not loaded by the TOC")
assert(runtimeSource:find("local getCoolinatorAnchor = _G.MSUF_GetCoolinatorCooldownAnchor", 1, true),
    "effective cooldown resolver does not consume the integration getter")
assert(mainSource:find('return "EssentialCooldownViewer", "GLOBAL", true', 1, true),
    "global cooldown mode is not compiled into an explicit anchor request")
assert(mainSource:find("MSUF_RefreshExternalUnitFrameAnchor", 1, true),
    "5.72 frame engine does not expose a targeted external-anchor rebind")
assert(mainSource:find("frame._msufNativeThirdPartyCooldownAnchor == true", 1, true),
    "native third-party anchor chains are still detached by the combat hard-lock path")
local dragStartSource = assert(mainSource:match(
    'f:SetScript%("OnDragStart".-f:SetScript%("OnDragStop"'
), "could not extract the 5.72 unitframe drag-start path")
assert(dragStartSource:find("self._msufNativeThirdPartyCooldownAnchor == true", 1, true),
    "unitframe drag does not recognize native third-party anchors")
assert(dragStartSource:find("MSUF_SnapshotFrameToUIParentCenter", 1, true),
    "third-party drag does not detach once into stable screen space")
assert(dragStartSource:find('self:SetScript("OnUpdate", nil)', 1, true),
    "third-party drag still leaves the per-frame update writer active")
assert(dragStartSource:find("if nativeThirdPartyDrag then", 1, true)
    and dragStartSource:find("return", 1, true),
    "third-party drag does not bypass repeated DB/anchor writes")
assert(not mainSource:find("SkironCooldownManager.AnchorProxy.SizeChanged", 1, true),
    "Skiron integration still lives in the monolithic unitframe file")
assert(integrationSource:find("CoolinatorPrimaryGroupAnchor", 1, true),
    "Coolinator primary group anchor is not owned by the integration module")
assert(integrationSource:find("if proxyGroup ~= 1 then return end", 1, true),
    "Skiron callback is not restricted to the primary layout group")
assert(not integrationSource:find('selectedAnchorRef == "ANCHOR:1"', 1, true),
    "child-group events can still replace the primary Skiron source")
assert(integrationSource:find(
    "if changed or sizeChanged == true then ScheduleEssentialCooldownAnchorConsumerRefresh() end",
    1, true
), "Skiron layout changes do not schedule a targeted unitframe reanchor")

local editModeDragSource = assert(editModeLayoutSource:match(
    "local function OnUpdate.-function Ticker%.BeginDrag"
), "could not extract the EditMode2 drag ticker")
assert(not editModeDragSource:find("pcall(function()", 1, true),
    "EditMode2 drag still allocates protected-call closures per frame")
assert(not editModeDragSource:find("MSUF_GetEffectiveCooldownFrame", 1, true),
    "EditMode2 drag still resolves the cooldown provider per frame")
assert(not editModeDragSource:find("MSUF_DB", 1, true),
    "EditMode2 drag still reads the global DB per frame")
assert(editModeDragSource:find("d.anchorPX", 1, true)
    and editModeDragSource:find("d.pointDX", 1, true),
    "EditMode2 drag does not use the cached screen-space transform")
assert(select(2, editModeDragSource:gsub("bar:SetPoint%(", "")) == 1,
    "EditMode2 drag has more than one unitframe SetPoint site")
assert(editModeDragSource:find("conf.offsetX ~= nextX", 1, true),
    "EditMode2 drag still reanchors unchanged offsets")

local function Round(value)
    return math.floor(value + 0.5)
end

local function PointOffset(point, width, height)
    local x = point:find("LEFT", 1, true) and -width * 0.5
        or point:find("RIGHT", 1, true) and width * 0.5
        or 0
    local y = point:find("TOP", 1, true) and height * 0.5
        or point:find("BOTTOM", 1, true) and -height * 0.5
        or 0
    return x, y
end

local function CheckDragTransform(point, baseX, extraY)
    local uiScale, anchorScale, frameScale = 0.711111, 0.8, 0.9
    local anchorX, anchorY = 1010, 540
    local targetCX, targetCY = 620, 310
    local pointDX, pointDY = PointOffset(point, 260, 42)
    local wantedX = targetCX * uiScale + pointDX * frameScale
    local wantedY = targetCY * uiScale + pointDY * frameScale
    local offX = (wantedX - anchorX * anchorScale) / anchorScale
    local offY = (wantedY - anchorY * anchorScale) / anchorScale
    local storedX = Round(offX - baseX)
    local storedY = Round(offY - extraY)
    local appliedX = anchorX * anchorScale + (baseX + storedX) * anchorScale
    local appliedY = anchorY * anchorScale + (extraY + storedY) * anchorScale
    assert(math.abs(appliedX - wantedX) <= anchorScale * 0.5 + 0.001,
        point .. " drag transform drifted horizontally")
    assert(math.abs(appliedY - wantedY) <= anchorScale * 0.5 + 0.001,
        point .. " drag transform drifted vertically")
end

CheckDragTransform("RIGHT", -20, 0)
CheckDragTransform("LEFT", 20, 0)
CheckDragTransform("TOP", 0, 0)
CheckDragTransform("TOP", 0, -40)
CheckDragTransform("TOP", 0, 40)

local timers = {}
local frames = {}
local inCombat = false
local coolinatorLoaded = false
local eventCallbacks = {}

local Frame = {}
Frame.__index = Frame

function Frame:GetName() return self.name end
function Frame:GetWidth() return self.width or 0 end
function Frame:GetHeight() return self.height or 0 end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsForbidden() return false end
function Frame:IsProtected() return self.protected == true end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:SetScript(script, callback) self.scripts[script] = callback end
function Frame:HookScript(script, callback)
    self.hooks[script] = self.hooks[script] or {}
    table.insert(self.hooks[script], callback)
end
function Frame:ClearAllPoints() self.relative = nil end
function Frame:SetAllPoints(relative) self.relative = relative end
function Frame:SetPoint() end
function Frame:EnableMouse() end
function Frame:SetAlpha() end
function Frame:Hide()
    if self.shown == false then return end
    self.shown = false
    for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
end
function Frame:Show()
    if self.shown ~= false then return end
    self.shown = true
    for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
end
function Frame:SetSize(width, height)
    self.width, self.height = width, height
    for _, callback in ipairs(self.hooks.OnSizeChanged or {}) do callback(self, width, height) end
end

local function NewFrame(name, width, height)
    local frame = setmetatable({
        name = name,
        width = width or 0,
        height = height or 0,
        shown = true,
        events = {},
        scripts = {},
        hooks = {},
    }, Frame)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

_G.UIParent = NewFrame("UIParent", 1920, 1080)
_G.WorldFrame = NewFrame("WorldFrame", 1920, 1080)
_G.CreateFrame = function(_, name)
    return NewFrame(name, 1, 1)
end
_G.InCombatLockdown = function() return inCombat end
_G.C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end,
}
_G.C_AddOns = {
    IsAddOnLoaded = function(name)
        return name == "Coolinator" and coolinatorLoaded
    end,
}
_G.EventRegistry = {
    RegisterCallback = function(_, event, callback)
        eventCallbacks[event] = callback
    end,
}

-- Execute the real 5.72 anchor-resolution block. This is the architectural
-- seam that used to rely on the EditMode fallback instead of compiling the
-- global CDM toggle into an explicit frame request.
local resolverBlock = assert(mainSource:match(
    "(local MSUF_COOLDOWN_VIEWER_ANCHORS.-_G%.MSUF_UsesEssentialCooldownAnchor = MSUF_UsesEssentialCooldownAnchor)"
), "could not extract the 5.72 anchor resolver")
local resolvedSource = NewFrame("ResolverCoolinator", 226, 24)
_G.MSUF_DB = { general = { anchorToCooldown = true, anchorName = "UIParent" } }
_G.MSUF_GetEffectiveCooldownFrame = function(name)
    assert(name == "EssentialCooldownViewer")
    return resolvedSource
end
assert(loadstring(resolverBlock, "5.72 anchor resolver"))()
local resolved, missing = _G.MSUF_ResolveConfiguredAnchorFrame(
    "player", { anchorToUnitframe = "GLOBAL" }, _G.UIParent
)
assert(resolved == resolvedSource and missing == nil,
    "global cooldown mode did not resolve to the effective third-party anchor")
assert(_G.MSUF_UsesEssentialCooldownAnchor({ anchorToUnitframe = "GLOBAL" }, _G.MSUF_DB.general) == true,
    "global cooldown mode was not classified as an Essential consumer")
local explicit = NewFrame("ExplicitUnitAnchor", 100, 20)
resolved = _G.MSUF_ResolveConfiguredAnchorFrame(
    "player", { anchorFrameName = "ExplicitUnitAnchor", anchorToUnitframe = "GLOBAL" }, _G.UIParent
)
assert(resolved == explicit,
    "explicit per-unit anchor did not retain precedence over the global cooldown toggle")
assert(_G.MSUF_UsesEssentialCooldownAnchor(
    { anchorFrameName = "ExplicitUnitAnchor", anchorToUnitframe = "GLOBAL" }, _G.MSUF_DB.general
) == false, "explicit per-unit anchor was incorrectly classified as a cooldown consumer")

local rebinds = 0
local widthRefreshes = 0
_G.MSUF_RefreshExternalUnitFrameAnchor = function(frameName)
    assert(frameName == "EssentialCooldownViewer")
    rebinds = rebinds + 1
    return true
end
_G.MSUF_ScheduleCooldownWidthRefresh = function(frameName)
    assert(frameName == "EssentialCooldownViewer")
    widthRefreshes = widthRefreshes + 1
    return true
end

local function FlushTimers(limit)
    limit = limit or 50
    local count = 0
    while #timers > 0 do
        count = count + 1
        assert(count <= limit, "timer retry loop did not terminate")
        local callback = table.remove(timers, 1)
        callback()
    end
end

local function FireEvent(event, addon)
    for i = 1, #frames do
        local frame = frames[i]
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, addon)
        end
    end
end

assert(loadfile(integrationPath))("MidnightSimpleUnitFrames", {})
FlushTimers()

local skironSource = NewFrame("SCM_GroupAnchor_1", 220, 40)
FireEvent("PLAYER_ENTERING_WORLD")
FlushTimers()
assert(_G.MSUF_GetSkironCooldownAnchorProxy() ~= nil,
    "Skiron primary anchor was not acquired")
assert(rebinds == 1 and widthRefreshes == 1,
    "Skiron acquisition did not refresh its consumers")

skironSource:SetSize(264, 40)
FlushTimers()
assert(rebinds == 2,
    "same-source Skiron layout change did not reanchor unitframes")
assert(widthRefreshes == 2,
    "same-source Skiron layout change did not refresh width consumers")

local skironEvent = eventCallbacks["SkironCooldownManager.AnchorProxy.SizeChanged"]
assert(type(skironEvent) == "function", "Skiron layout callback was not registered")
local childGroup = NewFrame("SCM_GroupAnchorProxy_2", 190, 40)
skironEvent(nil, 2, childGroup, 190, 40, "ANCHOR:1", false)
FlushTimers()
assert(_G.MSUF_GetSkironCooldownAnchorProxy().MSUFSkironSource == skironSource,
    "child-group layout event replaced the primary Skiron source")
assert(rebinds == 2 and widthRefreshes == 2,
    "child-group layout event refreshed primary consumers")

local skironRebindBase = rebinds
local skironWidthBase = widthRefreshes

local source = NewFrame("CoolinatorPrimaryGroupAnchor", 226, 24)
coolinatorLoaded = true
FireEvent("ADDON_LOADED", "Coolinator")
assert(_G.MSUF_GetCoolinatorCooldownAnchor() == nil,
    "resolver getter consumed acquisition before the scheduled lifecycle pass")
FlushTimers()
assert(_G.MSUF_GetCoolinatorCooldownAnchor() == source,
    "Coolinator primary anchor was not acquired")
assert(_G.MSUF_IsThirdPartyCooldownAnchor(source) == true,
    "acquired Coolinator source is not classified as a native third-party anchor")
assert(rebinds == skironRebindBase + 1, "Coolinator acquisition did not rebind targeted consumers exactly once")
assert(widthRefreshes == skironWidthBase + 1, "Coolinator acquisition did not refresh width consumers exactly once")
assert(source.hooks.OnSizeChanged and source.hooks.OnShow and source.hooks.OnHide,
    "Coolinator lifecycle hooks were not installed")

source:SetSize(254, 24)
assert(rebinds == skironRebindBase + 1, "same-source resize unnecessarily rebound unitframes")
assert(widthRefreshes == skironWidthBase + 2, "same-source resize did not refresh width consumers")

source:Hide()
assert(_G.MSUF_GetCoolinatorCooldownAnchor() == nil, "hidden Coolinator source remained active")
FlushTimers()
assert(rebinds == skironRebindBase + 2 and widthRefreshes == skironWidthBase + 3,
    "Coolinator loss did not refresh consumers")

source:Show()
assert(_G.MSUF_GetCoolinatorCooldownAnchor() == source, "shown Coolinator source was not reacquired")
FlushTimers()
assert(rebinds == skironRebindBase + 3 and widthRefreshes == skironWidthBase + 4,
    "Coolinator reacquisition did not refresh consumers")

inCombat = true
source:Hide()
assert(_G.MSUF_GetCoolinatorCooldownAnchor() == nil,
    "public resolver exposed a hidden Coolinator source during combat")
assert(rebinds == skironRebindBase + 3, "combat transition rebound protected consumers")
inCombat = false
FireEvent("PLAYER_REGEN_ENABLED")
FlushTimers()
assert(_G.MSUF_GetCoolinatorCooldownAnchor() == nil,
    "deferred Coolinator loss was not reconciled after combat")
assert(rebinds == skironRebindBase + 4 and widthRefreshes == skironWidthBase + 5,
    "post-combat Coolinator reconciliation did not refresh consumers")

print("coolinator anchor 5.72 smoke: OK")
