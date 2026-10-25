--- Menu2/MSUF_Menu2_Window.lua
--- Options window geometry, chrome, visibility and sizing/minimize state.
---
--- Owns: the slash-menu window frame, nav rail host and sizing/minimize behavior.
--- PageLifecycle owns page registration, construction, cache and restoration.
--- Navigation data, nav rail build,
--- persisted UI state, search bridge, page preview sync, and frame priority
--- helpers live in adjacent Menu2 modules.
--- Must not own runtime unitframe/groupframe gameplay logic.
local _, MSUF = ...
local ExportPublic = MSUF.ExportPublic
local M = MSUF.MSUF2
-- Load-time dependency handoff; runtime callbacks retain their original local bindings.
local Parts = {}
M.WindowParts = Parts
local FILE = "Shell/Menu2/MSUF_Menu2_Window.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local C_Timer = M.MenuTimer
local MenuRuntime = M.MenuRuntime
local IS_FOREVER = MSUF.Client.IsForever == true

-- Forever's Gamepad style drives this window with MSUF's own pad navigation
-- (Game/Forever/PadNavigation.lua). Blizzard's frame controls manager is never
-- called: registering an addon window there leaves the gamepad input state
-- tainted, and SmartNavigation rescans the window on every child CreateFrame.
local function ForeverPadUI()
    if not IS_FOREVER then return false end
    local input = InputUtil
    return input and type(input.IsGamepadUIEnabled) == "function" and input.IsGamepadUIEnabled() == true
end

local function RaiseForeverPadCursor()
    if not IS_FOREVER or ForeverPadUI() then return end
    if type(CanAutoSetGamePadCursorControl) == "function"
        and type(SetGamePadCursorControl) == "function"
        and CanAutoSetGamePadCursorControl(true)
    then
        SetGamePadCursorControl(true)
    end
end
local L = {}
local function RefreshLocaleCache()
    L.editOn = M.Tr("Edit: On")
    L.editOff = M.Tr("Edit: Off")
    L.editModeOn = M.Tr("Edit Mode: On")
    L.editModeOff = M.Tr("Edit Mode: Off")
    L.editModeOffCombat = M.Tr("Edit Mode: Off (Combat)")
    L.inCombat = M.Tr("In Combat")
    L.outOfCombat = M.Tr("Out of Combat")
end
RefreshLocaleCache()
if type(MSUF.RegisterLocaleCallback) == "function" then MSUF.RegisterLocaleCallback("MSUF_Menu2_Window", RefreshLocaleCache) end
local T = M.Theme
local W = M.Widgets
-- Deliberately transient: reloads and new logins start from the Dashboard.
M.sessionLastPage = nil
M._msuf2LayoutVersion = M._msuf2LayoutVersion or 0
local floor = math.floor
local max = math.max
local min = math.min
local IsEditModeActive
local RebuildActivePageForResize
--- One shared accessor, MSUF.GetAddonVersion from Game/Shared/Initialize.lua:
--- the core resolves it once from the TOC this client loaded, so the Options
--- package never reports its own "## Version" here.
local function GetAddonVersion()
    local getVersion = MSUF.GetAddonVersion
    return type(getVersion) == "function" and getVersion() or nil
