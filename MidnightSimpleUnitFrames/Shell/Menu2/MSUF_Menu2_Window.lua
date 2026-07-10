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
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
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
M.pages = M.pages or {}
M.pageOrder = M.pageOrder or {}
M.cache = M.cache or {}
-- Deliberately transient: reloads and new logins start from the Dashboard.
M.sessionLastPage = nil
M._msuf2LayoutVersion = M._msuf2LayoutVersion or 0
local floor = math.floor
local max = math.max
local min = math.min
local IsEditModeActive
local PREVIEW_WARNING_LINES = {
    "|cffff5555MSUF 6.0 Preview Warning:|r This build targets World of Warcraft 12.1 PTR APIs.",
    "|cffffd700MSUF:|r Aura display uses native 12.1 AuraContainer and AuraButton objects.",
    "|cffffd700MSUF:|r Use preview builds only for PTR testing; production builds should be versioned without alpha/beta/pre labels.",
}
local previewWarningShown = {}
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
local previewBuild
local function IsMSUF60PreviewBuild()
    if previewBuild ~= nil then return previewBuild end
    local ver = GetAddonVersion()
    if type(ver) ~= "string" or not ver:match("^6%.0") then
        previewBuild = false
        return previewBuild
    end
    local lower = ver:lower()
    previewBuild = (lower:find("alpha", 1, true)
        or lower:find("preview", 1, true)
        or lower:find("pre", 1, true)
        or lower:find("beta", 1, true)) and true or false
    return previewBuild
end
local function AddPreviewWarningLine(line)
    local chat = _G.DEFAULT_CHAT_FRAME
    if chat and type(chat.AddMessage) == "function" then
        chat:AddMessage(line)
    elseif type(_G.print) == "function" then
        _G.print(line)
    end
end
local function ShowPreviewWarning(source)
    source = source or "default"
    if previewWarningShown[source] or not IsMSUF60PreviewBuild() then return end
    previewWarningShown[source] = true
    for i = 1, #PREVIEW_WARNING_LINES do
        AddPreviewWarningLine(PREVIEW_WARNING_LINES[i])
    end
end
do
    if IsMSUF60PreviewBuild() then
        local loginWarningFrame = CreateFrame("Frame")
        loginWarningFrame:RegisterEvent("PLAYER_LOGIN")
        loginWarningFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_LOGIN")
            _G.C_Timer.After(2, function() ShowPreviewWarning("login") end)
        end)
    end
end
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
local DEFAULT_WINDOW_W, DEFAULT_WINDOW_H = 1180, 720
local MIN_WINDOW_W, MIN_WINDOW_H = 620, 430
local MAX_WINDOW_W, MAX_WINDOW_H = 1600, 1100
local WINDOW_W, WINDOW_H = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
local NAV_W = 158
local CONTENT_W = WINDOW_W - NAV_W - 34
local CONTENT_H = WINDOW_H - 74
local MENU_BASE_SCALE = 1.08
local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value) or fallback or minValue
    if value < minValue then value = minValue elseif value > maxValue then value = maxValue end
    return floor(value + 0.5)
end
local function ClampScale(value)
    value = tonumber(value) or 1
    if value < 0.25 then value = 0.25 elseif value > 1.5 then value = 1.5 end
    return value
end
local function EffectiveMenuScale(value)
    return ClampScale(ClampScale(value) * MENU_BASE_SCALE)
