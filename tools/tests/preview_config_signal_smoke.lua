-- Settings notifications use the real shipped providers and visible preview ownership.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, flavor)
local mutations = {
    ["no-publish"] = { "MSUF_UF_Runtime.lua", 'MSUF.EventBus:Publish("CONFIG_APPLIED", "MSUF_RefreshAllUnitAlphas")', "do end" },
    ["native-signal"] = { "MSUF_EventBus.lua", 'bus:DefineEvent("CONFIG_APPLIED")', "do end" },
    ["no-unsubscribe"] = { "MSUF_Menu2_UnitPreview_API.lua", 'bus:Unregister("CONFIG_APPLIED", CONFIG_SUBSCRIBER)', "do end" },
    ["combat-publish"] = { "MSUF_Menu2_UnitPreview_API.lua",
        'if not PreviewInCombat() then Preview.RequestRefresh(reason) end', 'Preview.RequestRefresh(reason)' },
    ["commit-publish"] = { "MSUF_UF_TextureLayer.lua", '  RecomputeDriverNeeds(frames)',
        '  RecomputeDriverNeeds(frames)\n  MSUF.EventBus:Publish("CONFIG_APPLIED", "internal-commit")' },
    ["status-fast-reason"] = { "MSUF_UF_Elements_Status.lua",
        'MSUF.EventBus:Publish("CONFIG_APPLIED", STATUS_REFRESH_ALIASES[i])',
        'MSUF.EventBus:Publish("CONFIG_APPLIED", reason or "MSUF_STATUS")' },
}
local mutation = mutations[arg[3]]
if mutation then
    local loadFile = world.LoadFile
    world.LoadFile = function(self, path, addon, namespace)
        if not path:find(mutation[1], 1, true) then return loadFile(self, path, addon, namespace) end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local first, last = assert(source:find(mutation[2], 1, true))
        local chunk = assert(loadstring(source:sub(1, first - 1) .. mutation[3] .. source:sub(last + 1), "@" .. path))
        setfenv(chunk, self.env)
        return pcall(chunk, addon, namespace)
    end
