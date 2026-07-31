--- Menu2 frame priority helpers.
---
--- The slash menu normally sits at dialog priority, then raises while MSUF Edit
--- Mode is active so direct-manipulation overlays and Menu2 controls stay in a
--- predictable stack order.
local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local MENU_NORMAL_FRAME_STRATA = "DIALOG"
-- Edit Mode priority is expressed by strata, never by repeatedly raising and
-- lowering the cached window's numeric frame level. WoW automatically raises
-- descendants with their parent but does not symmetrically rebase every
-- explicitly-levelled child when the parent is lowered. Toggling 10 <-> 900
-- therefore ratcheted cached preview descendants until SetFrameLevel exceeded
-- the engine's 0..65535 range.
local MENU_EDIT_FRAME_STRATA = "FULLSCREEN_DIALOG"
local MENU_NORMAL_FRAME_LEVEL = 10
local MENU_EDIT_FRAME_LEVEL = MENU_NORMAL_FRAME_LEVEL
-- Popups live on UIParent but share the window's strata, so they only win on the
-- numeric level. They must clear everything the window floats *inside* itself: a
-- pinned preview parks its card at scroll parent + 80 and stacks sidebars, handles
-- and bounds another ~90 above that. At 120 the Copy To panel was drawn under a
-- pinned preview and read as see-through. Raising only the popup band is safe --
-- these frames are not descendants of the window, so nothing ratchets with them.
local MENU_NORMAL_POPUP_FRAME_LEVEL = 400
local MENU_EDIT_POPUP_FRAME_LEVEL = MENU_NORMAL_POPUP_FRAME_LEVEL
local function IsMenuEditPriorityActive()
    if type(M.IsMSUFEditModeActive) ~= "function" then return false end
    return M.IsMSUFEditModeActive() == true
end
local function GetMenuFramePriority(level)
    if IsMenuEditPriorityActive() then return MENU_EDIT_FRAME_STRATA, level or MENU_EDIT_FRAME_LEVEL end
    return MENU_NORMAL_FRAME_STRATA, level or MENU_NORMAL_FRAME_LEVEL
end
local function ApplyMenuFramePriority(frame, level)
    if not frame then return end
    local strata, frameLevel = GetMenuFramePriority(level)
    if frame.SetFrameStrata then frame:SetFrameStrata(strata) end
    if frame.SetFrameLevel then frame:SetFrameLevel(frameLevel) end
    if frame.SetToplevel then frame:SetToplevel(false) end
end
local function ApplyMenuPopupFramePriority(frame)
    ApplyMenuFramePriority(frame, IsMenuEditPriorityActive() and MENU_EDIT_POPUP_FRAME_LEVEL or MENU_NORMAL_POPUP_FRAME_LEVEL)
end
local function ApplyMenuResizeProxyPriority(proxy, owner)
    if not proxy then return end
    local strata, fallbackLevel = GetMenuFramePriority()
    local ownerLevel = owner and owner.GetFrameLevel and owner:GetFrameLevel()
    if proxy.SetFrameStrata then proxy:SetFrameStrata(strata) end
    if proxy.SetFrameLevel then proxy:SetFrameLevel((ownerLevel or fallbackLevel) + 80) end
    if proxy.SetToplevel then proxy:SetToplevel(false) end
end
local function RefreshMenuFramePriority()
    if M.frame then
        ApplyMenuFramePriority(M.frame)
        ApplyMenuResizeProxyPriority(M.frame._msuf2ResizeProxy, M.frame)
    end
    if M.minimizedBar then ApplyMenuFramePriority(M.minimizedBar) end
end
M.ApplyMenuFramePriority = ApplyMenuFramePriority
M.ApplyMenuPopupFramePriority = ApplyMenuPopupFramePriority
M.ApplyMenuResizeProxyPriority = ApplyMenuResizeProxyPriority
M.RefreshMenuFramePriority = RefreshMenuFramePriority
M.MENU_NORMAL_FRAME_STRATA = MENU_NORMAL_FRAME_STRATA
M.MENU_EDIT_FRAME_STRATA = MENU_EDIT_FRAME_STRATA
M.MENU_FRAME_STRATA = MENU_EDIT_FRAME_STRATA
M.MENU_NORMAL_FRAME_LEVEL = MENU_NORMAL_FRAME_LEVEL
M.MENU_EDIT_FRAME_LEVEL = MENU_EDIT_FRAME_LEVEL
M.MENU_FRAME_LEVEL = MENU_EDIT_FRAME_LEVEL
M.MENU_NORMAL_POPUP_FRAME_LEVEL = MENU_NORMAL_POPUP_FRAME_LEVEL
M.MENU_EDIT_POPUP_FRAME_LEVEL = MENU_EDIT_POPUP_FRAME_LEVEL
M.MENU_POPUP_FRAME_LEVEL = MENU_NORMAL_POPUP_FRAME_LEVEL
