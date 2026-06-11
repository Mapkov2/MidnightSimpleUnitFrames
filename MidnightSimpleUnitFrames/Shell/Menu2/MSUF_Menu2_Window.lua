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

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

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
    if type(locale) == "table" and locale[key] ~= nil then
        return locale[key]
    end
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
if type(MSUF.RegisterLocaleCallback) == "function" then
    MSUF.RegisterLocaleCallback("MSUF_Menu2_Window", RefreshLocaleCache)
end

local T = M.Theme
local W = M.Widgets

M.pages = M.pages or {}
M.pageOrder = M.pageOrder or {}
M.cache = M.cache or {}
M._msuf2LayoutVersion = M._msuf2LayoutVersion or 0

local floor = math.floor
local max = math.max
local min = math.min
local IsEditModeActive

local PREVIEW_WARNING_LINES = {
    "|cffff5555MSUF 6.0 Preview Warning:|r This is an alpha/preview build for World of Warcraft 12.1.",
    "|cffffd700MSUF:|r MSUF 6.0 release is planned for 10.08.2026.",
    "|cffffd700MSUF:|r Blizzard rewrote the aura system in 12.1. Buffs, debuffs, and aura tracking currently do not work in MSUF.",
    "|cffffd700MSUF:|r Use this build only for preview/testing if you can play without MSUF aura display and aura configuration.",
}
local previewWarningShown = {}

local function GetAddonVersion()
    local getMeta = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
    if type(getMeta) == "function" then
        return getMeta(addonName or "MidnightSimpleUnitFrames", "Version")
    end
    if type(_G.GetAddOnMetadata) == "function" then
        return _G.GetAddOnMetadata(addonName or "MidnightSimpleUnitFrames", "Version")
    end
    return nil
end

local function IsMSUF60PreviewBuild()
    local ver = GetAddonVersion()
    if type(ver) ~= "string" or not ver:match("^6%.0") then return false end
    local lower = ver:lower()
    return lower:find("alpha", 1, true)
        or lower:find("preview", 1, true)
        or lower:find("pre", 1, true)
        or lower:find("beta", 1, true)
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

M.ShowPreviewWarning = ShowPreviewWarning

do
    local loginWarningFrame = CreateFrame("Frame")
    loginWarningFrame:RegisterEvent("PLAYER_LOGIN")
    loginWarningFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if _G.C_Timer and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(2, function() ShowPreviewWarning("login") end)
        else
            ShowPreviewWarning("login")
        end
    end)
end

local ApplyMenuFramePriority = M.ApplyMenuFramePriority
local ApplyMenuResizeProxyPriority = M.ApplyMenuResizeProxyPriority
local RefreshMenuFramePriority = M.RefreshMenuFramePriority
local EnsurePersistentMenuState = M.EnsurePersistentMenuState
local SavePersistentMenuState = M.SavePersistentMenuState
local SyncBossPagePreviewForKey = M.SyncBossPagePreviewForKey
local SyncGroupPagePreviewForKey = M.SyncGFPagePreviewForKey
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

local DEFAULT_WINDOW_W, DEFAULT_WINDOW_H = 900, 700
local MIN_WINDOW_W, MIN_WINDOW_H = 620, 430
local MAX_WINDOW_W, MAX_WINDOW_H = 1600, 1100
local WINDOW_W, WINDOW_H = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
local NAV_W = 174
local CONTENT_W = WINDOW_W - NAV_W - 24
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
    CONTENT_W = math.max(420, WINDOW_W - NAV_W - 24)
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

local function CursorPositionInUIParent()
    local parent = _G.UIParent
    if not (parent and parent.GetEffectiveScale and _G.GetCursorPosition) then return nil, nil end
    local scale = parent:GetEffectiveScale() or 1
    if scale == 0 then scale = 1 end
    local x, y = _G.GetCursorPosition()
    return (x or 0) / scale, (y or 0) / scale
end

