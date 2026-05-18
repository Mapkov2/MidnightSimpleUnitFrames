local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

M.Tr = M.Tr or function(text)
    if text == nil then return "" end
    local key = tostring(text)
    if type(ns.Translate) == "function" then
        local translated = ns.Translate(key)
        if translated ~= nil then return translated end
    end
    if type(ns.TR) == "function" then
        local translated = ns.TR(key)
        if translated ~= nil then return translated end
    end
    local locale = ns.L or _G.MSUF_L
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
if type(ns.RegisterLocaleCallback) == "function" then
    ns.RegisterLocaleCallback("MSUF_Menu2_Core", RefreshLocaleCache)
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

local DEFAULT_WINDOW_W, DEFAULT_WINDOW_H = 900, 700
local MIN_WINDOW_W, MIN_WINDOW_H = 620, 430
local MAX_WINDOW_W, MAX_WINDOW_H = 1600, 1100
local WINDOW_W, WINDOW_H = DEFAULT_WINDOW_W, DEFAULT_WINDOW_H
local NAV_W = 174
local CONTENT_W = WINDOW_W - NAV_W - 24
local CONTENT_H = WINDOW_H - 74
local NAV_BUTTON_H = 20
local NAV_BUTTON_STEP = 23
local MENU_BASE_SCALE = 1.08
local MENU_NORMAL_FRAME_STRATA = "DIALOG"
local MENU_EDIT_FRAME_STRATA = "FULLSCREEN"
local MENU_NORMAL_FRAME_LEVEL = 10
local MENU_EDIT_FRAME_LEVEL = 900
local MENU_NORMAL_POPUP_FRAME_LEVEL = 120
local MENU_EDIT_POPUP_FRAME_LEVEL = 980

local function IsMenuEditPriorityActive()
    if type(IsEditModeActive) ~= "function" then return false end
    local ok, active = pcall(IsEditModeActive)
    return ok and active == true
end

local function GetMenuFramePriority(level)
    if IsMenuEditPriorityActive() then
        return MENU_EDIT_FRAME_STRATA, level or MENU_EDIT_FRAME_LEVEL
    end
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
M.ApplyMenuPopupFramePriority = ApplyMenuPopupFramePriority

local NAV = {
    { key = "home", label = "Dashboard" },
    { header = "Frames", id = "unitframes", defaultOpen = true },
    { key = "uf_player", label = "Player", group = "unitframes" },
    { key = "uf_target", label = "Target", group = "unitframes" },
    { key = "uf_boss", label = "Boss Frames", group = "unitframes" },
    { key = "uf_focus", label = "Focus", group = "unitframes" },
    { key = "uf_pet", label = "Pet", group = "unitframes" },
    { key = "uf_targettarget", label = "Target of Target", group = "unitframes" },
    { key = "uf_focustarget", label = "Focus Target", group = "unitframes" },
    { header = "Group Frames", id = "groupframes", defaultOpen = true },
    { key = "gf_layout", label = "Layout", group = "groupframes" },
    { key = "gf_bars", label = "Health & Text", group = "groupframes" },
    { key = "gf_indicators", label = "Indicators", group = "groupframes" },
    { key = "gf_auras", label = "Buffs & Debuffs", group = "groupframes" },
    { header = "Auras", id = "auras", defaultOpen = true },
    { key = "auras2", label = "Unit Auras", group = "auras" },
    { header = "Appearance", id = "globalstyle", defaultOpen = true },
    { key = "opt_bars", label = "Bars", group = "globalstyle" },
    { key = "opt_castbar", label = "Castbars", group = "globalstyle" },
    { key = "opt_colors", label = "Colors", group = "globalstyle" },
    { key = "opt_fonts", label = "Fonts", group = "globalstyle" },
    { key = "opt_misc", label = "Miscellaneous", group = "globalstyle" },
    { key = "classpower", label = "Class Resources" },
    { key = "gameplay", label = "Gameplay" },
    { key = "profiles", label = "Profiles" },
    { header = "Advanced", id = "modules", defaultOpen = false },
    { key = "modules", label = "Modules", group = "modules" },
}
M.navItems = NAV

M.navHelp = M.navHelp or {
    home = "Start here for setup, scaling, support, changelog, and safe recovery actions.",
    uf_player = "Tune your own unit frame, including basics, text, portrait, bars, castbar, and status icons.",
    uf_target = "Configure the target frame and keep layout-related options visible while tuning.",
    uf_boss = "Configure boss frames and use the preview to test encounter-only frames safely.",
    uf_focus = "Set up the focus frame for interrupt, targeting, and encounter workflows.",
    uf_pet = "Tune the pet frame without mixing it into player or target options.",
    uf_targettarget = "Configure target-of-target behavior and inline target text.",
    uf_focustarget = "Configure the focus target frame, which follows the Focus frame and updates from focus target changes.",
    gf_layout = "Choose party, raid, and mythic raid layout behavior before tuning details.",
    gf_bars = "Configure group frame health, power, and text behavior.",
    gf_indicators = "Set status icons, class resources, and group indicators.",
    gf_auras = "Configure group buffs, debuffs, and aura display behavior.",
    auras2 = "Configure unit-frame auras with display, filtering, and per-unit controls.",
    opt_bars = "Shared bar textures, gradients, colors, outlines, and frame visuals.",
    opt_castbar = "Shared castbar settings, ticks, GCD, interrupt helpers, and focus cast tools.",
    opt_colors = "Shared color choices and state color behavior.",
    opt_fonts = "Shared font choices, sizes, outlines, and text shortening.",
    opt_misc = "General behavior, minimap, version checks, sounds, and Blizzard frame options.",
    classpower = "Configure class resources and detached class bars.",
    gameplay = "Mouseover, click-cast, targeting, combat crosshair, and gameplay helpers.",
    profiles = "Manage, duplicate, import, export, and back up profiles.",
    modules = "Advanced module switches and expert options.",
}

local ALIASES = {
    [""] = "home",
    home = "home",
    menu = "home",
    main = "home",
    options = "home",
    opt = "home",
    player = "uf_player",
    target = "uf_target",
    tot = "uf_targettarget",
    targettarget = "uf_targettarget",
    focustarget = "uf_focustarget",
    focus_target = "uf_focustarget",
    focustargettarget = "uf_focustarget",
    ft = "uf_focustarget",
    focus = "uf_focus",
    boss = "uf_boss",
    pet = "uf_pet",
    bars = "opt_bars",
    fonts = "opt_fonts",
    auras = "auras2",
    auras2 = "auras2",
    castbar = "opt_castbar",
    colors = "opt_colors",
    colours = "opt_colors",
    misc = "opt_misc",
    classpower = "classpower",
    gameplay = "gameplay",
    profiles = "profiles",
    layout = "gf_layout",
    health = "gf_bars",
    group = "gf_layout",
    groupframes = "gf_layout",
    class = "classpower",
    modules = "modules",
    search = "search",
}

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
local RefreshWindowControls

local SNAP_EDGE_PX = 24
local SNAP_FRAME_EDGE_PX = 4
local SNAP_SCREEN_MARGIN = 14
local MINIMIZED_WINDOW_W, MINIMIZED_WINDOW_H = 286, 32

local function IsSlashMenuSnapEnabled()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return true end
    return g.slashMenuSnapEnabled ~= false
end

local function IsAdvancedNavHidden()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return true end
    return g.hideAdvancedMenu ~= false
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
    for _, entry in pairs(M.cache) do
        if entry.wrapper and entry.wrapper.Hide then entry.wrapper:Hide() end
    end
end

local function SetTitle(key)
    local frame = M.frame
    if not frame then return end
    local spec = M.pages[key]
    local title = (spec and spec.title) or "MSUF"
    frame.title:SetText(M.Tr(title))
    if frame.subtitle then frame.subtitle:SetText("") end
    if frame.RefreshStatus then frame:RefreshStatus() end
end

local function SearchAPI()
    return M.Search
end

local function UpdateSearchPlaceholder(searchBox)
    local api = SearchAPI()
    if api and type(api.UpdateSearchPlaceholder) == "function" then return api.UpdateSearchPlaceholder(searchBox) end
    if searchBox and searchBox._msuf2SearchPlaceholder and searchBox._msuf2SearchPlaceholder.SetText then
        searchBox._msuf2SearchPlaceholder:SetText(M.Tr("Search"))
    end
end

local function MarkSearchIndexDirty()
    local api = SearchAPI()
    if api and type(api.MarkIndexDirty) == "function" then api.MarkIndexDirty() end
end

local function CancelSearchBackgroundIndex()
    local api = SearchAPI()
    if api and type(api.CancelBackgroundIndex) == "function" then api.CancelBackgroundIndex() end
end

local function RefreshSearchResultsPage()
    local api = SearchAPI()
    if api and type(api.RefreshResultsPage) == "function" then api.RefreshResultsPage() end
end

local function ScheduleSearchInputQuery(searchBox, query)
    local api = SearchAPI()
    if api and type(api.ScheduleInputQuery) == "function" then api.ScheduleInputQuery(searchBox, query) end
end

local function RunSearchInputQuery(query, openPage)
    local api = SearchAPI()
    if api and type(api.RunInputQuery) == "function" then api.RunInputQuery(query, openPage) end
end

local function OpenSearchResults(query)
    local api = SearchAPI()
    if api and type(api.OpenResults) == "function" then api.OpenResults(query) end
end

local function OpenSearchTarget(pageKey, query, fallback, preferredAnchor)
    local api = SearchAPI()
    if api and type(api.OpenTarget) == "function" then api.OpenTarget(pageKey, query, fallback, preferredAnchor) end
end

local function BumpSearchInputSerial()
    local api = SearchAPI()
    if api and type(api.BumpInputSerial) == "function" then api.BumpInputSerial() end
end
local function CurrentMenuLocaleKey()
    if type(ns.GetEffectiveLocale) == "function" then
        local ok, locale = pcall(ns.GetEffectiveLocale)
        if ok and locale then return tostring(locale) end
    end
    if ns.LOCALE then return tostring(ns.LOCALE) end
    if type(_G.GetLocale) == "function" then return tostring(_G.GetLocale()) end
    return ""
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
    for pageKey, btn in pairs(M.navButtons) do
        if labelsDirty and btn._msuf2RawLabel and btn.SetText then
            btn:SetText(M.Tr(btn._msuf2RawLabel))
        end
        if btn.SetActive then btn:SetActive(pageKey == key) end
    end
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

local function RunRefreshers(entry)
    if not entry or not entry.refreshers then return end
    for i = 1, #entry.refreshers do
        local fn = entry.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
end

local function BossPagePreviewInCombat()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function ApplyBossPagePreviewFallback(active, reason)
    if BossPagePreviewInCombat() then
        _G.MSUF2_BossUnitframePreviewActive = nil
        return
    end
    _G.MSUF2_BossUnitframePreviewActive = active and true or nil
    if type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
        _G.MSUF_ApplyBossUnitframePreviewState(active and true or false, reason or "MSUF2_BOSS_PAGE")
        return
    end
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
end

local lastBossPreviewActive
local lastBossPreviewFn

local function SyncBossPagePreviewForKey(key, force)
    local active = (key == "uf_boss")
        and M.frame and M.frame.IsShown and M.frame:IsShown()
    if BossPagePreviewInCombat() then
        _G.MSUF2_BossUnitframePreviewActive = nil
        lastBossPreviewActive = nil
        return
    end
    local fn = M.UnitPage and M.UnitPage.SetBossPagePreviewActive
    local globalActive = (_G.MSUF2_BossUnitframePreviewActive == true)
    if not force and lastBossPreviewActive == active and lastBossPreviewFn == fn and globalActive == (active == true) then return end
    lastBossPreviewActive = active
    lastBossPreviewFn = fn

    if type(fn) == "function" then
        local ok = pcall(fn, active and true or false)
        if ok then
            if active and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" and not BossPagePreviewInCombat() then
                _G.MSUF_ApplyBossUnitframePreviewState(true, "MSUF2_BOSS_PAGE_CORE")
            end
        else
            ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
        end
        return
    end
    ApplyBossPagePreviewFallback(active and true or false, "MSUF2_BOSS_PAGE_FALLBACK")
end

local GF_PAGE_KEYS = {
    gf_layout = true,
    gf_bars = true,
    gf_auras = true,
    gf_indicators = true,
}

local function IsGroupPageKey(key)
    return GF_PAGE_KEYS[key or ""] == true
end