end
local function WindowMaxBounds()
    local maxW, maxH = MAX_WINDOW_W, MAX_WINDOW_H
    local parent = _G.UIParent
    if parent and parent.GetWidth and parent.GetHeight then
        local scale = 1
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" then scale = EffectiveMenuScale(g.slashMenuScale) end
        maxW = min(maxW, floor(((parent:GetWidth() or maxW) / scale) - 28))
        maxH = min(maxH, floor(((parent:GetHeight() or maxH) / scale) - 28))
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
    CONTENT_W = math.max(420, WINDOW_W - NAV_W - 34)
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
    return ClampNumber(g.msuf2WindowW, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W),
        ClampNumber(g.msuf2WindowH, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
end
local function SaveWindowSize(frame)
    RefreshWindowMetrics(frame)
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return end
    g.msuf2WindowW = WINDOW_W
    g.msuf2WindowH = WINDOW_H
end
local RebuildActivePageForResize
local SNAP_EDGE_PX = 24
local SNAP_FRAME_EDGE_PX = 4
local SNAP_SCREEN_MARGIN = 14
local MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H = 286, 32
local WINDOW_MAXIMIZE_ANIM_SECONDS = 0.38
local WINDOW_MINIMIZE_ANIM_SECONDS = 0.34
local WINDOW_RESTORE_ANIM_SECONDS = 0.36
local WINDOW_SNAP_ANIM_SECONDS = 0.36
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
local function StopWindowLayoutAnimation(frame)
    local state = frame and frame._msuf2WindowLayoutAnim
    if not state then return end
    state.cancelled = true
    frame._msuf2WindowLayoutAnim = nil
    if state.driver and state.driver.SetScript then state.driver:SetScript("OnUpdate", nil) end
    if state.driver and state.driver.Hide then state.driver:Hide() end
end
M.StopWindowLayoutAnimation = StopWindowLayoutAnimation
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
            if type(state.onFinished) == "function" then state.onFinished(frame) end
        end
    end)
    driver:Show()
    return true
end
local function MinimizedBarTargetLayout(frame, bar)
    local layout = CaptureFrameLayout(bar, MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H)
    if not layout then
        layout = { x = 18, yTop = 18 + MINIMIZED_WINDOW_H, w = MINIMIZED_WINDOW_W, h = MINIMIZED_WINDOW_H }
    end
    local scale = WindowVisualScale(frame)
    if scale <= 0 then scale = 1 end
    layout.w = max(1, (layout.w or MINIMIZED_WINDOW_W) / scale)
    layout.h = max(1, (layout.h or MINIMIZED_WINDOW_H) / scale)
    return layout
end
local function ApplyWindowLayout(frame, layout, rebuild)
    if not (frame and layout and _G.UIParent) then return false end
    local maxW, maxH = WindowMaxBounds()
    local w = ClampNumber(layout.w, MIN_WINDOW_W, maxW, DEFAULT_WINDOW_W)
    local h = ClampNumber(layout.h, MIN_WINDOW_H, maxH, DEFAULT_WINDOW_H)
    frame:ClearAllPoints()
    frame:SetSize(w, h)
    frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", layout.x or SNAP_SCREEN_MARGIN, layout.yTop or DEFAULT_WINDOW_H)
    ApplyWindowResizeBounds(frame)
    if rebuild and RebuildActivePageForResize then
        RebuildActivePageForResize(frame)
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
    local frameLeft = (frame.GetLeft and frame:GetLeft()) or cursorX
    local frameRight = (frame.GetRight and frame:GetRight()) or cursorX
    local frameTop = (frame.GetTop and frame:GetTop()) or cursorY
    local frameBottom = (frame.GetBottom and frame:GetBottom()) or cursorY
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
    M.scrollChild:SetSize(CONTENT_W - 10, height)
    if entry and entry.wrapper then entry.wrapper:SetSize(CONTENT_W - 10, height) end
    if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
end
function RebuildActivePageForResize(frame)
    local key = M.activeKey or "home"
    SaveWindowSize(frame)
    ApplyScrollMetrics()
    M._msuf2LayoutVersion = (M._msuf2LayoutVersion or 0) + 1
    if M.InvalidatePage then M.InvalidatePage(key) end
    M.activeKey = nil
    if M.SelectPage and frame and frame:IsShown() then M.SelectPage(key) end
