--- Owns the current Class Resources preview surface and its deferred refresh.
--- Its public resume hook exists before any lazy renderer is constructed.
local _, MSUF = ...
local M = MSUF.MSUF2
local Preview = {}
M.ClassPowerStackPreview = Preview
local C_Timer = M.MenuTimer
local CP_PREVIEW_REFRESH_DELAY = 0.05

local function ClassPowerSurfaceShown(box)
    if not (box and box.IsShown and box:IsShown()) then return false end
    local hostShown = box._msufCPPreviewHostShown
    return type(hostShown) ~= "function" or hostShown(box) == true
end
local function ActivateClassPowerSurface(box)
    if box and not ClassPowerSurfaceShown(box) then box = nil end
    Preview.active = box
    return Preview.active
end
local function RequestClassPowerPreviewRefresh(box, reason)
    if not (box and box.Refresh) then return end
    box._msufCPRefreshReason = reason or box._msufCPRefreshReason
    local queued = box._msufCPRefreshQueued
    if queued then
        -- MenuRuntime can cancel a pending MenuTimer task when the menu is
        -- quiesced. Do not let that cancelled task permanently suppress every
        -- later Class Resources refresh after the menu resumes.
        if type(queued) ~= "table" or queued.active ~= false then return end
        box._msufCPRefreshQueued = nil
    end
    box._msufCPRefreshSerial = (tonumber(box._msufCPRefreshSerial) or 0) + 1
    local serial = box._msufCPRefreshSerial
    local function Run()
        if not box or serial ~= box._msufCPRefreshSerial then return end
        local refreshReason = box._msufCPRefreshReason
        box._msufCPRefreshReason = nil
        box._msufCPRefreshQueued = nil
        if box.IsShown and not box:IsShown() then return end
        if box._msufCPPreviewHostShown and not box:_msufCPPreviewHostShown() then return end
        box:Refresh(refreshReason or "CLASSPOWER_PREVIEW_REFRESH")
    end
    box._msufCPRefreshQueued = C_Timer.After(CP_PREVIEW_REFRESH_DELAY, Run)
end
-- The window invokes this before any lazy preview has been constructed.
-- Keep the API stable and resolve the surface through the current page entry;
-- invalidated/rebuilt pages must never resume a previously captured box.
function M.ResumeClassPowerPreview(reason, pageKey)
    pageKey = tostring(pageKey or M.activeKey or "classpower")
    local entry = M.cache and M.cache[pageKey]
    local box = entry and entry.classPowerPreview
    if not box or tostring(box._msufCPPreviewPageKey or "") ~= pageKey
        or not box:_msufCPPreviewHostShown() then return false end
    if not box:IsShown() then box:Show() end
    RequestClassPowerPreviewRefresh(box, reason or "CLASSPOWER_PREVIEW_RESUME")
    ActivateClassPowerSurface(box)
    return true
end


Preview.SurfaceShown = ClassPowerSurfaceShown
Preview.ActivateSurface = ActivateClassPowerSurface
Preview.RequestRefresh = RequestClassPowerPreviewRefresh