local function CaptureWindowLayout(frame)
    if not (frame and frame.GetLeft and frame.GetTop and frame.GetWidth and frame.GetHeight) then return nil end
    return {
        x = frame:GetLeft() or SNAP_SCREEN_MARGIN,
        yTop = frame:GetTop() or (((_G.UIParent and _G.UIParent.GetHeight and _G.UIParent:GetHeight()) or DEFAULT_WINDOW_H) - SNAP_SCREEN_MARGIN),
        w = frame:GetWidth() or WINDOW_W,
        h = frame:GetHeight() or WINDOW_H,
    }
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
    local restored = layout and ApplyWindowLayout(frame, layout, true)
    if not restored then
        ClampWindowSize(frame)
        if RebuildActivePageForResize then RebuildActivePageForResize(frame) end
    end
    if RefreshWindowControls then RefreshWindowControls(frame) end
    return true
end

local function MaximizeSlashMenuWindow(frame)
    if not frame then return false end
    if frame._msuf2WindowState == "maximized" then
        return RestoreSlashMenuWindow(frame)
    end

    frame._msuf2RestoreLayout = CaptureWindowLayout(frame)
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

    ApplyWindowLayout(frame, { x = x, yTop = yTop, w = localW, h = localH }, true)
    if RefreshWindowControls then RefreshWindowControls(frame) end
    return true
end

local function RestoreMinimizedSlashMenu(frame)
    if not frame then frame = M.frame end
    if not frame then return false end
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    frame._msuf2Minimized = nil
    ApplyMenuFramePriority(frame)
    frame:Show()
    if RefreshWindowControls then RefreshWindowControls(frame) end
    return true
end

local function HideSlashMenuAndMinibar(frame)
    frame = frame or M.frame
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    if frame and frame.Hide then frame:Hide() end
end

local function MinimizeSlashMenuWindow(frame)
    if not frame then return false end
    if not M.minimizedBar then return false end
    frame._msuf2Minimized = true
    if M.minimizedBar.title and frame.title and frame.title.GetText then
        M.minimizedBar.title:SetText(frame.title:GetText() or "MSUF Menu")
    end
    ApplyMenuFramePriority(M.minimizedBar)
    M.minimizedBar:Show()
    frame:Hide()
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

    if frame._msuf2WindowState == "maximized" then
        frame._msuf2WindowState = "normal"
        frame._msuf2RestoreLayout = nil
    end

    ApplyWindowLayout(frame, layout, true)
    if RefreshWindowControls then RefreshWindowControls(frame) end
    return true
end

local function ApplyScrollMetrics()
    if not M.scrollChild then return end
    local height = CONTENT_H
    local entry = M.activeKey and M.cache and M.cache[M.activeKey]
    if entry and tonumber(entry.height) then height = math.max(height, entry.height) end
    M.scrollChild:SetSize(CONTENT_W - 10, height)
    if entry and entry.wrapper then entry.wrapper:SetSize(CONTENT_W - 10, height) end
    if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then
        M.scrollFrame:_msuf2RefreshScrollBar()
    end
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
    if not M.pages[key] then
        M.pageOrder[#M.pageOrder + 1] = key
    end
    M.pages[key] = spec
end

local function HideAllCachedPages()
    if M.ReleasePinnedPreviews then M.ReleasePinnedPreviews("HIDE_ALL_PAGES", nil) end
    if M.ReleaseGFNativePreviews then M.ReleaseGFNativePreviews("HIDE_ALL_PAGES", nil) end
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
    local localeKey = CurrentMenuLocaleKey()
    local labelsDirty = M._msuf2NavLocaleKey ~= localeKey
    M._msuf2NavLocaleKey = localeKey
    local previousKey = M._msuf2NavActiveKey
    if labelsDirty then
        for pageKey, btn in pairs(M.navButtons) do
            if btn._msuf2RawLabel and btn.SetText then
                btn:SetText(M.Tr(btn._msuf2RawLabel))
            end
            if btn.SetActive then btn:SetActive(pageKey == key) end
        end
    elseif previousKey ~= key then
        local previous = previousKey and M.navButtons[previousKey]
        if previous and previous.SetActive then previous:SetActive(false) end
        local current = key and M.navButtons[key]
        if current and current.SetActive then current:SetActive(true) end
    end
    M._msuf2NavActiveKey = key
    if labelsDirty and M.navHeaders then
        for _, btn in pairs(M.navHeaders) do
            if btn._msuf2RawLabel and btn.SetText then
                btn:SetText(string.upper(M.Tr(btn._msuf2RawLabel)))
            end
        end
    end
    if labelsDirty and M.nav and M.nav.searchBox then
        UpdateSearchPlaceholder(M.nav.searchBox)
    end
end
M.UpdateNav = UpdateNav

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
    if opts.force ~= true and entry._msuf2RefreshRevision == revision then
        return false
    end
    for i = 1, #entry.refreshers do
        local fn = entry.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
    entry._msuf2RefreshRevision = revision
    return true
end
M.RunEntryRefreshers = RunRefreshers

IsEditModeActive = M.IsMSUFEditModeActive

local IsEditModeCombatLocked = M.IsEditModeCombatLocked

local function RefreshDashboardEditModeButton()
    local btn = M.dashboardEditModeButton
    if not btn then return end

    local active = IsEditModeActive()
    local combatLocked = IsEditModeCombatLocked() and true or false
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
M.RefreshDashboardEditModeButton = RefreshDashboardEditModeButton

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
            if M.RequestRefresh then M.RequestRefresh(nil, "edit-mode-ui") elseif M.Refresh then M.Refresh() end
            SyncGroupPagePreviewForKey(M.activeKey)
        else
            RefreshDashboardEditModeButton()
        end
    end)
    editModeUIHooked = true
