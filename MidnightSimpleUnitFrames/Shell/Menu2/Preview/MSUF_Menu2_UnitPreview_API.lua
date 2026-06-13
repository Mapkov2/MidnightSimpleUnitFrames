--- Unit preview public API, refresh hooks, and legacy globals.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local Preview = MSUF.MSUF_UFPreview or _G.MSUF_UFPreview
if not Preview then return end

local InstallPreviewHooks
local UninstallPreviewHooks

local function PreviewInCombat()
    local fn = Preview._PreviewInCombat
    return type(fn) == "function" and fn() or false
end

local function BoxOwnerInactive(box)
    local menu = (MSUF and MSUF.MSUF2) or _G.MSUF2
    if menu and menu.frame and menu.frame.IsShown and not menu.frame:IsShown() then return true end

    local pageKey = box and (box._msuf2PinnedPreviewPageKey or box._msufGFNativePreviewPageKey)
    if pageKey and menu and menu.activeKey and menu.activeKey ~= pageKey then return true end

    local wrapper = box and (box._msuf2PinnedPreviewWrapper or box._msufGFNativePreviewWrapper)
    if wrapper and wrapper.IsShown and not wrapper:IsShown() then return true end
    if wrapper and wrapper.IsVisible and not wrapper:IsVisible() then return true end
    return false
end

local function RequestRefreshForBox(box, reason)
    if not box or not box:IsShown() then
        if UninstallPreviewHooks then UninstallPreviewHooks() end
        return
    end
    if box.IsVisible and not box:IsVisible() then return end
    if BoxOwnerInactive(box) then
        box._refreshReason = nil
        box._refreshQueued = nil
        if box.Hide then box:Hide() end
        if UninstallPreviewHooks then UninstallPreviewHooks() end
        return
    end
    local hostShown = box._msuf2UnitPageHostShown
    if not box._msuf2PinnedFloating and type(hostShown) == "function" and not hostShown() then
        box._refreshReason = nil
        box._refreshQueued = nil
        if box.Hide then box:Hide() end
        return
    end
    if PreviewInCombat() then
        box._refreshReason = nil
        box._refreshQueued = nil
        return
    end
    if InstallPreviewHooks then InstallPreviewHooks() end
    local refresh = Preview.Refresh
    if type(refresh) ~= "function" then return end
    if reason == "OPTIONS_APPLY_DB_IMMEDIATE" then
        box._refreshQueued = nil
        refresh(box, reason)
        return
    end
    box._refreshReason = reason or box._refreshReason
    if box._refreshQueued then return end
    box._refreshQueued = true
    local function run()
        if not box then return end
        local refreshReason = box._refreshReason
        box._refreshReason = nil
        box._refreshQueued = nil
        local queuedRefresh = Preview.Refresh
        if type(queuedRefresh) == "function" and box:IsShown() and (not box.IsVisible or box:IsVisible()) then queuedRefresh(box, refreshReason) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

function Preview.RequestRefresh(reason)
    RequestRefreshForBox(Preview.active, reason)
end

function Preview.RequestRefreshForBox(box, reason)
    RequestRefreshForBox(box, reason)
end

_G.MSUF_UFPreview_RequestRefresh = function(reason)
    if PreviewInCombat() then return end
    Preview.RequestRefresh(reason)
end

_G.MSUF_UFPreview_SetStatusPreviewMode = function(mode)
    Preview.SetStatusPreviewMode(mode)
end

_G.MSUF_UFPreview_GetStatusPreviewMode = function()
    return Preview.GetStatusPreviewMode()
end

_G.MSUF_UFPreview_SelectStatusIcon = function(id)
    Preview.SelectStatusIcon(id)
end

local function WordList(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end
local PREVIEW_HOOK_NAMES = WordList [[
MSUF_ForceTextLayoutForUnitKey MSUF_UpdateAllFonts MSUF_UpdateAllFonts_Immediate MSUF_UpdateAllBarTextures MSUF_UpdateAllBarTextures_Immediate
MSUF_UpdateCastbarVisuals MSUF_ApplyCastbarUnitAndSync MSUF_SyncCastbarPositionPopup MSUF_SyncUnitPositionPopup MSUF_ApplyUnitFrameKey_Immediate
MSUF_UFCore_RefreshSettingsCache MSUF_RefreshAllIdentityColors MSUF_RefreshAllPowerTextColors MSUF_RefreshAllFrames MSUF_RefreshAllUnitAlphas MSUF_RequestAlphaRefresh
MSUF_ClassPower_Refresh MSUF_ApplyPowerBarEmbedLayout MSUF_ApplyPowerBarEmbedLayout_All MSUF_ApplyPowerBarEmbedLayout_ForUnitKey MSUF_RefreshRaidMarkerFrames
MSUF_RefreshLeaderIconFrames MSUF_RefreshLevelIndicatorFrames MSUF_RefreshEliteIconFrames MSUF_RequestStatusTextRefresh MSUF_RequestStatusCombatIndicatorRefresh
MSUF_RequestStatusRestingIndicatorRefresh MSUF_RequestStatusIncomingResIndicatorRefresh MSUF_SyncAuras3PositionPopup MSUF_Auras3_RefreshUnit MSUF_Auras3_RefreshAll
MSUF_Auras3_UpdateUnitAnchor MSUF_Auras3_RefreshEditPreview
]]

local wrappedNames = {}
local wrappers = {}
local lastPreviewHookScanAt = -100
local unpack = table.unpack or unpack

UninstallPreviewHooks = function()
    for name, original in pairs(wrappedNames) do
        if _G[name] == wrappers[name] then
            _G[name] = original
        end
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
                local results = { original(...) }
                if not PreviewInCombat() then Preview.RequestRefresh(name) end
                return unpack(results)
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

_G.MSUF_Menu2_CreateUnitPreviewBox = MSUF.MSUF_Menu2_CreateUnitPreviewBox