local function ResetStatusIndicatorTestModeOnMenuExit()
    if type(M.EnsureDB) ~= "function" then return false end

    local db = M.EnsureDB()
    if type(db) ~= "table" then return false end

    local changed = false
    local generalChanged = false
    db.general = (type(db.general) == "table") and db.general or {}
    if db.general.stateIconsTestMode == true then
        db.general.stateIconsTestMode = false
        changed = true
        generalChanged = true
    end

    local unitsToApply = {}
    local seenUnits = {}
    local unitPages = M.UnitPage and M.UnitPage.UNIT_PAGES
    if type(unitPages) == "table" then
        for _, page in pairs(unitPages) do
            local unit = page and page.unit
            if unit == "tot" then unit = "targettarget" end
            if unit and not seenUnits[unit] then
                seenUnits[unit] = true
                local unitConf = db[unit]
                if type(unitConf) == "table" and unitConf.stateIconsTestMode == true then
                    unitConf.stateIconsTestMode = false
                    changed = true
                    unitsToApply[#unitsToApply + 1] = unit
                elseif generalChanged then
                    unitsToApply[#unitsToApply + 1] = unit
                end
            end
        end
    end

    if not changed then return false end
    if type(M.RequestUnitApply) ~= "function" then return true end

    for i = 1, #unitsToApply do
        M.RequestUnitApply(unitsToApply[i], "MSUF2_STATUS_TEST_MENU_EXIT", {
            notify = false,
            preview = false,
        })
    end

    return true
end

local function CurrentGFMenuScope()
    local scope = M.gfScope
    if scope == "party" or scope == "raid" or scope == "mythicraid" then return scope end
    return "party"
end

local function GFPreviewCount(kind)
    if kind == "mythicraid" then return 20 end
    if kind == "raid" then return 30 end
    return 5
end

local function SetGFPagePreviewFlag(active, kind)
    _G.MSUF2_GFPagePreviewActive = active and true or nil
    _G.MSUF2_GFPagePreviewKind = active and kind or nil
end

local function HideGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if not (gf and gf.headers) then return end
    if gf.headers.party then gf.headers.party:Hide() end
    if type(gf.HideRaidHeaders) == "function" then gf.HideRaidHeaders(true)
    elseif gf.headers.raid then gf.headers.raid:Hide() end
end

local function RestoreGFHeaders(gf)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    if gf and type(gf.UpdateGroupVisibility) == "function" then gf.UpdateGroupVisibility() end
end

local lastGFPreviewActive
local lastGFPreviewKind
local lastGFPreviewEditMode
local lastGFPreviewRuntime

local function SyncGroupPagePreviewForKey(key, force)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        SetGFPagePreviewFlag(false)
        if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then
            _G.MSUF_GF_EM2_SetActivePreviewKind(nil)
        end
        return
    end

    local frameVisible = M.frame and M.frame.IsShown and M.frame:IsShown()
    local active = frameVisible and IsGroupPageKey(key)
    local gf = ns and ns.GF
    local kind = CurrentGFMenuScope()
    local editMode = IsEditModeActive() and true or false
    local hasRuntime = gf and type(gf.ShowPreview) == "function" and type(gf.HidePreview) == "function"
    if not force
        and lastGFPreviewActive == active
        and lastGFPreviewKind == kind
        and lastGFPreviewEditMode == editMode
        and lastGFPreviewRuntime == hasRuntime
    then
        return
    end
    lastGFPreviewActive = active
    lastGFPreviewKind = kind
    lastGFPreviewEditMode = editMode
    lastGFPreviewRuntime = hasRuntime

    if type(_G.MSUF_GF_EM2_SetActivePreviewKind) == "function" then
        _G.MSUF_GF_EM2_SetActivePreviewKind(active and kind or nil)
    end

    if editMode then
        SetGFPagePreviewFlag(false)
        return
    end

    if not hasRuntime then
        SetGFPagePreviewFlag(active, kind)
        return
    end

    if not active then
        SetGFPagePreviewFlag(false)
        local classicPanel = _G.MSUF_GFOptionsPanel
        if classicPanel and classicPanel.IsShown and classicPanel:IsShown() then return end
        gf.HidePreview("party")
        gf.HidePreview("raid")
        gf.HidePreview("mythicraid")
        if gf.SetPreviewAnchor then
            gf.SetPreviewAnchor("party", nil)
            gf.SetPreviewAnchor("raid", nil)
            gf.SetPreviewAnchor("mythicraid", nil)
        end
        RestoreGFHeaders(gf)
        return
    end

    SetGFPagePreviewFlag(true, kind)
    HideGFHeaders(gf)
    if gf.SetPreviewAnchor then
        gf.SetPreviewAnchor("party", nil)
        gf.SetPreviewAnchor("raid", nil)
        gf.SetPreviewAnchor("mythicraid", nil)
    end
    if kind ~= "party" then gf.HidePreview("party") end
    if kind ~= "raid" then gf.HidePreview("raid") end
    if kind ~= "mythicraid" then gf.HidePreview("mythicraid") end
    gf.ShowPreview(kind, GFPreviewCount(kind))
    if type(gf.RefreshPreviewLayout) == "function" then gf.RefreshPreviewLayout(kind) end
end

M.SyncGFPagePreviewForKey = SyncGroupPagePreviewForKey

IsEditModeActive = function()
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active ~= nil then
        return st.active == true
    end

    local em2 = rawget(_G, "MSUF_EM2")
    local state = em2 and em2.State
    if state and type(state.IsActive) == "function" then
        return state.IsActive() and true or false
    end

    local fn = rawget(_G, "MSUF_IsMSUFEditModeActive")
        or rawget(_G, "MSUF_IsInEditMode")
        or rawget(_G, "MSUF_IsEditModeActive")
    if type(fn) == "function" then
        local ok, result = pcall(fn)
        if ok then return result and true or false end
    end

    return rawget(_G, "MSUF_UnitEditModeActive") == true
        or rawget(_G, "MSUF_EDITMODE_ACTIVE") == true
end

local function IsEditModeCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

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
            if M.Refresh then M.Refresh() end
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

local function ClearSearchRegistryPage(pageKey)
    local api = SearchAPI()
    if api and type(api.ClearRegistryPage) == "function" then api.ClearRegistryPage(pageKey) end
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

local function TrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ShortLabel(text, limit)
    text = TrimText(text)
    limit = tonumber(limit) or 22
    if #text <= limit then return text end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end

function M.SelectPage(key)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    key = ALIASES[key or ""] or key or "home"
    local spec = M.pages[key]
    local cached = M.cache[key]
    local specVersion = spec and spec.version
    if cached and specVersion and cached.version ~= specVersion then
        M.InvalidatePage(key)
        cached = nil
        if M.activeKey == key then M.activeKey = nil end
    end
    if key == M.activeKey and cached then
        RunRefreshers(cached)
        SyncBossPagePreviewForKey(key)
        SyncGroupPagePreviewForKey(key)
        return true
    end

    local previousKey = M.activeKey
    local previous = previousKey and M.cache and M.cache[previousKey]
    if previous and previous.wrapper and previous.wrapper.Hide then
        previous.wrapper:Hide()
    else
        HideAllCachedPages()
    end

    local entry = BuildPageEntry(key, false)
    if not entry then return false end
    entry.hiddenBuild = false

    M.activeKey = key
    if M.frame then M.frame._msufCurrentKey = key end
    if M.scrollFrame and M.scrollFrame.SetVerticalScroll then
        M.scrollFrame:SetVerticalScroll(0)
    end
    if M.scrollChild then
        M.scrollChild:SetHeight(entry.height or CONTENT_H)
    end
    if M.scrollFrame and M.scrollFrame._msuf2RefreshScrollBar then
        M.scrollFrame:_msuf2RefreshScrollBar()
    end
    entry.wrapper:Show()
    RunRefreshers(entry)
    SetTitle(key)
    UpdateNav(key)
    SyncBossPagePreviewForKey(key)
    SyncGroupPagePreviewForKey(key)
    return true
end

function M.AttachNavTooltip(frame, title, text)
    if not (frame and frame.HookScript) then return end
    frame:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
        if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.72, 0.78, 0.92, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function CreateNavButton(parent, key, label, indent)
    local btn = T.Button(parent, M.Tr(label), NAV_W - 38 - (indent or 0), NAV_BUTTON_H)
    btn:SetScript("OnClick", function() M.SelectPage(key) end)
    btn._msuf2SkipHistoryCheckpoint = true
    btn._msuf2NavItem = true
    btn._msuf2NavIndent = indent or 0
    btn._msuf2RawLabel = label
    if T.AttachNavIcon then T.AttachNavIcon(btn, key, (indent or 0) > 0) end
    M.AttachNavTooltip(btn, label, M.navHelp and M.navHelp[key])
    M.navButtons[key] = btn
    if btn.RefreshVisual then btn:RefreshVisual() end
    return btn
end

local function ApplyNavHeaderVisual(btn, open)
    if not btn then return end
    local arrow = btn._msuf2NavArrow
    if arrow then
        if arrow.SetRotation then arrow:SetRotation(open and (math.pi * 0.5) or 0) end
        if arrow.SetVertexColor then
            local c = open and T.colors.navArrowOpen or T.colors.navArrowClosed
            arrow:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
    if btn.RefreshVisual then btn:RefreshVisual() end
end

local function AttachNavHoverGrow(btn)
    if not (btn and btn.HookScript) or btn._msuf2NavHoverGrow then return end
    btn._msuf2NavHoverGrow = true
    local baseScale, hoverScale = 1, 1.018
    if btn.SetScale then btn:SetScale(baseScale) end

    local function LayoutPillParts(parts, inset, lift)
        if not (parts and parts.L and parts.M and parts.R and btn.GetWidth and btn.GetHeight) then return end
        local w = btn:GetWidth() or 120
        local h = btn:GetHeight() or NAV_BUTTON_H
        local innerW = max(1, w - inset * 2)
        local innerH = max(1, h - inset * 2)
        local capW = min(floor(innerH * 0.5 + 0.5), floor(innerW * 0.5))
        local midW = max(1, innerW - capW * 2)
        lift = tonumber(lift) or 0

        parts.L:ClearAllPoints()
        parts.M:ClearAllPoints()
        parts.R:ClearAllPoints()
        parts.L:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset + lift)
        parts.L:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", inset, inset + lift)
        parts.L:SetWidth(capW)
        parts.R:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -inset, -inset + lift)
        parts.R:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset + lift)
        parts.R:SetWidth(capW)
        parts.M:SetPoint("TOPLEFT", parts.L, "TOPRIGHT", 0, 0)
        parts.M:SetPoint("BOTTOMRIGHT", parts.R, "BOTTOMLEFT", 0, 0)
        parts.M:SetWidth(midW)
    end

    local function LayoutPillVisual(hovering)
        if hovering then
            LayoutPillParts(btn._msuf2Fill, 0, 1)
            LayoutPillParts(btn._msuf2Edge, -1, 1)
        else
            LayoutPillParts(btn._msuf2Fill, 2, 0)
            LayoutPillParts(btn._msuf2Edge, 1, 0)
        end
    end

    local function OffsetRegion(region, lift)
        if not (region and region.GetNumPoints and region.GetPoint and region.ClearAllPoints and region.SetPoint) then return end
        if not region._msuf2NavBasePoints then
            local points = {}
            for i = 1, region:GetNumPoints() do
                local point, relativeTo, relativePoint, xOfs, yOfs = region:GetPoint(i)
                points[#points + 1] = { point, relativeTo, relativePoint, xOfs or 0, yOfs or 0 }
            end
            region._msuf2NavBasePoints = points
        end
        region:ClearAllPoints()
        local points = region._msuf2NavBasePoints
        for i = 1, #points do
            local p = points[i]
            region:SetPoint(p[1], p[2], p[3], p[4], p[5] + (lift or 0))
        end
    end

    local function SetVisualScale(self, hovering)
        if self.IsEnabled and not self:IsEnabled() then hovering = false end
        local scale = hovering and hoverScale or baseScale
        if self.SetScale then self:SetScale(baseScale) end
        LayoutPillVisual(hovering)
        if self._msuf2Label and self._msuf2Label.SetScale then self._msuf2Label:SetScale(scale) end
        if self._msuf2NavIcon and self._msuf2NavIcon.SetScale then self._msuf2NavIcon:SetScale(scale) end
        if self._msuf2NavArrow and self._msuf2NavArrow.SetScale then self._msuf2NavArrow:SetScale(scale) end
        OffsetRegion(self._msuf2Label, hovering and 1 or 0)
        OffsetRegion(self._msuf2NavIcon, hovering and 1 or 0)
        OffsetRegion(self._msuf2NavArrow, hovering and 1 or 0)
    end
    btn:HookScript("OnEnter", function(self) SetVisualScale(self, true) end)
    btn:HookScript("OnLeave", function(self) SetVisualScale(self, false) end)
    btn:HookScript("OnHide", function(self) SetVisualScale(self, false) end)
end

local function AttachHistoryTooltip(btn, getTitle, getText)
    if not btn then return end
    btn:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local title = type(getTitle) == "function" and getTitle(self) or getTitle
        local text = type(getText) == "function" and getText(self) or getText
        GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
        if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.72, 0.78, 0.92, true) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

