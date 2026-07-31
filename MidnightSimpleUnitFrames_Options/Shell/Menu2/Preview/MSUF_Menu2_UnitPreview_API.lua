--- Unit preview public API, refresh hooks, and legacy globals.
-- Bridges preview refresh calls for Menu2 without owning live unit-frame runtime state.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local Preview = MSUF.UFPreview or MSUF.MSUF_UFPreview or _G.MSUF_UFPreview
if not Preview then return end
local M = (MSUF and MSUF.MSUF2) or _G.MSUF2 or {}
local C_Timer = M.MenuTimer or _G.C_Timer
local WordList = M.WordList
local InstallPreviewHooks
local UninstallPreviewHooks
local UNIT_PREVIEW_REFRESH_DELAY = 0.05
local FAST_REFRESH_REASONS = {
    SHOW = true,
    COMBAT_ALPHA = true,
    STATUS_PREVIEW_MODE = true,
    STATUS_PREVIEW_SELECT = true,
    MENU_TEXT_FOCUS = true,
    MENU_TEXT_CLEAR_FOCUS = true,
}
local UNIT_PREVIEW_LIVE_STATE_DELAY = 0.2
local function PreviewRefreshDelay(reason)
    reason = tostring(reason or "")
    if FAST_REFRESH_REASONS[reason] or reason:find("^MSUF2_") or reason:find("^AURAS3_") then return 0 end
    -- Live-mirror events (health/power ticks out of combat) coalesce on a
    -- wider window so regen streams cost at most five renders per second.
    if reason == "UNIT_PREVIEW_LIVE_STATE" then return UNIT_PREVIEW_LIVE_STATE_DELAY end
    return UNIT_PREVIEW_REFRESH_DELAY
end
local function PreviewInCombat()
    local fn = Preview._PreviewInCombat
    return type(fn) == "function" and fn() or false
end
local function CancelQueuedRefresh(box)
    if not box then return end
    box._refreshReason = nil
    box._refreshQueued = nil
    box._refreshSerial = (tonumber(box._refreshSerial) or 0) + 1
end
local function BoxOwnerInactive(box)
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    if menu and menu.frame and menu.frame.IsShown and not menu.frame:IsShown() then return true end
    local pageKey = box and (box._msuf2PinnedPreviewPageKey or box._msufGFNativePreviewPageKey)
    if pageKey and menu and menu.activeKey and menu.activeKey ~= pageKey then return true end
    -- A pinned preview is deliberately reparented out of the page wrapper.
    -- During that hand-off the wrapper can briefly be non-visible even though
    -- the floating preview is the active, visible owner.
    if box and box._msuf2PinnedFloating == true then return false end
    local wrapper = box and (box._msuf2PinnedPreviewWrapper or box._msufGFNativePreviewWrapper)
    if wrapper and wrapper.IsShown and not wrapper:IsShown() then return true end
    return false
end
local function RequestRefreshForBox(box, reason)
    if not box or not box:IsShown() then
        if Preview.active == box then Preview.active = nil end
        if UninstallPreviewHooks and not Preview.active then UninstallPreviewHooks() end
        return
    end
    if BoxOwnerInactive(box) then
        CancelQueuedRefresh(box)
        if box.Hide then box:Hide() end
        if UninstallPreviewHooks then UninstallPreviewHooks() end
        return
    end
    local hostShown = box._msuf2UnitPageHostShown
    if not box._msuf2PinnedFloating and type(hostShown) == "function" and not hostShown() then
        CancelQueuedRefresh(box)
        if box.Hide then box:Hide() end
        return
    end
    if PreviewInCombat() then
        CancelQueuedRefresh(box)
        box._refreshAfterCombatReason = reason or box._refreshAfterCombatReason or "PLAYER_REGEN_ENABLED"
        Preview.active = box
        local retry = Preview._combatRefreshFrame
        if not retry and CreateFrame then
            retry = CreateFrame("Frame")
            Preview._combatRefreshFrame = retry
            retry:SetScript("OnEvent", function(self, event)
                if event ~= "PLAYER_REGEN_ENABLED" then return end
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                local pending = Preview.active
                local pendingReason = pending and pending._refreshAfterCombatReason
                if pending then pending._refreshAfterCombatReason = nil end
                if pending and pendingReason then RequestRefreshForBox(pending, pendingReason) end
            end)
        end
        if retry and retry.RegisterEvent then retry:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    Preview.active = box
    box._refreshAfterCombatReason = nil
    if InstallPreviewHooks then InstallPreviewHooks() end
    local refresh = Preview.Refresh
    if type(refresh) ~= "function" then return end
    if reason == "OPTIONS_APPLY_DB_IMMEDIATE" then
        CancelQueuedRefresh(box)
        refresh(box, reason)
        return
    end
    box._refreshReason = reason or box._refreshReason
    if box._refreshQueued then return end
    box._refreshSerial = (tonumber(box._refreshSerial) or 0) + 1
    local serial = box._refreshSerial
    box._refreshQueued = true
    local function run()
        if not box then return end
        if serial ~= box._refreshSerial then return end
        local refreshReason = box._refreshReason
        box._refreshReason = nil
        box._refreshQueued = nil
        if PreviewInCombat() then
            RequestRefreshForBox(box, refreshReason or "PLAYER_REGEN_ENABLED")
            return
        end
        if BoxOwnerInactive(box) then return end
        local currentHostShown = box._msuf2UnitPageHostShown
        if not box._msuf2PinnedFloating and type(currentHostShown) == "function" and not currentHostShown() then return end
        local queuedRefresh = Preview.Refresh
        -- IsVisible trails Show/parent visibility changes by a frame. Ownership
        -- above is based on stable shown/page state, so compose the preview as
        -- soon as its logical owner is active and let it become visible ready.
        if type(queuedRefresh) == "function" and box:IsShown() then
            Preview.active = box
            queuedRefresh(box, refreshReason)
        end
    end
    local delay = PreviewRefreshDelay(reason)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, run)
    else
        run()
    end
