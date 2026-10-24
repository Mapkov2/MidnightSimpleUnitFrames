--- Unit preview public API, settings subscription, and legacy globals.
-- Bridges preview refresh calls for Menu2 without owning live unit-frame runtime state.

local MSUF = _G.MSUF
local FILE = "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_API.lua"
local ExportPublic = MSUF.ExportPublic
local Preview = MSUF.UFPreview or MSUF.Require("MSUF_UFPreview", FILE)
local M = MSUF.MSUF2
local C_Timer = M.MenuTimer or C_Timer
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
    if M.frame and M.frame.IsShown and not M.frame:IsShown() then return true end
    local pageKey = box and (box._msuf2PinnedPreviewPageKey or box._msufGFNativePreviewPageKey)
    if pageKey and M.activeKey and M.activeKey ~= pageKey then return true end
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
        if BoxOwnerInactive(box) then
            if Preview.active == box then Preview.active = nil end
            if UninstallPreviewHooks then UninstallPreviewHooks() end
            return
        end
        local currentHostShown = box._msuf2UnitPageHostShown
        if not box._msuf2PinnedFloating and type(currentHostShown) == "function" and not currentHostShown() then
            if Preview.active == box then Preview.active = nil end
            if UninstallPreviewHooks then UninstallPreviewHooks() end
            return
        end
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
local bus = MSUF.EventBus
local CONFIG_SUBSCRIBER = "Menu2.UnitPreview.ConfigApplied"
local subscribed = false
UninstallPreviewHooks = function()
    -- A hidden old box must not unsubscribe the newly active owner.
    local active = Preview.active
    if active and active.IsShown and active:IsShown() and not BoxOwnerInactive(active) then return end
    if not subscribed then return end
    bus:Unregister("CONFIG_APPLIED", CONFIG_SUBSCRIBER)
    subscribed = false
end
Preview.UninstallRefreshHooks = UninstallPreviewHooks
local function ConfigApplied(_, reason)
    local active = Preview.active
    if not active or not active:IsShown() or BoxOwnerInactive(active) then
        if active then CancelQueuedRefresh(active) end
        if Preview.active == active then Preview.active = nil end
        UninstallPreviewHooks()
        return
    end
    -- The previous direct-call hooks suppressed settings notifications in
    -- combat. Explicit refresh requests retain the existing deferred retry.
    if not PreviewInCombat() then Preview.RequestRefresh(reason) end
    if not Preview.active then UninstallPreviewHooks() end
end
InstallPreviewHooks = function()
    if not Preview.active or not Preview.active:IsShown() or BoxOwnerInactive(Preview.active) then
        UninstallPreviewHooks()
        return
    end
    if subscribed then return end
    subscribed = bus:Register("CONFIG_APPLIED", CONFIG_SUBSCRIBER, ConfigApplied)
end

function MSUF.MSUF_Menu2_CreateUnitPreviewBox(parent, panel, width, height)
    local build = Preview._BuildPreview
    if type(build) ~= "function" then return nil end
    return build(parent, panel, width, height)
end
ExportPublic("MSUF_Menu2_CreateUnitPreviewBox", MSUF.MSUF_Menu2_CreateUnitPreviewBox)

-- A sample-effect layer follows its open settings section, so opening or closing one repaints the preview that
-- shows that page (the render reads the persisted section state and applies the edge).
local SAMPLE_LAYER_SECTION_IDS = { unit_dispel_overlay = true, unit_dispel_symbol = true }
local previousSectionStateChanged = M.OnCollapsibleSectionStateChanged
function M.OnCollapsibleSectionStateChanged(pageKey, sectionId, open, entry)
    if previousSectionStateChanged then previousSectionStateChanged(pageKey, sectionId, open, entry) end
    local active = Preview.active
    if SAMPLE_LAYER_SECTION_IDS[sectionId] and active and active._msuf2PinnedPreviewPageKey == pageKey then
        Preview.RequestRefresh("UNIT_PREVIEW_SAMPLE_LAYER")
    end
end