end
function M.RegisterPage(key, spec)
    if type(key) ~= "string" or type(spec) ~= "table" then return end
    if not M.pages[key] then M.pageOrder[#M.pageOrder + 1] = key end
    M.pages[key] = spec
end
local function HideAllCachedPages()
    M.CallIf(M.ReleasePinnedPreviews, "HIDE_ALL_PAGES", nil)
    M.CallIf(M.ReleaseGFNativePreviews, "HIDE_ALL_PAGES", nil)
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
        if btn.SetActive then btn:SetActive(pageKey == activeNavKey) end
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
    local profiling = M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStop
    local started = profiling and M.ProfileStart() or nil
    M._msuf2MenuDataRevision = CurrentMenuDataRevision() + 1
    M._msuf2MenuDataDirtyReason = reason
    if profiling then M.ProfileStop("dirty", tostring(reason or "unknown"), started) end
    return M._msuf2MenuDataRevision
end
local function RunRefreshers(entry, opts)
    if not entry or not entry.refreshers then return end
    opts = opts or {}
    local revision = CurrentMenuDataRevision()
    if opts.force ~= true and entry._msuf2RefreshRevision == revision then return false end
    local profiling = M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStop
    local started = profiling and M.ProfileStart() or nil
    for i = 1, #entry.refreshers do
        local fnStart = profiling and M.ProfileStart() or nil
        local fn = entry.refreshers[i]
        if type(fn) == "function" then fn() end
        if profiling then M.ProfileStop("refreshFn", tostring(entry.key or "page") .. "#" .. tostring(i), fnStart) end
    end
    entry._msuf2RefreshRevision = revision
    if profiling then M.ProfileStop("refreshPage", entry.key or "page", started, #entry.refreshers) end
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
        width = CONTENT_W - 34,
        fullWidth = CONTENT_W - 34,
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
local SECONDARY_NAV_TAB_PAD_X = 14
local SECONDARY_NAV_TAB_PAD_Y = 5
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
    bar:SetSize(ctx.width or 720, 34)
    local x = SECONDARY_NAV_TAB_PAD_X
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local w = tonumber(tab.width) or 72
        local btn = SecondaryNavButton(bar, tab.label, w, key == tab.key)
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -SECONDARY_NAV_TAB_PAD_Y)
        btn:SetScript("OnClick", function() M.SelectPage(tab.key) end)
        x = x + w + 6
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
    title:SetPoint("TOPLEFT", rail, "TOPLEFT", 10, -12)
    title:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -10, -12)
    title:SetJustifyH("LEFT")
    local y = -38
    for i = 1, #group.tabs do
        local tab = group.tabs[i]
        local btn = SecondaryNavButton(rail, tab.label, SECONDARY_NAV_RAIL_W - 20, key == tab.key)
        btn._msuf2SkipHistoryCheckpoint = true
        btn:SetPoint("TOPLEFT", rail, "TOPLEFT", 10, y)
        btn:SetScript("OnClick", function() M.SelectPage(tab.key) end)
        y = y - 30
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
    W.Text(sec, "This native page is not implemented yet.", 14, -42, ctx.width - 28, T.colors.muted)
    W.Text(sec, M.Format("Requested page: %s", tostring(requestedKey or "unknown")), 14, -68, ctx.width - 28, T.colors.dim)
    ctx:SetContentHeight(210)
