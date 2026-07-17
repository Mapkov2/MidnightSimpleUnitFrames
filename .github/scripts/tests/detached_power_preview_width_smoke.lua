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
assert(not factorySource:find("UF.RefreshPowerLayout()", 1, true),
    "cooldown width lifecycle still recompiles full Power layouts")
assert(factorySource:find("RefreshDetachedExternalWidth", 1, true),
    "cooldown width lifecycle does not use the width-only Power helper")
assert(factorySource:find("cooldownWidthSourceGeneration", 1, true),
    "cooldown width observer replacement has no generation fastpath")
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
assert(integrationSource:find('factory.RefreshExternalAnchor("EssentialCooldownViewer")', 1, true),
    "Skiron source transitions do not use the targeted external-anchor refresh")
assert(not integrationSource:find("factory.Apply(", 1, true),
    "Skiron lifecycle still invokes the full unit-frame Factory.Apply path")

-- Execute the real Factory lifecycle with fake frames. Only configured sources
-- may be observed. A source event must call the Class Resource layout-only API
-- first, then the width-only helper for every managed Power consumer without a
-- config compile, full element apply, or Factory.Apply.
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
local utility = FakeFrame("UtilityCooldownViewer", 230, 20)
local trackedBuffs = FakeFrame("BuffIconCooldownViewer", 238, 20)
_G.EssentialCooldownViewer = essential
_G.UtilityCooldownViewer = utility
_G.BuffIconCooldownViewer = trackedBuffs
local effectiveFrames = {
    EssentialCooldownViewer = essential,
    UtilityCooldownViewer = utility,
    BuffIconCooldownViewer = trackedBuffs,
}
local resolverCalls = {}
_G.MSUF_GetEffectiveCooldownFrame = function(name)
    resolverCalls[name] = (resolverCalls[name] or 0) + 1
    return effectiveFrames[name]
