--- Menu2/MSUF_Menu2_Window.lua
--- Cold-path options window shell, navigation, routing, page cache, and window
--- sizing/minimize state.
---
--- Owns: the slash-menu window frame, page registration/render routing, nav
--- rail host, and sizing/minimize behavior. Navigation data, nav rail build,
--- persisted UI state, search bridge, page preview sync, and frame priority
--- helpers live in adjacent Menu2 modules.
--- Must not own runtime unitframe/groupframe gameplay logic.
local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local MenuRuntime = M.MenuRuntime or {}
M.Tr = M.Tr or function(text)
    if text == nil then return "" end
    local key = tostring(text)
    if type(MSUF.Translate) == "function" then
        local translated = MSUF.Translate(key)
        if translated ~= nil then return translated end
    end
    if type(MSUF.TR) == "function" then
        local translated = MSUF.TR(key)
        if translated ~= nil then return translated end
    end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" and locale[key] ~= nil then return locale[key] end
    return key
end
local L_PROFILE, L_EDIT_ON, L_EDIT_OFF, L_EDIT_MODE_ON, L_EDIT_MODE_OFF, L_EDIT_MODE_OFF_COMBAT, L_IN_COMBAT, L_OUT_OF_COMBAT
local function RefreshLocaleCache()
    L_PROFILE = M.Tr("Profile:")
    L_EDIT_ON = M.Tr("Edit: On")
    L_EDIT_OFF = M.Tr("Edit: Off")
    L_EDIT_MODE_ON = M.Tr("Edit Mode: On")
    L_EDIT_MODE_OFF = M.Tr("Edit Mode: Off")
    L_EDIT_MODE_OFF_COMBAT = M.Tr("Edit Mode: Off (Combat)")
    L_IN_COMBAT = M.Tr("In Combat")
    L_OUT_OF_COMBAT = M.Tr("Out of Combat")
end
RefreshLocaleCache()
if type(MSUF.RegisterLocaleCallback) == "function" then MSUF.RegisterLocaleCallback("MSUF_Menu2_Window", RefreshLocaleCache) end
local T = M.Theme
local W = M.Widgets
local AccessibleNumber = M.AccessibleNumber
M.pages = M.pages or {}
M.pageOrder = M.pageOrder or {}
M.cache = M.cache or {}
M._msuf2PageLayoutVariants = M._msuf2PageLayoutVariants or {}
-- Deliberately transient: reloads and new logins start from the Dashboard.
M.sessionLastPage = nil
M._msuf2LayoutVersion = M._msuf2LayoutVersion or 0
local floor = math.floor
local max = math.max
local min = math.min
local IsEditModeActive
local function GetAddonVersion()
    local getMeta = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
    if type(getMeta) == "function" then return getMeta(addonName or "MidnightSimpleUnitFrames", "Version") end
    if type(_G.GetAddOnMetadata) == "function" then return _G.GetAddOnMetadata(addonName or "MidnightSimpleUnitFrames", "Version") end
    return nil
end
local function SetCachedText(owner, cacheKey, region, text)
    if owner[cacheKey] == text then return end
    owner[cacheKey] = text
    region:SetText(text)
end
local FEEDBACK_COLOR_KEYS = {
    ok = "ok", success = "ok", warning = "accent2", combat = "accent2",
    danger = "danger", error = "danger", info = "accent",
}
local ApplyMenuFramePriority = M.ApplyMenuFramePriority
local ApplyMenuResizeProxyPriority = M.ApplyMenuResizeProxyPriority
local RefreshMenuFramePriority = M.RefreshMenuFramePriority
local EnsurePersistentMenuState = M.EnsurePersistentMenuState
local SavePersistentMenuState = M.SavePersistentMenuState
local SyncBossPagePreviewForKey = M.SyncBossPagePreviewForKey
local function RequestBossPagePreviewForKey(key, force)
    local request = M.RequestBossPagePreviewForKey
    if type(request) == "function" then return request(key, force) end
    if type(SyncBossPagePreviewForKey) == "function" then return SyncBossPagePreviewForKey(key, force) end
end
local SyncGroupPagePreviewForKey = M.SyncGFPagePreviewForKey
local function RequestGroupPagePreviewForKey(key, force)
    local request = M.RequestGFPagePreviewForKey
    if type(request) == "function" then return request(key, force) end
    if type(SyncGroupPagePreviewForKey) == "function" then return SyncGroupPagePreviewForKey(key, force) end
end
local ResetBossPagePreviewCache = M.ResetBossPagePreviewCache
local ResetStatusIndicatorTestModeOnMenuExit = M.ResetStatusIndicatorTestModeOnMenuExit
local SearchBridge = M.SearchBridge or {}
local UpdateSearchPlaceholder = SearchBridge.UpdateSearchPlaceholder
local MarkSearchIndexDirty = SearchBridge.MarkSearchIndexDirty
local CancelSearchBackgroundIndex = SearchBridge.CancelSearchBackgroundIndex
local RefreshSearchResultsPage = SearchBridge.RefreshSearchResultsPage
local BumpSearchInputSerial = SearchBridge.BumpSearchInputSerial
local ClearSearchRegistryPage = SearchBridge.ClearSearchRegistryPage
local CurrentMenuLocaleKey = SearchBridge.CurrentMenuLocaleKey
local BuildNav = M.BuildNavRail
local CreateWindowControlButton = M.CreateWindowControlButton
local RefreshWindowControls = M.RefreshWindowControls
local ALIASES = M.ALIASES or {}
-- Menu2 is a visual editor, not a compact settings popup. The wider default
-- keeps navigation, scope tabs, previews, and paired controls readable at the
-- same time while retaining resize support for smaller displays.
local DEFAULT_WINDOW_W, DEFAULT_WINDOW_H = 1360, 860
-- The minimum remains useful through the compact preview. Full previews keep
-- their exact preferred geometry; an explicit resize-grip shrink may switch
-- them to Compact rather than squeezing the renderer into a third size.
local MIN_WINDOW_W, MIN_WINDOW_H = 900, 660
local MAX_WINDOW_W, MAX_WINDOW_H = 1760, 1200
-- Preserve the physical size users previously selected at 80%, but present it
-- as the new 100% reference. The stored value remains the legacy scale factor
-- so existing profiles retain their exact window size without a migration.
local MENU_SCALE_REFERENCE = 0.80
local MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT, MENU_SCALE_STEP_PERCENT = 25, 200, 5
local MENU_SCALE_MIN = MENU_SCALE_REFERENCE * (MENU_SCALE_MIN_PERCENT / 100)
local MENU_SCALE_MAX = MENU_SCALE_REFERENCE * (MENU_SCALE_MAX_PERCENT / 100)
local WINDOW_W, WINDOW_H = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
local NAV_W = 200
-- Gap the content frame leaves at the window bottom; the menu-scale control and
-- the support-link strip both live in it and share its center line.
local WINDOW_FOOTER_H = 30
local CONTENT_W = WINDOW_W - NAV_W - 32
local CONTENT_H = WINDOW_H - 76
local MENU_BASE_SCALE = 1.08
local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value) or fallback or minValue
    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
    return floor(value + 0.5)
end
local function ClampScale(value)
    value = tonumber(value) or MENU_SCALE_REFERENCE
    if value < MENU_SCALE_MIN then value = MENU_SCALE_MIN elseif value > MENU_SCALE_MAX then value = MENU_SCALE_MAX end
    return value
end
local function MenuScalePercent(value)
    return (ClampScale(value) / MENU_SCALE_REFERENCE) * 100
end
local function MenuScaleValue(percent)
    return ClampScale(((tonumber(percent) or 100) / 100) * MENU_SCALE_REFERENCE)
end
local function EffectiveMenuScale(value)
    return ClampScale(value) * MENU_BASE_SCALE
end
local function WindowMaxBounds()
    local maxW, maxH = MAX_WINDOW_W, MAX_WINDOW_H
    local parent = _G.UIParent
    if parent and parent.GetWidth and parent.GetHeight then
        local scale = 1
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" then scale = EffectiveMenuScale(g.slashMenuScale) end
        maxW = min(maxW, floor(((parent:GetWidth() or maxW) / scale) - 32))
        maxH = min(maxH, floor(((parent:GetHeight() or maxH) / scale) - 32))
    end
    return max(MIN_WINDOW_W, maxW), max(MIN_WINDOW_H, maxH)
end
local function ApplyWindowResizeBounds(frame)
    if not frame then return end
    local maxW, maxH = WindowMaxBounds()
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WINDOW_W, MIN_WINDOW_H, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(MIN_WINDOW_W, MIN_WINDOW_H) end
        if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
    end
