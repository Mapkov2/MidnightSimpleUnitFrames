-- Regression coverage for detached Power preview/live width parity.

_G = _G or _ENV

local function Exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function Join(left, right)
    left = tostring(left or ""):gsub("[/\\]+$", "")
    right = tostring(right or ""):gsub("^[/\\]+", "")
    return left == "." and "./" .. right or left .. "/" .. right
end

local function ResolveRepositoryRoot()
    for _, root in ipairs({ ".", "..", "../..", "../../.." }) do
        if Exists(Join(root, "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")) then return root end
    end
    error("repository root not found")
end

local ROOT = ResolveRepositoryRoot()
local MSUF = { MSUF2 = {} }
local helperPath = Join(ROOT, "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua")
local chunk, err = loadfile(helperPath)
assert(chunk, err)
chunk("MidnightSimpleUnitFrames", MSUF)

local ResolveWidth = assert(MSUF.MSUF2.ClassPowerPreview.ResolveDetachedPowerWidth)
local cooldown = {
    shown = true,
    GetWidth = function(self) return 218 end,
    IsShown = function(self) return self.shown end,
}
_G.MSUF_GetEffectiveCooldownFrame = function(name)
    if name == "EssentialCooldownViewer" then return cooldown end
end

assert(ResolveWidth({
    shape = "BAR", syncClass = false, classWidth = 280,
    widthMode = "cooldown", manualWidth = 333, frameWidth = 350,
}) == 218, "cooldown width mode incorrectly reused the Class Resource width")

assert(ResolveWidth({
    shape = "BAR", syncClass = true, classWidth = 280,
    widthMode = "cooldown", manualWidth = 333, frameWidth = 350,
}) == 280, "explicit Class Resource sync lost precedence")

assert(ResolveWidth({
    shape = "BAR", syncClass = true, classWidth = 0, classFallbackWidth = 346,
    widthMode = "cooldown", manualWidth = 333, frameWidth = 350,
}) == 346, "unavailable Class Resource width did not use its runtime fallback")

assert(ResolveWidth({
    shape = "BAR", syncClass = false, classWidth = 280,
    widthMode = "manual", manualWidth = 333, frameWidth = 350,
}) == 333, "manual detached width was not preserved")

cooldown.shown = false
assert(ResolveWidth({
    shape = "BAR", syncClass = false, widthMode = "cooldown",
    manualWidth = 333, frameWidth = 350,
}) == 333, "hidden cooldown frame did not fall back to manual width")

local relativeFrame = {}
local sharedWidthRelative
MSUF.UFBarTextCommon = {
    ExternalFrameWidth = function(frameName, relativeTo)
        assert(frameName == "EssentialCooldownViewer", "preview requested the wrong external width source")
        sharedWidthRelative = relativeTo
        return 224
    end,
}
assert(ResolveWidth({
    shape = "BAR", syncClass = false, widthMode = "cooldown",
    manualWidth = 333, frameWidth = 350, relativeTo = relativeFrame,
}) == 224, "preview bypassed the shared scale-aware external width resolver")
assert(sharedWidthRelative == relativeFrame, "preview did not preserve the live bar scale reference")
MSUF.UFBarTextCommon = nil

local canonicalFrame, canonicalPower = {}, {}
local canonicalCalls = 0
MSUF.UF = { Elements = { Power = {
    ResolveDetachedWidth = function(frame, power)
        canonicalCalls = canonicalCalls + 1
        assert(frame == canonicalFrame and power == canonicalPower,
            "preview changed the canonical live width inputs")
        return 229
    end,
} } }
assert(ResolveWidth({
    shape = "BAR", liveFrame = canonicalFrame, livePower = canonicalPower,
    widthMode = "cooldown", manualWidth = 333,
}) == 229 and canonicalCalls == 1,
    "preview did not consume the canonical live detached width resolver")
MSUF.UF = nil

assert(ResolveWidth({
    shape = "ORB", orbSize = 999, syncClass = true,
    classWidth = 280, widthMode = "cooldown", manualWidth = 333,
}) == 160, "orb size must remain independent and clamped to its runtime range")

local advancedSource = Read(Join(ROOT, "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"))
assert(advancedSource:find('APPLY_DETACHED_POWER_WIDTH_MODE = { preview = true, power = true, applyAll = false, classpowerApplied = true }', 1, true),
    "global detached width mode is not routed through the all-Power apply scope")
assert(advancedSource:find('self:Controls(layout, Bars, ApplyDetachedPowerWidthMode, "detached_power.layout"', 1, true),
    "detached width mode still uses the Player-only apply callback")