local function HistoryTooltipText(kind)
    local s = M.GetHistoryState and M.GetHistoryState() or {}
    local label = (kind == "undo") and s.undoLabel or s.redoLabel
    local canUse = (kind == "undo") and s.canUndo or s.canRedo
    if canUse and label then
        local text = M.Format("%s\nUndo: %d   Redo: %d", ShortLabel(label, 36), tonumber(s.undoCount) or 0, tonumber(s.redoCount) or 0)
        if kind == "undo" and s.canResetAll then
            text = text .. "\n" .. M.Tr("Shift-click: reset all MSUF2 menu changes from this open session.")
        end
        return text
    end
    local text = M.Format("No %s action in this MSUF2 menu session.\nUndo: %d   Redo: %d",
        kind == "undo" and "undo" or "redo",
        tonumber(s.undoCount) or 0,
        tonumber(s.redoCount) or 0)
    if kind == "undo" and s.canResetAll then
        text = text .. "\n" .. M.Tr("Shift-click: reset all MSUF2 menu changes from this open session.")
    end
    return text
end

local function CreateHistoryControls(parent)
    local row = CreateFrame("Frame", nil, parent)
    local rowW = NAV_W - 38
    row:SetSize(rowW, 26)
    local buttonGap = 6
    local buttonW = floor((rowW - buttonGap) * 0.5)

    local function StyleHistoryButton(btn, label, texture)
        btn._msuf2SolidPill = true
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", btn, "LEFT", 27, 0)
            btn._msuf2Label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            btn._msuf2Label:SetText(M.Tr(label))
        end
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 5)
        icon:SetTexture(texture)
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", btn, "LEFT", 9, 0)
        if icon.SetDesaturated then icon:SetDesaturated(false) end
        icon:SetVertexColor(1, 1, 1, 0.95)
        btn._msuf2HistoryIcon = icon
        return icon
    end

    local undo = T.Button(row, "", buttonW, 22)
    T.SkinDangerButton(undo)
    undo._msuf2SkipHistoryCheckpoint = true
    undo._msuf2HistorySource = "history:undo"
    undo._msuf2HistoryLabel = "Undo"
    undo:SetPoint("LEFT", row, "LEFT", 0, 0)
    StyleHistoryButton(undo, "Undo", T.media.historyUndo)
    undo:SetScript("OnClick", function()
        if _G.IsShiftKeyDown and _G.IsShiftKeyDown() and M.ResetHistorySession then
            M.ResetHistorySession()
        elseif M.Undo then
            M.Undo()
        end
    end)

    local redo = T.Button(row, "", buttonW, 22)
    T.SkinSuccessButton(redo)
    redo._msuf2SkipHistoryCheckpoint = true
    redo._msuf2HistorySource = "history:redo"
    redo._msuf2HistoryLabel = "Redo"
    redo:SetPoint("LEFT", undo, "RIGHT", buttonGap, 0)
    StyleHistoryButton(redo, "Redo", T.media.historyRedo)
    redo:SetScript("OnClick", function()
        if M.Redo then M.Redo() end
    end)

    AttachHistoryTooltip(undo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.undoLabel and ("Undo: " .. ShortLabel(s.undoLabel, 28)) or "Undo"
    end, function() return HistoryTooltipText("undo") end)
    AttachHistoryTooltip(redo, function()
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        return s.redoLabel and ("Redo: " .. ShortLabel(s.redoLabel, 28)) or "Redo"
    end, function() return HistoryTooltipText("redo") end)

    row.undo = undo
    row.redo = redo
    M.historyControls = row

    function M.RefreshHistoryControls()
        local controls = M.historyControls
        if not controls then return end
        local s = M.GetHistoryState and M.GetHistoryState() or {}
        local canUndo = s.canUndo and true or false
        local canRedo = s.canRedo and true or false
        local canResetAll = s.canResetAll and true or false
        if controls.undo then controls.undo._msuf2Danger = canUndo end
        if controls.redo then controls.redo._msuf2Success = canRedo end
        if controls.undo and controls.undo.SetEnabled then controls.undo:SetEnabled(canUndo or canResetAll) end
        if controls.redo and controls.redo.SetEnabled then controls.redo:SetEnabled(canRedo) end
        if controls.undo and controls.undo._msuf2HistoryIcon then
            if canUndo then
                controls.undo._msuf2HistoryIcon:SetVertexColor(1, 1, 1, 0.95)
            elseif canResetAll then
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.muted[1], T.colors.muted[2], T.colors.muted[3], 0.88)
            else
                controls.undo._msuf2HistoryIcon:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.42)
            end
        end
        if controls.redo and controls.redo._msuf2HistoryIcon then
            if canRedo then
                controls.redo._msuf2HistoryIcon:SetVertexColor(1, 1, 1, 0.95)
            else
                controls.redo._msuf2HistoryIcon:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.42)
            end
        end
    end

    M.RefreshHistoryControls()
    return row
end