end
local function BuildPageEntry(key, hidden)
    if not M.scrollChild then return nil end
    key = ALIASES[key or ""] or key or "home"
    local spec = M.pages[key]
    local specVersion = spec and spec.version
    local layoutVersion = M._msuf2LayoutVersion or 0
    local cached = M.cache and M.cache[key]
    if cached and cached.layoutVersion ~= layoutVersion then
        if M.InvalidatePage then
            M.InvalidatePage(key)
        else
            if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
            if cached.wrapper and cached.wrapper.SetParent then cached.wrapper:SetParent(nil) end
            M.cache[key] = nil
        end
        cached = nil
    end
    if cached and specVersion and cached.version ~= specVersion then
        if M.InvalidatePage then
            M.InvalidatePage(key)
        else
            if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
            if cached.wrapper and cached.wrapper.SetParent then cached.wrapper:SetParent(nil) end
            M.cache[key] = nil
        end
        cached = nil
    end
    if cached and cached.hiddenBuild == true and not hidden then
        if cached.wrapper and cached.wrapper.Hide then cached.wrapper:Hide() end
        if cached.wrapper and cached.wrapper.SetParent then cached.wrapper:SetParent(nil) end
        M.cache[key] = nil
        cached = nil
    end
    if cached then return cached end
    ClearSearchRegistryPage(key)
    local wrapper = CreateFrame("Frame", nil, M.scrollChild)
    wrapper:SetPoint("TOPLEFT", M.scrollChild, "TOPLEFT", 0, 0)
    wrapper:SetSize(CONTENT_W - 10, CONTENT_H)
    if hidden and wrapper.Hide then wrapper:Hide() end
    local entry = { key = key, wrapper = wrapper, refreshers = {}, height = CONTENT_H, version = specVersion, layoutVersion = layoutVersion, hiddenBuild = hidden and true or false }
    M.cache[key] = entry
    local ctx = CreateContext(key, wrapper, entry)
    BuildSecondaryPageNav(ctx, key)
    local prevBuildKey = M._msuf2SearchBuildKey
    M._msuf2SearchBuildKey = key
    local profiling = M.PerfProfile and M.PerfProfile.enabled == true and M.ProfileStart and M.ProfileStop
    local buildStarted = profiling and M.ProfileStart() or nil
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
            for i = 1, #builders do
                local builder = builders[i]
                if builder and builder._msuf2RelayoutPending and builder.RelayoutCollapsibles then
                    builder._msuf2RelayoutPending = nil
                    builder:RelayoutCollapsibles()
                end
            end
            -- Nested builders can resize their owning collapsible while they
            -- relayout. Reflow the page-level builder once more afterwards so
            -- its final cursor, not an earlier nested height, owns the page.
            for i = 1, #builders do
                local builder = builders[i]
                if builder and builder.ctx == ctx and builder.RelayoutCollapsibles then
                    builder:RelayoutCollapsibles()
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
    if profiling then M.ProfileStop("pageBuild", tostring(key) .. (hidden and ":hidden" or ""), buildStarted) end
    M._msuf2SearchBuildKey = prevBuildKey
    if hidden and wrapper.Hide then wrapper:Hide() end
    return entry
end
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
    if not key then return end
    stack = type(stack) == "table" and stack or {}
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
        return true, "Opened previous page."
    end
    M.pageBackStack = PushPageHistory(M.pageBackStack, page)
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
        return true, "Opened next page."
    end
    M.pageForwardStack = PushPageHistory(M.pageForwardStack, page)
    return false, "Dashboard forward navigation is not available right now."
end
function M.SelectPage(key)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    EnsurePersistentMenuState()
    key = ALIASES[key or ""] or key or "home"
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
        M.CallIf(M.ReleasePinnedPreviews, "SELECT_CACHED", key)
        M.CallIf(M.ReleaseGFNativePreviews, "SELECT_CACHED", key)
        RunRefreshers(cached)
        RequestBossPagePreviewForKey(key)
        RequestGroupPagePreviewForKey(key)
        if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
        if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
        return true
    end
    local previousKey = M.activeKey
    local previous = previousKey and M.cache and M.cache[previousKey]
    M.CallIf(M.ReleasePinnedPreviews, "SELECT_PAGE", key)
    M.CallIf(M.ReleaseGFNativePreviews, "SELECT_PAGE", key)
    if previous and previous.wrapper and previous.wrapper.Hide then
        previous.wrapper:Hide()
    else
        HideAllCachedPages()
    end
    local entry = BuildPageEntry(key, false)
    if not entry then return false end
    entry.hiddenBuild = false
    M.activeKey = key
    if not suppressPageHistory then RecordPageNavigation(previousKey, key) end
    M.sessionLastPage = key
    if M.frame then M.frame._msufCurrentKey = key end
    if M.scrollChild then SetFrameHeightIfChanged(M.scrollChild, entry.height or CONTENT_H) end
    if M.scrollFrame then
        if M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(0)
        elseif M.scrollFrame._msuf2RefreshScrollBar then
            M.scrollFrame:_msuf2RefreshScrollBar()
        end
    end
    entry.wrapper:Show()
    RememberPrimaryNavPage(key)
    RunRefreshers(entry)
    SetTitle(key)
    UpdateNav(key)
    if M.RefreshToolbarPageReset then M.RefreshToolbarPageReset() end
    RequestBossPagePreviewForKey(key)
    RequestGroupPagePreviewForKey(key)
    if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
    return true