local factorySource = Read(Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua"))
for _, scriptName in ipairs({ "OnSizeChanged", "OnShow", "OnHide" }) do
    assert(factorySource:find('frame:HookScript("' .. scriptName .. '", OnCooldownWidthSourceChanged)', 1, true),
        "cooldown width lifecycle is missing " .. scriptName)
end
assert(factorySource:find("_G.C_Timer.After(0, FlushCooldownWidthRefresh)", 1, true),
    "cooldown width lifecycle refresh is not coalesced")
assert(factorySource:find("UF.RefreshPowerLayout()", 1, true),
    "cooldown width lifecycle does not refresh all live Power layouts")
assert(factorySource:find('self:UnregisterEvent("PLAYER_REGEN_ENABLED")', 1, true),
    "combat cooldown width changes have no one-shot regen replay")

local renderSource = Read(Join(ROOT, "MidnightSimpleUnitFrames/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua"))
assert(renderSource:find("liveFrame = PreviewLiveFrame(key)", 1, true),
    "live Target frame is not forwarded into the detached width resolver")
local helperSource = Read(Join(ROOT, "MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"))
assert(helperSource:find("return liveResolver(liveFrame, livePower)", 1, true),
    "live Target preview still re-simulates detached width instead of using the live resolver")

local integrationSource = Read(Join(ROOT, "MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua"))
assert(integrationSource:find("proxy.MSUFSkironSource = nil", 1, true),
    "Skiron source loss leaves the stable proxy stale")
assert(integrationSource:find("refreshSkironAnchorProxy(proxy, isActiveProxy, true)", 1, true),
    "same-source Skiron resize does not invalidate detached Power width")
assert(integrationSource:find("MSUF_ScheduleCooldownWidthRefresh", 1, true),
    "Skiron lifecycle does not reach the shared cooldown width refresh")

-- Execute the real Factory lifecycle with fake frames. Source show/hide/resize
-- must coalesce to one all-Power refresh, combat changes must replay on regen,
-- and protected Blizzard sources must not be hooked during lockdown.
local timers = {}
local allFrames = {}
local inCombat = false
local function FakeFrame(name, width, height)
    local frame = {
        name = name,
        width = width or 220,
        height = height or 20,
        shown = true,
        hooks = {},
        events = {},
    }
    function frame:GetName() return self.name end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:IsShown() return self.shown end
    function frame:IsForbidden() return false end
    function frame:IsProtected() return self.protected == true end
    function frame:SetPoint() end
    function frame:ClearAllPoints() self.anchor = nil end
    function frame:SetAllPoints(relativeTo) self.anchor = relativeTo end
    function frame:EnableMouse() end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(script, callback) self.scripts = self.scripts or {}; self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        local callbacks = self.hooks[script]
        if not callbacks then callbacks = {}; self.hooks[script] = callbacks end
        callbacks[#callbacks + 1] = callback
    end
    function frame:FireScript(script, ...)
        local callbacks = self.hooks[script] or {}
        for i = 1, #callbacks do callbacks[i](self, ...) end
    end
    function frame:Show()
        local changed = not self.shown
        self.shown = true
        if changed then self:FireScript("OnShow") end
    end
    function frame:Hide()
        local changed = self.shown
        self.shown = false
        if changed then self:FireScript("OnHide") end
    end
    function frame:SetSize(newWidth, newHeight)
        self.width, self.height = newWidth, newHeight
        self:FireScript("OnSizeChanged", newWidth, newHeight)
    end
    allFrames[#allFrames + 1] = frame
    return frame
end
local function FlushTimers()
    local guard = 0
    while #timers > 0 do
        guard = guard + 1
        assert(guard < 30, "cooldown width timer loop did not settle")
        local queued = timers
        timers = {}
        for i = 1, #queued do queued[i]() end
    end
end
local function FireEvent(event, ...)
    for i = 1, #allFrames do
        local frame = allFrames[i]
        local callback = frame.events[event] and frame.scripts and frame.scripts.OnEvent
        if callback then callback(frame, event, ...) end
    end
end

_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
_G.InCombatLockdown = function() return inCombat end
_G.UIParent = FakeFrame("UIParent", 1920, 1080)
_G.WorldFrame = FakeFrame("WorldFrame", 1920, 1080)
_G.CreateFrame = function(_, name)
    local frame = FakeFrame(name)
    if name then _G[name] = frame end
    return frame
end
local essential = FakeFrame("EssentialCooldownViewer", 222, 20)
_G.EssentialCooldownViewer = essential
_G.UtilityCooldownViewer = nil
_G.BuffIconCooldownViewer = nil
_G.MSUF_GetEffectiveCooldownFrame = function(name) return _G[name] end
_G.MSUF_DB = {
    bars = {
        showClassPower = true,
        classPowerWidthMode = "cooldown",
        detachedPowerBarWidthMode = "cooldown",
    },
    player = { powerBarDetached = true },
    target = { powerBarDetached = true },
    focus = { powerBarDetached = true },
}
local powerRefreshes, classRefreshes = 0, 0
_G.MSUF_ClassPower_Apply = function() classRefreshes = classRefreshes + 1 end
_G.MSUF_UFPreview_RequestRefresh = function() end
local FactoryMSUF = {
    UF = {
        Factory = {},
        unitOrder = {},
        frames = {},
        spawned = true,
        RefreshPowerLayout = function(unit)
            assert(unit == nil, "cooldown width lifecycle refreshed only one unit")
            powerRefreshes = powerRefreshes + 1
        end,
    },
}
local factoryPath = Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua")
assert(loadfile(factoryPath))("MidnightSimpleUnitFrames", FactoryMSUF)
assert(essential.hooks.OnSizeChanged and essential.hooks.OnShow and essential.hooks.OnHide,
    "native cooldown source lifecycle hooks were not installed")

essential:Hide()
assert(#timers == 1, "native source hide did not queue one coalesced refresh")
FlushTimers()
assert(powerRefreshes == 1 and classRefreshes == 1,
    "native source hide did not refresh Class Resource and all detached Power bars")
essential:Show()
essential:SetSize(236, 20)
assert(#timers == 1, "same-frame source show/resize was not coalesced")
FlushTimers()
assert(powerRefreshes == 2, "native source reappearance/resize did not refresh all Power bars")

inCombat = true
essential:Hide()
assert(#timers == 0, "combat source hide ran a layout timer during lockdown")
inCombat = false
FireEvent("PLAYER_REGEN_ENABLED")
assert(#timers == 1, "combat source hide was not replayed once after regen")
FlushTimers()
assert(powerRefreshes == 3 and classRefreshes == 3,
    "post-combat replay did not refresh both live width owners")

local protected = FakeFrame("EssentialCooldownViewer", 248, 20)
protected.protected = true
_G.EssentialCooldownViewer = protected
inCombat = true
_G.MSUF_EnsureCooldownWidthObservers()
assert(protected.hooks.OnSizeChanged == nil, "protected cooldown source was hooked during combat")
inCombat = false
FireEvent("PLAYER_REGEN_ENABLED")
assert(protected.hooks.OnSizeChanged and #timers == 1,
    "protected cooldown source hook was not installed safely after combat")
FlushTimers()

-- Execute the real Skiron integration. Backing-frame hide/show is significant
-- even when width is unchanged; relying only on Skiron's size callback leaves
-- the stable proxy and live Target stale.
local registryCallback
_G.EventRegistry = {
    RegisterCallback = function(_, event, callback)
        assert(event == "SkironCooldownManager.AnchorProxy.SizeChanged", "unexpected Skiron event")
        registryCallback = callback
    end,
}
local skironSource = FakeFrame("SCM_GroupAnchorProxy_1", 222, 20)
skironSource.shown = false
local skironFallback = FakeFrame("SCM_GroupAnchor_1", 222, 20)
_G.SCM_GroupAnchorProxy_1 = skironSource
_G.SCM_GroupAnchor_1 = skironFallback
local factoryApplies = 0
FactoryMSUF.UF.Factory.Apply = function() factoryApplies = factoryApplies + 1; return true end
local integrationPath = Join(ROOT, "MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua")
assert(loadfile(integrationPath))("MidnightSimpleUnitFrames", FactoryMSUF)
assert(type(registryCallback) == "function", "Skiron callback was not registered")
FlushTimers()
local stableProxy = assert(_G.MSUF_SkironCooldownAnchor, "Skiron stable proxy was not created")
assert(skironSource.hooks.OnHide and skironSource.hooks.OnShow and skironSource.hooks.OnSizeChanged,
    "hidden Skiron proxy lifecycle hooks were not installed")
assert(skironFallback.hooks.OnHide and stableProxy.MSUFSkironSource == skironFallback,
    "visible Skiron fallback source was not observed and attached")

skironFallback:Hide()
FlushTimers()
assert(stableProxy.MSUFSkironSource == nil, "Skiron fallback loss left the stable proxy attached")

powerRefreshes, classRefreshes, factoryApplies = 0, 0, 0
skironSource:Show()
assert(stableProxy.MSUFSkironSource == skironSource,
    "same-size hidden Skiron proxy did not take ownership on Show")
FlushTimers()
assert(powerRefreshes == 1 and factoryApplies == 1,
    "same-size Skiron proxy Show did not reapply live Target/Focus width")

skironSource:Hide()
assert(stableProxy.MSUFSkironSource == nil and stableProxy.shown == false,
    "Skiron source hide left the stable proxy attached")
FlushTimers()
assert(powerRefreshes == 2 and factoryApplies == 2,
    "Skiron source hide did not refresh live width")

skironSource:Show()
FlushTimers()
assert(powerRefreshes == 3 and factoryApplies == 3,
    "same-size Skiron source reappearance did not refresh live width")

skironSource:SetSize(244, 20)
FlushTimers()
assert(powerRefreshes == 4,
    "same-proxy Skiron resize did not refresh live width")

print("detached power preview width smoke: ok")