local function BuildNav(parent)
    M.navButtons = {}
    M.navHeaders = {}
    M.navGroupForKey = {}
    M.navHeaderState = M.navHeaderState or {}
    local search = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    search:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
    search:SetHeight(20)
    search:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 20)
    search:EnableMouse(true)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetTextInsets(6, 22, 0, 0)
    T.SkinEditBox(search)
    local placeholder = search.Instructions
    if not (placeholder and placeholder.SetText and placeholder.SetPoint) then
        placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    elseif placeholder.ClearAllPoints then
        placeholder:ClearAllPoints()
    end
    placeholder:SetPoint("LEFT", search, "LEFT", 8, 0)
    placeholder:SetPoint("RIGHT", search, "RIGHT", -24, 0)
    if placeholder.SetJustifyH then placeholder:SetJustifyH("LEFT") end
    if placeholder.SetJustifyV then placeholder:SetJustifyV("MIDDLE") end
    if placeholder.SetWordWrap then placeholder:SetWordWrap(false) end
    if placeholder.SetNonSpaceWrap then placeholder:SetNonSpaceWrap(false) end
    if placeholder.SetAlpha then placeholder:SetAlpha(0.72) end
    T.StyleFontString(placeholder, T.colors.dim, 0)
    search._msuf2SearchPlaceholder = placeholder
    UpdateSearchPlaceholder(search)
    parent.searchBox = search
    search:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:SetFocus() end
    end)
    search:HookScript("OnEditFocusGained", function(self)
        if self.HighlightText then self:HighlightText() end
        UpdateSearchPlaceholder(self)
    end)
    search:HookScript("OnEditFocusLost", function(self)
        if self.HighlightText then self:HighlightText(0, 0) end
        UpdateSearchPlaceholder(self)
    end)
    search:SetScript("OnTextChanged", function(self)
        UpdateSearchPlaceholder(self)
        if self._msuf2SearchInternal then return end
        local query = TrimText(self:GetText() or "")
        ScheduleSearchInputQuery(self, query)
    end)
    search:SetScript("OnEnterPressed", function(self)
        local query = TrimText(self:GetText() or "")
        if query == "" then
            self:ClearFocus()
            return
        end
        BumpSearchInputSerial()
        RunSearchInputQuery(query, false)
        if M.searchResults and M.searchResults[1] then
            local first = M.searchResults[1]
            if first.noOpen then
                self:ClearFocus()
            else
                OpenSearchTarget(first.key, query, first.anchorFallback or first.label or first.title, first.anchor)
            end
        else
            OpenSearchResults(query)
        end
    end)
    search:SetScript("OnEscapePressed", function(self)
        self._msuf2SearchInternal = true
        self:SetText("")
        self._msuf2SearchInternal = nil
        self:ClearFocus()
        BumpSearchInputSerial()
        RunSearchInputQuery("", true)
    end)

    local clear = CreateFrame("Button", nil, parent)
    clear:SetSize(16, 16)
    clear:SetFrameLevel(search:GetFrameLevel() + 1)
    clear:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    local clearText = T.Font(clear, "GameFontDisableSmall", "x", T.colors.dim)
    clearText:SetPoint("CENTER", clear, "CENTER", 0, 0)
    clear:Hide()
    clear:SetScript("OnClick", function()
        search._msuf2SearchInternal = true
        search:SetText("")
        search._msuf2SearchInternal = nil
        BumpSearchInputSerial()
        RunSearchInputQuery("", true)
        clear:Hide()
        search:SetFocus()
    end)
    search:HookScript("OnTextChanged", function(self)
        clear:SetShown(TrimText(self:GetText() or "") ~= "")
    end)

    local listScroll = CreateFrame("ScrollFrame", nil, parent)
    listScroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -34)
    listScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 6)
    local list = CreateFrame("Frame", nil, listScroll)
    list:SetSize(NAV_W - 18, 1)
    listScroll:SetScrollChild(list)
    parent._msuf2NavListScroll = listScroll
    parent._msuf2NavList = list
    if T.StyleScrollFrame then T.StyleScrollFrame(listScroll, parent) end

    local created = {}
    for i = 1, #NAV do
        local item = NAV[i]
        if item.header then
            local id = item.id or item.header
            if M.navHeaderState[id] == nil then M.navHeaderState[id] = item.defaultOpen ~= false end
            local btn = T.Button(list, string.upper(M.Tr(item.header)), NAV_W - 38, NAV_BUTTON_H)
            btn._msuf2NavHeader = true
            btn._msuf2NavHeaderId = id
            btn._msuf2RawLabel = item.header
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", 24, 0)
            btn._msuf2Label:SetPoint("RIGHT", -8, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            local arrow = btn:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(10, 10)
            arrow:SetPoint("LEFT", btn, "LEFT", 5, 0)
            arrow:SetTexture(T.media.collapseArrow)
            btn._msuf2NavArrow = arrow
            btn:SetScript("OnClick", function(self)
                local groupId = self._msuf2NavHeaderId
                M.navHeaderState[groupId] = not M.navHeaderState[groupId]
                if parent._msuf2NavReflow then parent:_msuf2NavReflow() end
            end)
            btn._msuf2SkipHistoryCheckpoint = true
            AttachNavHoverGrow(btn)
            ApplyNavHeaderVisual(btn, M.navHeaderState[id])
            M.navHeaders[id] = btn
            created[#created + 1] = { kind = "header", id = id, button = btn }
        elseif item.key then
            local indent = item.group and 12 or 0
            local btn = CreateNavButton(list, item.key, item.label, indent)
            AttachNavHoverGrow(btn)
            if item.group then M.navGroupForKey[item.key] = item.group end
            created[#created + 1] = { kind = "page", group = item.group, button = btn }
            if item.key == "profiles" then
                created[#created + 1] = { kind = "history", frame = CreateHistoryControls(list) }
            end
        end
    end
    function parent:_msuf2NavReflow()
        local y = -4
        local advancedHidden = IsAdvancedNavHidden()
        for i = 1, #created do
            local item = created[i]
            local btn = item.button
            if advancedHidden and (item.id == "modules" or item.group == "modules") then
                if btn then btn:Hide() end
                if item.frame then item.frame:Hide() end
            elseif item.kind == "header" then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", 12, y)
                ApplyNavHeaderVisual(btn, M.navHeaderState[item.id])
                y = y - NAV_BUTTON_STEP
            elseif item.kind == "history" then
                local frame = item.frame
                frame:Show()
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", list, "TOPLEFT", 12, y - 2)
                y = y - 32
            elseif not item.group or M.navHeaderState[item.group] then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", 12 + (btn._msuf2NavIndent or 0), y)
                y = y - NAV_BUTTON_STEP
            else
                if btn then btn:Hide() end
                if item.frame then item.frame:Hide() end
            end
        end
        local contentH = math.max(math.abs(y) + 8, (listScroll.GetHeight and listScroll:GetHeight()) or 1)
        list:SetSize(NAV_W - 18, contentH)
        if listScroll._msuf2RefreshScrollBar then listScroll:_msuf2RefreshScrollBar() end
        if M.RefreshHistoryControls then M.RefreshHistoryControls() end
    end
    parent:_msuf2NavReflow()
end

function M.RefreshAdvancedNavVisibility()
    if M.nav and M.nav._msuf2NavReflow then M.nav:_msuf2NavReflow() end
    if M.activeKey then UpdateNav(M.activeKey) end
end

local function PaintWindowControlButton(btn, hover, down)
    if not btn then return end
    local fill = btn._msuf2ControlFill
    local edge = btn._msuf2ControlEdge
    local alpha = (btn.IsEnabled and not btn:IsEnabled()) and 0.42 or 1
    if fill and fill.SetVertexColor then
        if down then
            fill:SetVertexColor(0.050, 0.070, 0.130, 0.98 * alpha)
        elseif hover then
            fill:SetVertexColor(0.075, 0.095, 0.175, 0.96 * alpha)
        else
            fill:SetVertexColor(0.075, 0.080, 0.125, 0.92 * alpha)
        end
    end
    if edge and edge.SetVertexColor then
        if hover or down then
            edge:SetVertexColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.86 * alpha)
        else
            edge:SetVertexColor(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.70 * alpha)
        end
    end
    local active = hover or down
    local r, g, b = active and T.colors.accent[1] or 0.62, active and T.colors.accent[2] or 0.74, active and T.colors.accent[3] or 0.98
    local lineAlpha = (hover or down) and alpha or (0.88 * alpha)
    if btn._msuf2ControlLines then
        for i = 1, #btn._msuf2ControlLines do
            local line = btn._msuf2ControlLines[i]
            if line.SetVertexColor then
                if line._msuf2ControlShadow then
                    line:SetVertexColor(0.015, 0.020, 0.045, 0.72 * alpha)
                else
                    line:SetVertexColor(r, g, b, (line._msuf2ControlAlpha or lineAlpha))
                end
            end
        end
    end
    if btn._msuf2ControlText then
        btn._msuf2ControlText:SetTextColor(r, g, b, lineAlpha)
    end
    if btn._msuf2ControlTextShadow then
        btn._msuf2ControlTextShadow:SetTextColor(0.015, 0.020, 0.045, 0.72 * alpha)
    end
end

local function SetWindowControlIcon(btn, kind)
    if not btn then return end
    btn._msuf2ControlKind = kind
    btn._msuf2ControlLines = btn._msuf2ControlLines or {}
    for i = 1, #btn._msuf2ControlLines do
        btn._msuf2ControlLines[i]:Hide()
    end
    if btn._msuf2ControlText then btn._msuf2ControlText:Hide() end
    if btn._msuf2ControlTextShadow then btn._msuf2ControlTextShadow:Hide() end

    local function Line(index, w, h, x, y, shadow, customAlpha)
        local line = btn._msuf2ControlLines[index]
        if not line then
            line = btn:CreateTexture(nil, "ARTWORK")
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(true) end
            if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
            btn._msuf2ControlLines[index] = line
        end
        line:ClearAllPoints()
        line:SetSize(w, h)
        line:SetPoint("CENTER", btn, "CENTER", x, y)
        if line.SetRotation then line:SetRotation(0) end
        line._msuf2ControlShadow = shadow and true or nil
        line._msuf2ControlAlpha = customAlpha
        line:Show()
        return line
    end

    if kind == "minimize" then
        if not btn._msuf2ControlText then
            local shadow = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
            shadow:SetText("\226\128\147")
            shadow:SetPoint("CENTER", btn, "CENTER", 1, -3)
            btn._msuf2ControlTextShadow = shadow

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            text:SetText("\226\128\147")
            text:SetPoint("CENTER", btn, "CENTER", 0, -2)
            btn._msuf2ControlText = text
        end
        btn._msuf2ControlTextShadow:Show()
        btn._msuf2ControlText:Show()
    elseif kind == "restore" then
        Line(1, 9, 2, -2, 4)
        Line(2, 2, 8, 3, 0)
        Line(3, 9, 2, 2, 1)
        Line(4, 9, 2, 2, -5)
        Line(5, 2, 8, -3, -2)
        Line(6, 2, 8, 7, -2)
    else
        Line(1, 12, 2, 0, 5)
        Line(2, 12, 2, 0, -5)
        Line(3, 2, 12, -5, 0)
        Line(4, 2, 12, 5, 0)
    end
    PaintWindowControlButton(btn, btn._msuf2ControlHover, btn._msuf2ControlDown)
end

local function CreateWindowControlButton(parent, kind, tooltipTitle, tooltipText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(24, 24)
    local fill, edge = T.CreateSuperellipseLayers(btn, "_msuf2Control", 2, "BACKGROUND", "BORDER")
    btn._msuf2ControlFill = fill
    btn._msuf2ControlEdge = edge
    btn.SetWindowControlIcon = SetWindowControlIcon
    btn:SetScript("OnEnter", function(self)
        self._msuf2ControlHover = true
        PaintWindowControlButton(self, true, self._msuf2ControlDown)
    end)
    btn:SetScript("OnLeave", function(self)
        self._msuf2ControlHover = nil
        self._msuf2ControlDown = nil
        PaintWindowControlButton(self, false, false)
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._msuf2ControlDown = true
        PaintWindowControlButton(self, self._msuf2ControlHover, true)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._msuf2ControlDown = nil
        PaintWindowControlButton(self, self._msuf2ControlHover, false)
    end)
    btn:SetScript("OnEnable", function(self)
        PaintWindowControlButton(self, self._msuf2ControlHover, self._msuf2ControlDown)
    end)
    btn:SetScript("OnDisable", function(self)
        PaintWindowControlButton(self, false, false)
    end)
    AttachHistoryTooltip(btn, tooltipTitle, tooltipText)
    SetWindowControlIcon(btn, kind)
    return btn
end

function RefreshWindowControls(frame)
    frame = frame or M.frame
    if not frame then return end
    if frame.maximizeButton and frame.maximizeButton.SetWindowControlIcon then
        frame.maximizeButton:SetWindowControlIcon(frame._msuf2WindowState == "maximized" and "restore" or "maximize")
    end
end

local function CreateMinimizedBar(frame)
    if M.minimizedBar then return M.minimizedBar end
    local bar = T.Panel(UIParent, "MSUF2_MinimizedWindow", T.colors.bg, T.colors.border)
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

    SetWindowMetrics(ReadSavedWindowSize())
    local f = T.Panel(UIParent, "MSUF2_Window", T.colors.bg, T.colors.border)
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

    local nav = T.Panel(content, nil, T.colors.panelNav or T.colors.panel, T.colors.borderSoft)
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    f.nav = nav
    f._msufNavRail = nav
    f._msufNavStack = nav
    M.nav = nav
    BuildNav(nav)

    local host = T.Panel(content, nil, T.colors.panel, T.colors.borderSoft)
    host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    f.host = host
    f._msufMirrorHost = host
    if T.ApplyMenuAtmosphere then T.ApplyMenuAtmosphere(f, host, nav) end

    local status = T.Panel(host, nil, T.colors.header, T.colors.borderSoft)
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

    status.profileText = sbProfile
    status.editText = sbEdit
    status.combatText = sbCombat
    status.versionText = sbVersion
    status.text = sbProfile
    f.status = status
    function f:RefreshStatus()
        local profile = tostring(_G.MSUF_ActiveProfile or "Default")
        local edit = IsEditModeActive() and "On" or "Off"
        sbProfile:SetText("|cff4a90d9" .. L_PROFILE .. "|r |cffccd8e8" .. profile .. "|r  |cff3a4a66\194\183|r")
        if edit == "On" then
            sbEdit:SetText("|cff4ade80" .. L_EDIT_ON .. "|r  |cff3a4a66\194\183|r")
        else
            sbEdit:SetText("|cff5a6a88" .. L_EDIT_OFF .. "|r  |cff3a4a66\194\183|r")
        end
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            sbCombat:SetText("|cffef4444" .. L_IN_COMBAT .. "|r")
        else
            sbCombat:SetText("|cff22c55e" .. L_OUT_OF_COMBAT .. "|r")
        end
        local ver = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
        if type(ver) == "string" and ver ~= "" then
            sbVersion:SetText(ver:match("^%d") and ("v" .. ver) or ver)
        else
            sbVersion:SetText("v5.0 Beta 1")
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
        if M.Refresh then M.Refresh() end
        SyncGroupPagePreviewForKey(M.activeKey)
    end)
    f:SetScript("OnShow", function(self)
        if M.BlockCombatAction and M.BlockCombatAction() then
            self:Hide()
            return
        end
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
        CancelSearchBackgroundIndex()
        UnregisterStatusEvents()
        if W and type(W.CloseDropdown) == "function" then W.CloseDropdown() end
        if M.EndHistorySession then M.EndHistorySession() end
        ResetStatusIndicatorTestModeOnMenuExit()
        M.dashboardChangelogOpen = false
        lastBossPreviewActive = nil
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

local function GetBundledChangelog()
    local data = (type(ns) == "table" and ns.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" or type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then
        return nil
    end
    return data
end

local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local sectionHeader = opts.sectionHeader == true
    local left, right = sectionHeader and 0 or 14, sectionHeader and 0 or 14
    local bodyLeft = opts.bodyLeft or (sectionHeader and 16 or left)
    local top = opts.top or -130
    local headerH = sectionHeader and 42 or 48
    local contentW = max(120, (cardWidth or 420) - left - right)
    local scrollW = max(80, (cardWidth or 420) - bodyLeft - 44)

    local function RawFont(parentFrame, template, text, color, bump)
        local fs = parentFrame:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        if T.StyleFontString then
            T.StyleFontString(fs, color or T.colors.muted, bump or 0)
        elseif color and fs.SetTextColor then
            fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
        end
        fs:SetText(tostring(text or ""))
        return fs
    end

    if not sectionHeader then
        local line = parent:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top + 4)
        line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top + 4)
        line:SetHeight(1)
        line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)
    end

    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    if sectionHeader then
        header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top)
        header:SetHeight(headerH)
    else
        header:SetSize(contentW, headerH)
    end

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    headerBg:SetColorTexture(0, 0, 0, 0)

    local headerEdge = header:CreateTexture(nil, "BORDER")
    headerEdge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerEdge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerEdge:SetHeight(1)
    headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.44)

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.025)

    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    if sectionHeader then
        arrow:SetPoint("LEFT", header, "LEFT", 16, 0)
    else
        arrow:SetPoint("TOPRIGHT", header, "TOPRIGHT", -54, -9)
    end
    arrow:SetTexture(T.media.collapseArrow)

    local title = T.Font(header, "GameFontNormal", M.Tr(opts.title or "Changelog"), T.colors.text)
    if sectionHeader then
        title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    else
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -3)
        title:SetPoint("RIGHT", header, "RIGHT", -92, 0)
    end
    title:SetJustifyH("LEFT")

    local current = data and (data.currentVersion or (data.entries[1] and data.entries[1].version)) or nil
    local range = data and (data.rangeLabel or current or "") or M.Tr("No release notes bundled with this build.")
    local subtitle = RawFont(header, "GameFontDisableSmall", range, T.colors.dim, 0)
    if sectionHeader then
        subtitle:SetPoint("RIGHT", header, "RIGHT", -72, 0)
        subtitle:SetWidth(max(80, min(210, contentW - 190)))
        subtitle:SetJustifyH("RIGHT")
        subtitle:Hide()
    else
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        subtitle:SetPoint("RIGHT", header, "RIGHT", -8, 0)
        subtitle:SetJustifyH("LEFT")
    end

    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
    if sectionHeader then
        hint:SetPoint("RIGHT", header, "RIGHT", -16, 0)
    else
        hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -5)
    end
    hint:SetJustifyH("RIGHT")

    local summary = RawFont(parent, "GameFontHighlightSmall", "", T.colors.muted, 0)
    summary:SetPoint("TOPLEFT", parent, "TOPLEFT", bodyLeft + 10, top - headerH - 8)
    summary:SetWidth(max(80, (cardWidth or contentW) - bodyLeft - 28))
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(true) end

    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        summary:SetText(M.Tr("No release notes bundled with this build."))
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", bodyLeft + 2, top - headerH - 12)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -34, opts.bottom or 70)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)

    local y = -2
    local function AddText(text, fontObject, color, indent, gap, translate)
        local rawText = tostring(text or "")
        if translate and type(M.Tr) == "function" then
            rawText = M.Tr(rawText)
        end
        local fs = RawFont(child, fontObject or "GameFontHighlightSmall", rawText, color or T.colors.muted, 0)
        indent = indent or 0
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, y)
        fs:SetWidth(max(40, scrollW - indent - 2))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        fs:SetText(rawText)
        local h = (fs.GetStringHeight and fs:GetStringHeight()) or 0
        if h < 10 then h = 12 end
        y = y - h - (gap or 4)
        return fs
    end

    local function AddBullet(text, dotColor, textColor)
        dotColor = dotColor or T.colors.accent
        textColor = textColor or T.colors.muted
        local dot = child:CreateTexture(nil, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y - 6)
        dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.88)
        return AddText(text, "GameFontHighlightSmall", textColor, 18, 5, true)
    end

    local entries = data.entries
    local maxEntries = min(#entries, 4)
    for entryIndex = 1, maxEntries do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local date = tostring(entry.date or "")
            local heading = (date ~= "" and (version .. " - " .. date)) or version
            AddText(heading, "GameFontNormalSmall", T.colors.accent, 0, 8)

            local sections = entry.sections
            if type(sections) == "table" then
                for sectionIndex = 1, #sections do
                    local section = sections[sectionIndex]
                    if type(section) == "table" and type(section.bullets) == "table" and #section.bullets > 0 then
                        if sectionIndex > 1 then y = y - 3 end
                        local sectionTitle = tostring(section.title or "")
                        local isHighlights = sectionTitle == "Highlights"
                        AddText(sectionTitle, "GameFontNormalSmall", isHighlights and T.colors.accent or T.colors.accent2, 0, 4, true)
                        for bulletIndex = 1, #section.bullets do
                            AddBullet(
                                tostring(section.bullets[bulletIndex] or ""),
                                isHighlights and T.colors.accent2 or nil,
                                isHighlights and T.colors.text or nil
                            )
                        end
                    end
                end
            end
        end
    end

    child:SetHeight(max(1, math.abs(y) + 8))
    if T.StyleScrollFrame then T.StyleScrollFrame(scroll, parent) end

    local latest = entries[1]
    local sectionCount = 0
    if latest and type(latest.sections) == "table" then sectionCount = #latest.sections end
    local currentLabel = current or "Latest build"
    summary:SetText(M.Format(M.Tr("%s  -  %d sections. Click to view the bundled changelog."), currentLabel, sectionCount))

    local open = M.dashboardChangelogOpen == true
    local function PaintHeader(isOpen)
        if T.ApplyCollapseVisual then T.ApplyCollapseVisual(arrow, nil, isOpen) end
        if headerBg.SetColorTexture then
            headerBg:SetColorTexture(0, 0, 0, 0)
        end
        if headerEdge.SetColorTexture then
            headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], isOpen and 0.58 or 0.34)
        end
        hint:SetText(isOpen and M.Tr("Hide") or M.Tr("View"))
    end
    local function RefreshOpenState()
        M.dashboardChangelogOpen = open
        scroll:SetShown(open)
        summary:SetShown((not open) and not opts.hideSummaryWhenClosed)
        PaintHeader(open)
        if open then
            if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        elseif scroll._msuf2ScrollBar then
            scroll._msuf2ScrollBar:Hide()
        end
    end

    header:SetScript("OnClick", function()
        open = not open
        RefreshOpenState()
        if type(opts.onToggle) == "function" then opts.onToggle(open) end
    end)
    header:SetScript("OnEnter", function()
        if headerBg.SetColorTexture then headerBg:SetColorTexture(1, 1, 1, 0.025) end
    end)
    header:SetScript("OnLeave", function()
        PaintHeader(open)
    end)
    RefreshOpenState()