end
local function SetWindowMetrics(width, height)
    local maxW, maxH = WindowMaxBounds()
    WINDOW_W = ClampNumber(width, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    WINDOW_H = ClampNumber(height, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    CONTENT_W = math.max(420, WINDOW_W - NAV_W - 32)
    CONTENT_H = math.max(320, WINDOW_H - 74)
end
function M.GetContentMetrics()
    return CONTENT_W, CONTENT_H
end
local function RefreshWindowMetrics(frame)
    local width = (frame and frame.GetWidth and frame:GetWidth()) or WINDOW_W
    local height = (frame and frame.GetHeight and frame:GetHeight()) or WINDOW_H
    SetWindowMetrics(width, height)
end
local function ClampWindowSize(frame)
    if not frame then return end
    RefreshWindowMetrics(frame)
    if frame.SetSize then frame:SetSize(WINDOW_W, WINDOW_H) end
    ApplyWindowResizeBounds(frame)
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
end
local function ReadSavedWindowSize()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return DEFAULT_WINDOW_W, DEFAULT_WINDOW_H end
    local maxW, maxH = WindowMaxBounds()
    local savedW = tonumber(g.msuf2WindowW)
    local savedH = tonumber(g.msuf2WindowH)
    -- Upgrade only the former exact default. Deliberately customized window
    -- sizes remain untouched.
    if (savedW == nil and savedH == nil) or (savedW == 1180 and savedH == 720) then
        savedW, savedH = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
    end
    return ClampNumber(savedW, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W),
        ClampNumber(savedH, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
end
local function SaveWindowSize(frame)
    RefreshWindowMetrics(frame)
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return end
    g.msuf2WindowW = WINDOW_W
    g.msuf2WindowH = WINDOW_H
end
local RebuildActivePageForResize
local ApplyMenuFrameScale
local SNAP_EDGE_PX = 24
local SNAP_FRAME_EDGE_PX = 4
local SNAP_SCREEN_MARGIN = 16
local MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H = 286, 32
local WINDOW_MAXIMIZE_ANIM_SECONDS = 0.38
local WINDOW_MINIMIZE_ANIM_SECONDS = 0.34
local WINDOW_RESTORE_ANIM_SECONDS = 0.36
local WINDOW_SNAP_ANIM_SECONDS = 0.36
local WINDOW_RESIZE_ANIM_SECONDS = 0.14
local WINDOW_RESIZE_SETTLE_RATIO = 0.08
local WINDOW_RESIZE_SETTLE_MAX_PX = 12
local function IsSlashMenuSnapEnabled()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return true end
    return g.slashMenuSnapEnabled ~= false
end
local function WindowVisualScale(frame)
    local parent = _G.UIParent
    if not (frame and frame.GetEffectiveScale and parent and parent.GetEffectiveScale) then return 1 end
    local uiScale = parent:GetEffectiveScale() or 1
    if uiScale == 0 then uiScale = 1 end
    return (frame:GetEffectiveScale() or uiScale) / uiScale
end
local function FrameRectToUIParent(frame)
    local parent = _G.UIParent
    if not (frame and parent and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local scale = WindowVisualScale(frame)
    if scale <= 0 then scale = 1 end
    return l * scale, r * scale, t * scale, b * scale
end
local function CursorPositionInUIParent()
    local parent = _G.UIParent
    if not (parent and parent.GetEffectiveScale and _G.GetCursorPosition) then return nil, nil end
    local scale = parent:GetEffectiveScale() or 1
    if scale == 0 then scale = 1 end
    local x, y = _G.GetCursorPosition()
    return (x or 0) / scale, (y or 0) / scale
end
local function CaptureFrameLayout(frame, fallbackW, fallbackH)
    if not (frame and frame.GetLeft and frame.GetTop and frame.GetWidth and frame.GetHeight) then return nil end
    return {
        x = frame:GetLeft() or SNAP_SCREEN_MARGIN,
        yTop = frame:GetTop() or (((_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or DEFAULT_WINDOW_H) - SNAP_SCREEN_MARGIN),
        w = frame:GetWidth() or fallbackW or WINDOW_W,
        h = frame:GetHeight() or fallbackH or WINDOW_H,
    }
end
local function ApplyRawFrameLayout(frame, layout)
    if not (frame and layout and _G.UIParent) then return false end
    frame:ClearAllPoints()
    frame:SetSize(max(1, layout.w or WINDOW_W), max(1, layout.h or WINDOW_H))
    frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", layout.x or SNAP_SCREEN_MARGIN, layout.yTop or DEFAULT_WINDOW_H)
    return true
end
local function WindowMotionReduced()
    return T and T.ReducedMotionEnabled and T.ReducedMotionEnabled()
end
local function EaseWindowMorph(progress)
    progress = tonumber(progress) or 0
    if progress <= 0 then return 0 end
    if progress >= 1 then return 1 end
    return progress * progress * progress * (progress * (progress * 6 - 15) + 10)
end
local function LerpNumber(fromValue, toValue, progress)
    return (fromValue or 0) + (((toValue or 0) - (fromValue or 0)) * progress)
end
local function ResizeSettleStartValue(fromValue, toValue)
    local delta = (toValue or 0) - (fromValue or 0)
    if delta == 0 then return toValue end
    local offset = min(math.abs(delta) * WINDOW_RESIZE_SETTLE_RATIO, WINDOW_RESIZE_SETTLE_MAX_PX)
    return (toValue or 0) - (delta > 0 and offset or -offset)
end
local function SetWindowAnimationClipping(frame, state, active)
    if not (frame and state and frame.SetClipsChildren) then return end
    if active then
        if state.clippingApplied then return end
        state.restoreClipsChildren = frame.DoesClipChildren and frame:DoesClipChildren() or false
        state.clippingApplied = true
        frame:SetClipsChildren(true)
    elseif state.clippingApplied then
        state.clippingApplied = nil
        frame:SetClipsChildren(state.restoreClipsChildren == true)
    end
end
local function StopWindowLayoutAnimation(frame)
    local state = frame and frame._msuf2WindowLayoutAnim
    if not state then return end
    state.cancelled = true
    frame._msuf2WindowLayoutAnim = nil
    SetWindowAnimationClipping(frame, state, false)
    if state.driver and state.driver.SetScript then state.driver:SetScript("OnUpdate", nil) end
    if state.driver and state.driver.Hide then state.driver:Hide() end
end
M.StopWindowLayoutAnimation = StopWindowLayoutAnimation
local function SettleWindowLayoutAnimation(frame)
    local state = frame and frame._msuf2WindowLayoutAnim
    if not state then return false end
    local target, toAlpha, onFinished = state.target, state.toAlpha, state.onFinished
    StopWindowLayoutAnimation(frame)
    if target then ApplyRawFrameLayout(frame, target) end
    if toAlpha and frame.SetAlpha then frame:SetAlpha(toAlpha) end
    if type(onFinished) == "function" then onFinished(frame) end
    M.CallIf(M.ResolvePendingFixedPreviewExpansion, frame)
    return true
end
local function AnimateWindowLayout(frame, target, opts)
    if not (frame and target) then return false end
    opts = opts or {}
    StopWindowLayoutAnimation(frame)
    local start = opts.start or CaptureFrameLayout(frame)
    if not start then return false end
    if opts.applyStart then ApplyRawFrameLayout(frame, start) end
    local duration = tonumber(opts.duration) or WINDOW_RESTORE_ANIM_SECONDS
    if WindowMotionReduced() or duration <= 0.001 then
        ApplyRawFrameLayout(frame, target)
        if opts.toAlpha and frame.SetAlpha then frame:SetAlpha(opts.toAlpha) end
        if type(opts.onFinished) == "function" then opts.onFinished(frame) end
        M.CallIf(M.ResolvePendingFixedPreviewExpansion, frame)
        return true
    end
    local driver = frame._msuf2WindowLayoutDriver
    if not driver then
        driver = CreateFrame("Frame", nil, _G.UIParent or frame)
        frame._msuf2WindowLayoutDriver = driver
    end
    local state = {
        elapsed = 0,
        duration = duration,
        start = start,
        target = target,
        fromAlpha = opts.fromAlpha,
        toAlpha = opts.toAlpha,
        onFinished = opts.onFinished,
        driver = driver,
    }
    frame._msuf2WindowLayoutAnim = state
    -- Menu pages contain fixed-width preview renderers. Clip them to the shell
    -- while its bounds morph so they cannot paint outside the shrinking window
    -- and appear to trail behind it. The prior clip contract is restored when
    -- this short cold-path animation settles or is cancelled.
    SetWindowAnimationClipping(frame, state, true)
    if opts.suspendPagePreviews == true then
        -- Boss/GF page previews are UIParent-owned runtime frames rather than
        -- menu children, so clipping cannot contain them. Quiesce them for the
        -- transition; the final page rebuild resumes the active page exactly
        -- once after its destination geometry has committed.
        RequestBossPagePreviewForKey(nil, true)
        RequestGroupPagePreviewForKey(nil, true)
    end
    if state.fromAlpha and frame.SetAlpha then frame:SetAlpha(state.fromAlpha) end
    if frame.Show then frame:Show() end
    driver:SetScript("OnUpdate", function(self, elapsed)
        if state.cancelled or frame._msuf2Closing or frame._msuf2WindowLayoutAnim ~= state or (frame.IsShown and not frame:IsShown()) then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            return
        end
        state.elapsed = state.elapsed + (elapsed or 0)
        local p = state.elapsed / state.duration
        if p >= 1 then p = 1 end
        local eased = EaseWindowMorph(p)
        ApplyRawFrameLayout(frame, {
            x = LerpNumber(start.x, target.x, eased),
            yTop = LerpNumber(start.yTop, target.yTop, eased),
            w = LerpNumber(start.w, target.w, eased),
            h = LerpNumber(start.h, target.h, eased),
        })
        if state.fromAlpha and state.toAlpha and frame.SetAlpha then
            frame:SetAlpha(LerpNumber(state.fromAlpha, state.toAlpha, eased))
        end
        if p >= 1 then
            frame._msuf2WindowLayoutAnim = nil
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if state.cancelled or frame._msuf2Closing or (frame.IsShown and not frame:IsShown()) then return end
            ApplyRawFrameLayout(frame, target)
            if state.toAlpha and frame.SetAlpha then frame:SetAlpha(state.toAlpha) end
            SetWindowAnimationClipping(frame, state, false)
            if type(state.onFinished) == "function" then state.onFinished(frame) end
            -- Explicit Full Preview is a page-keyed intent, not geometry owned
            -- by this transient animation. Drain it only after the target layout
            -- and its normal resize/snap/maximize rebuild have both committed.
            M.CallIf(M.ResolvePendingFixedPreviewExpansion, frame)
        end
    end)
    driver:Show()
    return true
end
local function MinimizedBarTargetLayout(frame, bar)
    local layout = CaptureFrameLayout(bar, MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H)
    if not layout then
        layout = { x = 16, yTop = 16 + MINIMIZED_WINDOW_H, w = MINIMIZED_WINDOW_W, h = MINIMIZED_WINDOW_H }
    end
    local scale = WindowVisualScale(frame)
    if scale <= 0 then scale = 1 end
    layout.w = max(1, (layout.w or MINIMIZED_WINDOW_W) / scale)
    layout.h = max(1, (layout.h or MINIMIZED_WINDOW_H) / scale)
    return layout
end
local function ApplyWindowLayout(frame, layout, rebuild, rebuildOptions)
    if not (frame and layout and _G.UIParent) then return false end
    local maxW, maxH = WindowMaxBounds()
    local w = ClampNumber(layout.w, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    local h = ClampNumber(layout.h, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    frame:ClearAllPoints()
    frame:SetSize(w, h)
    frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", layout.x or SNAP_SCREEN_MARGIN, layout.yTop or DEFAULT_WINDOW_H)
    ApplyWindowResizeBounds(frame)
    if rebuild and RebuildActivePageForResize then
        RebuildActivePageForResize(frame, rebuildOptions)
    else
        SaveWindowSize(frame)
    end
    return true
end
local function RestoreSlashMenuWindow(frame)
    if not frame then return false end
    local layout = frame._msuf2RestoreLayout
    frame._msuf2WindowState = "normal"
    frame._msuf2RestoreLayout = nil
    local restored = false
    if layout then
        M.CallIf(RefreshWindowControls, frame)
        restored = AnimateWindowLayout(frame, layout, {
            duration = WINDOW_RESTORE_ANIM_SECONDS,
            suspendPagePreviews = true,
            onFinished = function()
                ApplyWindowLayout(frame, layout, true)
                M.CallIf(RefreshWindowControls, frame)
            end,
        })
    end
    if not restored then
        ClampWindowSize(frame)
        if RebuildActivePageForResize then RebuildActivePageForResize(frame) end
        M.CallIf(RefreshWindowControls, frame)
    end
    return true
end
local function MaximizeSlashMenuWindow(frame)
    if not frame then return false end
    if frame._msuf2WindowState == "maximized" then return RestoreSlashMenuWindow(frame) end
    frame._msuf2RestoreLayout = CaptureFrameLayout(frame)
    frame._msuf2WindowState = "maximized"
    local parent = _G.UIParent
    if not (parent and parent.GetWidth and parent.GetHeight) then return false end
    local screenW, screenH = parent:GetWidth() or 0, parent:GetHeight() or 0
    if screenW <= 0 or screenH <= 0 then return false end
    local scale = WindowVisualScale(frame)
    if scale <= 0 then scale = 1 end
    local maxW, maxH = WindowMaxBounds()
    local usableW = max(1, screenW - (SNAP_SCREEN_MARGIN * 2))
    local usableH = max(1, screenH - (SNAP_SCREEN_MARGIN * 2))
    local localW = ClampNumber(usableW / scale, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    local localH = ClampNumber(usableH / scale, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    local visualW = localW * scale
    local x = max(SNAP_SCREEN_MARGIN, floor((screenW - visualW) * 0.5 + 0.5))
    local yTop = screenH - SNAP_SCREEN_MARGIN
    local target = { x = x, yTop = yTop, w = localW, h = localH }
    M.CallIf(RefreshWindowControls, frame)
    AnimateWindowLayout(frame, target, {
        duration = WINDOW_MAXIMIZE_ANIM_SECONDS,
        suspendPagePreviews = true,
        onFinished = function()
            ApplyWindowLayout(frame, target, true)
            M.CallIf(RefreshWindowControls, frame)
        end,
    })
    return true
end
local function RestoreMinimizedSlashMenu(frame)
    if not frame then frame = M.frame end
    if not frame then return false end
    local start = M.minimizedBar and MinimizedBarTargetLayout(frame, M.minimizedBar) or nil
    local target = frame._msuf2PreMinimizeLayout or CaptureFrameLayout(frame)
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    frame._msuf2Minimized = nil
    ApplyMenuFramePriority(frame)
    if start and target then
        ApplyRawFrameLayout(frame, start)
        if frame.SetAlpha then frame:SetAlpha(0.08) end
        frame:Show()
        AnimateWindowLayout(frame, target, {
            start = start,
            applyStart = true,
            fromAlpha = 0.08,
            toAlpha = 1,
            duration = WINDOW_RESTORE_ANIM_SECONDS,
            suspendPagePreviews = true,
            onFinished = function()
                frame._msuf2PreMinimizeLayout = nil
                if frame.SetAlpha then frame:SetAlpha(1) end
                ApplyWindowLayout(frame, target, true)
                M.CallIf(M.UpdateMenuCombatListener)
                M.CallIf(RefreshWindowControls, frame)
            end,
        })
    else
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        frame._msuf2PreMinimizeLayout = nil
    end
    M.CallIf(M.UpdateMenuCombatListener)
    M.CallIf(RefreshWindowControls, frame)
    return true
end
local function HideSlashMenuAndMinibar(frame)
    frame = frame or M.frame
    if frame then
        frame._msuf2Closing = true
        frame._msuf2WindowState = "normal"
        frame._msuf2RestoreLayout = nil
        frame._msuf2PreMinimizeLayout = nil
        frame._msuf2Minimized = nil
    end
    StopWindowLayoutAnimation(frame)
    if frame and frame._msuf2CancelWindowInteractions then frame:_msuf2CancelWindowInteractions() end
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    if frame and frame.Hide then frame:Hide() end
    M.CallIf(M.UpdateMenuCombatListener)
end
local function MinimizeSlashMenuWindow(frame)
    if not frame then return false end
    if not M.minimizedBar then return false end
    local start = CaptureFrameLayout(frame)
    frame._msuf2Minimized = true
    frame._msuf2PreMinimizeLayout = start
    if M.minimizedBar.title and frame.title and frame.title.GetText then M.minimizedBar.title:SetText(frame.title:GetText() or "MSUF Menu") end
    ApplyMenuFramePriority(M.minimizedBar)
    if M.minimizedBar.SetAlpha then M.minimizedBar:SetAlpha(0) end
    M.minimizedBar:Show()
    local target = MinimizedBarTargetLayout(frame, M.minimizedBar)
    if start and target then
        AnimateWindowLayout(frame, target, {
            start = start,
            fromAlpha = 1,
            toAlpha = 0.08,
            duration = WINDOW_MINIMIZE_ANIM_SECONDS,
            suspendPagePreviews = true,
            onFinished = function()
                if frame.SetAlpha then frame:SetAlpha(1) end
                frame:Hide()
                ApplyRawFrameLayout(frame, start)
                if M.minimizedBar and M.minimizedBar.SetAlpha then M.minimizedBar:SetAlpha(1) end
                M.CallIf(M.UpdateMenuCombatListener)
            end,
        })
    else
        if M.minimizedBar.SetAlpha then M.minimizedBar:SetAlpha(1) end
        frame:Hide()
    end
    M.CallIf(M.UpdateMenuCombatListener)
    return true
end
local function GetSlashMenuSnapLayout(frame)
    if not (frame and IsSlashMenuSnapEnabled()) then return false end
    local parent = _G.UIParent
    if not (parent and parent.GetWidth and parent.GetHeight) then return false end
    local cursorX, cursorY = CursorPositionInUIParent()
    if not cursorX then return false end
    local screenW, screenH = parent:GetWidth() or 0, parent:GetHeight() or 0
    if screenW <= 0 or screenH <= 0 then return false end
    -- Region bounds are expressed in the frame's scaled coordinate space.
    -- Compare visual bounds in UIParent space so reduced menu scale cannot
    -- make an edge appear to reach the screen hundreds of pixels too early.
    local frameLeft, frameRight, frameTop, frameBottom = FrameRectToUIParent(frame)
    frameLeft = frameLeft or cursorX
    frameRight = frameRight or cursorX
    frameTop = frameTop or cursorY
    frameBottom = frameBottom or cursorY
    local left = cursorX <= SNAP_EDGE_PX or frameLeft <= SNAP_FRAME_EDGE_PX
    local right = cursorX >= (screenW - SNAP_EDGE_PX) or frameRight >= (screenW - SNAP_FRAME_EDGE_PX)
    if left and right then
        right = cursorX >= (screenW * 0.5)
        left = not right
    end
    local top = cursorY >= (screenH - SNAP_EDGE_PX) or frameTop >= (screenH - SNAP_FRAME_EDGE_PX)
    local bottom = cursorY <= SNAP_EDGE_PX or frameBottom <= SNAP_FRAME_EDGE_PX
    if not (left or right or top or bottom) then return false end
    if bottom and not (left or right) then return false end
    local scale = WindowVisualScale(frame)
    if scale <= 0 then scale = 1 end
    local maxW, maxH = WindowMaxBounds()
    local usableW = max(1, screenW - (SNAP_SCREEN_MARGIN * 2))
    local usableH = max(1, screenH - (SNAP_SCREEN_MARGIN * 2))
    local halfW = usableW * 0.5
    local halfH = usableH * 0.5
    local targetW = top and not (left or right) and usableW or halfW
    local targetH = ((left or right) and (top or bottom)) and halfH or usableH
    local localW = ClampNumber(targetW / scale, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    local localH = ClampNumber(targetH / scale, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    local visualW = localW * scale
    local visualH = localH * scale
    local x
    if right then
        x = screenW - SNAP_SCREEN_MARGIN - visualW
    else
        x = SNAP_SCREEN_MARGIN
    end
    if x < SNAP_SCREEN_MARGIN then x = SNAP_SCREEN_MARGIN end
    local yTop
    if bottom then
        yTop = SNAP_SCREEN_MARGIN + visualH
    else
        yTop = screenH - SNAP_SCREEN_MARGIN
    end
    if yTop > screenH - SNAP_SCREEN_MARGIN then yTop = screenH - SNAP_SCREEN_MARGIN end
    return {
        x = x,
        yTop = yTop,
        w = localW,
        h = localH,
        visualW = visualW,
        visualH = visualH,
        scale = scale,
        left = left,
        right = right,
        top = top,
        bottom = bottom,
    }
end
local function ApplySlashMenuSnap(frame)
    local layout = frame and frame._msuf2LastSnapLayout or nil
    if not layout then layout = GetSlashMenuSnapLayout(frame) end
    if not layout then return false end
    local start = CaptureFrameLayout(frame)
    if frame._msuf2WindowState == "maximized" then
        frame._msuf2WindowState = "normal"
        frame._msuf2RestoreLayout = nil
    end
    M.CallIf(RefreshWindowControls, frame)
    if start and AnimateWindowLayout(frame, layout, {
        start = start,
        duration = WINDOW_SNAP_ANIM_SECONDS,
        onFinished = function()
            ApplyWindowLayout(frame, layout, true)
            M.CallIf(RefreshWindowControls, frame)
        end,
    }) then
        return true
    end
    ApplyWindowLayout(frame, layout, true)
    M.CallIf(RefreshWindowControls, frame)
    return true
end
local function ApplyScrollMetrics()
    if not M.scrollChild then return end
    local height = CONTENT_H
    local entry = M.activeKey and M.cache and M.cache[M.activeKey]
    if entry and tonumber(entry.height) then height = math.max(height, entry.height) end
    M.scrollChild:SetSize(CONTENT_W - 12, height)
    if entry and entry.wrapper then entry.wrapper:SetSize(CONTENT_W - 12, height) end
    if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
end
local VISIBLE_SETTLE_RELAYOUT = { refreshUntrackedState = true }
local function QueueVisiblePageLayoutSettle(key, entry)
    if type(entry) ~= "table" or entry._msuf2VisibleLayoutSettleQueued then return end
    entry._msuf2VisibleLayoutSettleQueued = true
    local function Settle()
        entry._msuf2VisibleLayoutSettleQueued = nil
        if M.activeKey ~= key or not M.cache or M.cache[key] ~= entry then return end
        if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
        if not (entry.wrapper and entry.wrapper.IsShown and entry.wrapper:IsShown()) then return end

        -- A fresh WoW client can accept the first custom semibold SetFont call
        -- before its glyph metrics are renderable. Reapply this page's fonts
        -- once after visibility and fall back immediately when the requested
        -- face still cannot render text. Cached pages pay this cost only once.
        if not entry._msuf2VisibleFontSettled and T and type(T.RefreshMenuFonts) == "function" then
            entry._msuf2VisibleFontSettled = true
            -- This is the one-shot visibility retry for freshly created font
            -- strings, not a font-setting change. Preserve the resolved-path
            -- cache populated while the page was built.
            if type(T.RefreshMenuFontStrings) == "function" and type(entry.fontStrings) == "table" then
                T.RefreshMenuFontStrings(entry.fontStrings, true, true)
            else
                T.RefreshMenuFonts(entry.wrapper, true, true)
            end
        end

        -- A cached/new page can become visible in the same layout turn in
        -- which its accordion headers were created. If their anchored width
        -- resolved before OnSizeChanged was hooked, the first label layout can
        -- retain a zero-width span until an unrelated menu scale/resize event.
        -- Refresh once after visibility has settled; this is cold-path work and
        -- installs no recurring handler.
        local builders = {}
        local seenBuilders = {}
        for _, body in pairs(entry.sections or {}) do
            local section = body and body._msuf2CollapsibleEntry
            if section then
                if type(section._msuf2RefreshLayout) == "function" then
                    section._msuf2RefreshLayout()
                end
                local builder = section.builder
                if builder and not seenBuilders[builder] then
                    seenBuilders[builder] = true
                    builders[#builders + 1] = builder
                end
            end
        end
        for i = 1, #builders do
            local builder = builders[i]
            if type(builder.RelayoutCollapsibles) == "function" then
                builder:RelayoutCollapsibles(VISIBLE_SETTLE_RELAYOUT)
            end
        end
        ApplyScrollMetrics()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Settle)
    else
        Settle()
    end
end
local fixedPreviewRestoreSerial = 0
local fixedPreviewExpandIntentSerial = 0
local fixedPreviewRebuildExpandPageKey
local function ActiveFixedPreviewIsExpanded(pageKey)
    local expander = M._msuf2ActiveFixedPreviewExpander
    return expander and expander.expanded == true and not expander.disposed
        and (not pageKey or not expander.pageKey or expander.pageKey == pageKey)
end
function M.RememberFixedPreviewExpansionForRebuild(pageKey)
    if not ActiveFixedPreviewIsExpanded(pageKey) then return false end
    fixedPreviewRebuildExpandPageKey = pageKey or M.activeKey
    return fixedPreviewRebuildExpandPageKey ~= nil
end
function M.ConsumeFixedPreviewExpansionForSelection(pageKey)
    local restore = ActiveFixedPreviewIsExpanded()
        or fixedPreviewRebuildExpandPageKey == pageKey
        or (type(M.ShouldExpandFixedPreview) == "function" and M.ShouldExpandFixedPreview())
    fixedPreviewRebuildExpandPageKey = nil
    return restore == true
end
local function FixedPreviewExpanderForEntry(entry)
    local records = type(entry) == "table" and entry.pageHeaders or nil
    if type(records) ~= "table" then return nil end
    for i = 1, #records do
        local expander = records[i] and records[i].previewExpander
        if expander and not expander.disposed and type(expander.Open) == "function" then return expander end
    end
    return nil
end
local function RestoreExpandedFixedPreview(key, entry, serial, options)
    options = type(options) == "table" and options or {}
    local pendingIntent = options.pendingIntent
    local resolved = false
    local function TryRestore()
        if resolved or serial ~= fixedPreviewRestoreSerial or M.activeKey ~= key
            or not (M.cache and M.cache[key] == entry)
        then
            resolved = true
            return
        end
        local frame = M.frame
        if pendingIntent and not (frame and frame._msuf2PendingFixedPreviewExpand == pendingIntent) then
            resolved = true
            return
        end
        local expander = FixedPreviewExpanderForEntry(entry)
        if not expander then return end
        -- Responsive headers can wrap differently after the new page variant
        -- is built. A resize-grip shrink therefore decides against the NEW
        -- stack, never against stale pre-rebuild geometry.
        if options.autoCompactIfNoFit == true
            and type(expander.CanFitPreferredExpansion) == "function"
            and expander:CanFitPreferredExpansion() == false
        then
            resolved = true
            return
        end
        if pendingIntent then
            -- Consume only when the current page actually has an expander to
            -- satisfy the request. Until here, deferred Unit construction keeps
            -- the exact same intent alive across the bounded retry window.
            frame._msuf2PendingFixedPreviewExpand = nil
        end
        if expander.expanded == true then
            resolved = true
            if options.ensureRoom == true and type(M.EnsureFixedPreviewExpansionRoom) == "function" then
                M.EnsureFixedPreviewExpansionRoom(expander)
            end
        elseif expander:Open(options.reason or "WINDOW_LAYOUT_RESTORE", { preserveExpandedZoom = true }) then
            resolved = true
        elseif pendingIntent and not frame._msuf2PendingFixedPreviewExpand
            and pendingIntent.serial == fixedPreviewExpandIntentSerial
            and M.activeKey == key and M.cache and M.cache[key] == entry
        then
            -- A temporarily hidden/not-yet-owned renderer can reject Open even
            -- after it exists. Restore the same intent for the remaining retry;
            -- never overwrite a newer user action.
            frame._msuf2PendingFixedPreviewExpand = pendingIntent
        end
    end
    TryRestore()
    if resolved or not (C_Timer and C_Timer.After) then return end
    -- Unit previews create their shared renderer on the first visible frame;
    -- Group and Class previews normally restore synchronously. These bounded
    -- retries cover that one deferred construction without adding a ticker.
    C_Timer.After(0, TryRestore)
    C_Timer.After(0.05, TryRestore)
end
function M.ClearPendingFixedPreviewExpansion(pageKey)
    local frame = M.frame
    local pending = frame and frame._msuf2PendingFixedPreviewExpand
    if pending and pageKey and pending.pageKey ~= pageKey then return false end
    -- Also invalidate already-scheduled Unit construction retries. This closes
    -- the A -> B -> A and hide -> show windows where activeKey/cache identity can
    -- otherwise become true again before a 0.05-second retry fires.
    fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
    fixedPreviewExpandIntentSerial = fixedPreviewExpandIntentSerial + 1
    if frame then frame._msuf2PendingFixedPreviewExpand = nil end
    return pending ~= nil
end
function M.ResolvePendingFixedPreviewExpansion(frame)
    frame = frame or M.frame
    local pending = frame and frame._msuf2PendingFixedPreviewExpand
    if not pending then return false end
    -- Replacement animations inherit the intent. Only the newest settled
    -- layout may decide whether the full canvas needs more window height.
    if frame._msuf2WindowLayoutAnim then return false end
    local key = pending.pageKey
    local entry = key and M.cache and M.cache[key]
    if pending.serial ~= fixedPreviewExpandIntentSerial or M.activeKey ~= key
        or not entry or (frame.IsShown and not frame:IsShown())
    then
        frame._msuf2PendingFixedPreviewExpand = nil
        return false
    end
    fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
    RestoreExpandedFixedPreview(key, entry, fixedPreviewRestoreSerial, {
        reason = "DEFERRED_EXPLICIT_EXPAND",
        ensureRoom = true,
        pendingIntent = pending,
    })
    return true
end
function RebuildActivePageForResize(frame, options)
    options = type(options) == "table" and options or {}
    local key = M.activeKey or "home"
    local activeExpander = M._msuf2ActiveFixedPreviewExpander
    local restoreExpanded = activeExpander and activeExpander.expanded == true
        and not activeExpander.disposed
        and (not activeExpander.pageKey or activeExpander.pageKey == key)
    local autoCompactIfNoFit = restoreExpanded
        and options.allowAutoCompact == true and options.shrinking == true
    fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
    local restoreSerial = fixedPreviewRestoreSerial
    SaveWindowSize(frame)
    M._msuf2LayoutVersion = (M._msuf2LayoutVersion or 0) + 1
    M.CallIf(M.SetActivePageHeader, nil)
    M.activeKey = nil
    local selected = M.SelectPage and frame and frame:IsShown() and M.SelectPage(key)
    if selected and restoreExpanded then
        RestoreExpandedFixedPreview(key, M.cache and M.cache[key], restoreSerial, {
            autoCompactIfNoFit = autoCompactIfNoFit,
            reason = options.source == "resize-grip" and "WINDOW_RESIZE_RESTORE" or "WINDOW_LAYOUT_RESTORE",
        })
    end
    ApplyScrollMetrics()
    M.CallIf(M.RefreshGuidedTourChrome, "WINDOW_RESIZE")
end
function M.RegisterPage(key, spec)
    if type(key) ~= "string" or type(spec) ~= "table" then return end
    if not M.pages[key] then M.pageOrder[#M.pageOrder + 1] = key end
    M.pages[key] = spec
end
local function HideAllCachedPages()
    M.CallIf(M.ReleasePinnedPreviews, "HIDE_ALL_PAGES", nil)
    M.CallIf(M.ReleaseGFNativePreviews, "HIDE_ALL_PAGES", nil)
    M.CallIf(M.SetActivePageHeader, nil)
    for _, entry in pairs(M.cache) do
        if entry.wrapper and entry.wrapper.Hide then entry.wrapper:Hide() end
    end
end
local function SetTitle(key)
    local frame = M.frame
    if not frame then return end
    local spec = M.pages[key]
    local title = (spec and spec.title) or "MSUF"
    if frame._msuf2TitleKey ~= title then
        frame._msuf2TitleKey = title
        frame.title:SetText(M.Tr(title))
    end
    if frame.subtitle and frame._msuf2SubtitleText ~= "" then
        frame._msuf2SubtitleText = ""
        frame.subtitle:SetText("")
    end
    if frame.RefreshStatus then frame:RefreshStatus() end
end
local function UpdateNav(key)
    if not M.navButtons then return end
    local group = M.navGroupForKey and M.navGroupForKey[key]
    if group and M.navHeaderState and M.navHeaderState[group] == false then
        M.navHeaderState[group] = true
        if M.nav and M.nav._msuf2NavReflow then M.nav:_msuf2NavReflow() end
    end
    local activeNavKey = (M.navPrimaryForKey and M.navPrimaryForKey[key]) or key
    local localeKey = CurrentMenuLocaleKey()
    local labelsDirty = M._msuf2NavLocaleKey ~= localeKey
    M._msuf2NavLocaleKey = localeKey
    for pageKey, btn in pairs(M.navButtons) do
        if labelsDirty and btn._msuf2RawLabel and btn.SetText then btn:SetText(M.Tr(btn._msuf2RawLabel)) end
        local active = pageKey == activeNavKey
        if btn.SetActive and btn._msuf2Active ~= active then btn:SetActive(active) end
    end
    M._msuf2NavActiveKey = activeNavKey
    if labelsDirty and M.navHeaders then
        for _, btn in pairs(M.navHeaders) do
            if btn._msuf2RawLabel and btn.SetText then btn:SetText(string.upper(M.Tr(btn._msuf2RawLabel))) end
        end
    end
    if labelsDirty and M.navTitles then
        for _, title in pairs(M.navTitles) do
            if title._msuf2RawLabel and title.SetText then title:SetText(string.upper(M.Tr(title._msuf2RawLabel))) end
        end
    end
    if labelsDirty and M.nav and M.nav.searchBox then UpdateSearchPlaceholder(M.nav.searchBox) end
end
local function RememberPrimaryNavPage(key)
    local primary = M.navPrimaryForKey and M.navPrimaryForKey[key]
    if type(primary) ~= "string" or primary == "" then return end
    M.navLastPageForPrimary = type(M.navLastPageForPrimary) == "table" and M.navLastPageForPrimary or {}
    M.navLastPageForPrimary[primary] = key
end
function M.ResolvePrimaryNavClickTarget(primaryKey)
    primaryKey = tostring(primaryKey or "")
    local last = type(M.navLastPageForPrimary) == "table" and M.navLastPageForPrimary[primaryKey] or nil
    if type(last) == "string"
        and M.pages[last]
        and M.navPrimaryForKey
        and M.navPrimaryForKey[last] == primaryKey
    then
        return last
    end
    return primaryKey
end
local function CurrentMenuDataRevision()
    return tonumber(M._msuf2MenuDataRevision) or 0
end
function M.MarkMenuDataDirty(reason)
    M._msuf2MenuDataRevision = CurrentMenuDataRevision() + 1
    M._msuf2MenuDataDirtyReason = reason
    return M._msuf2MenuDataRevision
end
local function RunRefreshers(entry, opts)
    if not entry or not entry.refreshers then return end
    opts = opts or {}
    local revision = CurrentMenuDataRevision()
    if opts.force ~= true and entry._msuf2RefreshRevision == revision then return false end
    for i = 1, #entry.refreshers do
        local fn = entry.refreshers[i]
        if type(fn) == "function" then fn() end
    end
    entry._msuf2RefreshRevision = revision
    return true
end
IsEditModeActive = M.IsMSUFEditModeActive
local IsEditModeCombatLocked = M.IsEditModeCombatLocked
local function RefreshDashboardEditModeButton()
    local active = IsEditModeActive()
    local combatLocked = IsEditModeCombatLocked() and true or false
    local buttons = { M.dashboardEditModeButton, M.dashboardToolbarEditModeButton }
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            if active then
                btn:SetText(L_EDIT_MODE_ON)
            elseif combatLocked then
                btn:SetText(L_EDIT_MODE_OFF_COMBAT)
            else
                btn:SetText(L_EDIT_MODE_OFF)
            end
            if btn.SetEnabled then btn:SetEnabled(active or not combatLocked) end
            if btn.SetActive then btn:SetActive(active) end
        end
    end
    M.CallIf(M.RefreshGuidedTourChrome, "EDIT_MODE_STATUS")
end
local editModeUIHooked = false
local function EnsureEditModeUIHook()
    if editModeUIHooked then return end
    local register = rawget(_G, "MSUF_RegisterAnyEditModeListener")
    if type(register) ~= "function" then return end
    register(function()
        RefreshMenuFramePriority()
        local frame = M.frame
        if frame and frame:IsShown() then
            if frame.RefreshStatus then frame:RefreshStatus() end
            M.RequestOrRefresh(nil, "edit-mode-ui")
            M.CallIf(M.ResumeClassPowerPreview, "EDIT_MODE_UI", M.activeKey)
            RequestBossPagePreviewForKey(M.activeKey)
            RequestGroupPagePreviewForKey(M.activeKey)
        else
            RefreshDashboardEditModeButton()
        end
    end)
    editModeUIHooked = true
end
local function SetFrameHeightIfChanged(frame, height)
    if not (frame and frame.SetHeight) then return end
    height = tonumber(height) or CONTENT_H
    if frame._msuf2LastMenuHeight == height then return end
    frame._msuf2LastMenuHeight = height
    frame:SetHeight(height)
end
local function ApplyContextContentHeight(entry, wrapper, height)
    if type(entry) ~= "table" then return end
    height = math.max(CONTENT_H, tonumber(height) or CONTENT_H)
    entry.height = height
    SetFrameHeightIfChanged(wrapper, height)
    if not entry.hiddenBuild and M.scrollChild then
        SetFrameHeightIfChanged(M.scrollChild, height)
        if M.scrollFrame then
            M.scrollFrame._msuf2MaxScroll = nil
            M.scrollFrame._msuf2SmoothScrollTarget = nil
            if M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
        end
    end
end
local function CreateContext(key, wrapper, entry)
    local ctx = {
        key = key,
        wrapper = wrapper,
        entry = entry,
        refreshers = entry.refreshers,
        width = CONTENT_W - 32,
        fullWidth = CONTENT_W - 32,
        hiddenBuild = entry.hiddenBuild == true,
    }
    function ctx:SetContentHeight(height)
        height = math.max(CONTENT_H, tonumber(height) or CONTENT_H)
        if ctx._msuf2DeferContentHeight then
            entry.height = height
            entry._msuf2PendingContentHeight = height
            return
        end
        ApplyContextContentHeight(entry, wrapper, height)
    end
    function ctx:AddRefresher(fn)
        M.AddRefresher(ctx, fn)
    end
    return ctx
end
local SECONDARY_NAV_GROUPS = {
}
local SECONDARY_NAV_BY_KEY = {}
for _, group in pairs(SECONDARY_NAV_GROUPS) do
    for i = 1, #(group.tabs or {}) do
        local tab = group.tabs[i]
        if tab and tab.key then SECONDARY_NAV_BY_KEY[tab.key] = group end
    end
end
local SECONDARY_NAV_RAIL_W = 132
local SECONDARY_NAV_GAP = 12
local SECONDARY_NAV_MIN_RAIL_WIDTH = 680
local SECONDARY_NAV_TAB_PAD_X = 16
local SECONDARY_NAV_TAB_PAD_Y = 4
local function SecondaryNavButton(parent, label, width, active)
    local style = {
        bg = { 0.022, 0.032, 0.064, 0.94 },
        border = { 0.090, 0.135, 0.250, 0.58 },
        textColor = { 0.78, 0.87, 0.98, 1 },
        hoverBg = { 0.032, 0.046, 0.086, 0.96 },
        hoverBorder = { 0.120, 0.215, 0.405, 0.72 },
        activeBg = { 0.040, 0.100, 0.240, 0.98 },
        activeBorder = { 0.200, 0.430, 0.850, 0.94 },
        activeTextColor = { 0.94, 0.98, 1.00, 1 },
    }
    return W.TopButton(parent, M.Tr(label), width, 24, style, active)
end
local function BuildSecondaryTabs(ctx, key, group)
    if not (ctx and ctx.wrapper and group and group.tabs) then return end
    ctx._msuf2TopInset = 44
    local bar = CreateFrame("Frame", nil, ctx.wrapper)
    bar:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", 12, -12)
    bar:SetSize(ctx.width or 720, 36)
    local x = SECONDARY_NAV_TAB_PAD_X
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local w = tonumber(tab.width) or 72
        local btn = SecondaryNavButton(bar, tab.label, w, key == tab.key)
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -SECONDARY_NAV_TAB_PAD_Y)
        btn:SetScript("OnClick", function() M.SelectPage(tab.key) end)
        if M.RegisterMenuChromeControl then
            M.RegisterMenuChromeControl(btn, "secondary-navigation." .. tostring(tab.key), tab.label, "navigation",
                { navigationKey = tab.key })
        end
        x = x + w + 8
    end
    ctx._msuf2SecondaryNav = bar
end
local function BuildSecondaryRail(ctx, key, group)
    if not (ctx and ctx.wrapper and group and group.tabs) then return end
    local fullW = tonumber(ctx.fullWidth or ctx.width) or 720
    if fullW < SECONDARY_NAV_MIN_RAIL_WIDTH then
        BuildSecondaryTabs(ctx, key, group)
        return
    end
    ctx._msuf2ContentX = 12 + SECONDARY_NAV_RAIL_W + SECONDARY_NAV_GAP
    ctx.width = math.max(360, fullW - SECONDARY_NAV_RAIL_W - SECONDARY_NAV_GAP)
    local rail = T.Panel(ctx.wrapper, nil, T.colors.panel2, T.colors.borderSoft or T.colors.border)
    T.ApplySurface(rail, "rail")
    rail:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", 12, -12)
    rail:SetSize(SECONDARY_NAV_RAIL_W, math.max(260, math.min(CONTENT_H - 24, 520)))
    local title = T.Font(rail, "GameFontNormalSmall", M.Tr(group.title or ""), T.colors.accent)
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, -12)
    title:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -12, -12)
    title:SetJustifyH("LEFT")
    local y = -40
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local btn = SecondaryNavButton(rail, tab.label, SECONDARY_NAV_RAIL_W - 24, key == tab.key)
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("TOPLEFT", rail, "TOPLEFT", 12, y)
        btn:SetScript("OnClick", function() M.SelectPage(tab.key) end)
        if M.RegisterMenuChromeControl then
            M.RegisterMenuChromeControl(btn, "secondary-navigation." .. tostring(tab.key), tab.label, "navigation",
                { navigationKey = tab.key })
        end
        y = y - 32
    end
    ctx._msuf2SecondaryNav = rail
end
local function BuildSecondaryPageNav(ctx, key)
    local group = SECONDARY_NAV_BY_KEY[key]
    if not group then return end
    if group.mode == "rail" then
        BuildSecondaryRail(ctx, key, group)
    else
        BuildSecondaryTabs(ctx, key, group)
    end
end
local function BuildPlaceholderPage(ctx, requestedKey)
    local b = W.PageBuilder(ctx)
    local sec = b:Section("Native page missing", 130)
    W.Text(sec, "This native page is not implemented yet.", 16, -40, ctx.width - 32, T.colors.muted)
    W.Text(sec, M.Format("Requested page: %s", tostring(requestedKey or "unknown")), 16, -68, ctx.width - 32, T.colors.dim)
    ctx:SetContentHeight(210)
end
local BUILD_LAYOUT_ONLY_RELAYOUT = { skipStateRefresh = true }
local function CurrentPageLayoutSlot()
    return M.frame and M.frame._msuf2WindowState == "maximized" and "maximized" or "normal"
end
local function PageEntryMatchesLayout(entry, slot)
    return type(entry) == "table"
        and entry.layoutSlot == slot
        and entry.layoutWidth == CONTENT_W
        and entry.layoutHeight == CONTENT_H
end
local function RestorePageEntryRegistrations(entry)
    if type(entry) ~= "table" or type(entry.searchWidgets) ~= "table"
        or type(M.RegisterSearchWidget) ~= "function"
    then
        return
    end
    local previousBuildKey = M._msuf2SearchBuildKey
    M._msuf2SearchBuildKey = entry.key
    for i = 1, #entry.searchWidgets do
        local widget = entry.searchWidgets[i]
        local meta = widget and widget._msuf2SearchMeta
        if widget and type(meta) == "table" then M.RegisterSearchWidget(widget, meta) end
    end
    M._msuf2SearchBuildKey = previousBuildKey
end
local function RememberPageLayoutVariant(key, entry)
    if type(entry) ~= "table" then return end
    local variants = M._msuf2PageLayoutVariants[key]
    if type(variants) ~= "table" then
        variants = {}
        M._msuf2PageLayoutVariants[key] = variants
    end
    local previous = variants[entry.layoutSlot]
    if previous and previous ~= entry and previous.wrapper then
        previous._msuf2Invalidated = true
        M.CallIf(M.DisposePageHeader, previous)
        previous.wrapper:Hide()
        previous.wrapper:SetParent(nil)
    end
    variants[entry.layoutSlot] = entry
end
local function BuildPageEntry(key, hidden)
    if not M.scrollChild then return nil end
    key = ALIASES[key or ""] or key or "home"
    local spec = M.pages[key]
    local specVersion = spec and spec.version
    local layoutVersion = M._msuf2LayoutVersion or 0
    local layoutSlot = CurrentPageLayoutSlot()
    local cached = M.cache and M.cache[key]
        if cached and specVersion and cached.version ~= specVersion then
            if M.InvalidatePage then
                M.InvalidatePage(key)
            else
                M.CallIf(M.DisposePageHeader, cached)
                if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
            if cached.wrapper and cached.wrapper.SetParent then cached.wrapper:SetParent(nil) end
            M.cache[key] = nil
        end
        cached = nil
    end
    local registryCleared = false
    if cached and not PageEntryMatchesLayout(cached, layoutSlot) then
        if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
        ClearSearchRegistryPage(key)
        registryCleared = true
        M.cache[key] = nil
        local variants = M._msuf2PageLayoutVariants[key]
        local variant = type(variants) == "table" and variants[layoutSlot] or nil
        if PageEntryMatchesLayout(variant, layoutSlot)
            and (not specVersion or variant.version == specVersion)
            and variant._msuf2Invalidated ~= true
        then
            cached = variant
            cached.layoutVersion = layoutVersion
            M.cache[key] = cached
            RestorePageEntryRegistrations(cached)
        else
            cached = nil
        end
    end
    if cached and cached.hiddenBuild == true and not hidden then
        M.CallIf(M.DisposePageHeader, cached)
        if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
        if cached.wrapper and cached.wrapper.SetParent then cached.wrapper:SetParent(nil) end
        local variants = M._msuf2PageLayoutVariants[key]
        if type(variants) == "table" and variants[cached.layoutSlot] == cached then
            variants[cached.layoutSlot] = nil
        end
        M.cache[key] = nil
        cached = nil
    end
    if cached then return cached end
    if not registryCleared then ClearSearchRegistryPage(key) end
    local wrapper = CreateFrame("Frame", nil, M.scrollChild)
    wrapper:SetPoint("TOPLEFT", M.scrollChild, "TOPLEFT", 0, 0)
    wrapper:SetSize(CONTENT_W - 12, CONTENT_H)
    -- Building is always passive. SelectPage commits the entry, activates its
    -- optional fixed header, and only then reveals the completed wrapper.
    if wrapper.Hide then wrapper:Hide() end
    local entry = {
        key = key,
        wrapper = wrapper,
        refreshers = {},
        fontStrings = {},
        searchWidgets = {},
        height = CONTENT_H,
        version = specVersion,
        layoutVersion = layoutVersion,
        layoutSlot = layoutSlot,
        layoutWidth = CONTENT_W,
        layoutHeight = CONTENT_H,
        hiddenBuild = hidden and true or false,
    }
    M.cache[key] = entry
    RememberPageLayoutVariant(key, entry)
    local ctx = CreateContext(key, wrapper, entry)
    local previousFontCollectionEntry = M._msuf2FontCollectionEntry
    M._msuf2FontCollectionEntry = entry
    BuildSecondaryPageNav(ctx, key)
    local prevBuildKey = M._msuf2SearchBuildKey
    M._msuf2SearchBuildKey = key
    if spec and type(spec.build) == "function" then
        entry._msuf2PendingContentHeight = nil
        entry._msuf2Building = true
        ctx._msuf2Building = true
        ctx._msuf2DeferContentHeight = true
        local result = spec.build(ctx)
        ctx._msuf2Building = nil
        entry._msuf2Building = nil
        local builders = ctx._msuf2PageBuilders
        if type(builders) == "table" then
            local nestedLayoutChanged = false
            for i = 1, #builders do
                local builder = builders[i]
                if builder and builder._msuf2RelayoutPending and builder.RelayoutCollapsibles then
                    builder._msuf2RelayoutPending = nil
                    local changed = builder:RelayoutCollapsibles(BUILD_LAYOUT_ONLY_RELAYOUT)
                    if changed and builder.parent ~= ctx.wrapper then nestedLayoutChanged = true end
                end
            end
            -- Nested builders can resize their owning collapsible while they
            -- relayout. Reflow the page-level builder once more afterwards so
            -- its final cursor, not an earlier nested height, owns the page.
            if nestedLayoutChanged then
                for i = 1, #builders do
                    local builder = builders[i]
                    if builder and builder.parent == ctx.wrapper and builder.RelayoutCollapsibles then
                        builder:RelayoutCollapsibles(BUILD_LAYOUT_ONLY_RELAYOUT)
                    end
                end
            end
        end
        local finalHeight = tonumber(result) or entry._msuf2PendingContentHeight or entry.height or CONTENT_H
        ctx._msuf2DeferContentHeight = nil
        entry._msuf2PendingContentHeight = nil
        ctx:SetContentHeight(finalHeight)
    else
        entry._msuf2PendingContentHeight = nil
        ctx._msuf2DeferContentHeight = true
        BuildPlaceholderPage(ctx, key)
        local finalHeight = entry._msuf2PendingContentHeight or entry.height or CONTENT_H
        ctx._msuf2DeferContentHeight = nil
        entry._msuf2PendingContentHeight = nil
        ctx:SetContentHeight(finalHeight)
    end
    M._msuf2SearchBuildKey = prevBuildKey
    M._msuf2FontCollectionEntry = previousFontCollectionEntry
    if hidden and wrapper.Hide then wrapper:Hide() end
    return entry
end
-- Cold-path public entry point used by Search and Assistant V2. Callers must
-- invoke it only after an explicit menu interaction; it intentionally creates
-- and caches the requested page's real controls so RuntimeControlCatalog stays
-- the single executable source of truth.
M.BuildPageEntry = BuildPageEntry
local PAGE_HISTORY_LIMIT = 30
local suppressPageHistory
local function NormalizePageKey(key)
    if key == nil then return nil end
    key = ALIASES[key or ""] or key
    key = tostring(key or "")
    if key == "" then return nil end
    return key
end
local function PushPageHistory(stack, key)
    key = NormalizePageKey(key)
    stack = type(stack) == "table" and stack or {}
    -- Search is a transient surface: its result state is torn down on leave,
    -- so landing on it through Back/Forward would show an empty page. It never
    -- enters either stack; Back skips straight to the page before it.
    if not key or key == "search" then return stack end
    if stack[#stack] ~= key then stack[#stack + 1] = key end
    while #stack > PAGE_HISTORY_LIMIT do table.remove(stack, 1) end
    return stack
end
local function EnsurePageHistoryStacks()
    M.pageBackStack = type(M.pageBackStack) == "table" and M.pageBackStack or {}
    M.pageForwardStack = type(M.pageForwardStack) == "table" and M.pageForwardStack or {}
    return M.pageBackStack, M.pageForwardStack
end
local function RecordPageNavigation(fromKey, toKey)
    fromKey = NormalizePageKey(fromKey)
    toKey = NormalizePageKey(toKey)
    if not fromKey or not toKey or fromKey == toKey then return end
    M.pageBackStack = PushPageHistory(M.pageBackStack, fromKey)
    local _, forward = EnsurePageHistoryStacks()
    for key in pairs(forward) do forward[key] = nil end
end
local function OpenHistoryPage(page)
    local open = type(M.Open) == "function" and M.Open or M.SelectPage
    if type(open) ~= "function" then return false end
    suppressPageHistory = true
    local ok = open(page) ~= false
    suppressPageHistory = false
    return ok
end
function M.GetPageHistoryState()
    local back, forward = EnsurePageHistoryStacks()
    return {
        canBack = #back > 0,
        canForward = #forward > 0,
        backCount = #back,
        forwardCount = #forward,
        previousPage = back[#back],
        nextPage = forward[#forward],
    }
end
function M.GoBackPage()
    if M.BlockCombatAction and M.BlockCombatAction() then return false, "Dashboard back navigation is blocked in combat." end
    local back = EnsurePageHistoryStacks()
    local page = table.remove(back)
    if type(page) ~= "string" or page == "" then return false, "Dashboard back navigation has no previous native Menu2 page." end
    local current = M.activeKey
    if OpenHistoryPage(page) then
        M.pageForwardStack = PushPageHistory(M.pageForwardStack, current)
        -- Count real Back activations: once the user has gone back a few
        -- times, the discovery pulse on the button retires for good.
        local g = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
        if type(g) == "table" then g.pageHistoryBackUses = (tonumber(g.pageHistoryBackUses) or 0) + 1 end
        M.CallIf(M.RefreshPageHistoryNav, true)
        return true, "Opened previous page."
    end
    M.pageBackStack = PushPageHistory(M.pageBackStack, page)
    M.CallIf(M.RefreshPageHistoryNav, true)
    return false, "Dashboard back navigation is not available right now."
end
function M.GoForwardPage()
    if M.BlockCombatAction and M.BlockCombatAction() then return false, "Dashboard forward navigation is blocked in combat." end
    local _, forward = EnsurePageHistoryStacks()
    local page = table.remove(forward)
    if type(page) ~= "string" or page == "" then return false, "Dashboard forward navigation has no next native Menu2 page." end
    local current = M.activeKey
    if OpenHistoryPage(page) then
        M.pageBackStack = PushPageHistory(M.pageBackStack, current)
        M.CallIf(M.RefreshPageHistoryNav, true)
        return true, "Opened next page."
    end
    M.pageForwardStack = PushPageHistory(M.pageForwardStack, page)
    M.CallIf(M.RefreshPageHistoryNav, true)
    return false, "Dashboard forward navigation is not available right now."
end
--- Chrome hook: keeps the status-strip Back/Forward buttons in sync with the
--- page history stacks. Cold path -- runs only on page navigation, and stays a
--- no-op until BuildWindowChrome has created the buttons.
--- Discovery: until the user has actually gone back a few times, a normal
--- navigation that arms Back plays a soft one-shot pulse on the button
--- (C-side animation, no OnUpdate). Navigations driven by the history buttons
--- themselves pass suppressPulse so active use never blinks at the user.
local PAGE_HISTORY_DISCOVERY_USES = 3
function M.SetPageHistoryTourCue(enabled)
    local back, forward = M.pageHistoryBackButton, M.pageHistoryForwardButton
    if not (back and forward
        and type(back._msuf2SetTourCue) == "function"
        and type(forward._msuf2SetTourCue) == "function")
    then
        return false
    end
    M._pageHistoryTourCuePage = enabled == true and M.activeKey or nil
    local shown = M._pageHistoryTourCuePage ~= nil
    back._msuf2SetTourCue(shown)
    forward._msuf2SetTourCue(shown)
    return shown
end
function M.RefreshPageHistoryNav(suppressPulse)
    local back, forward = M.pageHistoryBackButton, M.pageHistoryForwardButton
    if not (back and forward) then return end
    local state = M.GetPageHistoryState()
    if back.SetEnabled then back:SetEnabled(state.canBack == true) end
    if forward.SetEnabled then forward:SetEnabled(state.canForward == true) end
    local cuePage = M._pageHistoryTourCuePage
    local showTourCue = cuePage ~= nil and M.activeKey == cuePage
    if cuePage ~= nil and not showTourCue then M._pageHistoryTourCuePage = nil end
    if type(back._msuf2SetTourCue) == "function" then
        back._msuf2SetTourCue(showTourCue)
    end
    if type(forward._msuf2SetTourCue) == "function" then
        forward._msuf2SetTourCue(showTourCue)
    end
    if suppressPulse or state.canBack ~= true then return end
    local pulse = back._msuf2DiscoveryPulse
    if not pulse then return end
    -- Hard combat gate on top of the quiescence teardown: the pulse can never
    -- start in combat, and a mid-play pulse is stopped by MenuRuntime:Quiesce
    -- like every other tracked menu animation.
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if M.frame and M.frame.IsShown and not M.frame:IsShown() then return end
    local g = type(M.GetGeneralDB) == "function" and M.GetGeneralDB() or nil
    if type(g) ~= "table" or (tonumber(g.pageHistoryBackUses) or 0) >= PAGE_HISTORY_DISCOVERY_USES then return end
    if pulse.Stop then pulse:Stop() end
    if pulse.Play then pulse:Play() end
end
function M.SelectPage(key)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    EnsurePersistentMenuState()
    key = ALIASES[key or ""] or key or "home"
    -- Unknown slash/deep-link targets must never hide the current page and
    -- leave an empty content area. Removed legacy pages and typos safely land
    -- on the Dashboard instead.
    if not (M.pages and M.pages[key]) then key = "home" end
    local restoreExpandedFixedPreview = M.ConsumeFixedPreviewExpansionForSelection(key)
    if M.activeKey and key ~= M.activeKey then M.CallIf(M.ClearPendingFixedPreviewExpansion) end
    local hasPendingFocus = false
    do
        local req = _G.MSUF_EM2_MenuFocusRequest
        hasPendingFocus = type(req) == "table"
            and req.explicit == true
            and req.consumed ~= true
            and (not req.pageKey or tostring(req.pageKey) == tostring(key))
        if not hasPendingFocus and type(M.CloseAutoFocusedSections) == "function" then M.CloseAutoFocusedSections(key) end
    end
    if key ~= "search" and M.activeKey == "search" then
        BumpSearchInputSerial()
        CancelSearchBackgroundIndex()
        M.searchResultsPending = nil
    end
    local spec = M.pages[key]
    local cached = M.cache[key]
    local specVersion = spec and spec.version
    if cached and specVersion and cached.version ~= specVersion then
        M.InvalidatePage(key)
        cached = nil
        if M.activeKey == key then M.activeKey = nil end
    end
    if key == M.activeKey and cached then
        M.sessionLastPage = key
        RememberPrimaryNavPage(key)
        M.CallIf(M.SetActivePageHeader, cached)
        M.CallIf(M.ReleasePinnedPreviews, "SELECT_CACHED", key)
        M.CallIf(M.ReleaseGFNativePreviews, "SELECT_CACHED", key)
        RunRefreshers(cached)
        QueueVisiblePageLayoutSettle(key, cached)
        M.CallIf(M.ResumeClassPowerPreview, "SELECT_CACHED", key)
        M.CallIf(M.ResumeGFNativePreviews, "SELECT_CACHED", key)
        M.CallIf(M.RunStickyHeaderActivation)
        RequestBossPagePreviewForKey(key)
        RequestGroupPagePreviewForKey(key)
        if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
        if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
        M.CallIf(M.GuidedTourOnPageSelected, key)
        M.CallIf(M.RefreshLayerOverviewContext)
        return true
    end
    local previousKey = M.activeKey
    local previous = previousKey and M.cache and M.cache[previousKey]
    M.CallIf(M.ReleasePinnedPreviews, "SELECT_PAGE", key)
    M.CallIf(M.ReleaseGFNativePreviews, "SELECT_PAGE", key)
    -- Clear the shared slot before touching either wrapper. Pages without an
    -- Editing/Page header therefore return to the original direct scroll
    -- anchor synchronously instead of inheriting stale chrome.
    M._msuf2DeferPageHeaderLayout = true
    M.CallIf(M.SetActivePageHeader, nil)
    M._msuf2DeferPageHeaderLayout = nil
    if previous and previous.wrapper and previous.wrapper.Hide then
        previous.wrapper:Hide()
    else
        HideAllCachedPages()
    end
    local entry = BuildPageEntry(key, false)
    if not entry then
        fixedPreviewRebuildExpandPageKey = nil
        M.CallIf(M.SetActivePageHeader, nil)
        return false
    end
    entry.hiddenBuild = false
    M.activeKey = key
    M.CallIf(M.SetActivePageHeader, entry)
    M.CallIf(M.RefreshLayerOverviewContext)
    if not suppressPageHistory then RecordPageNavigation(previousKey, key) end
    M.CallIf(M.RefreshPageHistoryNav, suppressPageHistory == true)
    M.sessionLastPage = key
    if M.frame then M.frame._msufCurrentKey = key end
    if M.scrollChild then SetFrameHeightIfChanged(M.scrollChild, entry.height or CONTENT_H) end
    if M.scrollFrame then
        -- Every rebuild lands the reader at the top. That is right for a page
        -- switch or a fresh result list; callers that only regrew a card on the
        -- current page use M.RebuildPageKeepingScroll below instead.
        if M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(0)
        elseif M.scrollFrame._msuf2RefreshScrollBar then
            M.scrollFrame:_msuf2RefreshScrollBar()
        end
    end
    entry.wrapper:Show()
    -- The wrapper is visible and activeKey committed: this is the earliest
    -- moment the docked panels' page-ownership gates pass, so wake their
    -- content now. Anything earlier sees a hidden wrapper and builds nothing.
    M.CallIf(M.RunStickyHeaderActivation)
    RememberPrimaryNavPage(key)
    RunRefreshers(entry)
    QueueVisiblePageLayoutSettle(key, entry)
    M.CallIf(M.ResumeClassPowerPreview, "SELECT_PAGE", key)
    M.CallIf(M.ResumeGFNativePreviews, "SELECT_PAGE", key)
    SetTitle(key)
    UpdateNav(key)
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
    RequestBossPagePreviewForKey(key)
    RequestGroupPagePreviewForKey(key)
    if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
    M.CallIf(M.GuidedTourOnPageSelected, key)
    -- A spec-version invalidation may have occurred inside this SelectPage.
    -- The local restore decision already owns that transition, so do not leave
    -- a second one-shot intent behind for an unrelated later navigation.
    fixedPreviewRebuildExpandPageKey = nil
    if restoreExpandedFixedPreview then
        fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
        RestoreExpandedFixedPreview(key, entry, fixedPreviewRestoreSerial, {
            reason = "PAGE_STATE_RESTORE",
        })
    end
    return true
end
local pageScrollRestoreSerial = 0
local function RestorePageScroll(key, offset, serial)
    if M.activeKey ~= key or serial ~= pageScrollRestoreSerial then return end
    local scroll = M.scrollFrame
    if not (scroll and scroll.SetVerticalScroll) then return end
    -- The themed setter already clamps against its accessible cached range.
    -- Avoid GetVerticalScrollRange here: Midnight may return a secret number.
    scroll:SetVerticalScroll(AccessibleNumber(offset, 0))
    M.CallIf(M.RefreshPinnedPreviews, scroll)
end
--- Rebuilds a page in place and keeps the reader where they were. Disclosures
--- that only grow or shrink a card need the rebuild for the new heights, but
--- SelectPage's viewport reset then throws the page back to the top.
--- Cards below the toggle settle their height after selection, so the immediate
--- restore covers the common case and the two retries cover the settled layout;
--- the serial drops stale retries once a newer rebuild has started.
--- Returns false only when nothing was rebuilt, so callers keep their fallback.
function M.RebuildPageKeepingScroll(key)
    key = key or M.activeKey
    if not (key and M.frame and M.frame.IsShown and M.frame:IsShown()) then return false end
    local scroll = M.scrollFrame
    local offset = AccessibleNumber(scroll and scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0, 0)
    pageScrollRestoreSerial = pageScrollRestoreSerial + 1
    local serial = pageScrollRestoreSerial
    M.InvalidatePage(key)
    if M.SelectPage(key) ~= false then
        RestorePageScroll(key, offset, serial)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() RestorePageScroll(key, offset, serial) end)
            C_Timer.After(0.05, function() RestorePageScroll(key, offset, serial) end)
        end
    end
    return true
end
local function CreateMinimizedBar(frame)
    if M.minimizedBar then return M.minimizedBar end
    local bar = T.Panel(UIParent, "MSUF2_MinimizedWindow", T.colors.glassShell or T.colors.bg, T.colors.border)
    T.ApplySurface(bar, "shell")
    bar:SetSize(MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H)
    bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 16, 16)
    ApplyMenuFramePriority(bar)
    bar:EnableMouse(true)
    bar:SetMovable(true)
    if bar.SetClampedToScreen then bar:SetClampedToScreen(true) end
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    bar:Hide()
    local title = T.Font(bar, "GameFontHighlightSmall", "MSUF Menu", T.colors.accent)
    title:SetPoint("LEFT", bar, "LEFT", 12, 0)
    title:SetPoint("RIGHT", bar, "RIGHT", -64, 0)
    title:SetJustifyH("LEFT")
    bar.title = title
    local restore = CreateWindowControlButton(bar, "maximize", "Restore", "Restore the minimized MSUF menu.")
    restore:SetPoint("RIGHT", bar, "RIGHT", -32, 0)
    restore:SetScript("OnClick", function() RestoreMinimizedSlashMenu(frame) end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(restore, "window.restore", "Restore MSUF menu", "action", {
            actionKey = "menu_window_restore",
            historyMode = "none",
            help = "Restores the minimized or maximized MSUF menu window.",
            command = {
                kind = "button",
                historyMode = "none",
                set = function()
                    if frame and frame._msuf2WindowState == "maximized" then
                        return RestoreSlashMenuWindow(frame)
                    end
                    return RestoreMinimizedSlashMenu(frame)
                end,
            },
        })
    end
    bar.restoreButton = restore
    local close = CreateWindowControlButton(bar, "close", "Close", "Close the minimized MSUF menu.")
    close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    close:SetScript("OnClick", function()
        bar:Hide()
        if frame then frame._msuf2Minimized = nil end
        M.CallIf(M.UpdateMenuCombatListener)
    end)
    bar.closeButton = close
    M.minimizedBar = bar
    return bar
end
-- The window shell is one big mouse surface, so a click that misses a control
-- used to start dragging the whole window (and arm edge snapping). Only the
-- chrome may move the window: the title strip above the content area plus the
-- bands along the other three edges that match the content insets.
local WINDOW_DRAG_TITLE_H = 40
local WINDOW_DRAG_EDGE_X = 16
local WINDOW_DRAG_EDGE_BOTTOM = 30
local function WindowDragStartAllowed(frame)
    if not (frame and frame.GetLeft and _G.GetCursorPosition) then return true end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return true end
    local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if not scale or scale == 0 then scale = 1 end
    local x, y = _G.GetCursorPosition()
    x, y = (x or 0) / scale, (y or 0) / scale
    if y >= top - WINDOW_DRAG_TITLE_H then return true end
    if y <= bottom + WINDOW_DRAG_EDGE_BOTTOM then return true end
    if x <= left + WINDOW_DRAG_EDGE_X or x >= right - WINDOW_DRAG_EDGE_X then return true end
    return false
end
local function BuildWindowShell()
    EnsurePersistentMenuState()
    SetWindowMetrics(ReadSavedWindowSize())
    local f = T.Panel(UIParent, "MSUF2_Window", T.colors.glassShell or T.colors.bg, T.colors.border)
    T.ApplySurface(f, "shell")
    ExportPublic("MSUF_StandaloneOptionsWindow", f)
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    ApplyMenuFramePriority(f)
    f:EnableMouse(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    ApplyWindowResizeBounds(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if WindowDragStartAllowed(self) then self:_msuf2BeginWindowDrag() end
    end)
    f:SetScript("OnDragStop", function(self) self:_msuf2FinishWindowDrag(true) end)
    f:SetScript("OnSizeChanged", function(self)
        if self._msuf2LiveResizing then
            self._msuf2ResizeMetricsDirty = true
            return
        end
        if self._msuf2WindowLayoutAnim then
            -- Raw animation geometry changes every render frame. Responsive
            -- metrics and preview layout commit once in the onFinished rebuild;
            -- recalculating them here makes the preview visibly chase the shell.
            return
        end
        RefreshWindowMetrics(self)
        ApplyScrollMetrics()
    end)
    f:Hide()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "MSUF2_Window") end
    local title = T.Font(f, "GameFontDisableSmall", "MSUF", T.colors.accent)
    title:SetPoint("TOPLEFT", 12, -6)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -6)
    title:SetJustifyH("LEFT")
    title:SetAlpha(0.82)
    f.title = title
    local subtitle = T.Font(f, "GameFontDisableSmall", "", T.colors.muted)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -16)
    subtitle:SetJustifyH("RIGHT")
    subtitle:Hide()
    f.subtitle = subtitle
    local windowControls = M.CreateWindowControlGroup(f, 3)
    -- The authored texture extends three pixels beyond the clickable group on
    -- the horizontal axis. Offset the anchor by 11 so the visible right edge,
    -- like the visible top edge, observes the rail's 8px outer spacing.
    windowControls:SetPoint("TOPRIGHT", f, "TOPRIGHT", -11, -7)
    f.windowControls = windowControls
    local close = M.CreateWindowControlButton(windowControls, "close", "Close", "Close the MSUF menu window.", 3)
    close:SetPoint("TOPRIGHT", windowControls, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() M.HideSlashMenuAndMinibar(f) end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(close, "window.close", "Close MSUF menu", "action", {
            actionKey = "menu_window_close",
            historyMode = "none",
            help = "Closes the MSUF menu window, including its minimized bar.",
        })
    end
    if M.minimizedBar and M.minimizedBar.closeButton and M.MarkRuntimeControlComponent then
        M.MarkRuntimeControlComponent(M.minimizedBar.closeButton, close)
    end
    f.closeButton = close
    local maximize = M.CreateWindowControlButton(windowControls, "maximize", "Maximize", "Maximize or restore the MSUF menu window.", 2)
    maximize:SetPoint("TOPRIGHT", close, "TOPLEFT", 0, 0)
    maximize:SetScript("OnClick", function() MaximizeSlashMenuWindow(f) end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(maximize, "window.maximize", "Maximize MSUF menu", "action", {
            actionKey = "menu_window_maximize",
            historyMode = "none",
            help = "Maximizes the MSUF menu window; the same title-bar button restores it when maximized.",
            command = {
                kind = "button",
                historyMode = "none",
                set = function()
                    if f._msuf2WindowState == "maximized" then return false end
                    return MaximizeSlashMenuWindow(f)
                end,
            },
        })
    end
    f.maximizeButton = maximize
    local minimize = M.CreateWindowControlButton(windowControls, "minimize", "Minimize", "Collapse the MSUF menu to a small taskbar-style bar.", 1)
    minimize:SetPoint("TOPRIGHT", maximize, "TOPLEFT", 0, 0)
    minimize:SetScript("OnClick", function() MinimizeSlashMenuWindow(f) end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(minimize, "window.minimize", "Minimize MSUF menu", "action", {
            actionKey = "menu_window_minimize",
            historyMode = "none",
            help = "Minimizes the MSUF menu to its compact draggable bar.",
        })
    end
    f.minimizeButton = minimize
    return { frame = f }
end

local function InstallMenuScaleControl(f)
    if not (f and T and type(T.Panel) == "function" and type(T.Font) == "function") then return end
    local control = T.Panel(f, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    if type(T.ApplySurface) == "function" then T.ApplySurface(control, "status") end
    control:SetSize(190, 22)
    control:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 4)
    control:SetFrameLevel(f:GetFrameLevel() + 20)
    control:EnableMouse(true)

    local label = T.Font(control, "GameFontDisableSmall", "", T.colors.muted)
    label:SetPoint("LEFT", control, "LEFT", 8, 0)
    label:SetWidth(76)
    label:SetJustifyH("LEFT")

    local slider = CreateFrame("Slider", nil, control)
    slider:SetPoint("LEFT", label, "RIGHT", 6, 0)
    slider:SetPoint("RIGHT", control, "RIGHT", -8, 0)
    slider:SetHeight(20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT)
    slider:SetValueStep(MENU_SCALE_STEP_PERCENT)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.SetStepsPerPage then slider:SetStepsPerPage(0) end
    if slider.EnableMouseWheel then slider:EnableMouseWheel(true) end
    if slider.SetPropagateMouseWheel then slider:SetPropagateMouseWheel(false) end
    slider._msuf2CursorDrag = true
    if type(T.StyleSlider) == "function" then T.StyleSlider(slider) end

    local function Percent(value)
        local pct = tonumber(value) or 100
        if pct < MENU_SCALE_MIN_PERCENT then pct = MENU_SCALE_MIN_PERCENT
        elseif pct > MENU_SCALE_MAX_PERCENT then pct = MENU_SCALE_MAX_PERCENT end
        return floor((pct / MENU_SCALE_STEP_PERCENT) + 0.5) * MENU_SCALE_STEP_PERCENT
    end
    local function UpdateVisual(value)
        local pct = Percent(value or slider:GetValue())
        label:SetText(string.format("%s %d%%", M.Tr("Menu"), pct))
        local fill = slider._msufFill
        if fill then
            local span = MENU_SCALE_MAX_PERCENT - MENU_SCALE_MIN_PERCENT
            local fraction = span > 0 and ((pct - MENU_SCALE_MIN_PERCENT) / span) or 0
            fill:SetWidth(max(1, max(1, slider:GetWidth() - 2) * fraction))
        end
        if slider._msuf2UpdateThumb then slider:_msuf2UpdateThumb() end
    end
    slider._msuf2UpdateFill = function(self) UpdateVisual(self:GetValue()) end

    local function Refresh()
        local g = M.GetGeneralDB and M.GetGeneralDB()
        local pct = Percent(MenuScalePercent(type(g) == "table" and g.slashMenuScale or MENU_SCALE_REFERENCE))
        slider._msuf2Refreshing = true
        slider:SetValue(pct)
        slider._msuf2Refreshing = nil
        UpdateVisual(pct)
    end
    local function Commit(value)
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) ~= "table" then return false end
        local pct = Percent(value or slider:GetValue())
        g.slashMenuScale = MenuScaleValue(pct)
        if ApplyMenuFrameScale then
            ApplyMenuFrameScale(f)
        elseif f.SetScale then
            f:SetScale(EffectiveMenuScale(g.slashMenuScale))
            ApplyWindowResizeBounds(f)
        end
        Refresh()
        return true
    end
    local function SetValueFromCursor()
        if not (_G.GetCursorPosition and slider.GetLeft and slider.GetWidth) then return end
        local left, width = slider:GetLeft(), slider:GetWidth()
        if not left or not width or width <= 0 then return end
        local cursorX = _G.GetCursorPosition()
        local effectiveScale = slider.GetEffectiveScale and slider:GetEffectiveScale() or 1
        if not effectiveScale or effectiveScale == 0 then effectiveScale = 1 end
        local fraction = ((cursorX / effectiveScale) - left) / width
        if fraction < 0 then fraction = 0 elseif fraction > 1 then fraction = 1 end
        local target = Percent(MENU_SCALE_MIN_PERCENT + ((MENU_SCALE_MAX_PERCENT - MENU_SCALE_MIN_PERCENT) * fraction))
        if target ~= tonumber(slider:GetValue()) then slider:SetValue(target) end
    end
    -- Same cursor-follow contract as W.Slider: the press keeps driving the
    -- value until the button is released, not just on the down-click.
    local function FollowScaleCursor(self)
        if not self._msuf2MenuScaleDragging then
            self:SetScript("OnUpdate", nil)
            return
        end
        if _G.IsMouseButtonDown and not _G.IsMouseButtonDown("LeftButton") then
            self._msuf2MenuScaleDragging = nil
            self:SetScript("OnUpdate", nil)
            Commit(self:GetValue())
            return
        end
        SetValueFromCursor()
    end

    slider:HookScript("OnValueChanged", function(self, value)
        if not self._msuf2Refreshing then UpdateVisual(value) end
    end)
    slider:SetScript("OnMouseDown", function(self, button)
        if button and button ~= "LeftButton" then return end
        self._msuf2MenuScaleDragging = true
        SetValueFromCursor()
        self:SetScript("OnUpdate", FollowScaleCursor)
    end)
    slider:SetScript("OnMouseUp", function(self, button)
        if button and button ~= "LeftButton" then return end
        self._msuf2MenuScaleDragging = nil
        self:SetScript("OnUpdate", nil)
        Commit(self:GetValue())
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not delta or delta == 0 then return end
        local step = MENU_SCALE_STEP * 100
        self:SetValue(Percent((tonumber(self:GetValue()) or 100) + (delta > 0 and step or -step)))
        Commit(self:GetValue())
    end)
    slider:HookScript("OnHide", function(self)
        self._msuf2MenuScaleDragging = nil
        self:SetScript("OnUpdate", nil)
    end)

    local tooltip = "Scales only the MSUF menu. Drag the bar or use the mouse wheel; changes apply immediately."
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(control, "MSUF Menu Scale", tooltip, { hook = true, owner = "ANCHOR_TOP" })
        M.AddTooltip(slider, "MSUF Menu Scale", tooltip, { hook = true, owner = "ANCHOR_TOP" })
    end
    if type(M.RegisterMenuChromeControl) == "function" then
        M.RegisterMenuChromeControl(slider, "window.menu-scale", "MSUF Menu Scale", "setting", {
            kind = "slider",
            settingKey = "general.slashMenuScale",
            historyMode = "none",
            help = "Reads and applies the MSUF configuration-menu scale percentage directly.",
            command = {
                kind = "slider", min = MENU_SCALE_MIN_PERCENT, max = MENU_SCALE_MAX_PERCENT,
                step = MENU_SCALE_STEP_PERCENT, percentIsValue = true, historyMode = "none",
                get = function()
                    local g = M.GetGeneralDB and M.GetGeneralDB()
                    return Percent(MenuScalePercent(type(g) == "table" and g.slashMenuScale or MENU_SCALE_REFERENCE))
                end,
                set = function(value)
                    slider:SetValue(Percent(value))
                    return Commit(slider:GetValue())
                end,
                refresh = Refresh,
            },
        })
    end
    control.slider, control.label, control.Refresh = slider, label, Refresh
    f.menuScaleControl, f.menuScaleSlider = control, slider
    f.RefreshMenuScaleControl = Refresh
    Refresh()
end

-- Same links as the dashboard support card, parked in the free bottom-left
-- corner of the footer band: faint until hovered so the chrome stays quiet.
-- The marks keep their colors at rest -- at 14px the brand color is the only
-- thing that tells them apart, so desaturating them on top of the low alpha
-- left five identical gray blobs. Anchored to the nav rail so the row lines up
-- with the nav buttons above it, and centered in the 30px band so it shares a
-- baseline with the menu-scale control on the right.
local SUPPORT_STRIP_NAV_INSET = 8 -- mirrors NAV_ITEM_X in MSUF_Menu2_NavRail
local function InstallSupportLinkStrip(f)
    if not (f and type(CreateFrame) == "function") then return end
    if f.supportLinkStrip then return end
    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local links = {
        { texture = "Discord.png", title = "Discord", tooltip = "Copy Discord Link", url = "https://discord.gg/2Gf9b2Wprz" },
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
    }
    local size, gap, idleAlpha = 14, 7, 0.45
    local strip = CreateFrame("Frame", nil, f)
    strip:SetSize((#links * size) + ((#links - 1) * gap), size)
    local rail = f.nav
    if rail then
        strip:SetPoint("TOPLEFT", rail, "BOTTOMLEFT", SUPPORT_STRIP_NAV_INSET, -floor((WINDOW_FOOTER_H - size) * 0.5))
    else
        strip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16 + SUPPORT_STRIP_NAV_INSET, floor((WINDOW_FOOTER_H - size) * 0.5))
    end
    strip:SetFrameLevel(f:GetFrameLevel() + 20)
    local previous
    for i = 1, #links do
        local data = links[i]
        local btn = CreateFrame("Button", nil, strip)
        btn:SetSize(size, size)
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        else
            btn:SetPoint("LEFT", strip, "LEFT", 0, 0)
        end
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(iconDir .. data.texture)
        icon:SetAlpha(idleAlpha)
        btn:SetScript("OnEnter", function() icon:SetAlpha(1) end)
        btn:SetScript("OnLeave", function() icon:SetAlpha(idleAlpha) end)
        btn:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink(data.title, data.url) end
        end)
        if type(M.AddTooltip) == "function" then
            M.AddTooltip(btn, data.title, data.tooltip, { hook = true, owner = "ANCHOR_TOP" })
        end
        previous = btn
    end
    f.supportLinkStrip = strip
end

-- Drag, snap and resize share transient proxy state but no page/chrome state.
local function InstallWindowInteractions(state)
    local f = state.frame
    local function EnsureResizeProxy()
        if f._msuf2ResizeProxy then return f._msuf2ResizeProxy end
        local proxy = CreateFrame("Frame", nil, UIParent)
        ApplyMenuResizeProxyPriority(proxy, f)
        proxy:Hide()
        local fill = proxy:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(T.colors.bg[1], T.colors.bg[2], T.colors.bg[3], 0.18)
        proxy.fill = fill
        local accent = T.colors.accent or { 0.22, 0.78, 0.94, 1 }
        local function Edge(pointA, pointB, width, height)
            local tex = proxy:CreateTexture(nil, "BORDER")
            tex:SetColorTexture(accent[1], accent[2], accent[3], 0.72)
            tex:SetPoint(unpack(pointA))
            tex:SetPoint(unpack(pointB))
            if width then tex:SetWidth(width) end
            if height then tex:SetHeight(height) end
            return tex
        end
        Edge({ "TOPLEFT", proxy, "TOPLEFT", 0, 0 }, { "TOPRIGHT", proxy, "TOPRIGHT", 0, 0 }, nil, 2)
        Edge({ "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 0, 0 }, nil, 2)
        Edge({ "TOPLEFT", proxy, "TOPLEFT", 0, 0 }, { "BOTTOMLEFT", proxy, "BOTTOMLEFT", 0, 0 }, 2, nil)
        Edge({ "TOPRIGHT", proxy, "TOPRIGHT", 0, 0 }, { "BOTTOMRIGHT", proxy, "BOTTOMRIGHT", 0, 0 }, 2, nil)
        local label = T.Font(proxy, "GameFontDisableSmall", "", accent)
        label:SetPoint("BOTTOMRIGHT", proxy, "TOPRIGHT", 0, 4)
        label:SetJustifyH("RIGHT")
        proxy.sizeLabel = label
        f._msuf2ResizeProxy = proxy
        return proxy
    end
    local function ShowWindowLayoutProxy(layout)
        if not layout then return nil end
        local scale = layout.scale or WindowVisualScale(f)
        if scale <= 0 then scale = 1 end
        local proxy = EnsureResizeProxy()
        ApplyMenuResizeProxyPriority(proxy, f)
        local left = layout.uiLeft or layout.x or SNAP_SCREEN_MARGIN
        local top = layout.uiTop or layout.yTop or DEFAULT_WINDOW_H
        proxy:ClearAllPoints()
        proxy:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        proxy:SetSize(layout.visualW or ((layout.w or WINDOW_W) * scale), layout.visualH or ((layout.h or WINDOW_H) * scale))
        if proxy.sizeLabel then proxy.sizeLabel:SetText(string.format("%d x %d", layout.w or WINDOW_W, layout.h or WINDOW_H)) end
        proxy:Show()
        return proxy
    end
    local function HideWindowLayoutProxy()
        local proxy = f._msuf2ResizeProxy
        if proxy then proxy:Hide() end
        f._msuf2SnapPreviewKey = nil
    end
    local FinishWindowDrag
    local function UpdateSnapPreview()
        if not f._msuf2DraggingWindow then return end
        if _G.IsMouseButtonDown and not _G.IsMouseButtonDown("LeftButton") then
            if FinishWindowDrag then FinishWindowDrag(true) end
            return
        end
        local layout = GetSlashMenuSnapLayout(f)
        if not layout then
            f._msuf2LastSnapLayout = nil
            HideWindowLayoutProxy()
            return
        end
        f._msuf2LastSnapLayout = layout
        local key = floor((layout.x or 0) + 0.5) .. ":"
            .. floor((layout.yTop or 0) + 0.5) .. ":"
            .. floor((layout.w or 0) + 0.5) .. ":"
            .. floor((layout.h or 0) + 0.5)
        if key == f._msuf2SnapPreviewKey then return end
        f._msuf2SnapPreviewKey = key
        ShowWindowLayoutProxy(layout)
    end
    local function BeginWindowDrag()
        -- Native moving and the animation driver both own the frame's anchors.
        -- Settle the pending target first so an immediate re-drag cannot fight
        -- the snap animation or retain an in-between window size.
        SettleWindowLayoutAnimation(f)
        if f._msuf2WindowState == "maximized" then
            f._msuf2WindowState = "normal"
            f._msuf2RestoreLayout = nil
            M.CallIf(M.RefreshWindowControls, f)
        end
        f._msuf2DraggingWindow = true
        f._msuf2SnapPreviewKey = nil
        f._msuf2LastSnapLayout = nil
        f:StartMoving()
        if IsSlashMenuSnapEnabled() then
            f:SetScript("OnUpdate", UpdateSnapPreview)
            UpdateSnapPreview()
        end
    end
    FinishWindowDrag = function(applySnap)
        local wasDragging = f._msuf2DraggingWindow == true
        f._msuf2DraggingWindow = nil
        f:SetScript("OnUpdate", nil)
        HideWindowLayoutProxy()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        -- OnDragStop also fires when the shell rejected OnDragStart because the
        -- press began over page content. Never turn that rejected gesture into
        -- an invisible edge snap, and never re-apply snap after fallback cleanup.
        if applySnap and wasDragging then ApplySlashMenuSnap(f) end
        f._msuf2LastSnapLayout = nil
    end
    f._msuf2BeginWindowDrag = BeginWindowDrag
    f._msuf2FinishWindowDrag = FinishWindowDrag
    local FinishResizeProxy
    local function UpdateResizeProxy()
        local state = f._msuf2ResizeState
        if not state then return end
        if not f._msuf2FinishingResize and _G.IsMouseButtonDown and not _G.IsMouseButtonDown("LeftButton") then
            if FinishResizeProxy then FinishResizeProxy(true) end
            return
        end
        local cursorX, cursorY = CursorPositionInUIParent()
        if not cursorX then return end
        local scale = state.scale or 1
        if scale <= 0 then scale = 1 end
        local maxW, maxH = WindowMaxBounds()
        local w = ClampNumber(state.startW + ((cursorX - state.cursorX) / scale), MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
        local h = ClampNumber(state.startH + ((state.cursorY - cursorY) / scale), MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
        if state.w == w and state.h == h then return end
        state.w, state.h = w, h
        ShowWindowLayoutProxy({ x = state.layout.x, yTop = state.layout.yTop, uiLeft = state.uiLeft, uiTop = state.uiTop, w = w, h = h, scale = scale })
    end
    local function BeginResizeProxy(button)
        if button ~= "LeftButton" then return false end
        SettleWindowLayoutAnimation(f)
        local cursorX, cursorY = CursorPositionInUIParent()
        local layout = CaptureFrameLayout(f)
        if not (cursorX and layout) then return false end
        f._msuf2LiveResizing = true
        f._msuf2ResizeMetricsDirty = nil
        f._msuf2WindowState = "normal"
        f._msuf2RestoreLayout = nil
        M.CallIf(M.RefreshWindowControls, f)
        f._msuf2ResizeState = {
            cursorX = cursorX,
            cursorY = cursorY,
            startW = layout.w or WINDOW_W,
            startH = layout.h or WINDOW_H,
            layout = layout,
            scale = WindowVisualScale(f),
        }
        local uiLeft, _, uiTop = FrameRectToUIParent(f)
        f._msuf2ResizeState.uiLeft = uiLeft or layout.x
        f._msuf2ResizeState.uiTop = uiTop or layout.yTop
        local proxy = EnsureResizeProxy()
        proxy:SetScript("OnUpdate", UpdateResizeProxy)
        proxy:Show()
        UpdateResizeProxy()
        return true
    end
    FinishResizeProxy = function(apply)
        local state = f._msuf2ResizeState
        f._msuf2FinishingResize = true
        if state then UpdateResizeProxy() end
        local proxy = f._msuf2ResizeProxy
        if proxy then
            proxy:SetScript("OnUpdate", nil)
            HideWindowLayoutProxy()
        end
        if not state then
            f._msuf2LiveResizing = nil
            f._msuf2ResizeMetricsDirty = nil
            f._msuf2FinishingResize = nil
            return
        end
        local w = state.w or state.startW
        local h = state.h or state.startH
        local changed = math.abs((w or state.startW) - state.startW) >= 1
            or math.abs((h or state.startH) - state.startH) >= 1
        f._msuf2ResizeState = nil
        f._msuf2ResizeMetricsDirty = nil
        f._msuf2LiveResizing = nil
        f._msuf2FinishingResize = nil
        if apply and changed then
            local layout = { x = state.layout.x, yTop = state.layout.yTop, w = w, h = h }
            local current = CaptureFrameLayout(f)
            local settleStart = current and {
                x = layout.x,
                yTop = layout.yTop,
                w = ResizeSettleStartValue(current.w, layout.w),
                h = ResizeSettleStartValue(current.h, layout.h),
            }
            local rebuildOptions = {
                source = "resize-grip",
                allowAutoCompact = true,
                shrinking = (w < state.startW - 0.5) or (h < state.startH - 0.5),
            }
            if settleStart and AnimateWindowLayout(f, layout, {
                start = settleStart,
                applyStart = true,
                duration = WINDOW_RESIZE_ANIM_SECONDS,
                onFinished = function()
                    ApplyWindowLayout(f, layout, true, rebuildOptions)
                end,
            }) then
                return
            end
            ApplyWindowLayout(f, layout, true, rebuildOptions)
        end
    end
    function f:_msuf2CancelWindowInteractions()
        self._msuf2DraggingWindow = nil
        self._msuf2LastSnapLayout = nil
        self._msuf2SnapPreviewKey = nil
        if self.SetScript then self:SetScript("OnUpdate", nil) end
        HideWindowLayoutProxy()
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        if FinishResizeProxy then FinishResizeProxy(false) end
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        BeginResizeProxy(button)
    end)
    grip:SetScript("OnMouseUp", function()
        FinishResizeProxy(true)
    end)
    grip:SetScript("OnHide", function()
        FinishResizeProxy(false)
    end)
    f.resizeGrip = grip
    InstallMenuScaleControl(f)
    CreateMinimizedBar(f)
    M.CallIf(M.RefreshWindowControls, f)
end

local function BuildWindowChrome(state)
    local f = state.frame
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -40)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, WINDOW_FOOTER_H)
    f.content = content
    local nav = T.Panel(content, nil, T.colors.glassRail or T.colors.panelNav or T.colors.panel, T.colors.borderSoft)
    T.ApplySurface(nav, "rail")
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    f.nav = nav
    f._msufNavRail = nav
    f._msufNavStack = nav
    M.nav = nav
    BuildNav(nav)
    InstallSupportLinkStrip(f)
    local host = T.Panel(content, nil, T.colors.glassHost or T.colors.panel, T.colors.borderSoft)
    T.ApplySurface(host, "host")
    host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 4, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    f.host = host
    f._msufMirrorHost = host
    if T.ApplyMenuAtmosphere then T.ApplyMenuAtmosphere(f, host, nav) end
    local status = T.Panel(host, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    T.ApplySurface(status, "status")
    status:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    status:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    status:SetHeight(60)
    local function StatusDivider(edge, inset, alpha)
        local line = status:CreateTexture(nil, "ARTWORK", nil, 6)
        line:SetHeight(1)
        line:SetPoint(edge .. "LEFT", status, edge .. "LEFT", inset, 0)
        line:SetPoint(edge .. "RIGHT", status, edge .. "RIGHT", -inset, 0)
        line:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], alpha)
    end
    StatusDivider("TOP", 0, 0.25)
    StatusDivider("BOTTOM", 16, 0.16)
    local function StatusText(point, relativeTo, relativePoint, x, y, justify, alpha)
        local fs = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
        fs:SetPoint(point, relativeTo, relativePoint, x, y)
        fs:SetJustifyH(justify or "LEFT")
        if alpha then fs:SetAlpha(alpha) end
        return fs
    end
    -- Browser-style Back/Forward page navigation. The history stacks live next
    -- to SelectPage; these two ghost buttons are their only visible surface.
    -- Cold path by construction: state changes on page navigation only, no
    -- OnUpdate, no events. All colors come from theme tokens so every menu
    -- accent (midnight, class, presets, custom, +tint) restyles them for free.
    -- The 22px art is a much smaller target than the empty strip around it, so
    -- the hit rect grows well past the glyph: down to just above the bottom
    -- divider, up to the text row, and outward to the side. The 2px gap between
    -- the pair is split 1/1 so neither arrow ever steals the other's clicks.
    local function HistoryNavButton(rotation, hitLeft, hitRight, onClick)
        local btn = CreateFrame("Button", nil, status)
        btn:SetSize(22, 22)
        if btn.SetHitRectInsets then btn:SetHitRectInsets(hitLeft, hitRight, -5, -11) end
        local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2HistNav", 1, "BACKGROUND", "BORDER")
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(T.media.dropdownChevron)
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER", 0, 0)
        if icon.SetRotation then icon:SetRotation(rotation) end
        btn._msuf2HistNavIcon = icon
        local function Paint(self, hover, down)
            local c = T.colors
            local disabled = self.IsEnabled and not self:IsEnabled()
            if self._msuf2TourCue then
                if fill then fill:SetVertexColor(c.pillActive[1], c.pillActive[2], c.pillActive[3], 0.90) end
                if edge then edge:SetVertexColor(c.pillEdgeActive[1], c.pillEdgeActive[2], c.pillEdgeActive[3], 0.92) end
                icon:SetVertexColor(c.pillTextActive[1], c.pillTextActive[2], c.pillTextActive[3], 1)
            elseif disabled then
                if fill then fill:SetVertexColor(0, 0, 0, 0) end
                if edge then edge:SetVertexColor(0, 0, 0, 0) end
                icon:SetVertexColor(c.disabled[1], c.disabled[2], c.disabled[3], 0.55)
            elseif down then
                if fill then fill:SetVertexColor(c.pillActive[1], c.pillActive[2], c.pillActive[3], 0.90) end
                if edge then edge:SetVertexColor(c.pillEdgeActive[1], c.pillEdgeActive[2], c.pillEdgeActive[3], 0.85) end
                icon:SetVertexColor(c.pillTextActive[1], c.pillTextActive[2], c.pillTextActive[3], 1)
            elseif hover then
                if fill then fill:SetVertexColor(c.pillHover[1], c.pillHover[2], c.pillHover[3], 0.92) end
                if edge then edge:SetVertexColor(c.pillEdgeHover[1], c.pillEdgeHover[2], c.pillEdgeHover[3], 0.80) end
                icon:SetVertexColor(c.text[1], c.text[2], c.text[3], 1)
            else
                if fill then fill:SetVertexColor(0, 0, 0, 0) end
                if edge then edge:SetVertexColor(0, 0, 0, 0) end
                icon:SetVertexColor(c.muted[1], c.muted[2], c.muted[3], 0.96)
            end
        end
        btn:SetScript("OnEnter", function(self) self._msuf2Hover = true; Paint(self, true, self._msuf2Down) end)
        btn:SetScript("OnLeave", function(self) self._msuf2Hover = nil; self._msuf2Down = nil; Paint(self, false, false) end)
        btn:SetScript("OnMouseDown", function(self) self._msuf2Down = true; Paint(self, self._msuf2Hover, true) end)
        btn:SetScript("OnMouseUp", function(self) self._msuf2Down = nil; Paint(self, self._msuf2Hover, false) end)
        btn:SetScript("OnEnable", function(self) Paint(self, self._msuf2Hover, self._msuf2Down) end)
        btn:SetScript("OnDisable", function(self) Paint(self, false, false) end)
        btn:SetScript("OnClick", onClick)
        -- The first upgrade-tour stop deliberately makes this impossible to
        -- miss. A native animation group flashes the complete button quickly;
        -- there is no Lua OnUpdate, and MenuRuntime quiescence tracks/stops it
        -- with every other menu animation.
        local tourBlink
        if btn.CreateAnimationGroup then
            tourBlink = btn:CreateAnimationGroup()
            if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(tourBlink) end
            if tourBlink.SetLooping then tourBlink:SetLooping("BOUNCE") end
            local fade = tourBlink:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.08)
            fade:SetDuration(0.16)
            btn._msuf2TourBlink = tourBlink
        end
        btn._msuf2SetTourCue = function(enabled)
            btn._msuf2TourCue = enabled == true or nil
            Paint(btn, btn._msuf2Hover, btn._msuf2Down)
            if btn._msuf2TourCue then
                if tourBlink and (not tourBlink.IsPlaying or not tourBlink:IsPlaying()) then tourBlink:Play() end
            else
                if tourBlink and tourBlink.Stop then tourBlink:Stop() end
                btn:SetAlpha(1)
            end
        end
        -- Disabled arrows keep their tooltip so the affordance stays learnable.
        if btn.SetMotionScriptsWhileDisabled then btn:SetMotionScriptsWhileDisabled(true) end
        Paint(btn, false, false)
        return btn
    end
    -- Bottom-left of the strip, in line with the toolbar button row on the
    -- right; the Profile/Edit/Combat text row above keeps its full width.
    local histBack = HistoryNavButton(-math.pi * 0.5, -12, -1, function() M.GoBackPage() end)
    histBack:SetPoint("BOTTOMLEFT", status, "BOTTOMLEFT", 18, 13)
    local histForward = HistoryNavButton(math.pi * 0.5, -1, -14, function() M.GoForwardPage() end)
    histForward:SetPoint("LEFT", histBack, "RIGHT", 2, 0)
    M.pageHistoryBackButton = histBack
    M.pageHistoryForwardButton = histForward
    -- Discovery pulse for the Back button: a soft accent halo one frame level
    -- below the button, driven purely by a C-side animation group. Base alpha
    -- stays 0, so outside a one-shot Play() the halo costs nothing and shows
    -- nothing; RefreshPageHistoryNav owns when it may fire.
    local glow = CreateFrame("Frame", nil, status)
    glow:SetPoint("TOPLEFT", histBack, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", histBack, "BOTTOMRIGHT", 2, -2)
    glow:SetFrameLevel(math.max(0, histBack:GetFrameLevel() - 1))
    local glowFill, glowEdge = T.CreateSuperellipseLayers(glow, "_msuf2HistNavGlow", 1, "BACKGROUND", "BORDER")
    if glowFill then glowFill:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.22) end
    if glowEdge then glowEdge:SetVertexColor(T.colors.pillEdgeActive[1], T.colors.pillEdgeActive[2], T.colors.pillEdgeActive[3], 0.55) end
    glow:SetAlpha(0)
    if glow.CreateAnimationGroup then
        local pulse = glow:CreateAnimationGroup()
        if T.TrackMenuAnimationGroup then T.TrackMenuAnimationGroup(pulse) end
        local function PulseStep(order, from, to, duration)
            local step = pulse:CreateAnimation("Alpha")
            step:SetOrder(order)
            step:SetFromAlpha(from)
            step:SetToAlpha(to)
            step:SetDuration(duration)
        end
        PulseStep(1, 0, 1, 0.18)
        PulseStep(2, 1, 0, 0.42)
        histBack._msuf2DiscoveryPulse = pulse
    end
    local function HistoryTargetTitle(field)
        local history = type(M.GetPageHistoryState) == "function" and M.GetPageHistoryState() or nil
        local spec = history and history[field] and M.pages and M.pages[history[field]]
        return spec and spec.title and M.Tr(spec.title) or ""
    end
    if M.AddTooltip then
        M.AddTooltip(histBack, function() return M.Tr("Previous page") end,
            function() return HistoryTargetTitle("previousPage") end, { hook = true })
        M.AddTooltip(histForward, function() return M.Tr("Next page") end,
            function() return HistoryTargetTitle("nextPage") end, { hook = true })
    end
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(histBack, "toolbar.page-back", "Previous Page", "action", {
            actionKey = "dashboard_page_back",
            historyMode = "none", help = "Opens the previous page from the menu page history.",
        })
        M.RegisterMenuChromeControl(histForward, "toolbar.page-forward", "Next Page", "action", {
            actionKey = "dashboard_page_forward",
            historyMode = "none", help = "Opens the next page from the menu page history.",
        })
    end
    M.RefreshPageHistoryNav(true)
    local sbProfile = StatusText("LEFT", status, "LEFT", 24, 15)
    local sbEdit = StatusText("LEFT", sbProfile, "RIGHT", 16, 0)
    local sbCombat = StatusText("LEFT", sbEdit, "RIGHT", 16, 0)
    local sbVersion = StatusText("RIGHT", status, "RIGHT", -16, 15, "RIGHT", 0.50)
    local sbFeedback = StatusText("RIGHT", sbVersion, "LEFT", -16, 15, "RIGHT", 0)
    sbFeedback:SetPoint("LEFT", sbCombat, "RIGHT", 16, 15)
    status.profileText = sbProfile
    status.editText = sbEdit
    status.combatText = sbCombat
    status.versionText = sbVersion
    status.feedbackText = sbFeedback
    status.text = sbProfile
    f.status = status
end

local function BuildWindowToolbar(state)
    local f, status = state.frame, state.frame.status
    local function RunToolbarSeeNewFeatures()
        if type(M.OpenSeeNewFeatures) == "function" then return M.OpenSeeNewFeatures() end
        if type(M.SelectPage) == "function" then return M.SelectPage("changelog") end
        return false
    end
    local function RunToolbarEditMode()
        if type(M.ToggleDashboardEditMode) == "function" then return M.ToggleDashboardEditMode() end
        if IsEditModeCombatLocked and IsEditModeCombatLocked() then
            M.CallIf(M.BlockCombatAction)
            RefreshDashboardEditModeButton()
            return
        end
        local active = IsEditModeActive and IsEditModeActive()
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then _G.MSUF_SetMSUFEditModeDirect(not active) end
        RefreshDashboardEditModeButton()
        if f.RefreshStatus then f:RefreshStatus() end
    end
    local toolbarEdit = T.Button(status, L_EDIT_MODE_OFF, 152, 24)
    toolbarEdit:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", -24, 12)
    T.CenterButtonLabel(toolbarEdit)
    toolbarEdit:SetScript("OnClick", RunToolbarEditMode)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(toolbarEdit, "toolbar.edit-mode", "Edit Mode", "action", {
            actionKey = "assistant.action.editMode.toggle",
            historyMode = "none", help = "Toggles MSUF Edit Mode.",
        })
    end
    M.dashboardToolbarEditModeButton = toolbarEdit
    local toolbarFeatures = T.Button(status, "See New Features", 132, 24)
    toolbarFeatures:SetPoint("RIGHT", toolbarEdit, "LEFT", -12, 0)
    T.CenterButtonLabel(toolbarFeatures)
    toolbarFeatures:SetScript("OnClick", RunToolbarSeeNewFeatures)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(toolbarFeatures, "toolbar.see-new-features", "See New Features", "ephemeral", {
            historyMode = "none", help = "Opens the full changelog with direct links to highlighted features.",
        })
    end
    local toolbarReset = T.Button(status, "Reset page", 88, 24)
    toolbarReset:SetPoint("RIGHT", toolbarFeatures, "LEFT", -12, 0)
    T.CenterButtonLabel(toolbarReset)
    if T.SkinDangerButton then T.SkinDangerButton(toolbarReset) end
    if M.AddTooltip then
        M.AddTooltip(toolbarReset, "Reset page", function()
            local key = M.activeKey
            local route = key and type(M.GetMenuBreadcrumb) == "function" and M.GetMenuBreadcrumb(key) or ""
            if route == "" then return nil end
            return M.Format("Resets all settings on %s to their defaults. Asks for confirmation first.", route)
        end, { hook = true })
    end
    toolbarReset:SetScript("OnClick", function()
        local key = M.activeKey
        if key and M.ShowPageResetConfirm and M.PageHasReset and M.PageHasReset(key) then
            M.ShowPageResetConfirm(key)
        end
    end)
    if M.RegisterMenuChromeControl then
        M.RegisterMenuChromeControl(toolbarReset, "toolbar.reset-page", "Reset current page", "action", {
            actionKey = "menu_reset_current_page_prompt",
            confirmRequired = true, historyMode = "none",
            command = { kind = "button", historyMode = "none", confirmRequired = true, set = function()
                local key = M.activeKey
                return key and M.PageHasReset and M.PageHasReset(key) and M.ResetPageToDefaults
                    and M.ResetPageToDefaults(key) or false
            end },
        })
    end
    local function RefreshToolbarPageReset()
        local key = M.activeKey
        local shown = key and M.PageHasReset and M.PageHasReset(key)
        toolbarReset:SetShown(shown and true or false)
        if toolbarReset.SetEnabled then toolbarReset:SetEnabled(shown and true or false) end
    end
    M.RefreshToolbarPageReset = RefreshToolbarPageReset
    RefreshToolbarPageReset()
    status.seeNewFeaturesButton = toolbarFeatures
    status.resetPageButton = toolbarReset
    status.editModeButton = toolbarEdit
    function M.ShowStatusFeedback(text, kind, seconds)
        if not (f and f.status and f.status.feedbackText and text and text ~= "") then return end
        local feedback = f.status.feedbackText
        local colorKey = FEEDBACK_COLOR_KEYS[kind]
        local color = colorKey and T.colors[colorKey] or T.colors.muted
        f.status._msuf2FeedbackSerial = (f.status._msuf2FeedbackSerial or 0) + 1
        local serial = f.status._msuf2FeedbackSerial
        feedback:SetText(M.Tr(tostring(text)))
        if feedback.SetTextColor then feedback:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
        feedback:SetAlpha(1)
        if T.PlayMotion then T.PlayMotion(feedback, "controlFocusIn", { fromAlpha = 0.25, toAlpha = 1, duration = 0.10 }) end
        local delay = tonumber(seconds) or 1.4
        C_Timer.After(delay, function()
            if not (f and f.status and f.status.feedbackText) then return end
            if f.status._msuf2FeedbackSerial ~= serial then return end
            if T.PlayMotion then
                T.PlayMotion(feedback, "controlFocusOut", {
                    fromAlpha = feedback.GetAlpha and feedback:GetAlpha() or 1,
                    toAlpha = 0,
                    duration = 0.16,
                    onFinished = function()
                        if f.status and f.status._msuf2FeedbackSerial == serial then feedback:SetText("") end
                    end,
                })
            else
                feedback:SetAlpha(0)
                feedback:SetText("")
            end
        end)
    end
    M.ShowInlineFeedback = M.ShowStatusFeedback
end

local function InstallWindowStatusRuntime(state)
    local f, status = state.frame, state.frame.status
    local sbProfile, sbEdit = status.profileText, status.editText
    local sbCombat, sbVersion = status.combatText, status.versionText
    local RefreshToolbarPageReset = M.RefreshToolbarPageReset
    function f:RefreshStatus()
        local profile = tostring(_G.MSUF_ActiveProfile or "Default")
        local profileText = "|cff4a90d9" .. L_PROFILE .. "|r |cffccd8e8" .. profile .. "|r  |cff3a4a66\194\183|r"
        SetCachedText(status, "_msuf2ProfileText", sbProfile, profileText)
        local editText = IsEditModeActive()
            and ("|cff4ade80" .. L_EDIT_ON .. "|r  |cff3a4a66\194\183|r")
            or ("|cff5a6a88" .. L_EDIT_OFF .. "|r  |cff3a4a66\194\183|r")
        SetCachedText(status, "_msuf2EditText", sbEdit, editText)
        local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
        local combatText = inCombat and ("|cffef4444" .. L_IN_COMBAT .. "|r")
            or ("|cff22c55e" .. L_OUT_OF_COMBAT .. "|r")
        SetCachedText(status, "_msuf2CombatText", sbCombat, combatText)
        local version = GetAddonVersion()
        local versionText = type(version) == "string" and version ~= ""
            and (version:match("^%d") and ("v" .. version) or version) or "v5.0 Beta 1"
        SetCachedText(status, "_msuf2VersionText", sbVersion, versionText)
        RefreshDashboardEditModeButton()
        RefreshToolbarPageReset()
    end
    local STATUS_EVENTS = {
        "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED", "UPDATE_BINDINGS",
    }
    local function SetStatusEventsRegistered(registered)
        if (status._msuf2EventsRegistered == true) == (registered == true) then return end
        status._msuf2EventsRegistered = registered and true or nil
        local method = registered and status.RegisterEvent or status.UnregisterEvent
        for i = 1, #STATUS_EVENTS do method(status, STATUS_EVENTS[i]) end
    end
    status:SetScript("OnEvent", function(_, event)
        if not (f and f:IsShown()) then
            SetStatusEventsRegistered(false)
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            M.CallIf(M.BlockCombatAction)
            M.HideSlashMenuAndMinibar(f)
            return
        elseif event == "PLAYER_REGEN_ENABLED" and M.activeKey == "search" then
            RefreshSearchResultsPage()
        end
        f:RefreshStatus()
        M.RequestOrRefresh(nil, event or "menu-status-event")
        RequestBossPagePreviewForKey(M.activeKey)
        RequestGroupPagePreviewForKey(M.activeKey)
    end)
    state.SetStatusEventsRegistered = SetStatusEventsRegistered
end

local function InstallWindowLifecycle(state)
    local f = state.frame
    local SetStatusEventsRegistered = state.SetStatusEventsRegistered
    f:SetScript("OnShow", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then
            self:Hide()
            return
        end
        if type(MenuRuntime.Resume) == "function" then MenuRuntime:Resume("menu-show") end
        self._msuf2Closing = nil
        if self.SetAlpha then self:SetAlpha(1) end
        ApplyMenuFramePriority(self)
        M.CallIf(M.RefreshWindowControls, self)
        self._msuf2Minimized = nil
        if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
        M.CallIf(M.StartHistorySession, "menu")
        SetStatusEventsRegistered(true)
        EnsureEditModeUIHook()
        if self.RefreshStatus then self:RefreshStatus() end
        if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
        local activeEntry = M.activeKey and M.cache and M.cache[M.activeKey]
        M.CallIf(M.SetActivePageHeader, activeEntry)
        if activeEntry then QueueVisiblePageLayoutSettle(M.activeKey, activeEntry) end
        M.CallIf(M.RefreshGuidedTourChrome, "WINDOW_SHOW")
        M.CallIf(M.ResumePinnedPreviews, "WINDOW_SHOW")
        M.CallIf(M.ResumeClassPowerPreview, "WINDOW_SHOW", M.activeKey)
        M.CallIf(M.ResumeGFNativePreviews, "WINDOW_SHOW", M.activeKey)
        -- Reopening the window is a page-show for the docked previews too: the
        -- window frame is visible here, so their ownership gates pass again.
        M.CallIf(M.RunStickyHeaderActivation)
        if activeEntry and type(M.ShouldExpandFixedPreview) == "function" and M.ShouldExpandFixedPreview() then
            fixedPreviewRestoreSerial = fixedPreviewRestoreSerial + 1
            RestoreExpandedFixedPreview(M.activeKey, activeEntry, fixedPreviewRestoreSerial, {
                reason = "WINDOW_SHOW_DEFAULT_EXPANDED",
            })
        end
        RequestBossPagePreviewForKey(M.activeKey)
        RequestGroupPagePreviewForKey(M.activeKey)
        M.CallIf(M.UpdateMenuCombatListener)
    end)
    f:SetScript("OnHide", function()
        M.CallIf(M.ClearPendingFixedPreviewExpansion)
        M.CallIf(M.SetActivePageHeader, nil)
        M.CallIf(M.HideLayerOverview)
        if M.StopWindowLayoutAnimation then M.StopWindowLayoutAnimation(f) end
        if f._msuf2CancelWindowInteractions then
            f:_msuf2CancelWindowInteractions()
        end
        if f._msuf2Closing then
            f._msuf2WindowState = "normal"
            f._msuf2RestoreLayout = nil
            f._msuf2PreMinimizeLayout = nil
            f._msuf2Minimized = nil
        end
        SetStatusEventsRegistered(false)
        -- The dropdown and its focus veil are UIParent-owned modal surfaces.
        -- They must be torn down synchronously when their menu owner disappears;
        -- an animated close can otherwise outlive the hidden window and veil the
        -- cached page when it is shown again.
        if W and type(W.CloseDropdown) == "function" then W.CloseDropdown({ immediate = true }) end
        M.CallIf(M.HideNavSearchPalette)
        M.CallIf(M.HideMenuPreviewPopups)
        M.CallIf(M.HideMenuCopyLinkPopup)
        if W and type(W.CloseMenuOwnedColorPicker) == "function" then W.CloseMenuOwnedColorPicker() end
        if type(M.ResetFocusVeil) == "function" then M.ResetFocusVeil(nil, { force = true }) end
        M.CallIf(M.EndHistorySession, "menu")
        ResetStatusIndicatorTestModeOnMenuExit()
        SavePersistentMenuState()
        ResetBossPagePreviewCache()
        M.CallIf(M.SuspendPinnedPreviews, "WINDOW_HIDE")
        M.CallIf(M.ReleaseGFNativePreviews, "WINDOW_HIDE", nil)
        -- Force: ResetBossPagePreviewCache just cleared lastCastbarPagePreviewUnit,
        -- so the castbar-page fake cast would dedupe against nil and never be
        -- stopped when the window closes straight from the castbar page.
        SyncBossPagePreviewForKey(nil, true)
        RequestGroupPagePreviewForKey(nil)
        M.CallIf(M.UpdateMenuCombatListener)
        if type(MenuRuntime.Quiesce) == "function" then
            local reason = M.IsConfigCombatLocked and M.IsConfigCombatLocked() and "combat" or "menu-hide"
            MenuRuntime:Quiesce(reason)
        end
        f._msuf2Closing = nil
    end)
end

local function ForwardMenuScrollWheel(delta)
    if not delta or delta == 0 then return false end
    local scroll = M.scrollFrame
    if not scroll then return false end
    local scrollBy = scroll._msuf2ScrollByWheel
    if type(scrollBy) == "function" then
        scrollBy(delta)
        return true
    end
    local handler = scroll.GetScript and scroll:GetScript("OnMouseWheel")
    if type(handler) ~= "function" then return false end
    handler(scroll, delta)
    return true
end
M.ForwardMenuScrollWheel = ForwardMenuScrollWheel

local function BuildWindowScrollHost(state)
    local f = state.frame
    local host, status = f.host, f.status
    local pageHeaderHost = CreateFrame("Frame", nil, host)
    pageHeaderHost:SetHeight(0)
    pageHeaderHost:Hide()
    -- Structural only: the page panel already owns its rounded glass surface,
    -- so the host paints no background of its own. Clipping is normally off
    -- (it cuts the panels' overscanned nine-slice corners) and turns on only
    -- while the stack overflows a too-short window - see LayoutPageHeaderHost.
    f.pageHeaderHost = pageHeaderHost
    M.pageHeaderHost = pageHeaderHost
    local scroll = CreateFrame("ScrollFrame", nil, host)
    f.scrollFrame = scroll
    M.scrollFrame = scroll
    local activeTopOwner, activeLayoutHost = status, host
    local function RefreshPinnedHeaderGeometry()
        if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        M.CallIf(M.RefreshPinnedPreviews, scroll)
    end
    --- Compact fixed chrome keeps a useful settings viewport. An explicitly
    --- expanded preview behaves like an accordion and may consume nearly all
    --- of it: the ScrollFrame still begins below the complete preview instead
    --- of letting the preview overlay or clip against the settings body.
    local STICKY_HEADER_MIN_BODY_REVEAL = 120
    local STICKY_HEADER_EXPANDED_BODY_REVEAL = 16
    local function ReadFrameCoordinate(frame, getter)
        if not (frame and type(frame[getter]) == "function") then return nil end
        local value = frame[getter](frame)
        local canaccessvalue = _G.canaccessvalue
        if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return nil end
        local issecretvalue = _G.issecretvalue
        if type(issecretvalue) == "function" and issecretvalue(value) == true then return nil end
        return tonumber(value)
    end
    local function HeaderAvailableHeight(topOwner, layoutHost)
        topOwner = topOwner or activeTopOwner or status
        layoutHost = layoutHost or activeLayoutHost or host
        local ownerBottom = ReadFrameCoordinate(topOwner, "GetBottom")
        local hostBottom = ReadFrameCoordinate(layoutHost, "GetBottom")
        if ownerBottom and hostBottom and ownerBottom > hostBottom then return ownerBottom - hostBottom end
        -- Construction-test and first-layout fallback. Guided chrome is
        -- anchored below status, while the normal top owner is status itself.
        local available = (tonumber(layoutHost and layoutHost.GetHeight and layoutHost:GetHeight()) or 0)
            - (tonumber(topOwner and topOwner.GetHeight and topOwner:GetHeight()) or 0)
        if topOwner ~= status then
            available = available - (tonumber(status and status.GetHeight and status:GetHeight()) or 0)
        end
        return max(0, available)
    end
    function M.GetPageHeaderAvailableHeight()
        return HeaderAvailableHeight(activeTopOwner, activeLayoutHost)
    end
    local function StickyHeaderStackHeight(topOwner, layoutHost)
        local list = scroll._msuf2StickyPageHeaders
        if type(list) ~= "table" or #list == 0 then return 0 end
        local total = 0
        for i = 1, #list do
            local record = list[i]
            if record and record.active then total = total + max(0, tonumber(record.hostHeight) or 0) end
        end
        if total <= 0 then return 0 end
        local available = HeaderAvailableHeight(topOwner, layoutHost)
        local minimumReveal = STICKY_HEADER_MIN_BODY_REVEAL
        for i = 1, #list do
            local record = list[i]
            if record and record.active and record.previewExpander
                and record.previewExpander.expanded == true
            then
                minimumReveal = STICKY_HEADER_EXPANDED_BODY_REVEAL
                break
            end
        end
        local limit = available - minimumReveal
        if limit > 0 and total > limit then return limit, true end
        return total, false
    end
    local function LayoutPageHeaderHost(topOwner, layoutHost)
        if topOwner then activeTopOwner = topOwner end
        if layoutHost then activeLayoutHost = layoutHost end
        topOwner = activeTopOwner or status
        layoutHost = activeLayoutHost or host
        pageHeaderHost:ClearAllPoints()
        pageHeaderHost:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)
        -- The fixed panel keeps the PageBuilder width (content - 32) with
        -- equal 12 px side insets.  The ScrollFrame remains 16 px narrower
        -- on the right to reserve its scrollbar gutter.
        pageHeaderHost:SetPoint("TOPRIGHT", topOwner, "BOTTOMRIGHT", -8, 0)
        scroll:ClearAllPoints()
        local stackHeight, clipped = StickyHeaderStackHeight(topOwner, layoutHost)
        if stackHeight > 0 then
            pageHeaderHost:SetHeight(stackHeight)
            -- On a window too short for the full stack, clip its overflow rather
            -- than painting over the settings body or outside the window.
            if pageHeaderHost.SetClipsChildren then pageHeaderHost:SetClipsChildren(clipped and true or false) end
            pageHeaderHost:Show()
            scroll:SetPoint("TOPLEFT", pageHeaderHost, "BOTTOMLEFT", 0, 0)
        else
            pageHeaderHost:SetHeight(0)
            pageHeaderHost:Hide()
            -- Plain pages bypass the optional slot completely. A hidden
            -- zero-height intermediary previously left several menus blank
            -- until a later layout pass repaired their mixed anchors.
            scroll:SetPoint("TOPLEFT", topOwner, "BOTTOMLEFT", 0, 0)
        end
        scroll:SetPoint("BOTTOMRIGHT", layoutHost, "BOTTOMRIGHT", -24, 0)
        scroll._msuf2TourAnchorOwner = topOwner
        scroll._msuf2TourAnchorHost = layoutHost
        scroll._msuf2MaxScroll = nil
        scroll._msuf2SmoothScrollTarget = nil
    end
    M.LayoutPageHeaderHost = LayoutPageHeaderHost
    --- Geometry only. Content wake-up runs separately (RunStickyHeaderActivation)
    --- once the page wrapper is shown, because a docked panel's page-visibility
    --- gates would reject any work started while the wrapper is still hidden.
    local function ActivateStickyHeaderStack(entry)
        local records = type(entry) == "table" and entry.pageHeaders or nil
        local active = {}
        if type(records) ~= "table" then return active end
        local stackOffset = 0
        for i = 1, #records do
            local record = records[i]
            if record and not record.disposed and record.entry == entry and record.Activate then
                if record:Activate(pageHeaderHost, stackOffset) then
                    stackOffset = stackOffset + max(0, tonumber(record.hostHeight) or 0)
                    active[#active + 1] = record
                end
            end
        end
        return active
    end
    --- The post-show half of page selection for docked panels. They live outside
    --- the page wrapper, so wrapper:Show() cannot reach them; SelectPage calls
    --- this after the wrapper is visible so every page-ownership gate inside the
    --- callbacks (activeKey, wrapper shown) evaluates against the final state.
    function M.RunStickyHeaderActivation()
        local list = scroll._msuf2StickyPageHeaders
        if type(list) ~= "table" then return 0 end
        local ran = 0
        for i = 1, #list do
            local record = list[i]
            if record and record.active and not record.disposed and type(record.onActivate) == "function" then
                record.onActivate(record)
                ran = ran + 1
            end
        end
        M.CallIf(M.ResolvePendingFixedPreviewExpansion, M.frame)
        return ran
    end
    function M.SetActivePageHeader(entry)
        local previous = scroll._msuf2StickyPageHeaders
        if type(previous) == "table" then
            for i = 1, #previous do
                local record = previous[i]
                if record and record.Deactivate and (type(entry) ~= "table" or record.entry ~= entry) then
                    record:Deactivate()
                end
            end
        end
        scroll._msuf2StickyPageHeaders = ActivateStickyHeaderStack(entry)
        -- Retained for the single-panel readers that predate the stack.
        scroll._msuf2StickyPageHeader = scroll._msuf2StickyPageHeaders[1]
        if not M._msuf2DeferPageHeaderLayout then
            LayoutPageHeaderHost()
            RefreshPinnedHeaderGeometry()
        end
        return scroll._msuf2StickyPageHeader ~= nil
    end
    --- Re-drive the slot after a docked panel changed its own height, without
    --- re-parenting anything: only the stack offsets and the host height move.
    function M.RelayoutPageHeaderHost()
        local list = scroll._msuf2StickyPageHeaders
        if type(list) ~= "table" or #list == 0 then return false end
        local stackOffset = 0
        for i = 1, #list do
            local record = list[i]
            if record and record.active and not record.disposed and record.Activate then
                record:Activate(pageHeaderHost, stackOffset)
                stackOffset = stackOffset + max(0, tonumber(record.hostHeight) or 0)
            end
        end
        LayoutPageHeaderHost()
        RefreshPinnedHeaderGeometry()
        return true
    end
    function M.DisposePageHeader(entry)
        local records = type(entry) == "table" and entry.pageHeaders or nil
        if type(records) ~= "table" or #records == 0 then return end
        local active = scroll._msuf2StickyPageHeaders
        if type(active) == "table" then
            for i = 1, #active do
                if active[i] and active[i].entry == entry then
                    M.SetActivePageHeader(nil)
                    break
                end
            end
        end
        for i = #records, 1, -1 do
            local record = records[i]
            if record and record.Dispose then record:Dispose() end
        end
    end
    LayoutPageHeaderHost(status, host)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W - 12, CONTENT_H)
    scroll:SetScrollChild(child)
    M.scrollChild = child
    M.CallIf(T.StyleScrollFrame, scroll, host)
    pageHeaderHost:EnableMouseWheel(true)
    if pageHeaderHost.SetPropagateMouseWheel then pageHeaderHost:SetPropagateMouseWheel(false) end
    pageHeaderHost:SetScript("OnMouseWheel", function(_, delta)
        ForwardMenuScrollWheel(delta)
    end)
    M.CallIf(M.InstallGuidedTourChrome, f, status, host, scroll)
end

-- An explicit Expand must produce a real full canvas even when the user is at
-- the compact minimum window height. Grow only by the measured shortfall; the
-- ensuing normal layout rebuild captures/restores the expanded state.
function M.EnsureFixedPreviewExpansionRoom(expander)
    local frame = M.frame
    if not (frame and expander and type(expander.GetPreferredExpansionShortfall) == "function")
        or frame._msuf2GrowingForFixedPreview
    then
        return false
    end
    local animation = frame._msuf2WindowLayoutAnim
    if animation then
        -- The animation owns raw geometry until its normal completion rebuild.
        -- Keep only a page-keyed intent so replacement animations inherit it;
        -- the settled resolver always obtains the current renderer from cache.
        local key = expander.pageKey or M.activeKey
        if not key then return false end
        fixedPreviewExpandIntentSerial = fixedPreviewExpandIntentSerial + 1
        frame._msuf2PendingFixedPreviewExpand = {
            serial = fixedPreviewExpandIntentSerial,
            pageKey = key,
        }
        return true
    end
    local shortfall = tonumber(expander:GetPreferredExpansionShortfall()) or 0
    if shortfall <= 0.5 then return false end
    local layout = CaptureFrameLayout(frame)
    if not layout then return false end
    local _, maxH = WindowMaxBounds()
    local currentH = tonumber(layout.h) or tonumber(frame.GetHeight and frame:GetHeight()) or WINDOW_H
    local targetH = min(maxH, math.ceil(currentH + shortfall))
    if targetH <= currentH + 0.5 then return false end
    layout.h = targetH
    frame._msuf2GrowingForFixedPreview = true
    local applied = ApplyWindowLayout(frame, layout, true, { source = "preview-expand" })
    frame._msuf2GrowingForFixedPreview = nil
    return applied == true
end

local function BuildWindow()
    if M.frame then return M.frame end
    M.CallIf(T.ApplyMenuAccent)
    local state = BuildWindowShell()
    InstallWindowInteractions(state)
    BuildWindowChrome(state)
    BuildWindowToolbar(state)
    InstallWindowStatusRuntime(state)
    InstallWindowLifecycle(state)
    BuildWindowScrollHost(state)
    local f = state.frame
    M.frame = f
    return f
end
ApplyMenuFrameScale = function(frame)
    if not (frame and frame.SetScale) then return end
    local g = M.GetGeneralDB()
    local previousW = frame.GetWidth and frame:GetWidth() or WINDOW_W
    local previousH = frame.GetHeight and frame:GetHeight() or WINDOW_H
    frame:SetScale(EffectiveMenuScale(g.slashMenuScale))
    ApplyWindowResizeBounds(frame)
    ClampWindowSize(frame)
    local currentW = frame.GetWidth and frame:GetWidth() or WINDOW_W
    local currentH = frame.GetHeight and frame:GetHeight() or WINDOW_H
    if (math.abs(currentW - previousW) >= 1 or math.abs(currentH - previousH) >= 1)
        and RebuildActivePageForResize
    then
        -- Scaling can reduce the screen-safe local window bounds. Rebuild once
        -- so cached responsive pages use the new content width immediately.
        RebuildActivePageForResize(frame, { source = "menu-scale" })
    end
    if type(frame.RefreshMenuScaleControl) == "function" then frame:RefreshMenuScaleControl() end
end
M.AssignNamedValues(M, [[
    UpdateNav RunEntryRefreshers RefreshDashboardEditModeButton BuildPageEntry
    GetEffectiveMenuScale ApplyMenuFrameScale HideSlashMenuAndMinibar ALIASES
]], UpdateNav, RunRefreshers, RefreshDashboardEditModeButton, BuildPageEntry,
    EffectiveMenuScale, ApplyMenuFrameScale, HideSlashMenuAndMinibar, ALIASES)
function M.MinimizeSlashMenuWindow(frame)
    return MinimizeSlashMenuWindow(frame or M.frame)
end
function M.MaximizeSlashMenuWindow(frame)
    return MaximizeSlashMenuWindow(frame or M.frame)
end
function M.RestoreSlashMenuWindow(frame)
    return RestoreSlashMenuWindow(frame or M.frame)
end
function M.RestoreMinimizedSlashMenu(frame)
    return RestoreMinimizedSlashMenu(frame or M.frame)
end
function M.Open(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    EnsurePersistentMenuState()
    M.CallIf(M.ApplyLocaleSelection)
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    f._msuf2Minimized = nil
    ApplyMenuFrameScale(f)
    ApplyMenuFramePriority(f)
    -- Cached pages can outlive external model changes while the window is
    -- hidden, including specialization-driven profile switches. Advance the
    -- shared snapshot revision once per explicit open so SelectPage refreshes
    -- the visible page from the current MSUF_DB instead of reusing stale UI.
    M.MarkMenuDataDirty("menu-open")
    f:Show()
    -- An unqualified open resumes an active guided setup before considering the
    -- one-time welcome. Explicit deep links always keep their requested page.
    if pageKey == nil then
        local guided = MSUF and MSUF.GuidedTour6
        if guided and type(guided.IsActive) == "function" and guided:IsActive() then
            local current = type(M.GetGuidedTourCurrentPage) == "function" and M.GetGuidedTourCurrentPage() or nil
            pageKey = current or "guided_setup"
        else
            local firstLoad = MSUF and MSUF.FirstLoad6
            if firstLoad and type(firstLoad.ShouldShowDashboard) == "function" and firstLoad:ShouldShowDashboard() then
                pageKey = "home"
            end
        end
    end
    M.SelectPage(pageKey or M.sessionLastPage or "home")
    return true
end
function M.Toggle(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then
        HideSlashMenuAndMinibar(M.frame)
        return false
    end
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.IsShown and M.minimizedBar:IsShown() then
        M.Open(pageKey or M.activeKey)
        return
    end
    if f:IsShown() and (not pageKey or pageKey == M.activeKey) then
        HideSlashMenuAndMinibar(f)
    else
        M.Open(pageKey)
    end
    return true
end
function M.InvalidatePage(key)
    if key then
        M.RememberFixedPreviewExpansionForRebuild(key)
        if key ~= "search" then MarkSearchIndexDirty() end
        M.CallIf(M.ReleasePinnedPreviews, "INVALIDATE_PAGE", nil, key)
        M.CallIf(M.ReleaseGFNativePreviews, "INVALIDATE_PAGE", nil)
        ClearSearchRegistryPage(key)
        if key == "home" then M.dashboardEditModeButton = nil end
        local entries, seen = {}, {}
        local entry = M.cache[key]
        if entry then entries[#entries + 1] = entry; seen[entry] = true end
        local variants = M._msuf2PageLayoutVariants[key]
        if type(variants) == "table" then
            for _, variant in pairs(variants) do
                if variant and not seen[variant] then
                    entries[#entries + 1] = variant
                    seen[variant] = true
                end
            end
        end
        for i = 1, #entries do
            local invalidated = entries[i]
            invalidated._msuf2Invalidated = true
            M.CallIf(M.DisposePageHeader, invalidated)
            if invalidated.wrapper then
                invalidated.wrapper:Hide()
                invalidated.wrapper:SetParent(nil)
            end
        end
        M.cache[key] = nil
        M._msuf2PageLayoutVariants[key] = nil
    else
        MarkSearchIndexDirty()
        local keys = {}
        for k in pairs(M.cache) do keys[k] = true end
        for k in pairs(M._msuf2PageLayoutVariants) do keys[k] = true end
        for k in pairs(keys) do M.InvalidatePage(k) end
    end
end