end
local function CreateMinimizedBar(frame)
    if M.minimizedBar then return M.minimizedBar end
    local bar = T.Panel(UIParent, "MSUF2_MinimizedWindow", T.colors.glassShell or T.colors.bg, T.colors.border)
    T.ApplySurface(bar, "shell")
    bar:SetSize(MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H)
    bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 18, 18)
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
    title:SetPoint("RIGHT", bar, "RIGHT", -62, 0)
    title:SetJustifyH("LEFT")
    bar.title = title
    local restore = CreateWindowControlButton(bar, "maximize", "Restore", "Restore the minimized MSUF menu.")
    restore:SetPoint("RIGHT", bar, "RIGHT", -31, 0)
    restore:SetScript("OnClick", function() RestoreMinimizedSlashMenu(frame) end)
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
    f:SetScript("OnDragStart", function(self) self:_msuf2BeginWindowDrag() end)
    f:SetScript("OnDragStop", function(self) self:_msuf2FinishWindowDrag(true) end)
    f:SetScript("OnSizeChanged", function(self)
        if self._msuf2LiveResizing then
            self._msuf2ResizeMetricsDirty = true
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
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -14)
    subtitle:SetJustifyH("RIGHT")
    subtitle:Hide()
    f.subtitle = subtitle
    local close = M.CreateWindowControlButton(f, "close", "Close", "Close the MSUF menu window.")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() M.HideSlashMenuAndMinibar(f) end)
    f.closeButton = close
    local maximize = M.CreateWindowControlButton(f, "maximize", "Maximize", "Maximize or restore the MSUF menu window.")
    maximize:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, 0)
    maximize:SetScript("OnClick", function() MaximizeSlashMenuWindow(f) end)
    f.maximizeButton = maximize
    local minimize = M.CreateWindowControlButton(f, "minimize", "Minimize", "Collapse the MSUF menu to a small taskbar-style bar.")
    minimize:SetPoint("TOPRIGHT", maximize, "TOPLEFT", -2, 0)
    minimize:SetScript("OnClick", function() MinimizeSlashMenuWindow(f) end)
    f.minimizeButton = minimize
    return { frame = f }
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
        f._msuf2DraggingWindow = nil
        f:SetScript("OnUpdate", nil)
        HideWindowLayoutProxy()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        if applySnap then ApplySlashMenuSnap(f) end
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
        if apply and changed then ApplyWindowLayout(f, { x = state.layout.x, yTop = state.layout.yTop, w = w, h = h }, true) end
        f._msuf2LiveResizing = nil
        f._msuf2FinishingResize = nil
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
    grip:SetSize(18, 18)
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
    CreateMinimizedBar(f)
    M.CallIf(M.RefreshWindowControls, f)
end