end
-- The status line shows composed text that is translated already.
local function SetCachedText(owner, cacheKey, region, text)
    if owner[cacheKey] == text then return end
    T.SetTranslatedText(region, text)
    owner[cacheKey] = text
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
local RequestBossPagePreviewForKey = M.RequestBossPagePreviewForKey
local RequestGroupPagePreviewForKey = M.RequestGFPagePreviewForKey
local ResetBossPagePreviewCache = M.ResetBossPagePreviewCache
local ResetStatusIndicatorTestModeOnMenuExit = M.ResetStatusIndicatorTestModeOnMenuExit
local SearchBridge = M.SearchBridge
local RefreshSearchResultsPage = SearchBridge.RefreshSearchResultsPage
local BuildNav = M.BuildNavRail
local CreateWindowControlButton = M.CreateWindowControlButton
local RefreshWindowControls = M.RefreshWindowControls
-- Menu2 is a visual editor, not a compact settings popup. The wider default
-- keeps navigation, scope tabs, previews, and paired controls readable at the
-- same time while retaining resize support for smaller displays.
local ApplyScrollMetrics = M.ApplyScrollMetrics
local QueueVisiblePageLayoutSettle = M.QueueVisiblePageLayoutSettle
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
    local parent = UIParent
    if parent and parent.GetWidth and parent.GetHeight then
        local scale = 1
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" then scale = EffectiveMenuScale(g.slashMenuScale) end
        maxW = min(maxW, floor(((parent:GetWidth() or maxW) / scale) - 32))
        maxH = min(maxH, floor(((parent:GetHeight() or maxH) / scale) - 32))
    end
    return max(MIN_WINDOW_W, maxW), max(MIN_WINDOW_H, maxH)