end

local function CreateContext(key, wrapper, entry)
    local ctx = {
        key = key,
        wrapper = wrapper,
        entry = entry,
        refreshers = entry.refreshers,
        width = CONTENT_W - 34,
    }
    function ctx:SetContentHeight(height)
        height = math.max(CONTENT_H, tonumber(height) or CONTENT_H)
        entry.height = height
        if wrapper.SetHeight then wrapper:SetHeight(height) end
        if not entry.hiddenBuild and M.scrollChild and M.scrollChild.SetHeight then M.scrollChild:SetHeight(height) end
    end
    function ctx:AddRefresher(fn)
        M.AddRefresher(ctx, fn)
    end
    return ctx
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
    if cached then return cached end

    ClearSearchRegistryPage(key)

    local wrapper = CreateFrame("Frame", nil, M.scrollChild)
    wrapper:SetPoint("TOPLEFT", M.scrollChild, "TOPLEFT", 0, 0)
    wrapper:SetSize(CONTENT_W - 10, CONTENT_H)
    if hidden and wrapper.Hide then wrapper:Hide() end

    local entry = { wrapper = wrapper, refreshers = {}, height = CONTENT_H, version = specVersion, layoutVersion = layoutVersion, hiddenBuild = hidden and true or false }
    M.cache[key] = entry

    local ctx = CreateContext(key, wrapper, entry)
    local prevBuildKey = M._msuf2SearchBuildKey
    M._msuf2SearchBuildKey = key
    if spec and type(spec.build) == "function" then
        local ok, result = pcall(spec.build, ctx)
        if ok and tonumber(result) then
            ctx:SetContentHeight(result)
        elseif not ok then
            entry.buildError = tostring(result or "unknown error")
        end
    else
        BuildPlaceholderPage(ctx, key)
    end
    M._msuf2SearchBuildKey = prevBuildKey

    if hidden and wrapper.Hide then wrapper:Hide() end
    return entry
end
M.BuildPageEntry = BuildPageEntry

local function StopPagePrewarm() end

local StartPagePrewarm = StopPagePrewarm

M.StartPagePrewarm = StartPagePrewarm
M.StopPagePrewarm = StopPagePrewarm

local PAGE_HISTORY_LIMIT = 30
local suppressPageHistory

local function ClearTable(tbl)
    if type(tbl) ~= "table" then return end
    for key in pairs(tbl) do tbl[key] = nil end
end

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