local function BuildWindowChrome(state)
    local f = state.frame
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
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
    status:SetHeight(58)
    local function StatusDivider(edge, inset, alpha)
        local line = status:CreateTexture(nil, "ARTWORK", nil, 6)
        line:SetHeight(1)
        line:SetPoint(edge .. "LEFT", status, edge .. "LEFT", inset, 0)
        line:SetPoint(edge .. "RIGHT", status, edge .. "RIGHT", -inset, 0)
        line:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], alpha)
    end
    StatusDivider("TOP", 0, 0.25)
    StatusDivider("BOTTOM", 14, 0.16)
    local function StatusText(point, relativeTo, relativePoint, x, y, justify, alpha)
        local fs = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
        fs:SetPoint(point, relativeTo, relativePoint, x, y)
        fs:SetJustifyH(justify or "LEFT")
        if alpha then fs:SetAlpha(alpha) end
        return fs
    end
    local sbProfile = StatusText("LEFT", status, "LEFT", 24, 15)
    local sbEdit = StatusText("LEFT", sbProfile, "RIGHT", 14, 0)
    local sbCombat = StatusText("LEFT", sbEdit, "RIGHT", 14, 0)
    local sbVersion = StatusText("RIGHT", status, "RIGHT", -18, 15, "RIGHT", 0.50)
    local sbFeedback = StatusText("RIGHT", sbVersion, "LEFT", -18, 15, "RIGHT", 0)
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
    local function RunToolbarNewTask()
        if type(M.SelectPage) == "function" then M.SelectPage("home") end
        if type(M.StartNewAssistantTask) == "function" then return M.StartNewAssistantTask() end
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                if type(M.StartNewAssistantTask) == "function" then M.StartNewAssistantTask() end
            end)
        end
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
    local toolbarEdit = T.Button(status, L_EDIT_MODE_OFF, 150, 24)
    toolbarEdit:SetPoint("BOTTOMRIGHT", status, "BOTTOMRIGHT", -26, 10)
    T.CenterButtonLabel(toolbarEdit)
    if T.SkinPrimaryButton then T.SkinPrimaryButton(toolbarEdit) end
    toolbarEdit:SetScript("OnClick", RunToolbarEditMode)
    M.dashboardToolbarEditModeButton = toolbarEdit
    local toolbarTask = T.Button(status, "New Task", 104, 24)
    toolbarTask:SetPoint("RIGHT", toolbarEdit, "LEFT", -12, 0)
    T.CenterButtonLabel(toolbarTask)
    toolbarTask:SetScript("OnClick", RunToolbarNewTask)
    local toolbarReset = T.Button(status, "Reset All", 88, 24)
    toolbarReset:SetPoint("RIGHT", toolbarTask, "LEFT", -12, 0)
    T.CenterButtonLabel(toolbarReset)
    if T.SkinDangerButton then T.SkinDangerButton(toolbarReset) end
    toolbarReset:SetScript("OnClick", function()
        local key = M.activeKey
        if key and M.ShowPageResetConfirm and M.PageHasReset and M.PageHasReset(key) then
            M.ShowPageResetConfirm(key)
        end
    end)
    local function RefreshToolbarPageReset()
        local key = M.activeKey
        local shown = key and M.PageHasReset and M.PageHasReset(key)
        toolbarReset:SetShown(shown and true or false)
        if toolbarReset.SetEnabled then toolbarReset:SetEnabled(shown and true or false) end
    end
    M.RefreshToolbarPageReset = RefreshToolbarPageReset
    RefreshToolbarPageReset()
    status.newTaskButton = toolbarTask
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
    local STATUS_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_DIFFICULTY_CHANGED" }
    local function SetStatusEventsRegistered(registered)
        if (status._msuf2EventsRegistered == true) == (registered == true) then return end
        status._msuf2EventsRegistered = registered and true or nil
        local method = registered and status.RegisterEvent or status.UnregisterEvent
        for i = 1, #STATUS_EVENTS do method(status, STATUS_EVENTS[i]) end
    end
    local function SetAssistantMenuRuntimeActive(active, reason)
        local assistant = (MSUF and MSUF.Assistant) or M.Assistant
        if not assistant then return false end
        if type(assistant.SetMenuRuntimeActive) == "function" then
            return assistant.SetMenuRuntimeActive(active == true, reason)
        end
        assistant._menuRuntimeActive = active == true and true or false
        assistant._menuRuntimeReason = tostring(reason or (active and "menu-show" or "menu-hide"))
        return assistant._menuRuntimeActive
    end
    status:SetScript("OnEvent", function(_, event)
        if not (f and f:IsShown()) then
            SetStatusEventsRegistered(false)
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            SetAssistantMenuRuntimeActive(false, "combat")
            CancelSearchBackgroundIndex()
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
    state.SetAssistantMenuRuntimeActive = SetAssistantMenuRuntimeActive
end

local function InstallWindowLifecycle(state)
    local f = state.frame
    local SetStatusEventsRegistered = state.SetStatusEventsRegistered
    local SetAssistantMenuRuntimeActive = state.SetAssistantMenuRuntimeActive
    f:SetScript("OnShow", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then
            self:Hide()
            return
        end
        SetAssistantMenuRuntimeActive(true, "menu-show")
        self._msuf2Closing = nil
        if self.SetAlpha then self:SetAlpha(1) end
        ShowPreviewWarning("menu")
        ApplyMenuFramePriority(self)
        M.CallIf(M.RefreshWindowControls, self)
        self._msuf2Minimized = nil
        if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
        M.CallIf(M.StartHistorySession)
        SetStatusEventsRegistered(true)
        EnsureEditModeUIHook()
        if self.RefreshStatus then self:RefreshStatus() end
        if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
        RequestBossPagePreviewForKey(M.activeKey)
        RequestGroupPagePreviewForKey(M.activeKey)
        M.CallIf(M.UpdateMenuCombatListener)
    end)
    f:SetScript("OnHide", function()
        SetAssistantMenuRuntimeActive(false, "menu-hide")
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
        CancelSearchBackgroundIndex()
        SetStatusEventsRegistered(false)
        if W and type(W.CloseDropdown) == "function" then W.CloseDropdown() end
        M.CallIf(M.EndHistorySession)
        ResetStatusIndicatorTestModeOnMenuExit()
        SavePersistentMenuState()
        ResetBossPagePreviewCache()
        M.CallIf(M.ReleasePinnedPreviews, "WINDOW_HIDE", nil)
        M.CallIf(M.ReleaseGFNativePreviews, "WINDOW_HIDE", nil)
        SyncBossPagePreviewForKey(nil)
        RequestGroupPagePreviewForKey(nil)
        M.CallIf(M.UpdateMenuCombatListener)
        f._msuf2Closing = nil
    end)
end

local function BuildWindowScrollHost(state)
    local f = state.frame
    local host, status = f.host, f.status
    local scroll = CreateFrame("ScrollFrame", nil, host)
    scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -22, 0)
    f.scrollFrame = scroll
    M.scrollFrame = scroll
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W - 10, CONTENT_H)
    scroll:SetScrollChild(child)
    M.scrollChild = child
    M.CallIf(T.StyleScrollFrame, scroll, host)