end
local timerWidgets = world.widgets
for _, name in ipairs({ "After", "NewTimer" }) do
    local native = world.env.C_Timer[name]
    world.env.C_Timer[name] = function(delay, callback)
        local result = native(delay, callback)
        local entry = timerWidgets.timers[#timerWidgets.timers]
        if entry then entry.due = timerWidgets:GetTime() + delay end
        return result
    end
end
local function Advance(delta)
    local target, ran = timerWidgets:GetTime() + delta, 0
    while true do
        local selected, due
        for index, entry in ipairs(timerWidgets.timers) do
            if entry.due <= target and (not due or entry.due < due) then selected, due = index, entry.due end
        end
        if not selected then break end
        local entry = table.remove(timerWidgets.timers, selected)
        timerWidgets:SetTime(due)
        if not entry.cancelled and not (entry.timer and entry.timer.cancelled) then entry.callback() end
        ran = ran + 1
        assert(ran < 2000, "test timer loop did not settle")
    end
    timerWidgets:SetTime(target)
end
world.env.MAX_BOSS_FRAMES = 5
world.env.UnitExists = function() return false end
world.env.UnitName = function() return "Player" end
for name, value in pairs({ UnitHealth = 500000, UnitHealthMax = 1000000, UnitPower = 100, UnitPowerMax = 100,
    UnitPowerType = 0, UnitHealthPercent = 50, UnitPowerPercent = 100, UnitGetTotalAbsorbs = 0,
    UnitGetIncomingHeals = 0, UnitGetTotalHealAbsorbs = 0, UnitEffectiveLevel = 90, GetMaxPlayerLevel = 90,
    GetMaxLevelForPlayerExpansion = 90 }) do world.env[name] = function() return value end end
world.env.AbbreviateNumbers, world.env.AbbreviateLargeNumbers = tostring, tostring
world.env.C_StringUtil = { AbbreviateNumbers = tostring, AbbreviateLargeNumbers = tostring }
world:Boot()
local failure = world:FirstFailure()
assert(not failure, tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
local env, ns, widgets = world.env, world.core, world.widgets
-- Unknown frame globals in the boot harness use a truthy sentinel. Native
-- missing named frames are nil; false permits the real factory to create them.
for _, unit in ipairs(ns.UF.unitOrder) do env[ns.UF.FrameName(unit)] = false end
env.MSUF_EnsureDB(true)
local Preview, M, bus = ns.UFPreview, ns.MSUF2, ns.EventBus
-- A provider is a kept global or an export the namespace registry holds (namespace-only names).
local function Provider(name)
    local value = rawget(env, name)
    if value == nil then value = ns.PublicGlobals[name] end
    return value
end
local shown, wrapperShown, menuShown = true, true, true
M.frame = { IsShown = function() return menuShown end }
M.activeKey = "unit-test"
local wrapper = { IsShown = function() return wrapperShown end }
local box = {
    IsShown = function() return shown end,
    Hide = function(self)
        shown = false
        if Preview.active == self then Preview.active = nil end
        Preview.UninstallRefreshHooks()
    end,
    _msuf2PinnedPreviewPageKey = "unit-test",
    _msuf2PinnedPreviewWrapper = wrapper,
}
local refreshes, requested = {}, {}
Preview.Refresh = function(_, reason) refreshes[#refreshes + 1] = reason end
local originalRequest = Preview.RequestRefresh
Preview.RequestRefresh = function(reason)
    requested[#requested + 1] = reason
    return originalRequest(reason)
end
local originalFonts, originalTextures = env.MSUF_UpdateAllFonts, env.MSUF_UpdateAllBarTextures
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.01)
assert(env.MSUF_UpdateAllFonts == originalFonts and env.MSUF_UpdateAllBarTextures == originalTextures,
    "showing a preview replaced a public refresh function")
assert(bus.internalEvents.CONFIG_APPLIED == true, "settings signal is not an internal event")
assert(not bus.driver:IsEventRegistered("CONFIG_APPLIED"), "settings signal registered a native event")
local signals = 0
bus:Register("CONFIG_APPLIED", "test.config-signal", function() signals = signals + 1 end)
local providers = {
    "MSUF_ForceTextLayoutForUnitKey", "MSUF_UpdateAllFonts", "MSUF_UpdateAllFonts_Immediate",
    "MSUF_UpdateAllBarTextures", "MSUF_UpdateAllBarTextures_Immediate", "MSUF_UpdateCastbarVisuals",
    "MSUF_ApplyCastbarUnitAndSync", "MSUF_ApplyCastbarVisualsForUnit", "MSUF_SyncCastbarPositionPopup",
    "MSUF_SyncUnitPositionPopup", "MSUF_ApplyUnitFrameKey_Immediate", "MSUF_UFCore_RefreshSettingsCache",
    "MSUF_RefreshAllIdentityColors", "MSUF_RefreshAllPowerTextColors", "MSUF_RefreshAllFrames",
    "MSUF_RefreshAllUnitAlphas", "MSUF_RequestAlphaRefresh", "MSUF_ClassPower_Apply", "MSUF_ClassPower_Refresh",
    "MSUF_ApplyPowerBarEmbedLayout", "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
    "MSUF_RefreshRaidMarkerFrames", "MSUF_RefreshLeaderIconFrames", "MSUF_RefreshLevelIndicatorFrames",
    "MSUF_RefreshIdentityTextFrames", "MSUF_RefreshEliteIconFrames", "MSUF_RequestStatusTextRefresh",
    "MSUF_RequestStatusCombatIndicatorRefresh", "MSUF_RequestStatusRestingIndicatorRefresh",
    "MSUF_RequestStatusIncomingResIndicatorRefresh", "MSUF_SyncAuras3PositionPopup", "MSUF_RefreshUnitTextureLayers",
}
for _, name in ipairs(providers) do
    local provider = assert(Provider(name), "missing real provider " .. name)
    local beforeSignals, beforeRequests = signals, #requested
    if name == "MSUF_ClassPower_Apply" then provider({})
    elseif name == "MSUF_ClassPower_Refresh" or name == "MSUF_UFCore_RefreshSettingsCache"
        or name == "MSUF_ApplyPowerBarEmbedLayout" then provider()
    else provider("player") end
    assert(signals > beforeSignals, name .. " did not publish after its direct exported call")
    assert(#requested > beforeRequests, name .. " did not reach the active preview")
    assert(Provider(name) == provider, name .. " was replaced during delivery")
    Advance(0.06)
end
local function Publish(reason) bus:Publish("CONFIG_APPLIED", reason) end
Advance(5)
Advance(0.1)
local beforeInternalSignals = signals
ns.UF.Factory.Apply("target")
assert(signals == beforeInternalSignals, "internal surface commit published a cold settings notification")
local before = #refreshes
local beforeTimers = #widgets.timers
Publish("first")
Publish("second")
Publish("third")
assert(#widgets.timers == beforeTimers + 1, "settings burst allocated more than one refresh task")
Advance(0.049)
assert(#refreshes == before, "settings debounce was shortened")
Advance(0.002)
assert(#refreshes == before + 1 and refreshes[#refreshes] == "third",
    "burst did not coalesce to its final reason: " .. #refreshes .. "/" .. before .. "/" .. tostring(refreshes[#refreshes]))
before = #refreshes
Provider("MSUF_RequestStatusTextRefresh")("player", "MSUF2_CALLER_STATUS_REASON")
Advance(0.001)
assert(#refreshes == before, "caller status reason changed the original direct-call debounce")
Advance(0.05)
assert(#refreshes == before + 1 and refreshes[#refreshes] == "MSUF_RequestStatusTextRefresh",
    "status adapter lost its original direct-call reason and delay")
Publish("MSUF2_TYPED_APPLY")
Advance(0.001)
assert(refreshes[#refreshes] == "MSUF2_TYPED_APPLY", "typed UI reason lost immediate scheduling")
before = #refreshes
assert(ns.ApplyService.RequestUnitDomains("player", "MSUF2_REAL_TYPED_APPLY", { notify = false, text = true }))
Advance(0.039)
assert(#refreshes == before, "typed application refreshed before its existing apply delay")
-- The direct text provider already queued the existing 0.05s refresh during
-- the 0.04s flush. The typed reason updates that task rather than replacing it.
Advance(0.06)
assert(#refreshes == before + 1 and refreshes[#refreshes] == "MSUF2_REAL_TYPED_APPLY",
    "real typed apply did not publish through the UI bridge")
Advance(0.1)
before = #refreshes
Publish("UNIT_PREVIEW_LIVE_STATE")
Advance(0.19)
assert(#refreshes == before, "live mirror delay was shortened")
Advance(0.02)
assert(#refreshes == before + 1, "live mirror refresh was lost")
-- Keep the existing PreviewInCombat predicate and its direct-call suppression.
widgets:SetCombat(true)
before = #requested
Publish("combat-suppressed")
assert(#requested == before, "settings signal changed the old in-combat suppression")
Preview.RequestRefreshForBox(box, "combat-explicit")
assert(box._refreshAfterCombatReason == "combat-explicit", "explicit combat request was lost")
widgets:SetCombat(false)
world:FireEvent("PLAYER_REGEN_ENABLED")
Advance(0.06)
assert(refreshes[#refreshes] == "combat-explicit", "combat exit did not deliver the one explicit retry")
before = #refreshes
world:FireEvent("PLAYER_REGEN_ENABLED")
Advance(0.06)
assert(#refreshes == before, "combat retry remained registered")
-- Hide invalidates a pending timer; showing immediately subscribes once.
Publish("cancel-on-hide")
box:Hide()
Advance(0.06)
assert(#refreshes == before, "hidden preview executed a queued refresh")
before = #requested
Publish("hidden")
assert(#requested == before, "hidden preview remained subscribed")
shown = true
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.01)
before = #requested
Publish("shown-again")
assert(#requested == before + 1, "immediate reshow lost or duplicated its subscription")
Advance(0.06)
-- A hidden former owner must not disconnect the replacement box, including
-- replacement during a notification callback.
local replacementShown = true
local replacement = { IsShown = function() return replacementShown end }
local swapped = false
Preview.RequestRefresh = function(reason)
    if reason == "swap-owner" and not swapped then
        swapped = true
        Preview.RequestRefreshForBox(replacement, "SHOW")
        box:Hide()
    end
    return originalRequest(reason)
end
Publish("swap-owner")
Advance(0.06)
assert(Preview.active == replacement and refreshes[#refreshes] == "swap-owner", "reentrant owner handoff was lost")
before = #refreshes
Publish("replacement-owner")
Advance(0.06)
assert(#refreshes == before + 1 and refreshes[#refreshes] == "replacement-owner", "old owner unsubscribed its replacement")
replacementShown, Preview.active = false, nil
Preview.UninstallRefreshHooks()
Preview.RequestRefresh = function(reason)
    requested[#requested + 1] = reason
    return originalRequest(reason)
end
shown, wrapperShown, box._msuf2PinnedFloating = true, true, nil
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.01)
Publish("queued-owner-change")
M.activeKey = "other-page"
Advance(0.06)
local subscriptions = bus.handlers.CONFIG_APPLIED
assert(Preview.active == nil and not (subscriptions and subscriptions.index["Menu2.UnitPreview.ConfigApplied"]),
    "queued refresh left its inactive owner subscribed")
M.activeKey, shown = "unit-test", true
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.01)
M.activeKey = "other-page"
before = #requested
Publish("inactive-page")
assert(#requested == before and Preview.active == nil, "inactive page retained its subscription")
M.activeKey, shown, wrapperShown = "unit-test", true, false
box._msuf2PinnedFloating = true
Preview.RequestRefreshForBox(box, "SHOW")
Advance(0.01)
before = #requested
Publish("floating")
assert(#requested == before + 1, "floating owner followed its hidden wrapper")
Advance(0.06)
box:Hide()
bus:Unregister("CONFIG_APPLIED", "test.config-signal")
assert(bus.handlers.CONFIG_APPLIED == nil, "preview leaked its settings subscription")
print("preview_config_signal_smoke: " .. flavor .. " 33 real direct providers and ownership/debounce/combat lifecycle passed")