end
function Preview.RequestRefresh(reason)
    RequestRefreshForBox(Preview.active, reason)
end
function Preview.RequestRefreshForBox(box, reason)
    RequestRefreshForBox(box, reason)
end
ExportPublic("MSUF_UFPreview_RequestRefresh", function(reason)
    Preview.RequestRefresh(reason)
end)
ExportPublic("MSUF_UFPreview_SetStatusPreviewMode", function(mode)
    Preview.SetStatusPreviewMode(mode)
end)
ExportPublic("MSUF_UFPreview_GetStatusPreviewMode", function()
    return Preview.GetStatusPreviewMode()
end)
ExportPublic("MSUF_UFPreview_SelectStatusIcon", function(id)
    Preview.SelectStatusIcon(id)
end)
local PREVIEW_HOOK_NAMES = WordList [[
MSUF_ForceTextLayoutForUnitKey MSUF_UpdateAllFonts MSUF_UpdateAllFonts_Immediate MSUF_UpdateAllBarTextures MSUF_UpdateAllBarTextures_Immediate
MSUF_UpdateCastbarVisuals MSUF_ApplyCastbarUnitAndSync MSUF_ApplyCastbarVisualsForUnit MSUF_SyncCastbarPositionPopup MSUF_SyncUnitPositionPopup MSUF_ApplyUnitFrameKey_Immediate
MSUF_UFCore_RefreshSettingsCache MSUF_RefreshAllIdentityColors MSUF_RefreshAllPowerTextColors MSUF_RefreshAllFrames MSUF_RefreshAllUnitAlphas MSUF_RequestAlphaRefresh
MSUF_ClassPower_Apply MSUF_ClassPower_Refresh MSUF_ApplyPowerBarEmbedLayout MSUF_ApplyPowerBarEmbedLayout_All MSUF_ApplyPowerBarEmbedLayout_ForUnitKey MSUF_RefreshRaidMarkerFrames
MSUF_RefreshLeaderIconFrames MSUF_RefreshLevelIndicatorFrames MSUF_RefreshIdentityTextFrames MSUF_RefreshEliteIconFrames MSUF_RequestStatusTextRefresh MSUF_RequestStatusCombatIndicatorRefresh
MSUF_RequestStatusRestingIndicatorRefresh MSUF_RequestStatusIncomingResIndicatorRefresh MSUF_SyncAuras3PositionPopup
MSUF_RefreshUnitTextureLayers
]]
local wrappedNames = {}
local wrappers = {}
local lastPreviewHookScanAt = -100
local function FinishPreviewHook(name, ...)
    if not PreviewInCombat() then Preview.RequestRefresh(name) end
    return ...
end
UninstallPreviewHooks = function()
    for name, original in pairs(wrappedNames) do
        if _G[name] == wrappers[name] then _G[name] = original end
        wrappedNames[name] = nil
        wrappers[name] = nil
    end
end
Preview.UninstallRefreshHooks = UninstallPreviewHooks
InstallPreviewHooks = function()
    if not (Preview.active and Preview.active.IsShown and Preview.active:IsShown()) then
        UninstallPreviewHooks()
        return
    end
    local now = (_G.GetTime and _G.GetTime()) or 0
    if now - lastPreviewHookScanAt < 1.0 then return end
    lastPreviewHookScanAt = now
    for i = 1, #PREVIEW_HOOK_NAMES do
        local name = PREVIEW_HOOK_NAMES[i]
        local fn = _G[name]
        if type(fn) == "function" and not wrappedNames[name] then
            local original = fn
            local function wrapper(...)
                if not (Preview.active and Preview.active.IsShown and Preview.active:IsShown()) then
                    UninstallPreviewHooks()
                    return original(...)
                end
                return FinishPreviewHook(name, original(...))
            end
            wrappedNames[name] = original
            wrappers[name] = wrapper
            _G[name] = wrapper
        end
    end
end

--- Wrapping the full runtime refresh surface is only useful while a preview exists.
--- Wrappers are removed as soon as the active preview is hidden or inactive.

function MSUF.MSUF_Menu2_CreateUnitPreviewBox(parent, panel, width, height)
    local build = Preview._BuildPreview
    if type(build) ~= "function" then return nil end
    return build(parent, panel, width, height)
end
ExportPublic("MSUF_Menu2_CreateUnitPreviewBox", MSUF.MSUF_Menu2_CreateUnitPreviewBox)