end

local function BuildDashboardUX(ctx)
    local root = ctx.wrapper
    local width = ctx.width or 760
    local x0, y0, gap = 12, -12, 16
    local layoutW = max(1, width - x0)
    local sideBySide = layoutW >= 760
    local sideW = sideBySide and min(330, max(300, math.floor(layoutW * 0.31))) or layoutW
    local mainW = sideBySide and (layoutW - sideW - gap) or layoutW
    local sideX = sideBySide and (x0 + mainW + gap) or x0

    local function Card(parent, title, x, y, w, h, bg, border)
        local card = T.Panel(parent or root, nil, bg or T.colors.panel2, border or T.colors.cardBorder or T.colors.borderSoft)
        card:SetPoint("TOPLEFT", parent or root, "TOPLEFT", x, y)
        card:SetSize(w, h)
        if title and title ~= "" then
            local label = T.Font(card, "GameFontNormal", M.Tr(title), T.colors.text)
            label:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
            card._msuf2Title = label
        end
        return card
    end

    local function SetDashboardGradient(texture, orientation, from, to)
        if not texture then return end
        from = from or { 1, 1, 1, 0 }
        to = to or { 1, 1, 1, 1 }
        local fromA = from[4] or 1
        local toA = to[4] or 1
        local media = T and T.media
        local horizontal = (orientation or "HORIZONTAL") == "HORIZONTAL"
        local path
        local color

        if horizontal then
            path = (toA >= fromA) and (media and media.gradHRev) or (media and media.gradH)
            color = (toA >= fromA) and to or from
        else
            path = (fromA >= toA) and (media and media.gradV) or (media and media.gradVRev)
            color = (fromA >= toA) and from or to
        end

        if path and path ~= "" then
            texture:SetTexture(path)
            texture:SetTexCoord(0, 1, 0, 1)
            if texture.SetVertexColor then
                texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
            end
        elseif texture.SetGradientAlpha then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradientAlpha(orientation or "HORIZONTAL", from[1], from[2], from[3], fromA, to[1], to[2], to[3], toA)
        elseif texture.SetGradient and CreateColor then
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            texture:SetGradient(orientation or "HORIZONTAL", CreateColor(from[1], from[2], from[3], fromA), CreateColor(to[1], to[2], to[3], toA))
        elseif texture.SetColorTexture then
            texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
        end
    end

    local function ApplyDashboardHeroGradient(card, w, h)
        if not (card and card.CreateTexture) or card._msuf2DashboardHeroGradient then return end
        card._msuf2DashboardHeroGradient = true

        local wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        wash:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(wash, "HORIZONTAL", { 0.020, 0.026, 0.064, 0.00 }, { 0.030, 0.210, 0.285, 0.16 })

        local top = card:CreateTexture(nil, "BACKGROUND", nil, 2)
        top:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
        top:SetHeight(max(54, min(96, floor((h or 190) * 0.42))))
        SetDashboardGradient(top, "VERTICAL", { 0.080, 0.320, 0.430, 0.08 }, { 0.020, 0.030, 0.070, 0.00 })

        local focus = card:CreateTexture(nil, "BACKGROUND", nil, 3)
        focus:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        focus:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(focus, "HORIZONTAL", { 0.080, 0.420, 0.560, 0.00 }, { 0.080, 0.420, 0.560, 0.05 })
    end

    local function Button(parent, text, x, y, w, h, onClick, skin)
        local btn = T.Button(parent, M.Tr(text or ""), w, h or 24)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
        end
        if skin == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
        if skin == "danger" and T.SkinDangerButton then T.SkinDangerButton(btn) end
        if onClick then btn:SetScript("OnClick", onClick) end
        return btn
    end

    local function Kicker(parent, text, x, y, color)
        local fs = T.Font(parent, "GameFontDisableSmall", string.upper(M.Tr(text or "")), color or T.colors.accent)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -14)
        return fs
    end

    local function Pill(parent, text, x, y, w, color)
        local pill = T.Panel(parent, nil, { 0.055, 0.070, 0.135, 0.92 }, { 0.160, 0.220, 0.430, 0.70 })
        pill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        pill:SetSize(w or 82, 20)
        local label = T.Font(pill, "GameFontDisableSmall", M.Tr(text or ""), color or T.colors.muted)
        label:SetPoint("CENTER", pill, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
        pill._msuf2Label = label
        return pill
    end

    local function AddTooltip(frame, title, text)
        if not (frame and frame.HookScript) then return end
        frame:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
            if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        frame:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    local function MakeDashboardActionCard(card, title, tooltip, onClick, showArrow)
        if not (card and card.CreateTexture and card.HookScript) then return card end
        card:EnableMouse(true)

        local hover = card:CreateTexture(nil, "BORDER", nil, 4)
        hover:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        hover:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        hover:SetColorTexture(0.240, 0.780, 0.940, 0.055)
        hover:Hide()
        card._msuf2DashboardActionHover = hover

        if showArrow then
            local arrow = T.Font(card, "GameFontNormal", ">", T.colors.dim)
            arrow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -18)
            arrow:SetJustifyH("RIGHT")
            card._msuf2DashboardActionArrow = arrow
        end

        card:HookScript("OnEnter", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Show() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then
                arrow:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 1)
            end
        end)
        card:HookScript("OnLeave", function(self)
            if self._msuf2DashboardActionHover then self._msuf2DashboardActionHover:Hide() end
            local arrow = self._msuf2DashboardActionArrow
            if arrow and arrow.SetTextColor then
                arrow:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
            end
        end)
        if onClick then card:SetScript("OnMouseUp", onClick) end
        AddTooltip(card, title, tooltip)
        return card
    end

    local function Select(pageKey)
        if M.SelectPage then M.SelectPage(pageKey) end
    end

    local function ToggleEditMode()
        local active = IsEditModeActive()
        if (not active) and IsEditModeCombatLocked() then
            if M.BlockCombatAction then M.BlockCombatAction() end
            RefreshDashboardEditModeButton()
            if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active)
        end
        RefreshMenuFramePriority()
        if C_Timer and C_Timer.After then C_Timer.After(0, RefreshMenuFramePriority) end
        RefreshDashboardEditModeButton()
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end

    local function CopyWagoLink()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf")
        end
    end

    local function ExportBackup()
        local fn = _G.MSUF_ExportSelectionToString
        if type(fn) == "function" then
            local ok, value = pcall(fn, "all")
            if ok and type(value) == "string" and value ~= "" and type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink("MSUF Profile Backup", value)
                return
            end
        end
        Select("profiles")
    end

    local function DashboardGlobalState()
        _G.MSUF_GlobalDB = _G.MSUF_GlobalDB or {}
        local gdb = _G.MSUF_GlobalDB
        gdb.global = (type(gdb.global) == "table") and gdb.global or {}
        gdb.global.dashboard = (type(gdb.global.dashboard) == "table") and gdb.global.dashboard or {}
        return gdb.global.dashboard
    end

    local function ActiveProfileKey()
        local key = tostring(_G.MSUF_ActiveProfile or "Default")
        if key == "" then key = "Default" end
        return key
    end

    local function WagoBackupConfirmed()
        local dash = DashboardGlobalState()
        local byProfile = dash.wagoProfileBackupConfirmed
        return type(byProfile) == "table" and byProfile[ActiveProfileKey()] == true
    end

    local function SetWagoBackupConfirmed(confirmed)
        local dash = DashboardGlobalState()
        dash.wagoProfileBackupConfirmed = (type(dash.wagoProfileBackupConfirmed) == "table") and dash.wagoProfileBackupConfirmed or {}
        local byProfile = dash.wagoProfileBackupConfirmed
        if confirmed == true then
            byProfile[ActiveProfileKey()] = true
        else
            byProfile[ActiveProfileKey()] = nil
        end
    end

    local function RefreshDashboard()
        if M.InvalidatePage then M.InvalidatePage("home") end
        if M.SelectPage then M.SelectPage("home") end
    end

    local function ConfirmWagoBackup()
        if WagoBackupConfirmed() then return end

        local function accept()
            SetWagoBackupConfirmed(true)
            RefreshDashboard()
        end

        if _G.StaticPopupDialogs and _G.StaticPopup_Show then
            local popup = _G.StaticPopupDialogs.MSUF2_WAGO_PROFILE_BACKUP_CONFIRM or {
                text = "%s",
                button1 = _G.YES or "Yes",
                button2 = _G.NO or "No",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
                OnAccept = accept,
            }
            popup.button1 = _G.YES or "Yes"
            popup.button2 = _G.NO or "No"
            popup.OnAccept = accept
            _G.StaticPopupDialogs.MSUF2_WAGO_PROFILE_BACKUP_CONFIRM = popup
            _G.StaticPopup_Show("MSUF2_WAGO_PROFILE_BACKUP_CONFIRM", M.Tr("Have you backed up this MSUF profile before using the Wago MSUF page?"))
            return
        end

        accept()
    end

    local function Percent(value, fallback)
        return math.floor(((tonumber(value) or fallback or 1) * 100) + 0.5)
    end

    local function Clamp(v, minV, maxV)
        v = tonumber(v) or minV
        if v < minV then return minV end
        if v > maxV then return maxV end
        return v
    end

    local function SnapPct(value, minPct, maxPct, stepPct)
        stepPct = stepPct or 1
        local pct = math.floor((tonumber(value) or 100) / stepPct + 0.5) * stepPct
        return Clamp(pct, minPct or 25, maxPct or 150)
    end

    local function SetSliderValueSafe(slider, value)
        if not (slider and slider.SetValue) then return end
        slider._msuf2Refreshing = true
        slider:SetValue(value)
        if slider.editBox and slider._msuf2FormatValue then slider.editBox:SetText(slider._msuf2FormatValue(value)) end
        if slider._msuf2UpdateFill then slider:_msuf2UpdateFill() end
        slider._msuf2Refreshing = nil
    end

    local function HideSliderValueBox(slider)
        if slider and slider.editBox then slider.editBox:Hide() end
        if slider and slider._msuf2StepButtons then
            for i = 1, #slider._msuf2StepButtons do
                slider._msuf2StepButtons[i]:Hide()
            end
        end
        if slider and slider._msuf2Title and slider._msuf2Title.SetFontObject then
            slider._msuf2Title:SetFontObject("GameFontHighlight")
        end
    end

    local function EnablePercentWheel(slider, minPct, maxPct, stepPct)
        if not slider then return end
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if not delta then return end
            local value = tonumber((self.GetValue and self:GetValue()) or 100) or 100
            value = value + ((delta > 0) and stepPct or -stepPct)
            self:SetValue(SnapPct(value, minPct, maxPct, stepPct))
        end)
    end

    local function PixelScale()
        if type(_G.MSUF_GetPixelPerfectScale) == "function" then
            local ok, v = pcall(_G.MSUF_GetPixelPerfectScale)
            if ok and tonumber(v) then return Clamp(v, 0.3, 1.5) end
        end
        if type(GetPhysicalScreenSize) == "function" then
            local _, h = GetPhysicalScreenSize()
            h = tonumber(h)
            if h and h > 0 then return Clamp(768 / h, 0.3, 1.5) end
        end
        return 1
    end

    local function GlobalState()
        local g = M.GetGeneralDB()
        g.UIScale = (type(g.UIScale) == "table") and g.UIScale or { Enabled = false, Scale = 1 }
        local ui = g.UIScale
        ui.Enabled = ui.Enabled == true
        ui.Scale = Clamp(ui.Scale, 0.3, 1.5)
        return g, ui
    end

    local function HasMovedFramesInEditMode()
        local g = M.GetGeneralDB and M.GetGeneralDB()
        if type(g) == "table" and g.hasMovedFramesInEditMode == true then return true end
        local st = rawget(_G, "MSUF_EditState")
        if type(st) == "table" and st.hasMovedFramesInEditMode == true then return true end

        local db = M.EnsureDB and M.EnsureDB() or _G.MSUF_DB
        if type(db) ~= "table" then return false end
        local defaults = {
            player = { -256, -180 },
            target = { 320, -180 },
            focus = { -260, -300 },
            targettarget = { 220, -300 },
            pet = { -275, -250 },
            boss = { 360, 230 },
            gf_party = { -400, 0 },
            gf_raid = { -500, 0 },
            gf_mythicraid = { -500, 0 },
        }
        for key, def in pairs(defaults) do
            local conf = db[key]
            if type(conf) == "table" then
                local x, y = tonumber(conf.offsetX), tonumber(conf.offsetY)
                if x and y and (math.abs(x - def[1]) > 0.5 or math.abs(y - def[2]) > 0.5) then
                    if type(g) == "table" then g.hasMovedFramesInEditMode = true end
                    return true
                end
            end
        end
        return false
    end

    local compactHeader = layoutW < 620
    local tinyHeader = layoutW < 430
    local headerH = tinyHeader and 184 or (compactHeader and 150 or 92)
    local header = Card(root, "Dashboard", x0, y0, layoutW, headerH, { 0.055, 0.070, 0.145, 0.82 }, T.colors.border)
    local actionX = compactHeader and 16 or max(16, layoutW - 456)
    local textW = compactHeader and (layoutW - 32) or max(110, actionX - 34)
    W.Text(header, "A calmer setup command center: start with movement, frames, group frames, or a safe profile import.", 16, -42, textW, T.colors.muted)
    local editW = tinyHeader and (layoutW - 32) or (compactHeader and floor((layoutW - 48) / 2) or 126)
    local importW = editW
    local resetW = tinyHeader and (layoutW - 32) or (compactHeader and (layoutW - 32) or 150)
    local actionY = compactHeader and -86 or -31
    local edit = Button(header, "Edit frames", actionX, actionY, editW, 28, ToggleEditMode, "primary")
    M.dashboardEditModeButton = edit
    AddTooltip(edit, "MSUF Edit Mode", "Drag frames to move them before tuning detailed settings.")
    RefreshDashboardEditModeButton()
    M.AddRefresher(ctx, RefreshDashboardEditModeButton)
    local import = Button(header, "Import profile", tinyHeader and actionX or (actionX + editW + 12), tinyHeader and (actionY - 36) or actionY, importW, 28, function() Select("profiles") end)
    AddTooltip(import, "Import profile", "Opens Profiles so you can back up first, then import safely.")
    local reset = Button(header, "Reset positions...", compactHeader and actionX or (actionX + editW + importW + 24), tinyHeader and (actionY - 72) or (compactHeader and (actionY - 36) or actionY), resetW, 28, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "reset")
        end
    end, "danger")
    AddTooltip(reset, "Reset Frame Positions", "Resets frame positions only. Profiles and menu settings stay intact.")

    local mainTop = y0 - headerH - 16
    local tinyHero = mainW < 390
    local heroH = tinyHero and 282 or (mainW < 560 and 218 or 190)
    local hero = Card(root, "", x0, mainTop, mainW, heroH, { 0.024, 0.050, 0.090, 0.90 }, { 0.085, 0.230, 0.340, 0.70 })
    ApplyDashboardHeroGradient(hero, mainW, heroH)
    Kicker(hero, "Recommended Start", 22, -24)
    local heroTitle = T.Font(hero, "GameFontNormalLarge", M.Tr("Build your unit frames in three clean steps."), T.colors.text)
    heroTitle:SetPoint("TOPLEFT", hero, "TOPLEFT", 22, -52)
    heroTitle:SetWidth(mainW - 44)
    heroTitle:SetJustifyH("LEFT")
    W.Text(hero, "Move frames first, tune the player frame, then configure group frames and auras. Advanced controls stay available without competing with the first-run path.", 22, -86, mainW - 44, T.colors.muted)
    if mainW >= 560 then
        Button(hero, "Edit frames", 22, -132, 104, 28, ToggleEditMode, "primary")
        Button(hero, "Set up Player", 138, -132, 118, 28, function() Select("uf_player") end)
        Button(hero, "Set up Group Frames", 268, -132, 156, 28, function() Select("gf_layout") end)
        Button(hero, "Import safely", 436, -132, 116, 28, function() Select("profiles") end)
    elseif tinyHero then
        Button(hero, "Edit frames", 22, -130, mainW - 44, 26, ToggleEditMode, "primary")
        Button(hero, "Set up Player", 22, -162, mainW - 44, 26, function() Select("uf_player") end)
        Button(hero, "Group Frames", 22, -194, mainW - 44, 26, function() Select("gf_layout") end)
        Button(hero, "Import safely", 22, -226, mainW - 44, 26, function() Select("profiles") end)
    else
        local actionW = max(96, math.floor((mainW - 56) / 2))
        Button(hero, "Edit frames", 22, -130, actionW, 26, ToggleEditMode, "primary")
        Button(hero, "Set up Player", 34 + actionW, -130, actionW, 26, function() Select("uf_player") end)
        Button(hero, "Group Frames", 22, -162, actionW, 26, function() Select("gf_layout") end)
        Button(hero, "Import safely", 34 + actionW, -162, actionW, 26, function() Select("profiles") end)
    end

    local featureTop = mainTop - heroH - 16
    local stackFeatures = mainW < 560
    local featureW = stackFeatures and mainW or math.floor((mainW - gap * 2) / 3)
    local function Feature(index, title, body, icon, pageKey)
        local x = stackFeatures and x0 or (x0 + ((index - 1) * (featureW + gap)))
        local y = stackFeatures and (featureTop - ((index - 1) * (142 + gap))) or featureTop
        local card = Card(root, "", x, y, featureW, 142)
        local ic = T.Font(card, "GameFontNormalLarge", icon, T.colors.accent)
        ic:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -20)
        local label = T.Font(card, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 18, -58)
        W.Text(card, body, 18, -86, featureW - 36, T.colors.muted)
        MakeDashboardActionCard(card, title, body, function() Select(pageKey) end, true)
    end
    Feature(1, "Unit Frames", "Player, target, focus, pet, and boss frame setup with one preview language.", "U", "uf_player")
    Feature(2, "Group Frames", "Party, Raid, and Mythic scopes with visible summaries.", "G", "gf_layout")
    Feature(3, "Auras", "Shared defaults plus per-unit overrides explained inline.", "A", "auras2")

    local featureBlockBottom = featureTop - (stackFeatures and ((142 * 3) + (gap * 2)) or 142)
    local sideTop = sideBySide and mainTop or (featureBlockBottom - 16)
    local profile = Card(root, "Active profile", sideX, sideTop, sideW, 108)
    local pText = T.Font(profile, "GameFontDisableSmall", "", T.colors.muted)
    pText:SetPoint("TOPLEFT", profile, "TOPLEFT", 16, -38)
    pText:SetWidth(sideW - 86)
    Pill(profile, "Safe", sideW - 56, -26, 42, T.colors.ok)
    local manageProfile = Button(profile, "Manage", 16, -66, 70, 22, function() Select("profiles") end)
    local exportProfile = Button(profile, "Export backup", 94, -66, 104, 22, ExportBackup)
    local duplicateProfile = Button(profile, "Duplicate", sideW - 98, -66, 82, 22, function() Select("profiles") end)
    AddTooltip(manageProfile, "Manage profile", "Open Profiles for rename, import, export, and profile maintenance.")
    AddTooltip(exportProfile, "Export backup", "Copies a full backup string for the current setup.")
    AddTooltip(duplicateProfile, "Duplicate profile", "Open Profiles to copy this setup into another profile.")
    local function RefreshProfileCard()
        pText:SetText(M.Format(M.Tr("%s - manual profile"), tostring(_G.MSUF_ActiveProfile or "Default")))
    end
    RefreshProfileCard()
    M.AddRefresher(ctx, RefreshProfileCard)

    local wagoTop = sideTop - 124
    local wago = Card(root, "Wago profile hub", sideX, wagoTop, sideW, 164, { 0.040, 0.080, 0.125, 0.92 }, { 0.140, 0.320, 0.430, 0.82 })
    W.Text(wago, "Browse shared MSUF imports, copy a backup first, then import on the Profiles page.", 16, -40, sideW - 32, T.colors.muted)
    Button(wago, "Browse Wago profiles", 16, -78, sideW - 32, 30, CopyWagoLink, "primary")
    Button(wago, "Backup current profile", 16, -116, math.floor((sideW - 40) / 2), 24, ExportBackup)
    Button(wago, "Import safely", 24 + math.floor((sideW - 40) / 2), -116, math.floor((sideW - 40) / 2), 24, function() Select("profiles") end)
    AddTooltip(wago, "Wago profile imports", "The Wago button opens a copyable search link. Importing stays on the Profiles page so backup and new-profile import are visible.")

    local checklistTop = wagoTop - 180
    local checklistH = 292
    local checklist = Card(root, "Setup checklist", sideX, checklistTop, sideW, checklistH)
    W.Text(checklist, "Useful for first-run orientation.", 16, -38, sideW - 32, T.colors.muted)
    local function Row(i, title, body, state, color, onClick, iconText)
        local row = Card(checklist, "", 16, -68 - ((i - 1) * 56), sideW - 32, 48, { 0.080, 0.095, 0.170, 0.72 }, T.colors.borderSoft)
        Pill(row, iconText or (i < 3 and "OK" or "!"), 10, -14, 28, color or T.colors.ok)
        local label = T.Font(row, "GameFontNormal", M.Tr(title), T.colors.text)
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 48, -9)
        W.Text(row, body, 48, -28, sideW - 132, T.colors.muted)
        Pill(row, state, sideW - 86, -14, 54, color or T.colors.ok)
        MakeDashboardActionCard(row, title, body, onClick, false)
    end
    local movedFrames = HasMovedFramesInEditMode()
    Row(1, "Profile ready", "Active profile is loaded.", "done", T.colors.ok, function() Select("profiles") end)
    Row(2, "Preview available", "Use pages to tune frames.", "done", T.colors.ok, function() Select("uf_player") end)
    Row(3, "Move frames", "Recommended before detail tuning.", movedFrames and "done" or "start", movedFrames and T.colors.ok or T.colors.accent2, ToggleEditMode, movedFrames and "OK" or "!")
    local wagoBackupConfirmed = WagoBackupConfirmed()
    Row(4, "Wago backup", "Confirm backup before using the Wago MSUF page.", wagoBackupConfirmed and "done" or "start", wagoBackupConfirmed and T.colors.ok or T.colors.accent2, ConfirmWagoBackup, wagoBackupConfirmed and "OK" or "!")

    local previewTop = checklistTop - checklistH - 16
    local preview = Card(root, "", sideX, previewTop, sideW, 150)
    Kicker(preview, "Live preview", 16, -18)
    local stage = T.Panel(preview, nil, { 0.015, 0.020, 0.038, 0.96 }, { 0.075, 0.105, 0.190, 0.75 })
    stage:SetPoint("TOPLEFT", preview, "TOPLEFT", 0, -48)
    stage:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", 0, 0)
    local sample = CreateFrame("Frame", nil, stage, T.Template and T.Template() or nil)
    local db = M.EnsureDB and M.EnsureDB() or _G.MSUF_DB or {}
    local playerConf = (type(db.player) == "table") and db.player or {}
    local bars = (type(db.bars) == "table") and db.bars or {}
    local rawW = Clamp(tonumber(playerConf.width) or 220, 90, 420)
    local rawH = Clamp(tonumber(playerConf.height) or 44, 20, 110)
    local classPowerH = (bars.showClassPower == true) and Clamp(tonumber(bars.classPowerHeight) or 4, 2, 18) or 0
    local frameScale = min(1.35, (sideW - 88) / rawW, 72 / (rawH + classPowerH + 8))
    if frameScale < 0.7 then frameScale = 0.7 end
    local function S(v) return math.floor((tonumber(v) or 0) * frameScale + 0.5) end
    local sampleW, sampleH = S(rawW), S(rawH)
    sample:SetSize(sampleW, sampleH)
    sample:SetPoint("CENTER", stage, "CENTER", 0, 0)
    if sample.SetBackdrop then
        sample:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
        sample:SetBackdropColor(0.02, 0.02, 0.025, 0.96)
        sample:SetBackdropBorderColor(0, 0, 0, 1)
    end
    local hpBg = sample:CreateTexture(nil, "BORDER")
    hpBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    hpBg:SetPoint("TOPLEFT", sample, "TOPLEFT", S(2), -S(2))
    hpBg:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -S(2), S(6))
    hpBg:SetVertexColor(0.08, 0.08, 0.085, 1)
    local hp = sample:CreateTexture(nil, "ARTWORK")
    hp:SetTexture(type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or "Interface\\Buttons\\WHITE8X8")
    hp:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 0, 0)
    hp:SetPoint("BOTTOMLEFT", hpBg, "BOTTOMLEFT", 0, 0)
    hp:SetWidth(max(1, (sampleW - S(4)) * 0.72))
    hp:SetVertexColor(0.12, 0.12, 0.13, 1)
    local powerH = Clamp(tonumber(playerConf.powerBarHeight) or tonumber(bars.powerBarHeight) or 3, 2, 12)
    local powerBg = sample:CreateTexture(nil, "BORDER")
    powerBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    powerBg:SetPoint("BOTTOMLEFT", sample, "BOTTOMLEFT", S(2), S(2))
    powerBg:SetPoint("BOTTOMRIGHT", sample, "BOTTOMRIGHT", -S(2), S(2))
    powerBg:SetHeight(max(2, S(powerH)))
    powerBg:SetVertexColor(0.06, 0.02, 0.08, 1)
    local power = sample:CreateTexture(nil, "ARTWORK")
    power:SetTexture(type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture() or "Interface\\Buttons\\WHITE8X8")
    power:SetPoint("TOPLEFT", powerBg, "TOPLEFT", 0, 0)
    power:SetPoint("BOTTOMLEFT", powerBg, "BOTTOMLEFT", 0, 0)
    power:SetWidth(max(1, (sampleW - S(4)) * 0.82))
    power:SetVertexColor(0.55, 0.17, 0.78, 1)
    if classPowerH > 0 then
        local cp = CreateFrame("Frame", nil, stage)
        cp:SetSize(sampleW, max(2, S(classPowerH)))
        cp:SetPoint("BOTTOM", sample, "TOP", 0, S(4))
        local gapPx = max(0, S(tonumber(bars.classPowerGap) or 0))
        local segW = math.floor((sampleW - (4 * gapPx)) / 5)
        for i = 1, 5 do
            local seg = cp:CreateTexture(nil, "ARTWORK")
            seg:SetTexture("Interface\\Buttons\\WHITE8X8")
            seg:SetPoint("TOPLEFT", cp, "TOPLEFT", (i - 1) * (segW + gapPx), 0)
            seg:SetPoint("BOTTOMLEFT", cp, "BOTTOMLEFT", (i - 1) * (segW + gapPx), 0)
            seg:SetWidth(i == 5 and (sampleW - ((i - 1) * (segW + gapPx))) or segW)
            seg:SetVertexColor(0.55, 0.17, 0.78, i <= 3 and 0.96 or 0.28)
        end
    end
    local sampleName = T.Font(sample, "GameFontNormal", tostring(_G.UnitName and _G.UnitName("player") or M.Tr("Player")), { 1, 1, 1, 1 })
    sampleName:SetPoint("LEFT", sample, "LEFT", S(10), 0)
    local sampleHp = T.Font(sample, "GameFontNormal", "439K - 100.0%", { 1, 1, 1, 1 })
    sampleHp:SetPoint("RIGHT", sample, "RIGHT", -S(8), 0)

    local recoveryTop = sideBySide and (featureBlockBottom - 16) or (previewTop - 166)
    local recoveryW = sideBySide and mainW or layoutW
    local recoveryOpen = M.dashboardRecoveryOpen == true
    local recoveryWrap = recoveryW < 620
    local recoveryH = recoveryOpen and (recoveryWrap and 154 or 122) or 42
    local recovery = Card(root, "", x0, recoveryTop, recoveryW, recoveryH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local head = CreateFrame("Button", nil, recovery)
    head:SetPoint("TOPLEFT", recovery, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", recovery, "TOPRIGHT", 0, 0)
    head:SetHeight(42)
    local headHover = head:CreateTexture(nil, "BACKGROUND")
    headHover:SetAllPoints()
    headHover:SetColorTexture(0, 0, 0, 0)
    local arrow = head:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(T.media.collapseArrow)
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
    if T.ApplyCollapseVisual then T.ApplyCollapseVisual(arrow, nil, recoveryOpen) end
    local recTitle = T.Font(head, "GameFontNormal", M.Tr("Display & recovery"), T.colors.text)
    recTitle:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    if recoveryW >= 520 then
        Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2)
    end
    head:SetScript("OnClick", function()
        M.dashboardRecoveryOpen = not recoveryOpen
        M.InvalidatePage("home")
        M.SelectPage("home")
    end)
    head:SetScript("OnEnter", function()
        if headHover.SetColorTexture then headHover:SetColorTexture(1, 1, 1, 0.025) end
    end)
    head:SetScript("OnLeave", function()
        if headHover.SetColorTexture then headHover:SetColorTexture(0, 0, 0, 0) end
    end)

    if recoveryOpen then
        local row3 = recoveryW < 520
        W.Text(recovery, "Reset tools, Wago access, and recovery shortcuts live here.", 16, -60, recoveryW - 32, T.colors.muted)
        Button(recovery, "Wago Profiles", 16, -94, 112, 22, CopyWagoLink, "primary")
        Button(recovery, "Print Help", 140, -94, 86, 22, function()
            if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help") end
        end)
        Button(recovery, "Discord", 238, -94, 80, 22, function()
            if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/JQnhZXnTAK") end
        end)
        Button(recovery, "Factory Reset All", recoveryWrap and 16 or (recoveryW - 152), recoveryWrap and -126 or -94, 136, 22, function()
            if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then pcall(_G.SlashCmdList["MIDNIGHTSUF"], "fullreset confirm") end
        end, "danger")
        if row3 then
            W.Text(recovery, "Factory reset affects every MSUF setting.", 160, -128, recoveryW - 176, T.colors.muted)
        end
    end

    local scalingTop = recoveryTop - recoveryH - 10
    local scalingOpen = M.dashboardScalingOpen == true
    local scalingColumns = (recoveryW >= 960) and 3 or ((recoveryW >= 680) and 2 or 1)
    local scalingH = scalingOpen and ((scalingColumns == 3) and 250 or ((scalingColumns == 2) and 382 or 548)) or 42
    local scaling = Card(root, "", x0, scalingTop, recoveryW, scalingH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local scaleHead = CreateFrame("Button", nil, scaling)
    scaleHead:SetPoint("TOPLEFT", scaling, "TOPLEFT", 0, 0)
    scaleHead:SetPoint("TOPRIGHT", scaling, "TOPRIGHT", 0, 0)
    scaleHead:SetHeight(42)
    local scaleHeadHover = scaleHead:CreateTexture(nil, "BACKGROUND")
    scaleHeadHover:SetAllPoints()
    scaleHeadHover:SetColorTexture(0, 0, 0, 0)
    local scaleArrow = scaleHead:CreateTexture(nil, "OVERLAY")
    scaleArrow:SetTexture(T.media.collapseArrow)
    scaleArrow:SetSize(10, 10)
    scaleArrow:SetPoint("LEFT", scaleHead, "LEFT", 16, 0)
    if T.ApplyCollapseVisual then T.ApplyCollapseVisual(scaleArrow, nil, scalingOpen) end
    local scaleTitle = T.Font(scaleHead, "GameFontNormal", M.Tr("Scaling"), T.colors.text)
    scaleTitle:SetPoint("LEFT", scaleArrow, "RIGHT", 8, 0)
    if recoveryW >= 520 then
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", Percent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", Percent(g.slashMenuScale, 1)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", Percent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
    end
    scaleHead:SetScript("OnClick", function()
        M.dashboardScalingOpen = not scalingOpen
        M.InvalidatePage("home")
        M.SelectPage("home")
    end)
    scaleHead:SetScript("OnEnter", function()
        if scaleHeadHover.SetColorTexture then scaleHeadHover:SetColorTexture(1, 1, 1, 0.025) end
    end)
    scaleHead:SetScript("OnLeave", function()
        if scaleHeadHover.SetColorTexture then scaleHeadHover:SetColorTexture(0, 0, 0, 0) end
    end)

    if scalingOpen then
        W.Text(scaling, "Use sliders for exact scale changes. Apply commits the selected value; Revert returns to the active value.", 16, -60, recoveryW - 32, T.colors.muted)

        local pendingGlobalEnabled, pendingGlobalScale, pendingMsufScale, pendingMenuScale
        local colGap = 24
        local colW = (scalingColumns == 3) and math.floor((recoveryW - 32 - (colGap * 2)) / 3)
            or ((scalingColumns == 2) and math.floor((recoveryW - 32 - colGap) / 2) or (recoveryW - 32))
        local globalX, globalTop = 16, -94
        local msufX = (scalingColumns == 3) and (16 + colW + colGap) or ((scalingColumns == 2) and (16 + colW + colGap) or 16)
        local msufTop = (scalingColumns == 3 or scalingColumns == 2) and -94 or -242
        local menuX = (scalingColumns == 3) and (16 + ((colW + colGap) * 2)) or 16
        local menuTop = (scalingColumns == 3) and -94 or ((scalingColumns == 2) and -242 or -390)

        local function AppliedGlobalScale()
            local _, ui = GlobalState()
            return ui.Enabled, Clamp(ui.Scale, 0.3, 1.5)
        end
        local function SelectedGlobalScale()
            local enabled, appliedScale = AppliedGlobalScale()
            local selectedEnabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or enabled
            local selectedScale = Clamp(pendingGlobalScale or appliedScale, 0.3, 1.5)
            return selectedEnabled, selectedScale, enabled, appliedScale
        end

        local function AppliedMsufScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.msufUiScale) or 1, 0.25, 1.5)
        end
        local function PendingMsufScale()
            return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 1.5)
        end
        local function AppliedMenuScale()
            local dbScale = M.GetGeneralDB()
            return Clamp(tonumber(dbScale.slashMenuScale) or 1, 0.25, 1.5)
        end
        local function PendingMenuScale()
            return Clamp(pendingMenuScale or AppliedMenuScale(), 0.25, 1.5)
        end

        W.Text(scaling, "Changes the global WoW UI scale through MSUF presets.", globalX, globalTop - 20, colW, T.colors.muted)
        local globalStatus = W.Text(scaling, "", globalX, globalTop - 40, colW, T.colors.muted)
        local globalScale = W.Slider(scaling, "Global UI Scale", 30, 150, 1, colW)
        HideSliderValueBox(globalScale)
        globalScale:ClearAllPoints()
        globalScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", globalX, globalTop - 64)
        if globalScale._msuf2SetLayoutWidth then globalScale:_msuf2SetLayoutWidth(colW) end
        if globalScale._msuf2Title then
            globalScale._msuf2Title:ClearAllPoints()
            globalScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", globalX, globalTop)
            globalScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(globalScale, 30, 150, 1)

        local globalApply, globalRevert
        local function RefreshGlobalScale()
            local selectedEnabled, selectedScale, appliedEnabled, appliedScale = SelectedGlobalScale()
            local applied = appliedEnabled and (Percent(appliedScale, 1) .. "%") or M.Tr("Off")
            local selected = selectedEnabled and (Percent(selectedScale, 1) .. "%") or M.Tr("Off")
            local changed = (selectedEnabled ~= appliedEnabled) or math.abs(selectedScale - appliedScale) > 0.001
            globalStatus:SetText(M.Format(M.Tr("Applied: %s   Selected: %s"), applied, selected))
            SetSliderValueSafe(globalScale, SnapPct(selectedScale * 100, 30, 150, 1))
            if globalApply then
                if changed then globalApply:Enable() else globalApply:Disable() end
                if globalApply.SetActive then globalApply:SetActive(changed) end
            end
            if globalRevert then
                if changed then globalRevert:Enable() else globalRevert:Disable() end
            end
        end
        globalScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 30, 150, 1)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingGlobalEnabled = true
            pendingGlobalScale = Clamp(pct / 100, 0.3, 1.5)
            RefreshGlobalScale()
        end)
        local function ApplyGlobalScale(enabled, value, preset)
            local dbScale, ui = GlobalState()
            ui.Enabled = enabled == true
            ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
            dbScale.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
            dbScale.globalUiScaleValue = ui.Enabled and ui.Scale or nil
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
                pcall(_G.MSUF_SetGlobalUiScale, ui.Scale, true)
            elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
                pcall(_G.MSUF_ResetGlobalUiScale, true)
            end
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false }) end
            RefreshGlobalScale()
        end
        Button(scaling, "1080p", globalX, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end)
        Button(scaling, "1440p", globalX + 60, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end)
        Button(scaling, "4K", globalX + 120, globalTop - 100, 42, 20, function() ApplyGlobalScale(true, 768 / 2160, "4k") end)
        Button(scaling, "Pixel", globalX + 170, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, PixelScale(), "pixel") end)
        globalApply = Button(scaling, "Apply", globalX, globalTop - 126, 72, 20, function()
            local selectedEnabled, selectedScale = SelectedGlobalScale()
            ApplyGlobalScale(selectedEnabled, selectedScale, selectedEnabled and "custom" or "auto")
        end, "primary")
        globalRevert = Button(scaling, "Revert", globalX + 82, globalTop - 126, 72, 20, function()
            pendingGlobalEnabled, pendingGlobalScale = nil, nil
            RefreshGlobalScale()
        end)
        Button(scaling, "Off", globalX + 164, globalTop - 126, 52, 20, function()
            pendingGlobalEnabled = false
            RefreshGlobalScale()
        end)

        W.Text(scaling, "Changes the actual MSUF unit frames in-game.", msufX, msufTop - 20, colW, T.colors.muted)
        local msufStatus = W.Text(scaling, "", msufX, msufTop - 40, colW, T.colors.muted)
        local msufScale = W.Slider(scaling, "MSUF Frame Scale", 25, 150, 5, colW)
        HideSliderValueBox(msufScale)
        msufScale:ClearAllPoints()
        msufScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", msufX, msufTop - 64)
        if msufScale._msuf2SetLayoutWidth then msufScale:_msuf2SetLayoutWidth(colW) end
        if msufScale._msuf2Title then
            msufScale._msuf2Title:ClearAllPoints()
            msufScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", msufX, msufTop)
            msufScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(msufScale, 25, 150, 5)

        local msufApply, msufRevert
        local function RefreshMsufScale()
            local applied = AppliedMsufScale()
            local pending = PendingMsufScale()
            local changed = math.abs(applied - pending) > 0.001
            msufStatus:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
            SetSliderValueSafe(msufScale, SnapPct(pending * 100, 25, 150, 5))
            if msufApply then
                if changed then msufApply:Enable() else msufApply:Disable() end
                if msufApply.SetActive then msufApply:SetActive(changed) end
            end
            if msufRevert then
                if changed then msufRevert:Enable() else msufRevert:Disable() end
            end
        end
        msufScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 25, 150, 5)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingMsufScale = pct / 100
            RefreshMsufScale()
        end)
        msufApply = Button(scaling, "Apply", msufX, msufTop - 100, 72, 20, function()
            local dbScale = M.GetGeneralDB()
            local scaleValue = PendingMsufScale()
            dbScale.msufUiScale = scaleValue
            pendingMsufScale = nil
            if type(_G.MSUF_ApplyMsufScale) == "function" then pcall(_G.MSUF_ApplyMsufScale, scaleValue) end
            if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false }) end
            local applyAll = _G.MSUF_ApplyAllSettings
            if type(applyAll) == "function" then pcall(applyAll) end
            RefreshMsufScale()
        end, "primary")
        msufRevert = Button(scaling, "Revert", msufX + 82, msufTop - 100, 72, 20, function()
            pendingMsufScale = nil
            RefreshMsufScale()
        end)

        W.Text(scaling, "Changes only this configuration menu window.", menuX, menuTop - 20, colW, T.colors.muted)
        local menuStatus = W.Text(scaling, "", menuX, menuTop - 40, colW, T.colors.muted)
        local menuScale = W.Slider(scaling, "MSUF Menu Scale", 25, 150, 5, colW)
        HideSliderValueBox(menuScale)
        menuScale:ClearAllPoints()
        menuScale:SetPoint("TOPLEFT", scaling, "TOPLEFT", menuX, menuTop - 64)
        if menuScale._msuf2SetLayoutWidth then menuScale:_msuf2SetLayoutWidth(colW) end
        if menuScale._msuf2Title then
            menuScale._msuf2Title:ClearAllPoints()
            menuScale._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", menuX, menuTop)
            menuScale._msuf2Title:SetWidth(colW)
        end
        EnablePercentWheel(menuScale, 25, 150, 5)

        local menuApply, menuRevert
        local function RefreshMenuScale()
            local applied = AppliedMenuScale()
            local pending = PendingMenuScale()
            local changed = math.abs(applied - pending) > 0.001
            menuStatus:SetText(M.Format(M.Tr("Applied: %d%%  Selected: %d%%"), Percent(applied, 1), Percent(pending, 1)))
            SetSliderValueSafe(menuScale, SnapPct(pending * 100, 25, 150, 5))
            if menuApply then
                if changed then menuApply:Enable() else menuApply:Disable() end
                if menuApply.SetActive then menuApply:SetActive(changed) end
            end
            if menuRevert then
                if changed then menuRevert:Enable() else menuRevert:Disable() end
            end
        end
        menuScale:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            local pct = SnapPct(value, 25, 150, 5)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            pendingMenuScale = pct / 100
            RefreshMenuScale()
        end)
        menuApply = Button(scaling, "Apply", menuX, menuTop - 100, 72, 20, function()
            local dbScale = M.GetGeneralDB()
            local scaleValue = PendingMenuScale()
            dbScale.slashMenuScale = scaleValue
            pendingMenuScale = nil
            if M.frame and M.frame.SetScale then M.frame:SetScale(EffectiveMenuScale(scaleValue)) end
            RefreshMenuScale()
        end, "primary")
        menuRevert = Button(scaling, "Revert", menuX + 82, menuTop - 100, 72, 20, function()
            pendingMenuScale = nil
            RefreshMenuScale()
        end)

        RefreshGlobalScale()
        RefreshMsufScale()
        RefreshMenuScale()
        M.AddRefresher(ctx, RefreshGlobalScale)
        M.AddRefresher(ctx, RefreshMsufScale)
        M.AddRefresher(ctx, RefreshMenuScale)
    end

    local changelogTop = scalingTop - scalingH - 10
    local changelogOpen = M.dashboardChangelogOpen == true
    local changelogH = changelogOpen and 360 or 42
    local changelog = Card(root, "", x0, changelogTop, recoveryW, changelogH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    BuildDashboardChangelog(changelog, recoveryW, {
        title = "Changelog",
        sectionHeader = true,
        top = 0,
        bottom = 18,
        hideSummaryWhenClosed = true,
        onToggle = function()
            M.InvalidatePage("home")
            M.SelectPage("home")
        end,
    })

    local supportTop = changelogTop - changelogH - 10
    local supportCompact = recoveryW < 560
    local supportH = supportCompact and 116 or 78
    local support = Card(root, "", x0, supportTop, recoveryW, supportH, { 0.030, 0.040, 0.078, 0.86 }, T.colors.borderSoft)
    local supportTitle = T.Font(support, "GameFontNormal", M.Tr("Support MSUF Development"), T.colors.text)
    supportTitle:SetPoint("TOPLEFT", support, "TOPLEFT", 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    if supportDesc.SetWordWrap then supportDesc:SetWordWrap(true) end
    if supportDesc.SetNonSpaceWrap then supportDesc:SetNonSpaceWrap(true) end

    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
    end
    local aboutText = M.Tr("by Mapko with the help from R41z0r")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        local displayVersion = aboutVer:match("^%d") and ("v" .. aboutVer) or aboutVer
        aboutText = M.Format(M.Tr("%s  -  by Mapko with the help from R41z0r"), displayVersion)
    end
    local supportDescH = (supportDesc.GetStringHeight and supportDesc:GetStringHeight()) or 0
    if supportDescH < 12 then supportDescH = 12 end
    local aboutY = -42 - supportDescH - 5
    local supportAbout = W.Text(support, aboutText, 16, aboutY, supportTextW, T.colors.muted)
    if supportAbout.SetWordWrap then supportAbout:SetWordWrap(true) end
    if supportAbout.SetNonSpaceWrap then supportAbout:SetNonSpaceWrap(true) end

    local supportAboutH = (supportAbout.GetStringHeight and supportAbout:GetStringHeight()) or 0
    if supportAboutH < 12 then supportAboutH = 12 end
    local supportTextBottom = math.abs(aboutY - supportAboutH)
    if supportCompact then
        supportH = max(supportH, floor(supportTextBottom + 24 + 24))
    else
        supportH = max(supportH, floor(supportTextBottom + 14))
    end
    support:SetHeight(supportH)

    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local supportLinks = {
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
    }
    local iconRow = CreateFrame("Frame", nil, support)
    iconRow:SetSize(160, 24)
    if supportCompact then
        iconRow:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 16, 12)
    else
        iconRow:SetPoint("RIGHT", support, "RIGHT", -16, 0)
    end
    local previous
    for i = 1, #supportLinks do
        local data = supportLinks[i]
        local btn = CreateFrame("Button", nil, iconRow)
        btn:SetSize(24, 24)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. data.texture)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        btn:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink(data.title, data.url)
            end
        end)
        AddTooltip(btn, data.title, data.tooltip)
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 10, 0)
        else
            btn:SetPoint("LEFT", iconRow, "LEFT", 0, 0)
        end
        previous = btn
    end

    local bottom = supportTop - supportH
    if sideBySide then bottom = min(bottom, previewTop - 150) end
    ctx:SetContentHeight(math.abs(bottom) + 42)
