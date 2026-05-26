--- Unit preview public API, refresh hooks, and legacy globals.

local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
_G.MSUF_NS = MSUF

local Preview = MSUF.MSUF_UFPreview or _G.MSUF_UFPreview
if not Preview then return end

local function PreviewInCombat()
    local fn = Preview._PreviewInCombat
    return type(fn) == "function" and fn() or false
end

function Preview.RequestRefresh(reason)
    local box = Preview.active
    if not box or not box:IsShown() then return end
    if PreviewInCombat() then
        box._refreshReason = nil
        box._refreshQueued = nil
        return
    end
    if InstallPreviewHooks then InstallPreviewHooks() end
    if reason == "OPTIONS_APPLY_DB_IMMEDIATE" then
        box._refreshQueued = nil
        Preview.Refresh(box, reason)
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
        Preview.Refresh(box, refreshReason)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
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

local hookedNames = {}
InstallPreviewHooks = function()
    local names = {
        "MSUF_ForceTextLayoutForUnitKey",
        "MSUF_UpdateAllFonts",
        "MSUF_UpdateAllFonts_Immediate",
        "MSUF_UpdateAllBarTextures",
        "MSUF_UpdateAllBarTextures_Immediate",
        "MSUF_UpdateCastbarVisuals",
        "MSUF_ApplyCastbarUnitAndSync",
        "MSUF_SyncCastbarPositionPopup",
        "MSUF_SyncUnitPositionPopup",
        "MSUF_ApplyUnitFrameKey_Immediate",
        "MSUF_UFCore_RefreshSettingsCache",
        "MSUF_RefreshAllIdentityColors",
        "MSUF_RefreshAllPowerTextColors",
        "MSUF_RefreshAllFrames",
        "MSUF_RefreshAllUnitAlphas",
        "MSUF_RequestAlphaRefresh",
        "MSUF_ClassPower_Refresh",
        "MSUF_ApplyPowerBarEmbedLayout",
        "MSUF_ApplyPowerBarEmbedLayout_All",
        "MSUF_ApplyPowerBarEmbedLayout_ForUnitKey",
        "MSUF_RefreshRaidMarkerFrames",
        "MSUF_RefreshLeaderIconFrames",
        "MSUF_RefreshLevelIndicatorFrames",
        "MSUF_RefreshEliteIconFrames",
        "MSUF_RequestStatusTextRefresh",
        "MSUF_RequestStatusCombatIndicatorRefresh",
        "MSUF_RequestStatusRestingIndicatorRefresh",
        "MSUF_RequestStatusIncomingResIndicatorRefresh",
        "MSUF_SyncAuras3PositionPopup",
        "MSUF_Auras3_RefreshUnit",
        "MSUF_Auras3_RefreshAll",
        "MSUF_Auras3_RefreshUnit",
        "MSUF_Auras3_RefreshAll",
        "MSUF_Auras3_UpdateUnitAnchor",
        "MSUF_Auras3_RefreshEditPreview",
    }
    for i = 1, #names do
        local name = names[i]
        local fn = _G[name]
        if type(fn) == "function" and type(hooksecurefunc) == "function" then
            if not hookedNames[name] then
                hookedNames[name] = true
                hooksecurefunc(name, function()
                    if not PreviewInCombat() then Preview.RequestRefresh(name) end
                end)
            end
        end
    end
end

if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
        if InstallPreviewHooks then InstallPreviewHooks() end
    end)
elseif InstallPreviewHooks then
    InstallPreviewHooks()
end

function MSUF.MSUF_Menu2_CreateUnitPreviewBox(parent, panel, width, height)
    local build = Preview._BuildPreview
    if type(build) ~= "function" then return nil end
    return build(parent, panel, width, height)
end

_G.MSUF_Menu2_CreateUnitPreviewBox = MSUF.MSUF_Menu2_CreateUnitPreviewBox