end
_G.MSUF_DB = {
    bars = {
        showClassPower = true,
        classPowerWidthMode = "cooldown",
        detachedPowerBarWidthMode = "cooldown",
    },
    player = { powerBarDetached = true, detachedPowerBarSyncClassPower = true },
    target = { powerBarDetached = true },
    focus = { powerBarDetached = true },
    targettarget = { powerBarDetached = true },
    focustarget = { powerBarDetached = true },
    pet = { powerBarDetached = true },
    boss = { powerBarDetached = true },
}
local UNIT_ORDER = {
    "player", "target", "focus", "targettarget", "focustarget", "pet",
    "boss1", "boss2", "boss3", "boss4", "boss5",
}
local refreshTrace = {}
local castbarRefreshTrace = {}
local previewRefreshes = 0
_G.MSUF_ClassPower_RefreshExternalWidth = function(sourceName)
    refreshTrace[#refreshTrace + 1] = "class:" .. tostring(sourceName)
    return true
end
_G.MSUF_ClassPower_Apply = function()
    error("cooldown width lifecycle used the full ClassPower apply path")
end
_G.MSUF_ClassPower_RefreshLayout = function()
    error("cooldown width lifecycle bypassed its source-specific ClassPower API")
end
_G.MSUF_UFPreview_RequestRefresh = function()
    previewRefreshes = previewRefreshes + 1
end
_G.MSUF_RefreshCastbarCooldownWidthSource = function(sourceName)
    castbarRefreshTrace[#castbarRefreshTrace + 1] = sourceName
    return true
end
local unitFrames = {}
for i = 1, #UNIT_ORDER do
    local unit = UNIT_ORDER[i]
    local frame = FakeFrame("MSUF_Test_" .. unit, 300, 30)
    frame.unit = unit
    frame.targetPowerBar = {}
    frame.MSUFSpec = {
        power = {
            enabled = true,
            detached = true,
            detachedSyncClass = unit == "player",
            detachedClassWidthFrameName = unit == "player" and "EssentialCooldownViewer" or nil,
            detachedWidthFrameName = unit ~= "player" and "EssentialCooldownViewer" or nil,
        },
    }
    unitFrames[unit] = frame
end
local FactoryMSUF = {
    UF = {
        Factory = {},
        Elements = { Power = {
            RefreshDetachedExternalWidth = function(frame, sourceName)
                refreshTrace[#refreshTrace + 1] = "power:" .. tostring(frame and frame.unit)
                assert(sourceName == (frame.unit == "player"
                    and frame.MSUFSpec.power.detachedClassWidthFrameName
                    or frame.MSUFSpec.power.detachedWidthFrameName),
                    "width-only Power helper received the wrong source")
                return true
            end,
        } },
        unitOrder = UNIT_ORDER,
        frames = unitFrames,
        spawned = true,
        RefreshPowerLayout = function()
            error("cooldown width lifecycle called UF.RefreshPowerLayout")
        end,
    },
}
local factoryPath = Join(ROOT, "MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua")
assert(loadfile(factoryPath))("MidnightSimpleUnitFrames", FactoryMSUF)
assert(essential.hooks.OnSizeChanged and essential.hooks.OnShow and essential.hooks.OnHide,
    "native cooldown source lifecycle hooks were not installed")
assert(not utility.hooks.OnSizeChanged and not trackedBuffs.hooks.OnSizeChanged,
    "unconfigured cooldown sources received lifecycle hooks")
assert(resolverCalls.EssentialCooldownViewer == 1
    and resolverCalls.UtilityCooldownViewer == nil
    and resolverCalls.BuffIconCooldownViewer == nil,
    "observer bootstrap resolved more than the configured source")

local function ResetRefreshTrace()
    refreshTrace = {}
    castbarRefreshTrace = {}
    previewRefreshes = 0
end

local function AssertWidthOnlyBatch(sourceName, message)
    assert(#refreshTrace == #UNIT_ORDER + 1,
        message .. ": expected one class layout and every live Power width")
    assert(refreshTrace[1] == "class:" .. sourceName,
        message .. ": Class Resource layout-only refresh did not run first")
    for i = 1, #UNIT_ORDER do
        assert(refreshTrace[i + 1] == "power:" .. UNIT_ORDER[i],
            message .. ": width-only Power order mismatch at " .. UNIT_ORDER[i])
    end
    assert(#castbarRefreshTrace == 0, message .. ": unrelated castbar refresh ran")
    assert(previewRefreshes == 1, message .. ": preview refresh was not coalesced")
end

local resolvedBeforeFastpath = resolverCalls.EssentialCooldownViewer
assert(_G.MSUF_EnsureCooldownWidthObservers() == true,
    "same-generation observer fastpath lost the active source")
assert(resolverCalls.EssentialCooldownViewer == resolvedBeforeFastpath,
    "same-generation observer fastpath resolved frames again")

ResetRefreshTrace()
essential:Hide()
essential:Show()
essential:SetSize(236, 20)
assert(#timers == 1, "same-frame source hide/show/resize was not coalesced")
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "coalesced native lifecycle")

ResetRefreshTrace()
inCombat = true
essential:SetSize(242, 20)
essential:SetSize(244, 20)
assert(#timers == 0, "combat source resize ran a layout timer during lockdown")
inCombat = false
FireEvent("PLAYER_REGEN_ENABLED")
assert(#timers == 1, "combat source hide was not replayed once after regen")
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "post-combat replay")

-- Force-resolving a replacement advances the active generation. Hooks on the
-- retired frame stay physically installed (WoW cannot unhook scripts) but must
-- become inert, while the new effective frame is observed exactly once.
local replacement = FakeFrame("EssentialCooldownViewerReplacement", 248, 20)
effectiveFrames.EssentialCooldownViewer = replacement
local replacementResolveBefore = resolverCalls.EssentialCooldownViewer
assert(_G.MSUF_EnsureCooldownWidthObservers(true) == true,
    "forced observer generation did not resolve the replacement source")
assert(resolverCalls.EssentialCooldownViewer == replacementResolveBefore + 1,
    "forced observer generation resolved the configured source more than once")
assert(replacement.hooks.OnSizeChanged and #replacement.hooks.OnSizeChanged == 1,
    "replacement cooldown source was not hooked exactly once")
ResetRefreshTrace()
essential:SetSize(250, 20)
assert(#timers == 0, "retired cooldown source hook remained active")
replacement:SetSize(252, 20)
assert(#timers == 1, "replacement cooldown source did not schedule a refresh")
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "replacement source")

-- Changing the configured source invalidates the observer generation and scans
-- only the newly required source. The old source hook must remain inert.
_G.MSUF_DB.bars.classPowerWidthMode = "utility"
_G.MSUF_DB.bars.detachedPowerBarWidthMode = "utility"
for i = 1, #UNIT_ORDER do
    local power = unitFrames[UNIT_ORDER[i]].MSUFSpec.power
    power.detachedClassWidthFrameName = UNIT_ORDER[i] == "player" and "UtilityCooldownViewer" or nil
    power.detachedWidthFrameName = UNIT_ORDER[i] ~= "player" and "UtilityCooldownViewer" or nil
end
assert(_G.MSUF_EnsureCooldownWidthObservers() == true,
    "newly configured Utility source was not observed")
assert(utility.hooks.OnSizeChanged and #utility.hooks.OnSizeChanged == 1,
    "Utility observer was not installed exactly once")
assert(not trackedBuffs.hooks.OnSizeChanged,
    "unconfigured tracked-buff source was scanned during a Utility transition")
ResetRefreshTrace()
replacement:SetSize(254, 20)
assert(#timers == 0, "previously configured Essential hook remained active")
utility:SetSize(256, 20)
assert(#timers == 1, "configured Utility source did not schedule a refresh")
FlushTimers()
AssertWidthOnlyBatch("UtilityCooldownViewer", "source-specific Utility lifecycle")

-- Castbars measure their preferred container rather than always measuring the
-- viewer. Container lifecycle must therefore be observed as castbar-only work:
-- no ClassPower/Power pass, but the live castbar and Unit Preview both refresh.
local utilityContainer = FakeFrame("UtilityCooldownViewer_AnchorContainer", 264, 20)
_G.UtilityCooldownViewer_AnchorContainer = utilityContainer
_G.MSUF_DB.bars.classPowerWidthMode = "player"
_G.MSUF_DB.bars.detachedPowerBarWidthMode = "manual"
_G.MSUF_DB.general = { castbarTargetMatchWidth = "utility", enableTargetCastbar = true }
assert(_G.MSUF_EnsureCooldownWidthObservers() == true,
    "castbar-only Utility source was not observed")
assert(utilityContainer.hooks.OnSizeChanged and #utilityContainer.hooks.OnSizeChanged == 1,
    "preferred Utility castbar container was not hooked exactly once")
local resolverBeforeContainer = resolverCalls.UtilityCooldownViewer
ResetRefreshTrace()
utilityContainer:SetSize(270, 20)
assert(#timers == 1, "castbar container resize was not coalesced")
FlushTimers()
assert(#refreshTrace == 0, "castbar-only container resize reached ClassPower/Power")
assert(#castbarRefreshTrace == 1 and castbarRefreshTrace[1] == "UtilityCooldownViewer",
    "castbar-only container resize did not refresh the matching live castbar")
assert(previewRefreshes == 1, "castbar-only container resize left Unit Preview stale")
assert(resolverCalls.UtilityCooldownViewer == resolverBeforeContainer,
    "source callback bypassed the cached observer-generation fastpath")

-- A protected source first discovered during combat cannot be hooked until
-- regen. Installing that hook must also perform one reconciliation because no
-- callback could have recorded changes from the unobserved interval.
local protectedTracked = FakeFrame("BuffIconCooldownViewerProtected", 278, 20)
protectedTracked.protected = true
effectiveFrames.BuffIconCooldownViewer = protectedTracked
_G.MSUF_DB.bars.classPowerWidthMode = "tracked_buffs"
_G.MSUF_DB.bars.detachedPowerBarWidthMode = "tracked_buffs"
_G.MSUF_DB.general = nil
for i = 1, #UNIT_ORDER do
    local power = unitFrames[UNIT_ORDER[i]].MSUFSpec.power
    power.detachedClassWidthFrameName = UNIT_ORDER[i] == "player" and "BuffIconCooldownViewer" or nil
    power.detachedWidthFrameName = UNIT_ORDER[i] ~= "player" and "BuffIconCooldownViewer" or nil
end
ResetRefreshTrace()
inCombat = true
assert(_G.MSUF_EnsureCooldownWidthObservers() == false,
    "protected source observer unexpectedly installed during combat")
assert(not protectedTracked.hooks.OnSizeChanged,
    "protected cooldown source was hooked during combat")
inCombat = false
FireEvent("PLAYER_REGEN_ENABLED")
assert(protectedTracked.hooks.OnSizeChanged and #timers == 1,
    "protected source was not hooked and reconciled once after regen")
FlushTimers()
AssertWidthOnlyBatch("BuffIconCooldownViewer", "protected-source regen reconciliation")

-- Restore the Essential configuration used by the Skiron integration below.
_G.MSUF_DB.bars.classPowerWidthMode = "cooldown"
_G.MSUF_DB.bars.detachedPowerBarWidthMode = "cooldown"
_G.MSUF_DB.general = nil
for i = 1, #UNIT_ORDER do
    local power = unitFrames[UNIT_ORDER[i]].MSUFSpec.power
    power.detachedClassWidthFrameName = UNIT_ORDER[i] == "player" and "EssentialCooldownViewer" or nil
    power.detachedWidthFrameName = UNIT_ORDER[i] ~= "player" and "EssentialCooldownViewer" or nil
end
assert(_G.MSUF_EnsureCooldownWidthObservers() == true,
    "Essential observer was not reactivated after the source change")

-- Execute the real Skiron integration. Backing-frame hide/show is significant
-- even when width is unchanged. Acquisition/loss rebind only explicit external
-- anchor consumers; resize is width-only. None of these may invoke Factory.Apply.
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
local externalAnchorRefreshes = 0
FactoryMSUF.UF.Factory.RefreshExternalAnchor = function(frameName)
    assert(frameName == "EssentialCooldownViewer", "Skiron refreshed the wrong external anchor")
    externalAnchorRefreshes = externalAnchorRefreshes + 1
    return true
end
FactoryMSUF.UF.Factory.Apply = function()
    error("Skiron lifecycle invoked full Factory.Apply")
end
local integrationPath = Join(ROOT, "MidnightSimpleUnitFrames/Integrations/MSUF_Integration_ThirdPartyAnchors.lua")
ResetRefreshTrace()
assert(loadfile(integrationPath))("MidnightSimpleUnitFrames", FactoryMSUF)
assert(type(registryCallback) == "function", "Skiron callback was not registered")
assert(_G.MSUF_GetSkironCooldownAnchorProxy() == nil and _G.MSUF_SkironCooldownAnchor == nil,
    "Skiron resolver getter consumed acquisition before the lifecycle handler")
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "Skiron initial acquisition")
assert(externalAnchorRefreshes == 1,
    "Skiron initial acquisition did not target external-anchor consumers once")
local stableProxy = assert(_G.MSUF_SkironCooldownAnchor, "Skiron stable proxy was not created")
assert(skironSource.hooks.OnHide and skironSource.hooks.OnShow and skironSource.hooks.OnSizeChanged,
    "hidden Skiron proxy lifecycle hooks were not installed")
assert(skironFallback.hooks.OnHide and stableProxy.MSUFSkironSource == skironFallback,
    "visible Skiron fallback source was not observed and attached")

ResetRefreshTrace()
skironFallback:Hide()
FlushTimers()
assert(stableProxy.MSUFSkironSource == nil, "Skiron fallback loss left the stable proxy attached")
AssertWidthOnlyBatch("EssentialCooldownViewer", "Skiron fallback loss")
assert(externalAnchorRefreshes == 2,
    "Skiron source loss did not target external-anchor consumers")

ResetRefreshTrace()
skironSource:Show()
assert(stableProxy.MSUFSkironSource == skironSource,
    "same-size hidden Skiron proxy did not take ownership on Show")
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "Skiron source acquisition")
assert(externalAnchorRefreshes == 3,
    "same-size Skiron acquisition did not target external-anchor consumers")

ResetRefreshTrace()
skironSource:SetSize(244, 20)
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "same-source Skiron resize")
assert(externalAnchorRefreshes == 3,
    "same-source Skiron resize unnecessarily rebound unit-frame anchors")

ResetRefreshTrace()
skironSource:Hide()
assert(stableProxy.MSUFSkironSource == nil and stableProxy.shown == false,
    "Skiron source hide left the stable proxy attached")
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "Skiron source loss")
assert(externalAnchorRefreshes == 4,
    "Skiron source hide did not target external-anchor consumers")

ResetRefreshTrace()
skironSource:Show()
FlushTimers()
AssertWidthOnlyBatch("EssentialCooldownViewer", "Skiron source reappearance")
assert(externalAnchorRefreshes == 5,
    "Skiron source reappearance did not target external-anchor consumers")

print("detached power preview width smoke: ok")