end
-- A width/height pair clamped to the screen-safe window bounds.
local function ClampWindowDims(width, height)
    local maxW, maxH = WindowMaxBounds()
    return ClampNumber(width, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W),
        ClampNumber(height, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
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
    WINDOW_W, WINDOW_H = ClampWindowDims(width, height)
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
    local savedW = tonumber(g.msuf2WindowW)
    local savedH = tonumber(g.msuf2WindowH)
    -- Upgrade only the former exact default. Deliberately customized window
    -- sizes remain untouched.
    if (savedW == nil and savedH == nil) or (savedW == 1180 and savedH == 720) then
        savedW, savedH = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
    end
    return ClampWindowDims(savedW, savedH)
end
local function SaveWindowSize(frame)
    RefreshWindowMetrics(frame)
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return end
    g.msuf2WindowW = WINDOW_W
    g.msuf2WindowH = WINDOW_H
end
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
    local parent = UIParent
    if not (frame and frame.GetEffectiveScale and parent and parent.GetEffectiveScale) then return 1 end
    local uiScale = parent:GetEffectiveScale() or 1
    if uiScale == 0 then uiScale = 1 end
    return (frame:GetEffectiveScale() or uiScale) / uiScale
end
local function FrameRectToUIParent(frame)
    local parent = UIParent
    if not (frame and parent and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local scale = WindowVisualScale(frame)
    if scale <= 0 then scale = 1 end
    return l * scale, r * scale, t * scale, b * scale
end
local function CursorPositionInUIParent()
    local parent = UIParent
    if not (parent and parent.GetEffectiveScale and GetCursorPosition) then return nil, nil end
    local scale = parent:GetEffectiveScale() or 1
    if scale == 0 then scale = 1 end
    local x, y = GetCursorPosition()
    return (x or 0) / scale, (y or 0) / scale
end
local function CaptureFrameLayout(frame, fallbackW, fallbackH)
    if not (frame and frame.GetLeft and frame.GetTop and frame.GetWidth and frame.GetHeight) then return nil end
    return {
        x = frame:GetLeft() or SNAP_SCREEN_MARGIN,
        yTop = frame:GetTop() or (((UIParent and UIParent.GetHeight and UIParent:GetHeight()) or DEFAULT_WINDOW_H) - SNAP_SCREEN_MARGIN),
        w = frame:GetWidth() or fallbackW or WINDOW_W,
        h = frame:GetHeight() or fallbackH or WINDOW_H,
    }
end
local function ApplyRawFrameLayout(frame, layout)
    if not (frame and layout and UIParent) then return false end
    frame:ClearAllPoints()
    frame:SetSize(max(1, layout.w or WINDOW_W), max(1, layout.h or WINDOW_H))
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", layout.x or SNAP_SCREEN_MARGIN, layout.yTop or DEFAULT_WINDOW_H)
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
-- Commits a settled (or skipped) layout morph: final geometry and alpha, the
-- caller's hook, then any page-keyed Full Preview intent.
local function CommitWindowLayout(frame, target, toAlpha, onFinished)
    if target then ApplyRawFrameLayout(frame, target) end
    if toAlpha and frame.SetAlpha then frame:SetAlpha(toAlpha) end
    if type(onFinished) == "function" then onFinished(frame) end
    M.ResolvePendingFixedPreviewExpansion(frame)
end
local function SettleWindowLayoutAnimation(frame)
    local state = frame and frame._msuf2WindowLayoutAnim
    if not state then return false end
    local target, toAlpha, onFinished = state.target, state.toAlpha, state.onFinished
    StopWindowLayoutAnimation(frame)
    CommitWindowLayout(frame, target, toAlpha, onFinished)
    return true
end
-- hot path: kept whole (perf rule)
local function AnimateWindowLayout(frame, target, opts)
    if not (frame and target) then return false end
    opts = opts or {}
    StopWindowLayoutAnimation(frame)
    local start = opts.start or CaptureFrameLayout(frame)
    if not start then return false end
    if opts.applyStart then ApplyRawFrameLayout(frame, start) end
    local duration = tonumber(opts.duration) or WINDOW_RESTORE_ANIM_SECONDS
    if WindowMotionReduced() or duration <= 0.001 then
        CommitWindowLayout(frame, target, opts.toAlpha, opts.onFinished)
        return true
    end
    local driver = frame._msuf2WindowLayoutDriver
    if not driver then
        driver = PixelLayoutRegion(CreateFrame("Frame", nil, UIParent or frame))
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
            M.ResolvePendingFixedPreviewExpansion(frame)
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
    if not (frame and layout and UIParent) then return false end
    local maxW, maxH = WindowMaxBounds()
    local w = ClampNumber(layout.w, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    local h = ClampNumber(layout.h, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    frame:ClearAllPoints()
    frame:SetSize(w, h)
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", layout.x or SNAP_SCREEN_MARGIN, layout.yTop or DEFAULT_WINDOW_H)
    ApplyWindowResizeBounds(frame)
    if rebuild and RebuildActivePageForResize then
        RebuildActivePageForResize(frame, rebuildOptions)
    else
        SaveWindowSize(frame)
    end
    return true
end
-- Back to the plain "normal" state with no saved restore geometry; `closing`
-- also forgets the minimize bookkeeping.
local function ResetWindowState(frame, closing)
    frame._msuf2WindowState = "normal"
    frame._msuf2RestoreLayout = nil
    if closing then
        frame._msuf2PreMinimizeLayout = nil
        frame._msuf2Minimized = nil
    end
end
local function RestoreSlashMenuWindow(frame)
    if not frame then return false end
    local layout = frame._msuf2RestoreLayout
    ResetWindowState(frame)
    local restored = false
    if layout then
        RefreshWindowControls(frame)
        restored = AnimateWindowLayout(frame, layout, {
            duration = WINDOW_RESTORE_ANIM_SECONDS,
            suspendPagePreviews = true,
            onFinished = function()
                ApplyWindowLayout(frame, layout, true)
                RefreshWindowControls(frame)
            end,
        })
    end
    if not restored then
        ClampWindowSize(frame)
        if RebuildActivePageForResize then RebuildActivePageForResize(frame) end
        RefreshWindowControls(frame)
    end
    return true
end
local function MaximizeSlashMenuWindow(frame)
    if not frame then return false end
    if frame._msuf2WindowState == "maximized" then return RestoreSlashMenuWindow(frame) end
    frame._msuf2RestoreLayout = CaptureFrameLayout(frame)
    frame._msuf2WindowState = "maximized"
    local parent = UIParent
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
    local target = { x = x / scale, yTop = yTop / scale, uiLeft = x, uiTop = yTop, w = localW, h = localH }
    RefreshWindowControls(frame)
    AnimateWindowLayout(frame, target, {
        duration = WINDOW_MAXIMIZE_ANIM_SECONDS,
        suspendPagePreviews = true,
        onFinished = function()
            ApplyWindowLayout(frame, target, true)
            RefreshWindowControls(frame)
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
                M.UpdateMenuCombatListener()
                RefreshWindowControls(frame)
            end,
        })
    else
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        frame._msuf2PreMinimizeLayout = nil
    end
    M.UpdateMenuCombatListener()
    RefreshWindowControls(frame)
    return true
end
local function HideSlashMenuAndMinibar(frame)
    frame = frame or M.frame
    if frame then
        frame._msuf2Closing = true
        ResetWindowState(frame, true)
    end
    StopWindowLayoutAnimation(frame)
    if frame and frame._msuf2CancelWindowInteractions then frame:_msuf2CancelWindowInteractions() end
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    if frame and frame.Hide then frame:Hide() end
    M.UpdateMenuCombatListener()
end
local function MinimizeSlashMenuWindow(frame)
    if not frame then return false end
    if not M.minimizedBar then return false end
    local start = CaptureFrameLayout(frame)
    frame._msuf2Minimized = true
    frame._msuf2PreMinimizeLayout = start
    if M.minimizedBar.title and frame.title and frame.title.GetText then T.SetTranslatedText(M.minimizedBar.title, frame.title:GetText() or "MSUF Menu") end
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
                M.UpdateMenuCombatListener()
            end,
        })
    else
        if M.minimizedBar.SetAlpha then M.minimizedBar:SetAlpha(1) end
        frame:Hide()
    end
    M.UpdateMenuCombatListener()
    return true
end
local function GetSlashMenuSnapLayout(frame)
    if not (frame and IsSlashMenuSnapEnabled()) then return false end
    local parent = UIParent
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
        x = x / scale,
        yTop = yTop / scale,
        uiLeft = x,
        uiTop = yTop,
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
    if frame._msuf2WindowState == "maximized" then ResetWindowState(frame) end
    RefreshWindowControls(frame)
    if start and AnimateWindowLayout(frame, layout, {
        start = start,
        duration = WINDOW_SNAP_ANIM_SECONDS,
        onFinished = function()
            ApplyWindowLayout(frame, layout, true)
            RefreshWindowControls(frame)
        end,
    }) then
        return true
    end
    ApplyWindowLayout(frame, layout, true)
    RefreshWindowControls(frame)
    return true
end
RebuildActivePageForResize = function(frame, options)
    options = type(options) == "table" and options or {}
    local key = M.activeKey or "home"
    local activeExpander = M._msuf2ActiveFixedPreviewExpander
    local restoreExpanded = activeExpander and activeExpander.expanded == true
        and not activeExpander.disposed
        and (not activeExpander.pageKey or activeExpander.pageKey == key)
    local autoCompactIfNoFit = restoreExpanded
        and options.allowAutoCompact == true and options.shrinking == true
    SaveWindowSize(frame)
    -- Page selection reflows the retained entry for the new metrics. Its
    -- discrete layout slot changes only when the page needs another structure.
    M._msuf2LayoutVersion = (M._msuf2LayoutVersion or 0) + 1
    M.SetActivePageHeader(nil)
    M.activeKey = nil
    local selected = M.SelectPage and frame and frame:IsShown() and M.SelectPage(key)
    if selected and restoreExpanded then
        M.RestoreFixedPreview(key, M.cache and M.cache[key], {
            autoCompactIfNoFit = autoCompactIfNoFit,
            reason = options.source == "resize-grip" and "WINDOW_RESIZE_RESTORE" or "WINDOW_LAYOUT_RESTORE",
        })
    end
    ApplyScrollMetrics()
    M.RefreshGuidedTourChrome("WINDOW_RESIZE")
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
                btn:SetText(L.editModeOn, true)
            elseif combatLocked then
                btn:SetText(L.editModeOffCombat, true)
            else
                btn:SetText(L.editModeOff, true)
            end
            if btn.SetEnabled then btn:SetEnabled(active or not combatLocked) end
            if btn.SetActive then btn:SetActive(active) end
        end
    end
    M.RefreshGuidedTourChrome("EDIT_MODE_STATUS")
end
local editModeUIHooked = false
local function EnsureEditModeUIHook()
    if editModeUIHooked then return end
    local register = MSUF.Require("MSUF_RegisterAnyEditModeListener", FILE)
    register(function()
        RefreshMenuFramePriority()
        local frame = M.frame
        if frame and frame:IsShown() then
            if frame.RefreshStatus then frame:RefreshStatus() end
            M.RequestOrRefresh(nil, "edit-mode-ui")
            M.ResumeClassPowerPreview("EDIT_MODE_UI", M.activeKey)
            RequestBossPagePreviewForKey(M.activeKey)
            RequestGroupPagePreviewForKey(M.activeKey)
        else
            RefreshDashboardEditModeButton()
        end
    end)
    editModeUIHooked = true
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
    bar.restoreButton = restore
    local close = CreateWindowControlButton(bar, "close", "Close", "Close the minimized MSUF menu.")
    close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    close:SetScript("OnClick", function()
        bar:Hide()
        if frame then frame._msuf2Minimized = nil end
        M.UpdateMenuCombatListener()
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
    if not (frame and frame.GetLeft and GetCursorPosition) then return true end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return true end
    local scale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if not scale or scale == 0 then scale = 1 end
    local x, y = GetCursorPosition()
    x, y = (x or 0) / scale, (y or 0) / scale
    if y >= top - WINDOW_DRAG_TITLE_H then return true end
    if y <= bottom + WINDOW_DRAG_EDGE_BOTTOM then return true end
    if x <= left + WINDOW_DRAG_EDGE_X or x >= right - WINDOW_DRAG_EDGE_X then return true end
    return false
end
-- hot path: kept whole (perf rule)
local function InstallWindowDragInteractions(f)
    local function EnsureResizeProxy()
        if f._msuf2ResizeProxy then return f._msuf2ResizeProxy end
        local proxy = PixelLayoutRegion(CreateFrame("Frame", nil, UIParent), true)
        ApplyMenuResizeProxyPriority(proxy, f)
        proxy:Hide()
        local fill = PixelLayoutRegion(proxy:CreateTexture(nil, "BACKGROUND"))
        fill:SetAllPoints()
        fill:SetColorTexture(T.colors.bg[1], T.colors.bg[2], T.colors.bg[3], 0.18)
        proxy.fill = fill
        local accent = T.colors.accent or { 0.22, 0.78, 0.94, 1 }
        local function Edge(pointA, pointB, width, height)
            local tex = PixelLayoutRegion(proxy:CreateTexture(nil, "BORDER"))
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
        if proxy.sizeLabel then T.SetTranslatedText(proxy.sizeLabel, string.format("%d x %d", layout.w or WINDOW_W, layout.h or WINDOW_H)) end
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
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
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
            ResetWindowState(f)
            M.RefreshWindowControls(f)
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
    return EnsureResizeProxy, ShowWindowLayoutProxy, HideWindowLayoutProxy
end
local function InstallWindowInteractions(state)
    local f = state.frame
    local EnsureResizeProxy, ShowWindowLayoutProxy, HideWindowLayoutProxy = InstallWindowDragInteractions(f)
    local FinishResizeProxy
    local function UpdateResizeProxy()
        local state = f._msuf2ResizeState
        if not state then return end
        if not f._msuf2FinishingResize and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            if FinishResizeProxy then FinishResizeProxy(true) end
            return
        end
        local cursorX, cursorY = CursorPositionInUIParent()
        if not cursorX then return end
        local scale = state.scale or 1
        if scale <= 0 then scale = 1 end
        -- Inline ClampWindowDims: this runs on every resize-drag frame.
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
        ResetWindowState(f)
        M.RefreshWindowControls(f)
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
    local grip = PixelLayoutRegion(CreateFrame("Button", nil, f))
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    PixelLayoutRegion(grip, "SetNormalTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    PixelLayoutRegion(grip, "SetHighlightTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    PixelLayoutRegion(grip, "SetPushedTexture", "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
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
    Parts.InstallMenuScaleControl(f)
    CreateMinimizedBar(f)
    M.RefreshWindowControls(f)
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
        M.QueueFixedPreviewExpansion(key)
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

local function WindowSize() return WINDOW_W, WINDOW_H end

-- Explicit load-time exports for the following responsibility modules.
Parts.ApplyMenuFramePriority = ApplyMenuFramePriority
Parts.ApplyMenuFrameScale = ApplyMenuFrameScale
Parts.ApplyScrollMetrics = ApplyScrollMetrics
Parts.ApplyWindowResizeBounds = ApplyWindowResizeBounds
Parts.BuildNav = BuildNav
Parts.CONTENT_H = CONTENT_H
Parts.CONTENT_W = CONTENT_W
Parts.C_Timer = C_Timer
Parts.EffectiveMenuScale = EffectiveMenuScale
Parts.EnsureEditModeUIHook = EnsureEditModeUIHook
Parts.EnsurePersistentMenuState = EnsurePersistentMenuState
Parts.ExportPublic = ExportPublic
Parts.FEEDBACK_COLOR_KEYS = FEEDBACK_COLOR_KEYS
Parts.FILE = FILE
Parts.GetAddonVersion = GetAddonVersion
Parts.HideSlashMenuAndMinibar = HideSlashMenuAndMinibar
Parts.IS_FOREVER = IS_FOREVER
Parts.InstallWindowInteractions = InstallWindowInteractions
Parts.IsEditModeActive = IsEditModeActive
Parts.IsEditModeCombatLocked = IsEditModeCombatLocked
Parts.MENU_SCALE_MAX_PERCENT = MENU_SCALE_MAX_PERCENT
Parts.MENU_SCALE_MIN_PERCENT = MENU_SCALE_MIN_PERCENT
Parts.MENU_SCALE_REFERENCE = MENU_SCALE_REFERENCE
Parts.MENU_SCALE_STEP_PERCENT = MENU_SCALE_STEP_PERCENT
Parts.MaximizeSlashMenuWindow = MaximizeSlashMenuWindow
Parts.MenuRuntime = MenuRuntime
Parts.MenuScalePercent = MenuScalePercent
Parts.MenuScaleValue = MenuScaleValue
Parts.MinimizeSlashMenuWindow = MinimizeSlashMenuWindow
Parts.NAV_W = NAV_W
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.QueueVisiblePageLayoutSettle = QueueVisiblePageLayoutSettle
Parts.RaiseForeverPadCursor = RaiseForeverPadCursor
Parts.ReadSavedWindowSize = ReadSavedWindowSize
Parts.RefreshDashboardEditModeButton = RefreshDashboardEditModeButton
Parts.RefreshSearchResultsPage = RefreshSearchResultsPage
Parts.RefreshWindowMetrics = RefreshWindowMetrics
Parts.RequestBossPagePreviewForKey = RequestBossPagePreviewForKey
Parts.RequestGroupPagePreviewForKey = RequestGroupPagePreviewForKey
Parts.ResetBossPagePreviewCache = ResetBossPagePreviewCache
Parts.ResetStatusIndicatorTestModeOnMenuExit = ResetStatusIndicatorTestModeOnMenuExit
Parts.ResetWindowState = ResetWindowState
Parts.RestoreMinimizedSlashMenu = RestoreMinimizedSlashMenu
Parts.RestoreSlashMenuWindow = RestoreSlashMenuWindow
Parts.SavePersistentMenuState = SavePersistentMenuState
Parts.SetCachedText = SetCachedText
Parts.SetWindowMetrics = SetWindowMetrics
Parts.SyncBossPagePreviewForKey = SyncBossPagePreviewForKey
Parts.T = T
Parts.W = W
Parts.WINDOW_FOOTER_H = WINDOW_FOOTER_H
Parts.WINDOW_H = WINDOW_H
Parts.WINDOW_W = WINDOW_W
Parts.WindowDragStartAllowed = WindowDragStartAllowed
Parts.WindowSize = WindowSize
Parts.floor = floor
Parts.max = max
Parts.min = min
Parts.L = L