end

local function BuildWindow()
    if M.frame then return M.frame end
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
local function ApplyMenuFrameScale(frame)
    if not (frame and frame.SetScale) then return end
    local g = M.GetGeneralDB()
    frame:SetScale(EffectiveMenuScale(g.slashMenuScale))
    ApplyWindowResizeBounds(frame)
    ClampWindowSize(frame)
end
M.AssignNamedValues(M, [[
    ShowPreviewWarning UpdateNav RunEntryRefreshers RefreshDashboardEditModeButton BuildPageEntry
    GetEffectiveMenuScale ApplyMenuFrameScale HideSlashMenuAndMinibar ALIASES
]], ShowPreviewWarning, UpdateNav, RunRefreshers, RefreshDashboardEditModeButton, BuildPageEntry,
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
    f:Show()
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
        if key ~= "search" then MarkSearchIndexDirty() end
        M.CallIf(M.ReleasePinnedPreviews, "INVALIDATE_PAGE", nil, key)
        M.CallIf(M.ReleaseGFNativePreviews, "INVALIDATE_PAGE", nil)
        ClearSearchRegistryPage(key)
        if key == "home" then M.dashboardEditModeButton = nil end
        local entry = M.cache[key]
        if entry and entry.wrapper then
            entry._msuf2Invalidated = true
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        M.cache[key] = nil
    else
        MarkSearchIndexDirty()
        for k in pairs(M.cache) do M.InvalidatePage(k) end
    end
end