local function RecordPageNavigation(fromKey, toKey)
    fromKey = NormalizePageKey(fromKey)
    toKey = NormalizePageKey(toKey)
    if not fromKey or not toKey or fromKey == toKey then return end
    M.pageBackStack = PushPageHistory(M.pageBackStack, fromKey)
    M.pageForwardStack = type(M.pageForwardStack) == "table" and M.pageForwardStack or {}
    ClearTable(M.pageForwardStack)
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
    local back = type(M.pageBackStack) == "table" and M.pageBackStack or {}
    local forward = type(M.pageForwardStack) == "table" and M.pageForwardStack or {}
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
    M.pageBackStack = type(M.pageBackStack) == "table" and M.pageBackStack or {}
    local page = table.remove(M.pageBackStack)
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
    M.pageForwardStack = type(M.pageForwardStack) == "table" and M.pageForwardStack or {}
    local page = table.remove(M.pageForwardStack)
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
    if key == "search" then StopPagePrewarm() end
    local hasPendingFocus = false
    do
        local req = _G.MSUF_EM2_MenuFocusRequest
        hasPendingFocus = type(req) == "table"
            and req.explicit == true
            and req.consumed ~= true
            and (not req.pageKey or tostring(req.pageKey) == tostring(key))
        if not hasPendingFocus and type(M.CloseAutoFocusedSections) == "function" then
            M.CloseAutoFocusedSections(key)
        end
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
        if M.ReleasePinnedPreviews then M.ReleasePinnedPreviews("SELECT_CACHED", key) end
        if M.ReleaseGFNativePreviews then M.ReleaseGFNativePreviews("SELECT_CACHED", key) end
        RunRefreshers(cached)
        SyncBossPagePreviewForKey(key)
        SyncGroupPagePreviewForKey(key)
        if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
        if key ~= "search" then StartPagePrewarm("select-cached") end
        return true
    end

    local previousKey = M.activeKey
    local previous = previousKey and M.cache and M.cache[previousKey]
    if M.ReleasePinnedPreviews then M.ReleasePinnedPreviews("SELECT_PAGE", key) end
    if M.ReleaseGFNativePreviews then M.ReleaseGFNativePreviews("SELECT_PAGE", key) end
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
    if key ~= "search" then M.PersistMenuStateValue("lastPage", key) end
    if M.frame then M.frame._msufCurrentKey = key end
    if M.scrollChild then
        M.scrollChild:SetHeight(entry.height or CONTENT_H)
    end
    if M.scrollFrame then
        if M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(0)
        elseif M.scrollFrame._msuf2RefreshScrollBar then
            M.scrollFrame:_msuf2RefreshScrollBar()
        end
    end
    entry.wrapper:Show()
    RunRefreshers(entry)
    SetTitle(key)
    UpdateNav(key)
    SyncBossPagePreviewForKey(key)
    SyncGroupPagePreviewForKey(key)
    if hasPendingFocus and type(M.FocusRequestedSection) == "function" then M.FocusRequestedSection(key, { flash = true }) end
    if key ~= "search" then StartPagePrewarm("select") end
    return true
end

local function CreateMinimizedBar(frame)
    if M.minimizedBar then return M.minimizedBar end
    local bar = T.Panel(UIParent, "MSUF2_MinimizedWindow", T.colors.glassShell or T.colors.bg, T.colors.border)
    if T.ApplyMaterial then T.ApplyMaterial(bar, "shell") elseif T.ApplyGlass then T.ApplyGlass(bar, "shell") end
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

    local close = T.CloseButton(bar)
    close:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    close:SetScript("OnClick", function()
        bar:Hide()
        if frame then frame._msuf2Minimized = nil end
    end)
    bar.closeButton = close

    M.minimizedBar = bar
    return bar
end