end

M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboardUX, version = 6 })

local function ApplyMenuFrameScale(frame)
    if not (frame and frame.SetScale) then return end
    local g = M.GetGeneralDB()
    frame:SetScale(EffectiveMenuScale(g.slashMenuScale))
    ApplyWindowResizeBounds(frame)
    ClampWindowSize(frame)
end

M.GetEffectiveMenuScale = EffectiveMenuScale
M.ApplyMenuFrameScale = ApplyMenuFrameScale

function M.Open(pageKey)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    if M.ApplyLocaleSelection then M.ApplyLocaleSelection() end
    local f = BuildWindow()
    if M.minimizedBar and M.minimizedBar.Hide then M.minimizedBar:Hide() end
    f._msuf2Minimized = nil
    ApplyMenuFrameScale(f)
    ApplyMenuFramePriority(f)
    f:Show()
    M.SelectPage(pageKey or M.activeKey or "home")
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
        ClearSearchRegistryPage(key)
        if key == "home" then M.dashboardEditModeButton = nil end
        local entry = M.cache[key]
        if entry and entry.wrapper then
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        M.cache[key] = nil
    else
        MarkSearchIndexDirty()
        for k in pairs(M.cache) do M.InvalidatePage(k) end
    end
end

_G.MSUF2_Open = function(pageKey) M.Open(pageKey) end
_G.MSUF2_Toggle = function(pageKey) M.Toggle(pageKey) end