local function BuildWindow()
    if M.frame then return M.frame end

    EnsurePersistentMenuState()
    SetWindowMetrics(ReadSavedWindowSize())
    local f = T.Panel(UIParent, "MSUF2_Window", T.colors.glassShell or T.colors.bg, T.colors.border)
    if T.ApplyMaterial then T.ApplyMaterial(f, "shell") elseif T.ApplyGlass then T.ApplyGlass(f, "shell") end
    _G.MSUF_StandaloneOptionsWindow = f
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER", UIParent, "CENTER", -60, 10)
    ApplyMenuFramePriority(f)
    f:EnableMouse(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    ApplyWindowResizeBounds(f)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if self._msuf2BeginWindowDrag then
            self:_msuf2BeginWindowDrag()
            return
        end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        if self._msuf2FinishWindowDrag then
            self:_msuf2FinishWindowDrag(true)
            return
        end
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        ApplySlashMenuSnap(self)
    end)
    f:SetScript("OnSizeChanged", function(self)
        if self._msuf2LiveResizing then
            self._msuf2ResizeMetricsDirty = true
            return
        end
        RefreshWindowMetrics(self)
        ApplyScrollMetrics()
    end)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "MSUF2_Window")
    end

    local title = T.Font(f, "GameFontDisableSmall", "MSUF", T.colors.accent)
    title:SetPoint("TOPLEFT", 12, -6)
    title:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -6)
    title:SetJustifyH("LEFT")
    title:SetAlpha(0.50)
    f.title = title

    local subtitle = T.Font(f, "GameFontDisableSmall", "", T.colors.muted)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -14)
    subtitle:SetJustifyH("RIGHT")
    subtitle:Hide()
    f.subtitle = subtitle

    local close = T.CloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() HideSlashMenuAndMinibar(f) end)
    f.closeButton = close

    local maximize = CreateWindowControlButton(f, "maximize", "Maximize", "Maximize or restore the MSUF menu window.")
    maximize:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, 0)
    maximize:SetScript("OnClick", function() MaximizeSlashMenuWindow(f) end)
    f.maximizeButton = maximize

    local minimize = CreateWindowControlButton(f, "minimize", "Minimize", "Collapse the MSUF menu to a small taskbar-style bar.")
    minimize:SetPoint("TOPRIGHT", maximize, "TOPLEFT", -2, 0)
    minimize:SetScript("OnClick", function() MinimizeSlashMenuWindow(f) end)
    f.minimizeButton = minimize

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
        proxy:ClearAllPoints()
        proxy:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", layout.x or SNAP_SCREEN_MARGIN, layout.yTop or DEFAULT_WINDOW_H)
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
            if RefreshWindowControls then RefreshWindowControls(f) end
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

        ShowWindowLayoutProxy({ x = state.layout.x, yTop = state.layout.yTop, w = w, h = h, scale = scale })
    end

    local function BeginResizeProxy(button)
        if button ~= "LeftButton" then return false end
        local cursorX, cursorY = CursorPositionInUIParent()
        local layout = CaptureWindowLayout(f)
        if not (cursorX and layout) then return false end
        f._msuf2LiveResizing = true
        f._msuf2ResizeMetricsDirty = nil
        f._msuf2WindowState = "normal"
        f._msuf2RestoreLayout = nil
        if RefreshWindowControls then RefreshWindowControls(f) end
        f._msuf2ResizeState = {
            cursorX = cursorX,
            cursorY = cursorY,
            startW = layout.w or WINDOW_W,
            startH = layout.h or WINDOW_H,
            layout = layout,
            scale = WindowVisualScale(f),
        }
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
        if apply and changed then
            ApplyWindowLayout(f, { x = state.layout.x, yTop = state.layout.yTop, w = w, h = h }, true)
        end
        f._msuf2LiveResizing = nil
        f._msuf2FinishingResize = nil
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
    RefreshWindowControls(f)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    f.content = content

    local nav = T.Panel(content, nil, T.colors.glassRail or T.colors.panelNav or T.colors.panel, T.colors.borderSoft)
    if T.ApplyMaterial then T.ApplyMaterial(nav, "rail") elseif T.ApplyGlass then T.ApplyGlass(nav, "rail") end
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    f.nav = nav
    f._msufNavRail = nav
    f._msufNavStack = nav
    M.nav = nav
    BuildNav(nav)

    local host = T.Panel(content, nil, T.colors.glassHost or T.colors.panel, T.colors.borderSoft)
    if T.ApplyMaterial then T.ApplyMaterial(host, "host") elseif T.ApplyGlass then T.ApplyGlass(host, "host") end
    host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    f.host = host
    f._msufMirrorHost = host
    if T.ApplyMenuAtmosphere then T.ApplyMenuAtmosphere(f, host, nav) end

    local status = T.Panel(host, nil, T.colors.glassStatus or T.colors.header, T.colors.borderSoft)
    if T.ApplyMaterial then T.ApplyMaterial(status, "status") elseif T.ApplyGlass then T.ApplyGlass(status, "status") end
    status:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    status:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    status:SetHeight(22)
    local statusTopLine = status:CreateTexture(nil, "ARTWORK", nil, 6)
    statusTopLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    statusTopLine:SetHeight(1)
    statusTopLine:SetPoint("TOPLEFT", status, "TOPLEFT", 0, 0)
    statusTopLine:SetPoint("TOPRIGHT", status, "TOPRIGHT", 0, 0)
    statusTopLine:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.25)

    local sbProfile = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbProfile:SetPoint("LEFT", status, "LEFT", 10, 0)
    sbProfile:SetJustifyH("LEFT")
    local sbEdit = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbEdit:SetPoint("LEFT", sbProfile, "RIGHT", 14, 0)
    sbEdit:SetJustifyH("LEFT")
    local sbCombat = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbCombat:SetPoint("LEFT", sbEdit, "RIGHT", 14, 0)
    sbCombat:SetJustifyH("LEFT")
    local sbVersion = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbVersion:SetPoint("RIGHT", status, "RIGHT", -10, 0)
    sbVersion:SetJustifyH("RIGHT")
    sbVersion:SetAlpha(0.50)
    local sbFeedback = T.Font(status, "GameFontDisableSmall", "", T.colors.muted)
    sbFeedback:SetPoint("RIGHT", sbVersion, "LEFT", -18, 0)
    sbFeedback:SetPoint("LEFT", sbCombat, "RIGHT", 16, 0)
    sbFeedback:SetJustifyH("RIGHT")
    sbFeedback:SetAlpha(0)

    status.profileText = sbProfile
    status.editText = sbEdit
    status.combatText = sbCombat
    status.versionText = sbVersion
    status.feedbackText = sbFeedback
    status.text = sbProfile
    f.status = status
    function M.ShowStatusFeedback(text, kind, seconds)
        if not (f and f.status and f.status.feedbackText and text and text ~= "") then return end
        local feedback = f.status.feedbackText
        local color = T.colors.muted
        if kind == "ok" or kind == "success" then
            color = T.colors.ok or color
        elseif kind == "warning" or kind == "combat" then
            color = T.colors.accent2 or color
        elseif kind == "danger" or kind == "error" then
            color = T.colors.danger or color
        elseif kind == "info" then
            color = T.colors.accent or color
        end
        f.status._msuf2FeedbackSerial = (f.status._msuf2FeedbackSerial or 0) + 1
        local serial = f.status._msuf2FeedbackSerial
        feedback:SetText(M.Tr(tostring(text)))
        if feedback.SetTextColor then feedback:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
        feedback:SetAlpha(1)
        if T.PlayMotion then T.PlayMotion(feedback, "controlFocusIn", { fromAlpha = 0.25, toAlpha = 1, duration = 0.10 }) end
        local delay = tonumber(seconds) or 1.4
        if C_Timer and C_Timer.After then
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
    end
    M.ShowInlineFeedback = M.ShowStatusFeedback
    function f:RefreshStatus()
        local profile = tostring(_G.MSUF_ActiveProfile or "Default")
        local edit = IsEditModeActive() and "On" or "Off"
        local profileText = "|cff4a90d9" .. L_PROFILE .. "|r |cffccd8e8" .. profile .. "|r  |cff3a4a66\194\183|r"
        if status._msuf2ProfileText ~= profileText then
            status._msuf2ProfileText = profileText
            sbProfile:SetText(profileText)
        end
        local editText
        if edit == "On" then
            editText = "|cff4ade80" .. L_EDIT_ON .. "|r  |cff3a4a66\194\183|r"
        else
            editText = "|cff5a6a88" .. L_EDIT_OFF .. "|r  |cff3a4a66\194\183|r"
        end
        if status._msuf2EditText ~= editText then
            status._msuf2EditText = editText
            sbEdit:SetText(editText)
        end
        local combatText
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            combatText = "|cffef4444" .. L_IN_COMBAT .. "|r"
        else
            combatText = "|cff22c55e" .. L_OUT_OF_COMBAT .. "|r"
        end
        if status._msuf2CombatText ~= combatText then
            status._msuf2CombatText = combatText
            sbCombat:SetText(combatText)
        end
        local ver = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
        local versionText
        if type(ver) == "string" and ver ~= "" then
            versionText = ver:match("^%d") and ("v" .. ver) or ver
        else
            versionText = "v5.0 Beta 1"
        end
        if status._msuf2VersionText ~= versionText then
            status._msuf2VersionText = versionText
            sbVersion:SetText(versionText)
        end
        RefreshDashboardEditModeButton()
    end
    local function RegisterStatusEvents()
        if status._msuf2EventsRegistered then return end
        status._msuf2EventsRegistered = true
        status:RegisterEvent("PLAYER_REGEN_DISABLED")
        status:RegisterEvent("PLAYER_REGEN_ENABLED")
        status:RegisterEvent("GROUP_ROSTER_UPDATE")
        status:RegisterEvent("PLAYER_ENTERING_WORLD")
        status:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    end
    local function UnregisterStatusEvents()
        if not status._msuf2EventsRegistered then return end
        status._msuf2EventsRegistered = nil
        status:UnregisterEvent("PLAYER_REGEN_DISABLED")
        status:UnregisterEvent("PLAYER_REGEN_ENABLED")
        status:UnregisterEvent("GROUP_ROSTER_UPDATE")
        status:UnregisterEvent("PLAYER_ENTERING_WORLD")
        status:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED")
    end
    status:SetScript("OnEvent", function(_, event)
        if not (f and f:IsShown()) then
            UnregisterStatusEvents()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            CancelSearchBackgroundIndex()
            if M.BlockCombatAction then M.BlockCombatAction() end
            HideSlashMenuAndMinibar(f)
            return
        elseif event == "PLAYER_REGEN_ENABLED" and M.activeKey == "search" then
            RefreshSearchResultsPage()
        end
        f:RefreshStatus()
        if M.RequestRefresh then M.RequestRefresh(nil, event or "menu-status-event") elseif M.Refresh then M.Refresh() end
        SyncGroupPagePreviewForKey(M.activeKey)
    end)
    f:SetScript("OnShow", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then
            self:Hide()
            return
        end
        ShowPreviewWarning("menu")
        ApplyMenuFramePriority(self)
        self._msuf2Minimized = nil
        if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
        if M.StartHistorySession then M.StartHistorySession() end
        RegisterStatusEvents()
        EnsureEditModeUIHook()
        if self.RefreshStatus then self:RefreshStatus() end
        if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then M.scrollFrame:_msuf2RefreshScrollBar() end
        SyncBossPagePreviewForKey(M.activeKey)
        SyncGroupPagePreviewForKey(M.activeKey)
    end)
    f:SetScript("OnHide", function()
        if f._msuf2FinishWindowDrag then f:_msuf2FinishWindowDrag(false) end
        if FinishResizeProxy then FinishResizeProxy(false) end
        StopPagePrewarm()
        CancelSearchBackgroundIndex()
        UnregisterStatusEvents()
        if W and type(W.CloseDropdown) == "function" then W.CloseDropdown() end
        if M.EndHistorySession then M.EndHistorySession() end
        ResetStatusIndicatorTestModeOnMenuExit()
        SavePersistentMenuState()
        ResetBossPagePreviewCache()
        if M.ReleasePinnedPreviews then M.ReleasePinnedPreviews("WINDOW_HIDE", nil) end
        if M.ReleaseGFNativePreviews then M.ReleaseGFNativePreviews("WINDOW_HIDE", nil) end
        SyncBossPagePreviewForKey(nil)
        SyncGroupPagePreviewForKey(nil)
    end)

    local scroll = CreateFrame("ScrollFrame", nil, host)
    scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -22, 0)
    f.scrollFrame = scroll
    M.scrollFrame = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W - 10, CONTENT_H)
    scroll:SetScrollChild(child)
    M.scrollChild = child
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, host) end

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

M.GetEffectiveMenuScale = EffectiveMenuScale
M.ApplyMenuFrameScale = ApplyMenuFrameScale
M.HideSlashMenuAndMinibar = HideSlashMenuAndMinibar
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
M.ALIASES = ALIASES

function M.Open(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    EnsurePersistentMenuState()
    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    f._msuf2Minimized = nil
    ApplyMenuFrameScale(f)
    ApplyMenuFramePriority(f)
    f:Show()
    M.SelectPage(pageKey or "home")
    return true
end

function M.Toggle(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then
        HideSlashMenuAndMinibar(M.frame)
        return false
    end
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.IsShown and M.minimizedBar:IsShown() then
        M.Open(pageKey or M.activeKey or "home")
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
        if M.ReleasePinnedPreviews then M.ReleasePinnedPreviews("INVALIDATE_PAGE", nil, key) end
        if M.ReleaseGFNativePreviews then M.ReleaseGFNativePreviews("INVALIDATE_PAGE", nil) end
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