_G.MSUF_OpenStandaloneOptionsWindow = function(pageKey) M.Open(pageKey or "home") end
_G.MSUF_ShowStandaloneOptionsWindow = function(pageKey) M.Open(pageKey or "home") end
_G.MSUF_HideStandaloneOptionsWindow = function()
    HideSlashMenuAndMinibar(M.frame)
end
_G.MSUF_OpenOptionsMenu = function() M.Open("home") end
_G.MSUF_OpenPage = function(pageKey) return M.SelectPage(pageKey or "home") end
_G.MSUF_SwitchMirrorPage = function(pageKey) return M.SelectPage(pageKey or "home") end
_G.MSUF_GetCurrentMirrorPage = function() return M.activeKey or "home" end
_G.MSUF_GetMirrorPages = function() return M.pages end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function()
        local win = M.frame
        local bar = M.minimizedBar
        local visible = (win and win.IsShown and win:IsShown())
            or (bar and bar.IsShown and bar:IsShown())
        if not visible then return end
        if M.BlockCombatAction then M.BlockCombatAction() end
        HideSlashMenuAndMinibar(win)
    end)
end

SLASH_MSUF2OPTIONS1 = "/msuf"
SlashCmdList["MSUF2OPTIONS"] = function(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = msg:lower()
    local cmd = msg:match("^(%S+)") or ""
    if cmd == "versiontest" then
        if type(_G.MSUF_VersionCheck_DebugFakeUpdate) == "function" then
            pcall(_G.MSUF_VersionCheck_DebugFakeUpdate)
        else
            print("|cffffd700MSUF:|r Version test helper is not loaded.")
        end
        return
    end
    if cmd == "help" or cmd == "reset" or cmd == "fullreset" or cmd == "absorb" or cmd == "analytics" then
        if cmd ~= "help" and M.BlockCombatAction and M.BlockCombatAction() then return end
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], msg)
        end
        return
    end
    if msg == "locale" or msg == "locales" or msg == "loc" then
        local total, missing = 0, 0
        if type(M.GetLocaleCoverage) == "function" then
            total, missing = M.GetLocaleCoverage()
        end
        local locale = ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
        print(string.format("|cff00b7ebMSUF2|r locale %s: %d keys seen, %d missing translations.", locale, total or 0, missing or 0))
        return
    end
    M.Open(ALIASES[msg] or msg or "home")
end

SLASH_MSUFOPTIONS1 = SLASH_MSUFOPTIONS1 or "/msufoptions"
SlashCmdList["MSUFOPTIONS"] = SlashCmdList["MSUFOPTIONS"] or function(msg)
    M.Open(ALIASES[tostring(msg or ""):lower()] or "home")
end

