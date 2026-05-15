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

local NAV = {
    { key = "home", label = "Dashboard" },
    { header = "Unit Frames", id = "unitframes", defaultOpen = true },
    { key = "uf_player", label = "Player", group = "unitframes" },
    { key = "uf_target", label = "Target", group = "unitframes" },
    { key = "uf_targettarget", label = "Target of Target", group = "unitframes" },
    { key = "uf_focus", label = "Focus", group = "unitframes" },
    { key = "uf_boss", label = "Boss Frames", group = "unitframes" },
    { key = "uf_pet", label = "Pet", group = "unitframes" },
    { header = "Group Frames", id = "groupframes", defaultOpen = true },
    { key = "gf_layout", label = "Layout", group = "groupframes" },
    { key = "gf_bars", label = "Health & Text", group = "groupframes" },
    { key = "gf_auras", label = "Buffs & Debuffs", group = "groupframes" },
    { key = "gf_indicators", label = "Indicators", group = "groupframes" },
    { header = "Global Style", id = "globalstyle", defaultOpen = true },
    { key = "opt_bars", label = "Bars", group = "globalstyle" },
    { key = "opt_fonts", label = "Fonts", group = "globalstyle" },
    { key = "auras2", label = "Unit Auras", group = "globalstyle" },
    { key = "opt_castbar", label = "Castbar", group = "globalstyle" },
    { key = "opt_colors", label = "Colors", group = "globalstyle" },
    { key = "opt_misc", label = "Miscellaneous", group = "globalstyle" },
    { key = "classpower", label = "Class Resources" },
    { key = "gameplay", label = "Gameplay" },
    { header = "Modules", id = "modules", defaultOpen = false },
    { key = "modules", label = "Style", group = "modules" },
    { key = "profiles", label = "Profiles" },
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

local SEARCH_KEYWORDS = {
    home = "dashboard start support links quick navigation edit mode move drag frames unitframe unit frames reset positions ui scale menu scale profiles wago discord patreon github curseforge paypal slash command addon options minimap help recover support search",
    uf_player = "unit frame unitframe player frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power",
    uf_target = "unit frame unitframe target frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power",
    uf_targettarget = "unit frame unitframe target of target tot frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power",
    uf_focus = "unit frame unitframe focus frame basics enable disable hide show width height scale size health power portrait text castbar focus kick interrupt auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power",
    uf_boss = "unit frame unitframe boss frames bossframe bossframes frame basics enable disable hide show width height scale size health power portrait text castbar boss range fade range check distance check out of range transparency alpha auras buffs debuffs preview anchoring anchor boss layout copy to edit mode move drag position x offset y offset color name hp power",
    uf_pet = "unit frame unitframe pet frame basics enable disable hide show width height scale size health power portrait text castbar auras buffs debuffs range fade range check distance check out of range transparency alpha preview anchoring anchor global anchor custom anchor copy to edit mode move drag position x offset y offset color name hp power",
    gf_layout = "group frames groupframes party raid mythic raid layout growth direction sorting role order frame scaling scale transparency alpha opacity anchoring anchor position move drag tooltip range fade preview show hide player solo enable width height spacing columns rows sorting role group number visibility",
    gf_bars = "group frames groupframes party raid health text power bar name hp text heal prediction absorb display range fade range check distance check out of range layout font size anchor offset opacity alpha smooth fill show power tank healer damage incoming heals shields debuff stripe dispel overlay",
    gf_auras = "group frames groupframes party raid buffs debuffs defensives externals text coloring private auras cooldown style aura utilities filter anchor icon size max buffs max debuffs custom buffs custom debuffs cooldown swipe masque pandemic dispel own buffs hots healer buffs raid debuffs boss debuffs",
    gf_indicators = "group frames groupframes party raid indicators status icons spell indicators corner indicators group number focus glow border dispel aggro threat role icon custom spells slots preview current show all marker raid marker ready check leader assist dead ghost offline afk dnd",
    opt_bars = "global style bars textures texture gradient gradient direction hp power absorb display highlight borders outline border aggro purge boss target glow bar colors background tint backdrop bg dark mode shared texture opacity alpha health texture power texture frame outline",
    opt_fonts = "global style fonts font family size outline shadow color text readability name hp power health spell cooldown bigger smaller text size name shortening realm names truncate font color",
    auras2 = "global style unit auras buffs debuffs icon size caps rows spacing sorting cooldown timer text tooltip private aura filter override dispel stealable only mine own buffs own debuffs pandemic reminders click through clickthrough aura position aura size",
    opt_castbar = "global style castbar textures outline shake fill direction empowered casts empower stages evoker augmentation devastation preservation hold release interrupt ready focus kick kick cooldown demon hunter demonhunter dh havoc vengeance devour consume magic disrupt counterspell pummel rebuke wind shear mind freeze skull bash muzzle spear hand strike counter shot quell silence name shortening latency spark channel ticks gcd global cooldown boss castbar target castbar focus castbar player castbar",
    opt_colors = "global style colors class bar colors background backgrond backround bg backdrop tint opacity alpha unitframe colors npc type colors bar colors dispel castbar mouseover highlight gameplay superellipse color swatches portrait colors power colors font color health color reaction color aura colors crosshair colors",
    opt_misc = "global style miscellaneous misc language localization localisation locale translation range fade range check range checker distance check out of range unit frame range check ui behavior tooltip tooltips combat settings general blizzard frames default frames hide blizzard disable blizzard update intervals performance minimap minimap icon target sounds version check menu behavior snap edge snap",
    classpower = "class resources combo points holy power soul shards chi maelstrom eclipse essence evoker runes runic power stagger brewmaster resource prediction auto hide detached power bar alternative mana behavior style quick actions class power resource bar alternate mana monk druid rogue paladin warlock death knight",
    gameplay = "gameplay combat crosshair click cast click cast clickthrough click-through focus target modifier mouseover interaction targeting spells mouse buttons keybind modifier ctrl shift alt fadenkreuz melee range spell target sound target lost mouseover heal click casting",
    modules = "modules style skins optional modules compatibility rounded unitframes portrait decoration minimap compartment addon compartment",
    profiles = "profiles profile management spec profiles specialization auto switch create copy delete reset import export legacy import wago active profile share string profile string backup restore",
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

local function SearchPlaceholderText()
    local text = M.Tr("Search")
    if type(text) ~= "string" or text == "" then text = "Search" end
    return text .. "..."
end

local function SearchBoxHasText(searchBox)
    if not (searchBox and searchBox.GetText) then return false end
    return (searchBox:GetText() or ""):match("%S") ~= nil
end

local function RefreshSearchPlaceholder(searchBox)
    if not searchBox then return end
    local text = SearchPlaceholderText()
    if searchBox.Instructions and searchBox.Instructions.SetText then
        searchBox.Instructions:SetText(text)
    end
    if searchBox._msuf2SearchPlaceholder and searchBox._msuf2SearchPlaceholder.SetText then
        searchBox._msuf2SearchPlaceholder:SetText(text)
    end
end

local function UpdateSearchPlaceholder(searchBox)
    if not searchBox then return end
    RefreshSearchPlaceholder(searchBox)
    local placeholder = searchBox._msuf2SearchPlaceholder
    if not placeholder then return end
    local focused = (searchBox.HasFocus and searchBox:HasFocus()) and true or false
    if focused or SearchBoxHasText(searchBox) then
        placeholder:Hide()
    else
        placeholder:Show()
    end
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
    _G.MSUF2_BossUnitframePreviewActive = active and true or nil
    if BossPagePreviewInCombat() then return end
    if type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
        _G.MSUF_ApplyBossUnitframePreviewState(active and true or false, reason or "MSUF2_BOSS_PAGE")
        return
    end
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
end

local IsEditModeActive
local lastBossPreviewActive
local lastBossPreviewFn

local function SyncBossPagePreviewForKey(key, force)
    local active = (key == "uf_boss")
        and M.frame and M.frame.IsShown and M.frame:IsShown()
    local fn = M.UnitPage and M.UnitPage.SetBossPagePreviewActive
    if not force and lastBossPreviewActive == active and lastBossPreviewFn == fn then return end
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

local ClearSearchRegistryPage

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

local function NormalizeSearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("\195\132", "ae"):gsub("\195\164", "ae")
    text = text:gsub("\195\150", "oe"):gsub("\195\182", "oe")
    text = text:gsub("\195\156", "ue"):gsub("\195\188", "ue")
    text = text:gsub("\195\159", "ss")
    text = text:gsub("[/\\_%-%.:;,%(%)]", " ")
    text = string.lower(text)
    text = text:gsub("[^%w%s]+", " ")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local function DisplaySearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%s+", " ")
    return TrimText(text)
end

local function AddSearchText(parts, text)
    if text == nil then return end
    text = DisplaySearchText(text)
    if text == "" then return end
    parts[#parts + 1] = text
    local translated = M.Tr(text)
    if translated and translated ~= text then parts[#parts + 1] = translated end
end

local function AddRawSearchText(parts, text)
    if text == nil then return end
    text = tostring(text)
    if text ~= "" then parts[#parts + 1] = text end
end

local MIN_SEARCH_QUERY_LEN = 2
local SEARCH_TEXT_MAX_LEN = 170
local SEARCH_BACKGROUND_STEP_SEC = 0.08
local SEARCH_INPUT_DEBOUNCE_SEC = 0.10
local SEARCH_MAX_RESULTS = 24
local SEARCH_VISIBLE_RESULTS = 12
local SEARCH_MIN_RESULT_SCORE = 40
local SEARCH_MAX_RAW_WORDS = 12
local SEARCH_MAX_QUERY_CLAUSES = 8
local SEARCH_MAX_TERMS_PER_CLAUSE = 18
local _searchRecords = nil
local _searchRecordsDirty = true
local _searchIndexing = false
local _searchIndexQueue = nil
local _searchInputSerial = 0
local _searchRegistrySerial = 0
local _searchAliasTypoKeys = nil
local _searchAliasTypoCache = {}
local _searchQueryClauseCacheNorm = nil
local _searchQueryClauseCacheClauses = nil
local _searchRegistry = {}
local _searchRegistryByPage = {}
M.searchRegistry = _searchRegistry

local function MarkSearchIndexDirty()
    _searchRecordsDirty = true
end

local function SearchCombatLocked()
    return (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
end

local function CancelSearchBackgroundIndex()
    _searchIndexing = false
    _searchIndexQueue = nil
end

local SEARCH_NOISE_TEXT = {
    [""] = true,
    ["x"] = true,
    ["+"] = true,
    ["-"] = true,
    ["<"] = true,
    [">"] = true,
    ["|"] = true,
}

local SEARCH_STOP_WORDS = {
    a = true,
    an = true,
    ["and"] = true,
    are = true,
    can = true,
    cant = true,
    change = true,
    changed = true,
    changing = true,
    configure = true,
    configured = true,
    customize = true,
    customise = true,
    ["do"] = true,
    does = true,
    doesnt = true,
    find = true,
    fixed = true,
    fix = true,
    ["for"] = true,
    get = true,
    help = true,
    how = true,
    i = true,
    ["in"] = true,
    is = true,
    it = true,
    make = true,
    my = true,
    need = true,
    ["not"] = true,
    of = true,
    on = true,
    ["or"] = true,
    please = true,
    pls = true,
    setting = true,
    settings = true,
    setup = true,
    thanks = true,
    the = true,
    thx = true,
    to = true,
    want = true,
    where = true,
    why = true,
    with = true,
    would = true,
    t = true,
    etc = true,
    wtf = true,
    dumb = true,
    stupid = true,
    plsfix = true,
    wie = true,
    kann = true,
    ich = true,
    ist = true,
    sind = true,
    das = true,
    die = true,
    der = true,
    den = true,
    dem = true,
    ein = true,
    eine = true,
    einer = true,
    mein = true,
    meine = true,
    nicht = true,
    warum = true,
    wo = true,
    was = true,
    aendern = true,
    andern = true,
    einstellen = true,
    einstellungen = true,
    finde = true,
    finden = true,
    bitte = true,
    du = true,
    fuer = true,
    fur = true,
    mal = true,
    man = true,
    mich = true,
    mir = true,
    mit = true,
    nur = true,
    und = true,
    oder = true,
}

local SEARCH_QUERY_ALIASES = {
    evoker = { "empowered", "empower", "empowered casts", "stage", "stages", "hold cast", "release cast", "quell", "essence", "augmentation", "devastation", "preservation" },
    devastation = { "evoker", "empowered", "empower", "empowered casts", "essence" },
    preservation = { "evoker", "empowered", "empower", "empowered casts", "essence" },
    augmentation = { "evoker", "empowered", "empower", "empowered casts", "essence", "ebon might" },
    empower = { "empowered", "empowered casts", "stage", "stages", "hold cast", "release cast" },
    empowered = { "empower", "empowered casts", "stage", "stages", "hold cast", "release cast" },
    stage = { "empowered", "empowered casts", "blink", "castbar" },
    stages = { "empowered", "empowered casts", "blink", "castbar" },

    demonhunter = { "demon hunter", "dh", "havoc", "vengeance", "disrupt", "consume magic", "devour", "interrupt", "kick", "interrupt ready" },
    dh = { "demon hunter", "demonhunter", "havoc", "vengeance", "disrupt", "consume magic", "devour", "interrupt", "kick", "interrupt ready" },
    havoc = { "demon hunter", "demonhunter", "dh", "disrupt", "consume magic", "interrupt", "kick" },
    vengeance = { "demon hunter", "demonhunter", "dh", "disrupt", "consume magic", "interrupt", "kick" },
    devour = { "consume", "consume magic", "purge", "dispel", "disrupt", "interrupt", "kick", "interrupt ready" },
    consume = { "consume magic", "devour", "purge", "dispel", "interrupt", "kick" },
    disrupt = { "demon hunter", "demonhunter", "dh", "interrupt", "kick", "focus kick", "interrupt ready" },

    kick = { "interrupt", "interrupt ready", "focus kick", "counterspell", "disrupt", "pummel", "rebuke", "wind shear", "mind freeze", "muzzle", "skull bash", "spear hand strike", "counter shot", "quell", "silence" },
    kicks = { "interrupt", "interrupt ready", "focus kick", "counterspell", "disrupt", "pummel", "rebuke", "wind shear", "mind freeze", "muzzle", "skull bash", "spear hand strike", "counter shot", "quell", "silence" },
    interrupt = { "kick", "interrupt ready", "focus kick", "counterspell", "disrupt", "pummel", "rebuke", "wind shear", "mind freeze", "muzzle", "skull bash", "spear hand strike", "counter shot", "quell", "silence" },
    interrupts = { "kick", "interrupt", "interrupt ready", "focus kick" },
    counterspell = { "interrupt", "kick", "interrupt ready", "focus kick" },
    pummel = { "interrupt", "kick", "interrupt ready" },
    rebuke = { "interrupt", "kick", "interrupt ready" },
    windshear = { "wind shear", "interrupt", "kick", "interrupt ready" },
    silence = { "interrupt", "kick", "interrupt ready" },
    quell = { "evoker", "interrupt", "kick", "interrupt ready" },

    cast = { "castbar", "cast bar", "spell name", "channel", "gcd" },
    casting = { "castbar", "cast bar", "spell name", "channel", "gcd" },
    castbar = { "cast bar", "casts", "casting", "spell name", "channel", "gcd" },
    castbars = { "castbar", "cast bar", "casts", "casting", "spell name", "channel", "gcd" },
    zauberleiste = { "castbar", "cast bar", "casts", "casting" },

    background = { "bar background tint", "background tint", "background opacity", "background alpha", "backdrop", "bg", "bar colors", "transparency", "alpha", "unitframe colors" },
    backgrond = { "background", "bar background tint", "background tint", "bg" },
    backgroud = { "background", "bar background tint", "background tint", "bg" },
    backround = { "background", "bar background tint", "background tint", "bg" },
    bakground = { "background", "bar background tint", "background tint", "bg" },
    hintergrund = { "background", "bar background tint", "background tint", "bg" },
    bg = { "background", "bar background tint", "background tint", "background opacity", "background alpha" },
    backdrop = { "background", "bar background tint", "background tint", "bg" },
    alpha = { "opacity", "transparency", "fade", "background alpha", "in combat", "out of combat" },
    opacity = { "alpha", "transparency", "fade", "background opacity", "in combat", "out of combat" },
    transparent = { "transparency", "alpha", "opacity", "fade" },
    transparency = { "alpha", "opacity", "fade", "background" },
    fade = { "alpha", "opacity", "transparency", "range fade", "out of range" },
    fades = { "fade", "alpha", "opacity", "range fade", "out of range" },
    faded = { "fade", "alpha", "opacity", "range fade", "out of range" },
    range = { "range fade", "out of range", "range alpha", "range check", "distance", "distance check" },
    rangecheck = { "range check", "range fade", "out of range", "distance check", "unit frame range check", "out of range alpha", "range fade affects" },
    rangechecker = { "range check", "range fade", "out of range", "distance check", "unit frame range check" },
    distance = { "range", "range fade", "out of range", "range check", "distance check", "alpha" },
    distancecheck = { "range check", "range fade", "out of range", "distance check", "unit frame range check" },
    outofrange = { "out of range", "range fade", "range alpha", "range check", "distance" },
    check = { "range check", "range fade", "out of range", "distance check", "ready check", "version check" },
    checker = { "check", "range check", "range fade", "out of range" },
    checking = { "check", "range check", "range fade", "out of range" },
    reichweite = { "range", "range fade", "out of range", "range check", "distance" },
    reichweiten = { "range", "range fade", "out of range", "range check", "distance" },
    reichweitencheck = { "range check", "range fade", "out of range", "distance check" },
    entfernung = { "distance", "range", "range fade", "out of range", "range check" },
    ausserhalb = { "out of range", "range fade", "range check" },
    misc = { "miscellaneous", "global style", "tooltips", "blizzard frames", "update intervals", "language" },
    miscellaneous = { "misc", "global style", "tooltips", "blizzard frames", "update intervals", "language" },
    verschiedenes = { "misc", "miscellaneous", "global style", "tooltips", "blizzard frames", "update intervals", "language" },

    move = { "edit mode", "position", "positions", "drag", "x offset", "y offset", "anchor", "anchoring" },
    moving = { "edit mode", "position", "positions", "drag", "x offset", "y offset", "anchor", "anchoring" },
    drag = { "edit mode", "move", "position", "x offset", "y offset" },
    position = { "positions", "move", "edit mode", "x offset", "y offset", "anchor", "anchoring" },
    positions = { "position", "move", "edit mode", "x offset", "y offset", "anchor", "anchoring", "reset positions" },
    anchor = { "anchoring", "position", "move", "attach", "global anchor", "custom anchor" },
    anchoring = { "anchor", "position", "move", "attach", "global anchor", "custom anchor" },
    unitframe = { "unit frame", "unit frames", "player frame", "target frame", "focus frame", "boss frame", "frame basics", "anchoring", "edit mode" },
    unitframes = { "unit frame", "unit frames", "player frame", "target frame", "focus frame", "boss frame", "frame basics", "anchoring", "edit mode" },
    unitfram = { "unitframe", "unit frame", "unit frames", "frame basics", "anchoring", "edit mode" },
    unitfrme = { "unitframe", "unit frame", "unit frames", "frame basics", "anchoring", "edit mode" },
    player = { "player frame", "playerframe" },
    target = { "target frame", "targetframe" },
    focus = { "focus frame", "focusframe" },
    pet = { "pet frame", "petframe" },
    fram = { "frame", "unit frame", "frames", "frame basics" },
    frame = { "unit frame", "frames", "unitframe", "frame basics" },
    frames = { "unit frames", "unitframe", "frame basics", "edit mode" },
    playerframe = { "player frame", "move player frame", "drag player frame", "player position", "unit frame", "frame basics", "anchoring", "edit mode" },
    targetframe = { "target frame", "move target frame", "drag target frame", "target position", "unit frame", "frame basics", "anchoring", "edit mode" },
    focusframe = { "focus frame", "move focus frame", "drag focus frame", "focus position", "unit frame", "frame basics", "anchoring", "edit mode", "focus kick" },
    petframe = { "pet frame", "move pet frame", "drag pet frame", "pet position", "unit frame", "frame basics", "anchoring", "edit mode" },
    bossframe = { "boss frame", "boss frames", "unit frame", "boss layout" },
    bossframes = { "boss frame", "boss frames", "unit frame", "boss layout", "boss preview" },
    size = { "width", "height", "scale", "frame basics", "frame scaling" },
    resize = { "size", "width", "height", "scale", "frame basics", "frame scaling" },
    bigger = { "size", "scale", "width", "height", "font size" },
    smaller = { "size", "scale", "width", "height", "font size" },
    big = { "bigger", "size", "scale", "width", "height", "font size" },
    small = { "smaller", "size", "scale", "width", "height", "font size", "text size", "icon size" },
    scale = { "size", "frame scaling", "menu scale", "ui scale" },

    hp = { "health", "health text", "health bar", "leben" },
    health = { "hp", "health text", "health bar", "life", "leben" },
    leben = { "health", "hp", "health bar", "health text" },
    name = { "name text", "text", "font", "name shortening" },
    names = { "name text", "text", "font", "name shortening" },
    text = { "font", "fonts", "name text", "health text", "power text", "spell name" },
    font = { "fonts", "text", "font size", "outline", "shadow" },
    fonts = { "font", "text", "font size", "outline", "shadow" },
    mana = { "power", "power bar", "alternative mana", "alt mana" },
    power = { "mana", "power bar", "class resources", "resource" },
    resource = { "class resources", "classpower", "power", "combo points", "essence" },
    resources = { "class resources", "classpower", "power", "combo points", "essence" },

    profile = { "profiles", "import", "export", "copy profile", "spec profiles", "wago" },
    profiles = { "profile", "import", "export", "copy profile", "spec profiles", "wago" },
    import = { "profiles", "profile", "import string", "wago", "legacy import" },
    export = { "profiles", "profile", "export string", "copy profile", "wago" },
    wago = { "profiles", "import", "export", "profile string" },
    reload = { "refresh", "apply", "not updating", "profile", "reset" },
    reset = { "reset positions", "factory reset", "profile reset", "profiles" },
    broken = { "not updating", "reset positions", "profile reset", "reload", "factory reset" },
    broke = { "broken", "not updating", "reset positions", "profile reset", "reload" },
    bugged = { "broken", "not updating", "reload", "reset positions" },
    wrong = { "not updating", "colors", "profile", "reset" },
    missing = { "not visible", "hidden", "invisible", "gone", "load conditions" },
    gone = { "missing", "not visible", "hidden", "invisible" },
    invisible = { "not visible", "hidden", "alpha", "transparency", "range fade" },
    hidden = { "hide", "show", "enable", "disable", "not visible" },
    show = { "enable", "visible", "not hidden" },
    hide = { "disable", "hidden", "not visible" },
    disabled = { "enable", "show", "frame basics" },
    enabled = { "enable", "show", "frame basics" },
    offscreen = { "reset positions", "move", "edit mode", "position" },
    overlap = { "text layer", "position", "anchor", "offset", "frame level" },
    overlapping = { "overlap", "text layer", "position", "anchor", "offset" },
    lag = { "performance", "update intervals", "auras", "cooldown", "filters" },
    fps = { "performance", "update intervals", "auras", "cooldown", "filters" },
    bad = { "wrong", "broken", "performance", "lag", "fps" },
    performance = { "update intervals", "auras", "cooldown", "filters", "range fade" },
    combat = { "combat lockdown", "in combat", "out of combat", "alpha", "settings" },
    lockdown = { "combat lockdown", "combat", "protected frames", "reload" },

    raidframes = { "group frames", "groupframes", "raid frames", "raid frame", "raid", "party", "layout", "group layout", "anchoring", "move raid frames" },
    partyframes = { "group frames", "groupframes", "party frames", "party frame", "party", "raid", "layout", "group layout", "anchoring", "move party frames" },
    gruppenframes = { "group frames", "party", "raid", "layout" },
    raid = { "group frames", "groupframes", "raid frames", "raid frame", "layout", "party", "anchoring", "move raid frames" },
    party = { "group frames", "groupframes", "party frames", "party frame", "layout", "raid", "anchoring", "move party frames" },
    group = { "group frames", "party", "raid", "layout" },
    groupframes = { "group frames", "party", "raid", "layout" },
    debuff = { "debuffs", "auras", "aura", "buffs" },
    debuffs = { "debuff", "auras", "aura", "buffs" },
    buff = { "buffs", "auras", "aura", "debuffs" },
    buffs = { "buff", "auras", "aura", "debuffs" },
    aura = { "auras", "buffs", "debuffs", "private auras", "cooldown", "aura filters" },
    auras = { "aura", "buffs", "debuffs", "private auras", "cooldown", "aura filters" },
    hot = { "hots", "healer buffs", "own buffs", "aura indicators", "group buffs" },
    hots = { "hot", "healer buffs", "own buffs", "aura indicators", "group buffs" },
    own = { "only mine", "own buffs", "own debuffs", "player only", "aura filters" },
    personal = { "only mine", "own buffs", "own debuffs", "player only", "aura filters" },
    spellid = { "spell id", "custom spells", "custom auras", "aura utilities" },
    spellids = { "spell id", "custom spells", "custom auras", "aura utilities" },
    bossdebuff = { "boss debuffs", "raid debuffs", "custom auras", "private auras" },
    bossdebuffs = { "boss debuffs", "raid debuffs", "custom auras", "private auras" },
    private = { "private auras", "auras", "raid mechanics" },
    dispel = { "dispel overlay", "dispellable debuffs", "magic", "curse", "poison", "disease" },
    stealable = { "auras", "buffs", "purge", "dispel", "spellsteal" },
    purge = { "dispel", "stealable", "auras", "buffs" },
    pandemic = { "auras", "cooldown text", "debuffs", "timer" },
    timer = { "cooldown text", "aura timers", "cast time", "combat timer" },
    cooldown = { "cooldown text", "cooldown swipe", "aura timers", "interrupt ready" },
    cooldowns = { "cooldown", "cooldown text", "cooldown swipe", "aura timers", "interrupt ready" },
    absorb = { "absorbs", "absorb display", "heal prediction", "health" },
    absorbs = { "absorb", "absorb display", "heal prediction", "health" },
    heal = { "heal prediction", "incoming heals", "health", "healer" },
    aggro = { "threat", "aggro", "highlight borders", "indicators" },
    threat = { "aggro", "highlight borders", "indicators" },

    blizzard = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" },
    default = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" },
    unlock = { "edit mode", "move", "drag", "frames unlocked", "lock frames" },
    locked = { "edit mode", "move", "drag", "frames locked", "lock frames" },
    solo = { "show solo", "show player solo", "party frames solo", "group frames" },
    self = { "player", "show player", "hide player", "party frames" },
    tooltip = { "tooltips", "unitframe tooltips", "mouseover tooltip" },
    tooltips = { "tooltip", "unitframe tooltips", "mouseover tooltip" },
    language = { "locale", "localization", "translation", "sprache" },
    sprache = { "language", "locale", "localization", "translation" },
    click = { "click cast", "clickthrough", "click-through", "mouse", "mouseover", "target modifier" },
    clickcast = { "click cast", "click casting", "mouse", "targeting" },
    clickthrough = { "click-through", "click through", "mouse", "auras", "unitframe tooltips" },
    mouseover = { "mouse", "mouseover highlight", "tooltip", "click cast", "targeting" },
    menu = { "dashboard", "menu scale", "ui scale", "search", "support" },
    window = { "menu", "dashboard", "reset positions", "ui scale" },
    ui = { "ui scale", "menu scale", "dashboard" },

    unit = { "unit frame", "unit frames", "unitframe", "frame basics" },
    units = { "unit frame", "unit frames", "unitframe", "frame basics" },
    einheit = { "unit", "unit frame", "unitframe" },
    einheiten = { "unit", "unit frames", "unitframe" },
    einheitenfenster = { "unit frame", "unitframe", "frames" },
    spieler = { "player", "player frame", "playerframe" },
    spielerframe = { "player frame", "playerframe", "unit frame" },
    ziel = { "target", "target frame", "targetframe" },
    zielframe = { "target frame", "targetframe", "unit frame" },
    zielziel = { "target of target", "targettarget", "tot" },
    tot = { "target of target", "targettarget", "target target" },
    targettarget = { "target of target", "tot", "target target" },
    fokus = { "focus", "focus frame", "focusframe", "focus kick" },
    fokusframe = { "focus frame", "focusframe", "focus kick" },
    begleiter = { "pet", "pet frame", "petframe" },
    haustier = { "pet", "pet frame", "petframe" },

    enable = { "show", "visible", "frame basics", "aktivieren" },
    disable = { "hide", "hidden", "frame basics", "deaktivieren" },
    visible = { "show", "enable", "sichtbar" },
    aktivieren = { "enable", "show", "visible" },
    deaktivieren = { "disable", "hide", "hidden" },
    anzeigen = { "show", "visible", "enable" },
    ausblenden = { "hide", "hidden", "disable" },
    sichtbar = { "visible", "show", "enable" },
    unsichtbar = { "invisible", "hidden", "alpha", "transparency" },
    versteckt = { "hidden", "hide", "disable" },
    verschieben = { "move", "drag", "position", "edit mode", "anchor" },
    bewegen = { "move", "drag", "position", "edit mode" },
    ziehen = { "drag", "move", "edit mode" },
    verankern = { "anchor", "anchoring", "position" },
    anker = { "anchor", "anchoring", "position" },
    koordinaten = { "x offset", "y offset", "position", "anchor" },
    editmode = { "edit mode", "move", "drag", "position" },
    loadconditions = { "load conditions", "visibility", "show", "hide" },
    breite = { "width", "size", "resize", "frame basics" },
    hoehe = { "height", "size", "resize", "frame basics" },
    groesse = { "size", "resize", "scale", "width", "height" },
    skalierung = { "scale", "size", "frame scaling", "ui scale" },

    layout = { "group frames", "frame basics", "growth", "sorting", "anchoring" },
    sorting = { "sort", "role order", "group frames", "layout" },
    sortierung = { "sorting", "role order", "group frames", "layout" },
    growth = { "growth direction", "layout", "group frames" },
    spalten = { "columns", "layout", "group frames" },
    reihen = { "rows", "layout", "auras", "group frames" },
    rolle = { "role", "role icon", "sorting", "tank", "healer", "dps" },
    role = { "role icon", "sorting", "tank", "healer", "dps" },
    groupnumber = { "group number", "indicators", "group frames" },
    tank = { "role icon", "group indicators", "sorting" },
    healer = { "role icon", "healer buffs", "group indicators" },
    dps = { "role icon", "group indicators", "sorting" },

    healthbar = { "health bar", "health", "hp", "bar colors" },
    powerbar = { "power bar", "power", "mana", "class resources" },
    lebensbalken = { "health bar", "health", "hp" },
    energieleiste = { "power bar", "power", "mana" },
    manabar = { "mana", "power bar", "power" },
    color = { "colors", "bar colors", "unitframe colors", "class colors" },
    colours = { "colors", "color", "bar colors" },
    farbe = { "colors", "color", "bar colors", "class colors" },
    farben = { "colors", "color", "bar colors", "class colors" },
    klassfarbe = { "class color", "class colors", "health color" },
    classcolor = { "class color", "class colors", "health color" },
    reaction = { "reaction color", "npc type colors", "colors" },
    npc = { "npc type colors", "reaction color", "colors" },
    highlight = { "mouseover highlight", "highlight borders", "colors", "bars" },

    fontsize = { "font size", "text size", "fonts", "text" },
    textsize = { "text size", "font size", "fonts", "text" },
    schrift = { "font", "fonts", "text", "font size" },
    schriftart = { "font", "fonts", "font family" },
    schriftgroesse = { "font size", "text size", "fonts" },
    namen = { "names", "name text", "name shortening" },
    realm = { "realm names", "name shortening", "short names" },
    server = { "realm names", "name shortening", "short names" },
    truncate = { "name shortening", "short names", "max name length" },
    nameshortening = { "name shortening", "short names", "truncate names", "realm names" },
    healthtext = { "health text", "hp text", "text", "fonts" },
    powertext = { "power text", "mana text", "text", "fonts" },
    nametext = { "name text", "text", "fonts", "name shortening" },

    portrait = { "portraits", "portrait mode", "class icon", "2d portrait", "3d portrait" },
    portraits = { "portrait", "portrait mode", "class icon" },
    avatar = { "portrait", "portraits", "class icon" },
    portraet = { "portrait", "portraits", "class icon" },
    portraitdeko = { "portrait decoration", "modules", "style" },
    castbalken = { "castbar", "cast bar", "casting" },
    zauberbalken = { "castbar", "cast bar", "casting" },
    spell = { "spell name", "castbar", "auras", "spell id" },
    spellname = { "spell name", "castbar", "name shortening" },
    globalcooldown = { "gcd", "global cooldown", "castbar" },
    interruptready = { "interrupt ready", "focus kick", "kick", "castbar" },
    kanal = { "channel", "channel ticks", "castbar" },
    kanalisieren = { "channel", "channel ticks", "castbar" },
    unterbrechen = { "interrupt", "kick", "focus kick", "interrupt ready" },
    fokuskick = { "focus kick", "interrupt", "kick", "castbar" },

    stack = { "stacks", "aura stack count", "auras" },
    stacks = { "stack", "aura stack count", "auras" },
    stapel = { "stacks", "stack", "auras" },
    cooldowntext = { "cooldown text", "timer", "auras" },
    swipe = { "cooldown swipe", "auras", "cooldown" },
    staerkungszauber = { "buffs", "buff", "auras" },
    schwaechungszauber = { "debuffs", "debuff", "auras" },
    zauber = { "spell", "auras", "castbar", "spell id" },
    defensives = { "defensives", "externals", "group buffs", "auras" },
    externals = { "defensives", "external cooldowns", "group buffs", "auras" },

    gruppe = { "group frames", "groupframes", "party", "raid", "layout" },
    gruppen = { "group frames", "groupframes", "party", "raid", "layout" },
    gruppenrahmen = { "group frames", "groupframes", "party", "raid", "layout" },
    gruppenfenster = { "group frames", "groupframes", "party", "raid", "layout" },
    raidframe = { "raid frames", "raidframes", "group frames", "layout" },
    partyframe = { "party frames", "partyframes", "group frames", "layout" },
    schlachtzug = { "raid", "raid frames", "group frames" },
    mythic = { "mythic raid", "raid", "group frames" },
    readycheck = { "ready check", "status icons", "group indicators" },
    bereitschaft = { "ready check", "status icons", "group indicators" },
    statusicon = { "status icons", "indicators", "dead", "offline", "ready check" },
    statusicons = { "status icons", "indicators", "dead", "offline", "ready check" },
    marker = { "raid marker", "markers", "indicators" },
    raidmarker = { "raid marker", "marker", "indicators" },
    leader = { "leader icon", "status icons", "indicators" },
    assist = { "assist icon", "status icons", "indicators" },
    offline = { "offline icon", "status icons", "indicators" },
    afk = { "afk icon", "status icons", "indicators" },
    dead = { "dead icon", "ghost", "status icons", "indicators" },

    profil = { "profile", "profiles", "import", "export" },
    importieren = { "import", "profiles", "wago", "profile string" },
    exportieren = { "export", "profiles", "profile string" },
    kopieren = { "copy profile", "profiles", "import", "export" },
    teilen = { "share profile", "export", "wago" },
    backup = { "profiles", "export", "copy profile" },
    restore = { "profiles", "import", "reset" },

    minimap = { "minimap icon", "minimap button", "miscellaneous" },
    minimapicon = { "minimap icon", "minimap button", "miscellaneous" },
    minimapbutton = { "minimap icon", "minimap button", "miscellaneous" },
    minikarte = { "minimap", "minimap icon", "miscellaneous" },
    sound = { "sounds", "target sound", "target lost", "miscellaneous" },
    sounds = { "sound", "target sound", "target lost", "miscellaneous" },
    targetsound = { "target sound", "target lost", "sounds", "miscellaneous" },
    versioncheck = { "version check", "miscellaneous", "update intervals" },
    menuscale = { "menu scale", "dashboard", "ui scale" },
    uiscale = { "ui scale", "dashboard", "menu scale" },
    unitauras = { "unit auras", "auras", "buffs", "debuffs" },
    globalstyle = { "global style", "bars", "fonts", "colors", "castbar", "miscellaneous" },
    blizzardframes = { "blizzard frames", "default frames", "hide blizzard", "disable blizzard" },
    standardframes = { "default frames", "blizzard frames", "hide blizzard" },

    crosshair = { "combat crosshair", "gameplay", "melee range spell", "range check" },
    fadenkreuz = { "crosshair", "combat crosshair", "gameplay", "melee range spell" },
    melee = { "melee range spell", "crosshair", "range check" },
    maus = { "mouse", "mouseover", "click cast", "targeting" },
    maustaste = { "mouse buttons", "click cast", "targeting" },
    klick = { "click", "click cast", "clickthrough", "targeting" },
    klicken = { "click", "click cast", "clickthrough", "targeting" },
    heilung = { "heal", "healer", "click cast", "mouseover" },
    mouseoverheal = { "mouseover heal", "click cast", "healing" },

    ruckelt = { "lag", "fps", "performance", "update intervals" },
    haengt = { "lag", "fps", "performance", "update intervals" },
    langsam = { "slow", "performance", "lag", "fps" },
    cpu = { "performance", "update intervals", "auras", "cooldown" },
    speicher = { "performance", "auras", "profiles" },
    optimieren = { "performance", "update intervals", "auras", "fps" },
    rounded = { "rounded unitframes", "modules", "style" },
    roundedunitframes = { "rounded unitframes", "modules", "style" },
    rund = { "rounded", "rounded unitframes", "modules" },
    classpower = { "class resources", "power", "resource" },
    klassenressourcen = { "class resources", "classpower", "resource" },
    klassenressource = { "class resources", "classpower", "resource" },
    combopoints = { "combo points", "class resources", "rogue" },
    soulshards = { "soul shards", "class resources", "warlock" },
    runen = { "runes", "runic power", "class resources" },
    eclipse = { "eclipse", "class resources", "druid" },
    stagger = { "stagger", "class resources", "brewmaster" },
}

local CONTROL_KIND_LABEL = {
    faq = "FAQ",
    easteregg = "Easter Egg",
    section = "Section",
    button = "Button",
    toggle = "Toggle",
    slider = "Slider",
    dropdown = "Dropdown",
    segment = "Choice",
    textinput = "Text Input",
    color = "Color",
}

local function AddSearchTermUnique(list, seen, term)
    if #list >= SEARCH_MAX_TERMS_PER_CLAUSE then return end
    term = NormalizeSearchText(term)
    if term == "" or SEARCH_STOP_WORDS[term] or seen[term] then return end
    seen[term] = true
    list[#list + 1] = term
end

local function SearchRawWords(normalized)
    local raw = {}
    for word in tostring(normalized or ""):gmatch("%S+") do
        if not SEARCH_STOP_WORDS[word] then raw[#raw + 1] = word end
        if #raw >= SEARCH_MAX_RAW_WORDS then break end
    end
    return raw
end

local SearchEditDistanceWithin

local function SearchAliasTypoKeys()
    if _searchAliasTypoKeys then return _searchAliasTypoKeys end
    local keys = {}
    for key in pairs(SEARCH_QUERY_ALIASES) do
        if #key >= 5 then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    _searchAliasTypoKeys = keys
    return keys
end

local function SearchAliasKeyForTypo(word)
    if not SearchEditDistanceWithin or #word < 5 then return nil end
    if _searchAliasTypoCache[word] ~= nil then return _searchAliasTypoCache[word] or nil end
    local maxDistance = (#word >= 8) and 2 or 1
    local bestKey, bestDelta
    local keys = SearchAliasTypoKeys()
    for i = 1, #keys do
        local key = keys[i]
        if math.abs(#key - #word) <= maxDistance and SearchEditDistanceWithin(word, key, maxDistance) then
            local delta = math.abs(#key - #word)
            if not bestKey or delta < bestDelta or (delta == bestDelta and #key < #bestKey) then
                bestKey = key
                bestDelta = delta
            end
        end
    end
    _searchAliasTypoCache[word] = bestKey or false
    return bestKey
end

local function SearchCanonicalWords(raw)
    local words = {}
    local i = 1
    while i <= #raw do
        local word = raw[i]
        local nextWord = raw[i + 1]
        if word == "demon" and nextWord == "hunter" then
            words[#words + 1] = "demonhunter"
            i = i + 2
        elseif word == "death" and nextWord == "knight" then
            words[#words + 1] = "deathknight"
            i = i + 2
        elseif word == "wind" and nextWord == "shear" then
            words[#words + 1] = "windshear"
            i = i + 2
        elseif word == "cast" and nextWord == "bar" then
            words[#words + 1] = "castbar"
            i = i + 2
        elseif word == "health" and nextWord == "bar" then
            words[#words + 1] = "healthbar"
            i = i + 2
        elseif word == "power" and nextWord == "bar" then
            words[#words + 1] = "powerbar"
            i = i + 2
        elseif word == "class" and (nextWord == "resource" or nextWord == "resources" or nextWord == "power") then
            words[#words + 1] = "classpower"
            i = i + 2
        elseif word == "click" and (nextWord == "cast" or nextWord == "casting") then
            words[#words + 1] = "clickcast"
            i = i + 2
        elseif word == "click" and nextWord == "through" then
            words[#words + 1] = "clickthrough"
            i = i + 2
        elseif word == "edit" and nextWord == "mode" then
            words[#words + 1] = "editmode"
            i = i + 2
        elseif word == "load" and (nextWord == "condition" or nextWord == "conditions") then
            words[#words + 1] = "loadconditions"
            i = i + 2
        elseif word == "ready" and nextWord == "check" then
            words[#words + 1] = "readycheck"
            i = i + 2
        elseif word == "raid" and nextWord == "marker" then
            words[#words + 1] = "raidmarker"
            i = i + 2
        elseif word == "group" and nextWord == "number" then
            words[#words + 1] = "groupnumber"
            i = i + 2
        elseif word == "name" and nextWord == "shortening" then
            words[#words + 1] = "nameshortening"
            i = i + 2
        elseif word == "global" and nextWord == "cooldown" then
            words[#words + 1] = "globalcooldown"
            i = i + 2
        elseif word == "focus" and nextWord == "kick" then
            words[#words + 1] = "fokuskick"
            i = i + 2
        elseif word == "interrupt" and nextWord == "ready" then
            words[#words + 1] = "interruptready"
            i = i + 2
        elseif word == "minimap" and (nextWord == "icon" or nextWord == "button") then
            words[#words + 1] = "minimapicon"
            i = i + 2
        elseif word == "menu" and nextWord == "scale" then
            words[#words + 1] = "menuscale"
            i = i + 2
        elseif word == "ui" and nextWord == "scale" then
            words[#words + 1] = "uiscale"
            i = i + 2
        elseif word == "target" and (nextWord == "sound" or nextWord == "sounds") then
            words[#words + 1] = "targetsound"
            i = i + 2
        elseif word == "unit" and (nextWord == "aura" or nextWord == "auras") then
            words[#words + 1] = "unitauras"
            i = i + 2
        elseif word == "global" and nextWord == "style" then
            words[#words + 1] = "globalstyle"
            i = i + 2
        elseif word == "spell" and nextWord == "id" then
            words[#words + 1] = "spellid"
            i = i + 2
        elseif word == "health" and nextWord == "text" then
            words[#words + 1] = "healthtext"
            i = i + 2
        elseif word == "power" and nextWord == "text" then
            words[#words + 1] = "powertext"
            i = i + 2
        elseif word == "name" and nextWord == "text" then
            words[#words + 1] = "nametext"
            i = i + 2
        elseif word == "class" and nextWord == "color" then
            words[#words + 1] = "classcolor"
            i = i + 2
        elseif word == "range" and (nextWord == "check" or nextWord == "checker" or nextWord == "checking") then
            words[#words + 1] = "rangecheck"
            i = i + 2
        elseif word == "distance" and (nextWord == "check" or nextWord == "checker" or nextWord == "checking") then
            words[#words + 1] = "distancecheck"
            i = i + 2
        elseif word == "out" and nextWord == "range" then
            words[#words + 1] = "outofrange"
            i = i + 2
        elseif word == "unit" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "unitframe"
            i = i + 2
        elseif word == "player" and nextWord == "frame" then
            words[#words + 1] = "playerframe"
            i = i + 2
        elseif word == "target" and nextWord == "frame" then
            words[#words + 1] = "targetframe"
            i = i + 2
        elseif word == "focus" and nextWord == "frame" then
            words[#words + 1] = "focusframe"
            i = i + 2
        elseif word == "pet" and nextWord == "frame" then
            words[#words + 1] = "petframe"
            i = i + 2
        elseif word == "boss" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "bossframes"
            i = i + 2
        elseif word == "party" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "partyframes"
            i = i + 2
        elseif word == "raid" and (nextWord == "frame" or nextWord == "frames") then
            words[#words + 1] = "raidframes"
            i = i + 2
        else
            words[#words + 1] = word
            i = i + 1
        end
    end
    return words
end

local function BuildSearchQueryClauses(query)
    local normalized = NormalizeSearchText(query)
    if normalized == _searchQueryClauseCacheNorm and _searchQueryClauseCacheClauses then
        return normalized, _searchQueryClauseCacheClauses
    end
    local raw = SearchRawWords(normalized)
    local words = SearchCanonicalWords(raw)
    local clauses = {}
    for i = 1, #words do
        if #clauses >= SEARCH_MAX_QUERY_CLAUSES then break end
        local word = words[i]
        local terms, seen = {}, {}
        AddSearchTermUnique(terms, seen, word)
        local aliases = SEARCH_QUERY_ALIASES[word]
        if not aliases then
            local aliasKey = SearchAliasKeyForTypo(word)
            if aliasKey then
                AddSearchTermUnique(terms, seen, aliasKey)
                aliases = SEARCH_QUERY_ALIASES[aliasKey]
            end
        end
        if aliases then
            for k = 1, #aliases do AddSearchTermUnique(terms, seen, aliases[k]) end
        end
        if #terms > 0 then
            clauses[#clauses + 1] = { word = word, terms = terms }
        end
    end
    _searchQueryClauseCacheNorm = normalized
    _searchQueryClauseCacheClauses = clauses
    return normalized, clauses
end

local function BuildSearchTokenList(normalized)
    local tokens, seen = {}, {}
    for token in tostring(normalized or ""):gmatch("%S+") do
        if #token >= 2 and not SEARCH_STOP_WORDS[token] and not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
            if #tokens >= 110 then break end
        end
    end
    return tokens
end

SearchEditDistanceWithin = function(a, b, maxDistance)
    if a == b then return true end
    maxDistance = tonumber(maxDistance) or 1
    local la, lb = #a, #b
    if math.abs(la - lb) > maxDistance then return false end

    if maxDistance <= 1 then
        if la == lb then
            local firstMismatch, mismatches = nil, 0
            for i = 1, la do
                if a:sub(i, i) ~= b:sub(i, i) then
                    mismatches = mismatches + 1
                    firstMismatch = firstMismatch or i
                    if mismatches > 2 then return false end
                end
            end
            if mismatches <= 1 then return true end
            return mismatches == 2
                and firstMismatch < la
                and a:sub(firstMismatch, firstMismatch) == b:sub(firstMismatch + 1, firstMismatch + 1)
                and a:sub(firstMismatch + 1, firstMismatch + 1) == b:sub(firstMismatch, firstMismatch)
        end

        local short, long = a, b
        if la > lb then short, long = b, a end
        local i, j, edits = 1, 1, 0
        while i <= #short and j <= #long do
            if short:sub(i, i) == long:sub(j, j) then
                i = i + 1
                j = j + 1
            else
                edits = edits + 1
                if edits > 1 then return false end
                j = j + 1
            end
        end
        return true
    end

    local prev, curr = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        curr[0] = i
        local rowMin = curr[0]
        local ca = a:sub(i, i)
        for j = 1, lb do
            local cost = (ca == b:sub(j, j)) and 0 or 1
            local value = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            curr[j] = value
            if value < rowMin then rowMin = value end
        end
        if rowMin > maxDistance then return false end
        prev, curr = curr, prev
    end
    return prev[lb] <= maxDistance
end

local function SearchFuzzyTokenMatch(rec, term)
    if not rec or not rec.tokens or #term < 5 or term:find(" ", 1, true) then return false end
    local maxDistance = (#term >= 8) and 2 or 1
    for i = 1, #rec.tokens do
        local token = rec.tokens[i]
        if math.abs(#token - #term) <= maxDistance and SearchEditDistanceWithin(token, term, maxDistance) then
            return true
        end
    end
    return false
end

local function SearchTermScore(rec, term, queryWord)
    local haystack = rec.haystack or ""
    local score = 0
    if haystack:find(term, 1, true) then
        if rec.labelNorm == term or rec.titleNorm == term then score = score + 180 end
        if rec.labelNorm:sub(1, #term) == term or rec.titleNorm:sub(1, #term) == term then score = score + 90 end
        if rec.labelNorm:find(term, 1, true) then score = score + 70 end
        if rec.titleNorm:find(term, 1, true) then score = score + 55 end
        if rec.hintNorm and rec.hintNorm:find(term, 1, true) then score = score + 45 end
        if rec.groupNorm:find(term, 1, true) then score = score + 35 end
        if term ~= queryWord then score = score + 35 end
        return true, score + 10
    end
    if SearchFuzzyTokenMatch(rec, term) then
        return true, (term == queryWord) and 28 or 20
    end
    return false, 0
end

local function SearchClauseScore(rec, clause)
    local best = 0
    for i = 1, #clause.terms do
        local matched, score = SearchTermScore(rec, clause.terms[i], clause.word)
        if matched and score > best then best = score end
    end
    return best > 0, best
end

local function SearchLooksLikeSupportQuestion(query)
    local normalized = NormalizeSearchText(query)
    if normalized == "" then return false end
    if tostring(query or ""):find("?", 1, true) then return true end
    if normalized:find("how ", 1, true) or normalized:find("where ", 1, true) or normalized:find("why ", 1, true) then return true end
    if normalized:find("what ", 1, true) or normalized:find("help ", 1, true) then return true end
    if normalized:find("do i", 1, true) or normalized:find("can i", 1, true) then return true end
    for _, word in ipairs({ "missing", "gone", "invisible", "broken", "bugged", "wrong", "offscreen", "overlap", "overlapping", "lag", "fps", "lockdown" }) do
        if normalized:find(word, 1, true) then return true end
    end
    if normalized:find("not showing", 1, true) or normalized:find("doesnt show", 1, true) or normalized:find("not working", 1, true) then return true end
    if normalized:find("too big", 1, true) or normalized:find("too small", 1, true) or normalized:find("too many", 1, true) then return true end
    for _, word in ipairs({ "move", "drag", "resize", "hide", "show", "enable", "disable", "change", "reset", "import", "export" }) do
        if normalized == word or normalized:find("^" .. word .. " ", 1, false) or normalized:find(" " .. word .. " ", 1, false) then
            return true
        end
    end
    if normalized:find("my ", 1, true) and (
        normalized:find("change", 1, true)
        or normalized:find("move", 1, true)
        or normalized:find("hide", 1, true)
        or normalized:find("show", 1, true)
        or normalized:find("not", 1, true)
    ) then
        return true
    end
    return false
end

local function SearchSupportQuestionBoost(rec, clauses)
    if not rec or rec.kind ~= "faq" then return 0 end
    local haystack = rec.haystack or ""
    local direct = 0
    for i = 1, #(clauses or {}) do
        local word = clauses[i].word
        if word and word ~= "" and haystack:find(word, 1, true) then
            direct = direct + 1
        end
    end
    if direct > 0 then return 160 + direct * 90 end
    return -160
end

local function IsSearchableDisplayText(text)
    text = DisplaySearchText(text)
    if text == "" or #text > SEARCH_TEXT_MAX_LEN then return false end
    local normalized = NormalizeSearchText(text)
    if normalized == "" or SEARCH_NOISE_TEXT[normalized] then return false end
    if #normalized < 2 then return false end
    return true
end

local function FontStringText(region)
    if not (region and region.GetObjectType and region:GetObjectType() == "FontString") then return nil end
    local raw = region._msuf2SearchText
    local text = raw
    if text == nil and region.GetText then text = region:GetText() end
    text = DisplaySearchText(text)
    if text == "" then return nil end
    return text
end

local function SearchValueText(item)
    if type(item) == "table" then
        return item.text or item.label or item.name or item.title or item.value or item.key
    end
    return item
end

local function AddValuesSearchText(parts, values)
    if type(values) == "function" then
        return
    end
    if type(values) ~= "table" then return end
    local limit = math.min(#values, 120)
    for i = 1, limit do
        local item = values[i]
        AddSearchText(parts, SearchValueText(item))
        if type(item) == "table" then
            AddSearchText(parts, item.tooltip)
            AddSearchText(parts, item.desc or item.description)
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            AddSearchText(parts, key)
            AddSearchText(parts, SearchValueText(item))
            if type(item) == "table" then
                AddSearchText(parts, item.tooltip)
                AddSearchText(parts, item.desc or item.description)
            end
            extra = extra + 1
            if extra >= 40 then break end
        end
    end
end

local function SearchSectionTitle(frame)
    if not frame then return nil end
    local entry = frame._msuf2CollapsibleEntry
    if entry and entry.label then
        local text = FontStringText(entry.label)
        if IsSearchableDisplayText(text) then return text end
    end
    if frame.title then
        local text = FontStringText(frame.title)
        if IsSearchableDisplayText(text) then return text end
    end
    if IsSearchableDisplayText(frame._msuf2SearchTitle) then return DisplaySearchText(frame._msuf2SearchTitle) end
    return nil
end

local function SectionPathForAnchor(anchor, pageTitle)
    local path, seen = {}, {}
    local parent = anchor and anchor.GetParent and anchor:GetParent()
    local pageNorm = NormalizeSearchText(pageTitle or "")
    while parent do
        local title = SearchSectionTitle(parent)
        local norm = NormalizeSearchText(title or "")
        if norm ~= "" and norm ~= pageNorm and not seen[norm] then
            seen[norm] = true
            table.insert(path, 1, title)
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    return path
end

local function SearchHint(pageInfo, anchor)
    local parts, seen = {}, {}
    local function Add(text)
        text = DisplaySearchText(text)
        local norm = NormalizeSearchText(text)
        if norm ~= "" and not seen[norm] then
            seen[norm] = true
            parts[#parts + 1] = text
        end
    end
    Add(pageInfo.group)
    Add(pageInfo.label or pageInfo.title)
    local sections = SectionPathForAnchor(anchor, pageInfo.title or pageInfo.label)
    for i = 1, #sections do Add(sections[i]) end
    return table.concat(parts, " > ")
end

local function BuildSearchPageInfos()
    local groupLabels, navInfo = {}, {}
    for i = 1, #NAV do
        local item = NAV[i]
        if item.header then groupLabels[item.id or item.header] = item.header end
    end

    local infos, seen = {}, {}
    local function AddPageInfo(key, label, group)
        if not key or key == "search" or seen[key] then return end
        seen[key] = true
        local spec = M.pages[key]
        local info = {
            key = key,
            label = M.Tr(label or (spec and spec.title) or key),
            group = group and M.Tr(group) or "",
            title = M.Tr((spec and spec.title) or label or key),
        }
        infos[#infos + 1] = info
        navInfo[key] = info
    end

    for i = 1, #NAV do
        local item = NAV[i]
        if item.key then
            AddPageInfo(item.key, item.label, item.group and groupLabels[item.group] or nil)
        end
    end
    for i = 1, #(M.pageOrder or {}) do
        local key = M.pageOrder[i]
        local spec = M.pages[key]
        AddPageInfo(key, spec and spec.title or key, nil)
    end
    return infos, navInfo
end

ClearSearchRegistryPage = function(pageKey)
    if not pageKey then return end
    local ids = _searchRegistryByPage[pageKey]
    if ids then
        for i = 1, #ids do
            _searchRegistry[ids[i]] = nil
        end
        _searchRegistryByPage[pageKey] = nil
        MarkSearchIndexDirty()
    end
end

local function CopyStaticSearchValues(values)
    if type(values) == "function" or type(values) ~= "table" then return nil end
    local out, count = {}, 0
    local limit = math.min(#values, 80)
    for i = 1, limit do
        local item = values[i]
        local text = SearchValueText(item)
        if text ~= nil then
            count = count + 1
            out[count] = text
        end
    end
    local extra = 0
    for key, item in pairs(values) do
        if type(key) ~= "number" or key < 1 or key > #values then
            count = count + 1
            out[count] = key
            local text = SearchValueText(item)
            if text ~= nil then
                count = count + 1
                out[count] = text
            end
            extra = extra + 1
            if extra >= 30 then break end
        end
    end
    return count > 0 and out or nil
end

function M.RegisterSearchWidget(widget, meta)
    if not widget or type(meta) ~= "table" then return end
    local pageKey = meta.pageKey or M._msuf2SearchBuildKey or M.activeKey
    if type(pageKey) ~= "string" or pageKey == "" or pageKey == "search" then return end

    local label = DisplaySearchText(meta.label or meta.title or meta.text or widget._msuf2SearchText or widget._msuf2SearchTitle)
    if not IsSearchableDisplayText(label) then return end

    local id = widget._msuf2SearchRegistryId
    if not id or widget._msuf2SearchRegistryPage ~= pageKey or not _searchRegistry[id] then
        _searchRegistrySerial = _searchRegistrySerial + 1
        id = pageKey .. ":" .. tostring(_searchRegistrySerial)
        widget._msuf2SearchRegistryId = id
        widget._msuf2SearchRegistryPage = pageKey
        _searchRegistryByPage[pageKey] = _searchRegistryByPage[pageKey] or {}
        _searchRegistryByPage[pageKey][#_searchRegistryByPage[pageKey] + 1] = id
    end

    _searchRegistry[id] = {
        id = id,
        pageKey = pageKey,
        label = label,
        kind = meta.kind or widget._msuf2ControlKind or "control",
        anchor = meta.anchor or widget._msuf2Title or widget._msuf2Label or widget,
        values = CopyStaticSearchValues(meta.values or widget.values),
        keywords = meta.keywords,
        help = meta.help or meta.description,
    }
    MarkSearchIndexDirty()
end

local function AddSearchRecord(records, seenRecords, pageInfo, label, anchor, kind, extraParts)
    label = DisplaySearchText(label)
    if not IsSearchableDisplayText(label) then return end

    kind = kind or "text"
    local displayHint = SearchHint(pageInfo, anchor)
    local hint = (kind == "faq") and "" or displayHint
    local parts = {}
    AddSearchText(parts, label)
    if kind ~= "faq" then
        AddSearchText(parts, hint)
        AddSearchText(parts, pageInfo.label)
        AddSearchText(parts, pageInfo.group)
        AddSearchText(parts, pageInfo.title)
    end
    if kind == "page" then
        AddRawSearchText(parts, SEARCH_KEYWORDS[pageInfo.key])
    end
    if extraParts then
        for i = 1, #extraParts do AddSearchText(parts, extraParts[i]) end
    end

    local recordId = table.concat({
        tostring(pageInfo.key or ""),
        tostring(kind or ""),
        tostring(anchor or ""),
        NormalizeSearchText(label),
        NormalizeSearchText(hint),
    }, "\031")
    if seenRecords[recordId] then return end
    seenRecords[recordId] = true

    displayHint = DisplaySearchText(displayHint)
    local labelNorm = NormalizeSearchText(label)
    local titleNorm = (kind == "faq") and "" or NormalizeSearchText(pageInfo.title or pageInfo.label or "")
    local groupNorm = (kind == "faq") and "" or NormalizeSearchText(pageInfo.group or "")
    local hintNorm = (kind == "faq") and "" or NormalizeSearchText(displayHint)
    local haystackNorm = NormalizeSearchText(table.concat(parts, " "))
    local record = {
        key = pageInfo.key,
        label = label,
        group = pageInfo.group or "",
        title = pageInfo.title or pageInfo.label or "",
        hint = displayHint,
        kind = kind,
        anchor = anchor,
        labelNorm = labelNorm,
        groupNorm = groupNorm,
        titleNorm = titleNorm,
        hintNorm = hintNorm,
        haystack = haystackNorm,
        tokens = BuildSearchTokenList(haystackNorm),
        order = #records + 1,
    }
    records[#records + 1] = record
    return record
end

local SEARCH_FAQ = {
    {
        label = "Why are boss frames not visible?",
        answer = "Boss frames normally appear only during boss encounters. Enable Boss Frames and use Edit Mode or Boss Preview to test them outside combat.",
        pageKey = "uf_boss",
        target = "Opens: Boss > Frame Basics / Boss Layout",
        anchorText = "Enable boss castbars Boss Layout Boss Preview Frame Basics",
        keywords = { "boss frames not visible", "boss frames hidden", "why boss not show", "warum sehe ich boss frames nicht", "bossframes weg", "boss preview", "boss frames anzeigen", "boss frames sichtbar", "boss frames show" },
        priority = 20,
    },
    {
        label = "How do I move frames?",
        answer = "Open MSUF Edit Mode, select the frame, then drag it. Use the unit page > Anchoring only for exact anchor/X/Y fine-tuning.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move frames drag position x offset y offset",
        keywords = { "where do i move my unitframe", "how to move unitframe", "how to move a unitframe", "how do i move unitframe", "move unitframe", "move unit frame", "move frames", "drag frames", "position", "verschieben", "frames bewegen", "edit mode", "x offset", "y offset", "unitframe position", "move player unitframe", "move target unitframe", "move focus unitframe", "move pet unitframe", "move boss unitframe", "how do i move the player frame", "move player frame", "move target frame", "move focus frame", "move pet frame", "move boss frame", "drag player frame", "drag target frame", "player frame position" },
        priority = 320,
    },
    {
        label = "How do I move the player frame?",
        answer = "Use MSUF Edit Mode to drag the player frame. For exact anchor or X/Y values, open Player > Anchoring after that.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move player frame drag player frame position x offset y offset",
        keywords = { "how do i move the player frame", "how to move player frame", "how to move player unitframe", "where do i move my player frame", "move my player frame", "move player frame", "move player unitframe", "drag player frame", "player frame position", "playerframe position", "player x y", "player anchor", "player anchoring", "spieler frame verschieben", "spieler verschieben" },
        priority = 360,
    },
    {
        label = "How do I move or anchor one unit frame?",
        answer = "Use MSUF Edit Mode to drag a single unit frame. Use the unit page > Anchoring when you need exact anchor targets or X/Y values.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode Anchoring Anchor unit to Custom anchor target Global anchor move position",
        keywords = { "unit frame anchor", "unitframe anchor", "anchor player frame", "custom anchor", "global anchor", "anchor target frame", "anchor focus frame", "unitframe position", "unit frame position", "player frame position", "move player frame", "move target frame", "move focus frame", "move unitframe", "player x y", "target x y" },
        priority = 160,
    },
    {
        label = "How do I move party or raid frames?",
        answer = "Open Group Frames > Layout. Use Layout, Frame Scaling, and Anchoring for party/raid position, growth, spacing, size, and anchor behavior.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > Anchoring",
        anchorText = "Anchoring Layout Frame Scaling growth direction spacing columns position move party raid",
        keywords = { "move raid frames", "move party frames", "move group frames", "raidframes position", "partyframes position", "groupframes position", "group frame anchor", "raid frame anchor", "party frame anchor", "gruppe verschieben", "raid verschieben" },
        priority = 55,
    },
    {
        label = "How do I resize a unit frame?",
        answer = "Open that unit page and use Frame Basics for width, height, and scale. Text size is in Global Style > Fonts or the unit Text section.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics width height scale size player target focus boss pet",
        keywords = { "resize unitframe", "resize unit frame", "make frame bigger", "make player frame bigger", "make target frame smaller", "width height scale", "unitframe size", "frame size", "frames too big", "frames too small" },
        priority = 40,
    },
    {
        label = "How do I resize party or raid frames?",
        answer = "Open Group Frames > Layout. General/Layout controls frame width, height, spacing, columns, and growth; Frame Scaling controls scale behavior.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout",
        anchorText = "General Layout Frame Scaling width height spacing columns growth scale",
        keywords = { "resize raid frames", "resize party frames", "resize group frames", "raid frame size", "party frame size", "group frame size", "raid frames too big", "party frames too small", "group scale" },
        priority = 45,
    },
    {
        label = "How do I change portraits?",
        answer = "Open the unit page, then use the Portrait section for mode, render type, shape, size, offset, and border.",
        pageKey = "uf_player",
        target = "Opens: Player > Portrait",
        anchorText = "Portrait mode render type shape size offset class icon portrait background",
        keywords = { "portrait", "portraits", "avatar", "face", "bild", "portraet", "portrait mode", "portrait shape", "class icon", "2d portrait", "3d portrait", "portrait background" },
        priority = 15,
    },
    {
        label = "How do I change castbars?",
        answer = "Use the unit page for per-unit castbar toggles and Global Style > Castbar for shared textures, direction, GCD, text, and interrupt options.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar",
        anchorText = "Castbar Textures & Outline GCD Bar Focus Kick Interrupt Ready Indicator",
        keywords = { "castbar", "cast bar", "gcd", "interrupt", "focus kick", "channel ticks", "zauberleiste", "castbar texture", "castbar direction", "spell name" },
        priority = 20,
    },
    {
        label = "Where are Evoker empowered cast settings?",
        answer = "Open Global Style > Castbar and use Empowered Casts for Evoker stage color, stage blink, and blink timing.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Empowered Casts",
        anchorText = "Empowered Casts Evoker stage blink empower hold release",
        keywords = { "evoker castbar", "evoker cast bar", "empowered casts", "empower", "empower stage", "stage blink", "hold cast", "release cast", "augmentation", "devastation", "preservation", "quell" },
        priority = 180,
    },
    {
        label = "Where are Demon Hunter interrupt and castbar settings?",
        answer = "Open Global Style > Castbar for Focus Kick and Interrupt Ready Indicator. Per-unit castbar interrupt toggles are on each unit page.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Interrupt Ready Indicator",
        anchorText = "Interrupt Ready Indicator Focus Kick Demon Hunter devour consume magic disrupt kick",
        keywords = { "devour demonhunter castbar", "devour demon hunter castbar", "dh castbar", "demon hunter interrupt", "demonhunter interrupt", "havoc kick", "vengeance kick", "consume magic", "disrupt", "interrupt ready", "focus kick", "kick cooldown" },
        priority = 180,
    },
    {
        label = "How do I change my background?",
        answer = "For bar backgrounds, open Global Style > Colors > Bar Background Tint. For whole-frame alpha, use the unit page > Transparency.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Background Tint",
        anchorText = "Bar Background Tint background backgrond backround bg backdrop opacity alpha",
        keywords = { "how do i change my backgrond", "how do i change my background", "change background", "change backgrond", "backround", "backgroud", "background color", "bar background", "background tint", "bg color", "backdrop", "opacity", "alpha", "transparent background", "hintergrund" },
        priority = 70,
    },
    {
        label = "How do I make unit frames transparent?",
        answer = "Open the unit page > Transparency for in-combat/out-of-combat alpha. Group frame transparency is in Group Frames > Layout > Transparency.",
        pageKey = "uf_player",
        target = "Opens: Player > Transparency",
        anchorText = "Transparency alpha in combat out of combat opacity background preserve hp color",
        keywords = { "transparent unitframe", "transparent unit frame", "alpha unitframe", "opacity unitframe", "fade frame", "frame alpha", "in combat alpha", "out of combat alpha", "transparent player frame", "transparent target frame" },
        priority = 40,
    },
    {
        label = "How do I change bar textures, gradients, or outlines?",
        answer = "Open Global Style > Bars. Textures & Gradient controls shared bar textures; Frame Outline and Highlight Borders control borders.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Textures & Gradient",
        anchorText = "Textures & Gradient Frame Outline Highlight Borders texture gradient outline border",
        keywords = { "bar texture", "health texture", "power texture", "change texture", "gradient", "outline", "border", "bar border", "frame outline", "highlight border", "shared texture" },
        priority = 35,
    },
    {
        label = "How do I change health, power, or class colors?",
        answer = "Open Global Style > Colors. Bar Colors and Power Bar Colors control HP/power colors; Class Bar Colors controls class overrides.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Bar Colors",
        anchorText = "Bar Colors Power Bar Colors Class Bar Colors health hp power class color",
        keywords = { "health color", "hp color", "power color", "mana color", "class color", "bar color", "reaction color", "npc color", "color by class", "farbe", "farben" },
        priority = 35,
    },
    {
        label = "How do I change colors?",
        answer = "Most shared colors are in Global Style > Colors. Bar texture and border style controls are in Global Style > Bars.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors",
        anchorText = "Colors Bar Background Tint Bar Colors Unitframe Colors Class Bar Colors",
        keywords = { "colors", "colours", "farbe", "farben", "class color", "reaction color", "bar color", "background color", "unitframe colors" },
        priority = 10,
    },
    {
        label = "How do I change fonts and text?",
        answer = "Global Style > Fonts controls shared font settings. Unit pages contain per-unit name, health, and power text position and pattern settings.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts",
        anchorText = "Global Font Text Style Name & Power Colors Name Shortening font size outline shadow",
        keywords = { "font", "fonts", "text", "schrift", "name text", "hp text", "health text", "power text", "text size", "font size", "outline", "shadow", "name shortening", "make text bigger", "text too small" },
        priority = 25,
    },
    {
        label = "Where do I change HP, name, or power text position?",
        answer = "Open the unit page and use Text for name/health/power text patterns, anchors, offsets, font sizes, and layering.",
        pageKey = "uf_player",
        target = "Opens: Player > Text",
        anchorText = "Text name health power text anchor offset font size layer hp pattern",
        keywords = { "hp text position", "health text position", "name position", "power text position", "move text", "text anchor", "text offset", "name text", "health pattern", "power pattern", "percent hp" },
        priority = 35,
    },
    {
        label = "How do I import, export, or switch profiles?",
        answer = "Open Profiles for active profile, spec auto-switching, import/export strings, legacy imports, and reset options.",
        pageKey = "profiles",
        target = "Opens: Profiles > Export / Import",
        anchorText = "Export / Import Profile Management Spec Profiles import export wago string",
        keywords = { "profile", "profiles", "import", "export", "wago", "copy profile", "reset profile", "profil", "spec profile", "profile string", "import string", "export string", "share profile" },
        priority = 35,
    },
    {
        label = "How do I reset positions or recover a broken layout?",
        answer = "Use Dashboard > Reset Positions for frame movers. Use Profiles only when you want to reset, copy, import, or replace profile data.",
        pageKey = "home",
        target = "Opens: Dashboard > Reset Positions",
        anchorText = "Reset Positions Factory Reset Profiles Print Help recovery support",
        keywords = { "reset positions", "reset movers", "frames off screen", "frame offscreen", "broken layout", "recover layout", "factory reset", "fullreset", "help reset", "position reset" },
        priority = 45,
    },
    {
        label = "How do I configure group frames?",
        answer = "Use Group Frames pages: Layout for size/growth/sorting, Health & Text for bars/text, Buffs & Debuffs for auras, and Indicators for status icons.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout",
        anchorText = "Group Frames Layout Health & Text Buffs & Debuffs Indicators party raid growth sorting",
        keywords = { "group frames", "groupframes", "party", "raid", "mythic raid", "gruppe", "raid frames", "layout", "growth", "sorting", "raidframes", "partyframes" },
        priority = 20,
    },
    {
        label = "How do I configure buffs and debuffs?",
        answer = "Unit Auras controls unitframe auras. Group Buffs & Debuffs controls group-frame aura layout, filtering, cooldowns, and private auras.",
        pageKey = "auras2",
        target = "Opens: Global Style > Unit Auras",
        anchorText = "Unit Auras Display Caps & Icons Aura Filters & Sorting Private Auras buffs debuffs",
        keywords = { "buff", "buffs", "debuff", "debuffs", "auras", "aura", "private aura", "cooldown", "filter", "only my buffs", "only my debuffs", "hide buffs", "show debuffs", "aura size", "aura position" },
        priority = 25,
    },
    {
        label = "How do I configure group buffs, debuffs, or defensives?",
        answer = "Open Group Frames > Buffs & Debuffs. It has sections for Buffs, Debuffs, Defensives, Private Auras, cooldown style, and aura utilities.",
        pageKey = "gf_auras",
        target = "Opens: Group Frames > Buffs & Debuffs",
        anchorText = "Buffs Debuffs Defensives Private Auras Cooldown Style Aura Utilities group frames",
        keywords = { "raid buffs", "raid debuffs", "party buffs", "party debuffs", "group auras", "group buffs", "group debuffs", "defensives", "externals", "private aura raid", "group cooldown swipe" },
        priority = 40,
    },
    {
        label = "How do I add or change status icons and indicators?",
        answer = "Unit frame status icons are on each unit page. Group frame indicators are in Group Frames > Indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators",
        anchorText = "Indicators Status Icons Spell Indicators Corner Indicators role icon dispel aggro raid marker",
        keywords = { "status icons", "indicator", "indicators", "corner indicator", "spell indicator", "raid marker", "role icon", "leader icon", "ready check", "aggro icon", "threat icon", "focus glow" },
        priority = 35,
    },
    {
        label = "Why is something not updating immediately?",
        answer = "Some layout changes rebuild frames, while visual changes apply instantly. If needed, close and reopen the menu or reload after large profile/import changes.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Update intervals",
        anchorText = "Update intervals refresh reload apply not updating performance",
        keywords = { "not updating", "does not update", "refresh", "reload", "apply", "changes not showing", "aktualisiert nicht", "settings not applying", "profile not applying", "need reload" },
        priority = 20,
    },
    {
        label = "How do I disable Blizzard unit frames?",
        answer = "Open Global Style > Miscellaneous and use the Blizzard frame toggles.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames disable blizzard hide blizzard default frames playerframe",
        keywords = { "blizzard frames", "disable blizzard", "hide blizzard", "playerframe", "default frames", "standard frames", "hide default frames", "disable default unit frames", "blizzard player frame" },
        priority = 35,
    },
    {
        label = "Where is the minimap icon setting?",
        answer = "Open Global Style > Miscellaneous > Blizzard Frames and use Show MSUF minimap icon.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames Show MSUF minimap icon minimap button addon compartment",
        keywords = { "minimap", "minimap icon", "minimap button", "hide minimap icon", "show minimap icon", "addon compartment", "minikarte", "minimap symbol" },
        priority = 185,
    },
    {
        label = "Where are target sound settings?",
        answer = "Open Global Style > Miscellaneous > Blizzard Frames and use Play sound on Target/Target Lost.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Blizzard Frames",
        anchorText = "Blizzard Frames Play sound on Target Target Lost target sounds",
        keywords = { "target sound", "target sounds", "target lost sound", "play sound", "sound on target", "sound target lost", "ziel sound", "sounds" },
        priority = 170,
    },
    {
        label = "Where are menu snap or menu behavior settings?",
        answer = "Open Global Style > Miscellaneous > Menu behavior for edge snap and related menu behavior.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Menu behavior",
        anchorText = "Menu behavior edge snap windows snap menu resize ui scale menu scale",
        keywords = { "menu snap", "edge snap", "window snap", "menu behavior", "menu resize", "menu scale", "ui scale", "menu too big", "menu too small", "fenster einrasten" },
        priority = 65,
    },
    {
        label = "Where is Miscellaneous?",
        answer = "Open Global Style > Miscellaneous for language, menu behavior, update intervals, tooltips, Blizzard frames, minimap icon, sounds, and range fade.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous",
        anchorText = "Miscellaneous misc global style language menu behavior update intervals tooltips blizzard frames minimap sounds range fade",
        keywords = { "misc", "miscellaneous", "where is misc", "where is miscellaneous", "global style misc", "global style miscellaneous", "verschiedenes", "allgemein", "sonstiges" },
        priority = 260,
    },
    {
        label = "How do I change range fading?",
        answer = "Open Global Style > Miscellaneous and use the Range Fade section for affected units, alpha, and portrait fading.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Range Fade",
        anchorText = "Range Fade unit frame range check range checker distance check out of range range alpha distance fade portrait fading",
        keywords = { "range fade", "range check", "range checker", "unit frame range check", "distance check", "out of range", "range alpha", "distance fade", "reichweite", "reichweitencheck", "entfernung", "fade portrait", "frame fades", "out of range opacity" },
        priority = 45,
    },
    {
        label = "Where is the unit frame range check?",
        answer = "Open Global Style > Miscellaneous > Range Fade. It controls target, focus, and boss out-of-range fading; group range fade is in Group Frames > Health & Text.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Range Fade",
        anchorText = "Range Fade unit frame range check range checker distance check out of range alpha target focus boss",
        keywords = { "unit frame range check", "unitframe range check", "unit frames range check", "range check unitframe", "range check unit frame", "range checker", "distance check", "distance checker", "out of range unit frame", "out of range frames", "target out of range", "focus out of range", "boss out of range", "target range fade", "focus range fade", "boss range fade", "reichweitencheck", "reichweite check", "entfernung check" },
        priority = 165,
    },
    {
        label = "How do I change language or translations?",
        answer = "Open Global Style > Miscellaneous > Language. Translation coverage can also be checked with the /msuf locale command.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Language",
        anchorText = "Language locale localization translation deDE ruRU frFR esES",
        keywords = { "language", "locale", "translation", "translations", "localization", "localisation", "sprache", "deutsch", "english", "russian", "french", "spanish" },
        priority = 25,
    },
    {
        label = "How do I change unitframe tooltips?",
        answer = "Open Global Style > Miscellaneous > Unitframe tooltips to control mouseover tooltip behavior.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Unitframe tooltips",
        anchorText = "Unitframe tooltips tooltip mouseover hide tooltip show tooltip",
        keywords = { "tooltip", "tooltips", "unit tooltip", "mouseover tooltip", "hide tooltip", "show tooltip", "tooltip on mouseover" },
        priority = 20,
    },
    {
        label = "How do I change click, mouseover, or targeting behavior?",
        answer = "Open Gameplay for crosshair, click-cast, focus/target modifier, mouseover, interaction, and targeting options.",
        pageKey = "gameplay",
        target = "Opens: Gameplay",
        anchorText = "Gameplay click cast focus target modifier mouseover interaction targeting combat crosshair",
        keywords = { "click cast", "clickcast", "click casting", "clickthrough", "click-through", "mouseover", "target modifier", "focus modifier", "mouse buttons", "targeting", "combat crosshair" },
        priority = 30,
    },
    {
        label = "How do I change class resources?",
        answer = "Open Class Resources for combo points, holy power, soul shards, chi, maelstrom, essence, runes, stagger, detached power, and alternative mana.",
        pageKey = "classpower",
        target = "Opens: Class Resources",
        anchorText = "Class Resources Layout Behavior Style Auto-Hide Detached Power Bar Alternative Mana",
        keywords = { "class resource", "class resources", "combo points", "holy power", "soul shards", "chi", "maelstrom", "essence", "runes", "stagger", "alternative mana", "alt mana", "detached power" },
        priority = 25,
    },
    {
        label = "How do I hide or show a unit frame?",
        answer = "Open that unit page and use Frame Basics > Enable. Boss frames also have Boss Layout options.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics Enable hide show player target focus boss pet",
        keywords = { "hide unitframe", "show unitframe", "disable unitframe", "enable unitframe", "hide player frame", "hide target frame", "hide focus frame", "hide pet frame", "show player frame", "enable target frame", "disable boss frame" },
        priority = 30,
    },
    {
        label = "Where are load conditions?",
        answer = "Open the matching unit page and use Load Conditions to control when player, target, focus, boss, or pet frames are shown.",
        pageKey = "uf_player",
        target = "Opens: Player > Load Conditions",
        anchorText = "Load Conditions show hide visibility player target focus boss pet combat group instance",
        keywords = { "load conditions", "visibility conditions", "show conditions", "hide conditions", "when to show frame", "when to hide frame", "frame visibility", "combat visibility", "instance visibility", "ladebedingungen", "sichtbarkeit" },
        priority = 80,
    },
    {
        label = "Why is my player, target, focus, or pet frame gone?",
        answer = "Open the matching unit page and check Frame Basics > Enable, Load Conditions, alpha/transparency, and range fade.",
        pageKey = "uf_player",
        target = "Opens: Player > Frame Basics",
        anchorText = "Frame Basics Enable Load Conditions Transparency Range Fade player target focus pet gone missing invisible",
        keywords = { "player frame gone", "target frame gone", "focus frame gone", "pet frame gone", "unitframe missing", "unitframe invisible", "frame not visible", "frame disappeared", "cannot see player frame", "target not showing", "focus not showing", "pet not showing", "unitframe hidden" },
        priority = 55,
    },
    {
        label = "Where is Target of Target?",
        answer = "Open Target of Target. Use Frame Basics to enable it, Text for labels, and Anchoring/Edit Mode for placement.",
        pageKey = "uf_targettarget",
        target = "Opens: Target of Target > Frame Basics",
        anchorText = "Frame Basics Target of Target ToT Enable Text Anchoring",
        keywords = { "target of target", "tot", "targettarget", "target target", "where is tot", "tot missing", "show target of target", "enable tot", "target of target frame" },
        priority = 45,
    },
    {
        label = "Why is my castbar not showing?",
        answer = "Open the unit page > Castbar to enable that unit's castbar. Shared castbar visuals are in Global Style > Castbar.",
        pageKey = "uf_player",
        target = "Opens: Player > Castbar",
        anchorText = "Castbar Enable player target focus boss pet show interrupt icon text",
        keywords = { "castbar not showing", "castbar missing", "player castbar gone", "target castbar missing", "focus castbar missing", "boss castbar missing", "show castbar", "enable castbar", "my castbar disappeared", "no cast bar" },
        priority = 55,
    },
    {
        label = "Where is the GCD bar?",
        answer = "Open Global Style > Castbar > GCD Bar. It controls instant-cast GCD display, time text, spell name, and icon.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > GCD Bar",
        anchorText = "GCD Bar instant casts show time text spell name icon",
        keywords = { "gcd", "gcd bar", "global cooldown", "instant casts", "show gcd", "gcd timer", "gcd spell", "gcd icon" },
        priority = 130,
    },
    {
        label = "Where do I change castbar spell names or long cast text?",
        answer = "Open Global Style > Castbar > Name Shortening for castbar spell name shortening, max length, and reserved space.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar > Name Shortening",
        anchorText = "Name Shortening spell name max name length reserved space castbar",
        keywords = { "cast name too long", "spell name too long", "castbar text too long", "shorten castbar name", "castbar spell name", "max name length", "reserved space", "cast text overlap" },
        priority = 45,
    },
    {
        label = "Why are class resources missing?",
        answer = "Open Class Resources. Check Enable, Auto-Hide, class-specific behavior, detached power, and alternative mana settings.",
        pageKey = "classpower",
        target = "Opens: Class Resources > Layout / Auto-Hide",
        anchorText = "Class Resources Enable Auto-Hide Behavior Detached Power Bar Alternative Mana",
        keywords = { "class resources missing", "combo points missing", "holy power missing", "soul shards missing", "chi missing", "maelstrom missing", "essence missing", "runes missing", "stagger missing", "class power not showing", "resource bar missing" },
        priority = 55,
    },
    {
        label = "Where do I configure detached power or alternative mana?",
        answer = "Open Class Resources for global class-resource bars. Per-unit detached power options are in the unit page > Power Bar.",
        pageKey = "classpower",
        target = "Opens: Class Resources > Detached Power Bar",
        anchorText = "Detached Power Bar Alternative Mana Power Bar class resources sync width anchor",
        keywords = { "detached power", "detached power bar", "alternative mana", "alt mana", "dual resource", "power bar detached", "anchor to class resource", "sync width to class resource" },
        priority = 45,
    },
    {
        label = "Why are my buffs or debuffs missing?",
        answer = "Open Unit Auras. Check Display, Aura Filters & Sorting, Only Mine, boss aura filters, dispellable filters, and icon caps.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Aura Filters & Sorting",
        anchorText = "Aura Filters & Sorting Display Only my buffs Only my debuffs Show Debuffs Include boss buffs dispellable",
        keywords = { "buffs missing", "debuffs missing", "auras missing", "buff not showing", "debuff not showing", "hide buffs", "show debuffs", "only my buffs", "only my debuffs", "boss aura missing", "dispellable debuff missing", "aura filter" },
        priority = 60,
    },
    {
        label = "Why do I have too many buffs or debuffs?",
        answer = "Open Unit Auras > Caps & Icons. Lower max buffs/debuffs, rows, icon size, and adjust filters.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Caps & Icons",
        anchorText = "Caps & Icons Max Buffs Max Debuffs Icon size rows spacing filters",
        keywords = { "too many buffs", "too many debuffs", "too many auras", "aura spam", "buff spam", "debuff spam", "max buffs", "max debuffs", "aura cap", "icon size", "aura rows" },
        priority = 55,
    },
    {
        label = "Where are private auras?",
        answer = "Unit private aura controls are in Unit Auras > Private Auras. Group-frame private auras are in Group Frames > Buffs & Debuffs > Private Auras.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Private Auras",
        anchorText = "Private Auras Unit Auras Group Buffs Debuffs raid mechanics",
        keywords = { "private auras", "private aura", "raid private aura", "private aura missing", "show private aura", "private aura icon", "private auras group frames" },
        priority = 45,
    },
    {
        label = "Where do I change aura cooldown text?",
        answer = "Open Unit Auras > Text Coloring for timer colors and text sizes. Group aura cooldown style is in Group Frames > Buffs & Debuffs > Cooldown Style.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Text Coloring",
        anchorText = "Text Coloring Cooldown Timer Text cooldown text size safe warning urgent stack count",
        keywords = { "aura cooldown text", "aura cooldown text too small", "aura timer too small", "buff timer", "debuff timer", "cooldown text size", "stack text size", "timer color", "aura timer color", "cooldown swipe", "pandemic color" },
        priority = 150,
    },
    {
        label = "Where do I change group health text or power bars?",
        answer = "Open Group Frames > Health & Text. It controls health colors, bars, power bar, text, heal prediction, dispel overlay, debuff stripe, and range fade.",
        pageKey = "gf_bars",
        target = "Opens: Group Frames > Health & Text",
        anchorText = "Health Colors Bars Power Bar Text Heal Prediction Dispel Overlay Debuff Stripe Range Fade group range check raid range check party range check",
        keywords = { "group health text", "raid health text", "party health text", "group power bar", "raid power bar", "party power bar", "heal prediction", "incoming heals", "dispel overlay", "debuff stripe", "group range fade", "group range check", "raid range check", "party range check", "raid out of range", "party out of range", "range check raid frames" },
        priority = 55,
    },
    {
        label = "Where is party or raid range check?",
        answer = "Open Group Frames > Health & Text > Range Fade. That controls party and raid out-of-range fading.",
        pageKey = "gf_bars",
        target = "Opens: Group Frames > Health & Text > Range Fade",
        anchorText = "Range Fade group frame range check raid range check party range check out of range alpha",
        keywords = { "group range check", "group frame range check", "group frames range check", "raid range check", "raid frame range check", "raid frames range check", "party range check", "party frame range check", "party frames range check", "raid out of range", "party out of range", "group out of range", "range check raid frames", "range check party frames" },
        priority = 140,
    },
    {
        label = "Where are absorb bars or heal prediction?",
        answer = "Global absorb styling is in Global Style > Bars > Absorb Display. Group incoming heals are in Group Frames > Health & Text > Heal Prediction.",
        pageKey = "opt_bars",
        target = "Opens: Global Style > Bars > Absorb Display",
        anchorText = "Absorb Display Heal Prediction incoming heals absorb health group frames",
        keywords = { "absorb", "absorbs", "absorb bar", "absorb texture", "heal prediction", "incoming heals", "healing prediction", "shields", "shield bar", "health absorb" },
        priority = 45,
    },
    {
        label = "Where do I change aggro, threat, dispel, or raid markers?",
        answer = "Use Global Style > Bars for highlight borders and Group Frames > Indicators for role, threat, dispel, spell, corner, and raid-marker indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators",
        anchorText = "Indicators Status Icons Spell Indicators Corner Indicators aggro threat dispel role icon raid marker",
        keywords = { "aggro", "threat", "aggro border", "threat border", "dispel indicator", "magic indicator", "curse indicator", "poison indicator", "disease indicator", "raid marker", "role icon", "ready check", "leader icon" },
        priority = 50,
    },
    {
        label = "Why is text overlapping or in the wrong place?",
        answer = "Open the unit page > Text. Adjust anchors, offsets, font size, spacing, split spacing, and layer/draw order.",
        pageKey = "uf_player",
        target = "Opens: Player > Text",
        anchorText = "Text anchor offset font size layer draw order spacing split spacing overlaps bars portraits status icons",
        keywords = { "text overlap", "text overlapping", "text wrong place", "text on bar", "text on portrait", "name overlap", "hp text overlap", "power text overlap", "draw order", "text layer", "split spacing", "move text" },
        priority = 55,
    },
    {
        label = "Why is MSUF lagging or costing FPS?",
        answer = "Open Global Style > Miscellaneous > Update intervals. Also reduce aura counts/timers if aura-heavy layouts are expensive.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous > Update intervals",
        anchorText = "Update intervals performance lag fps auras cooldown timers filters",
        keywords = { "lag", "fps", "performance", "stutter", "slow", "too much cpu", "heavy", "optimize", "update intervals", "aura performance", "cooldown text performance", "combat performance" },
        priority = 55,
    },
    {
        label = "Why can I not change something in combat?",
        answer = "WoW blocks some protected frame changes in combat. Leave combat, then apply layout, anchoring, enable/disable, profile, or protected-frame changes.",
        pageKey = "opt_misc",
        target = "Opens: Global Style > Miscellaneous",
        anchorText = "combat lockdown protected frames settings in combat out of combat",
        keywords = { "combat lockdown", "cannot change in combat", "can't change in combat", "protected frame", "blocked in combat", "in combat settings", "combat error", "leave combat", "why can't i move in combat" },
        priority = 50,
    },
    {
        label = "Where did the menu window go?",
        answer = "Open MSUF again with /msuf. If frame positions are broken, use Dashboard > Reset Positions or the profile/reset tools.",
        pageKey = "home",
        target = "Opens: Dashboard > Reset Positions",
        anchorText = "Reset Positions menu window offscreen dashboard slash msuf recovery",
        keywords = { "menu gone", "menu missing", "window offscreen", "menu offscreen", "can't open menu", "cannot open menu", "lost menu", "options window gone", "reset menu position", "where is menu" },
        priority = 45,
    },
    {
        label = "Why did my profile or import look wrong?",
        answer = "Open Profiles. Check active profile, spec profiles, import/export, and legacy imports. Large imports may need a reload.",
        pageKey = "profiles",
        target = "Opens: Profiles > Profile Management / Export / Import",
        anchorText = "Profile Management Spec Profiles Export Import legacy imports active profile reload",
        keywords = { "profile wrong", "profile missing", "profile gone", "import failed", "import looks wrong", "wago import wrong", "profile not loading", "spec profile wrong", "active profile", "legacy import", "copy profile" },
        priority = 55,
    },
    {
        label = "Why are party or raid frames not showing?",
        answer = "Open Group Frames > Layout. Check enable/show behavior, player/solo visibility, layout mode, frame scaling, and anchoring.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Layout show hide player solo party raid enable frame scaling anchoring",
        keywords = { "party frames not showing", "raid frames not showing", "group frames missing", "party frames gone", "raid frames gone", "hide player solo", "show party frames", "show raid frames", "group frames invisible", "party hidden", "raid hidden" },
        priority = 60,
    },
    {
        label = "Where do I make names shorter?",
        answer = "Open Global Style > Fonts > Name Shortening for unit names. Castbar spell name shortening is in Global Style > Castbar > Name Shortening.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening",
        anchorText = "Name Shortening names too long max name length castbar spell name shortening",
        keywords = { "name too long", "names too long", "shorten names", "name shortening", "long names", "cut names", "truncate names", "player name too long", "target name too long" },
        priority = 45,
    },
    {
        label = "Where do I make the menu bigger or smaller?",
        answer = "Use the Dashboard scale controls for menu scale or UI scale. You can also resize the MSUF2 window from its corner.",
        pageKey = "home",
        target = "Opens: Dashboard > UI Scale / Menu Scale",
        anchorText = "UI Scale Menu Scale resize window bigger smaller dashboard",
        keywords = { "menu too big", "menu too small", "make menu bigger", "make menu smaller", "ui scale", "menu scale", "resize window", "options too big", "options too small" },
        priority = 45,
    },
    {
        label = "Where do I change click-through auras?",
        answer = "Open Unit Auras > Display for click-through aura behavior. Gameplay contains click-cast and targeting behavior.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display click-through auras click through click cast gameplay targeting",
        keywords = { "clickthrough auras", "click-through auras", "click through auras", "auras block mouse", "can't click through buffs", "aura mouse", "click aura", "click cast not working", "mouse blocked by auras" },
        priority = 45,
    },
    {
        label = "Where are optional modules or style modules?",
        answer = "Open Modules > Style for optional style modules such as rounded unit frames and portrait decoration.",
        pageKey = "modules",
        target = "Opens: Modules > Style",
        anchorText = "Modules Style rounded unitframes portrait decoration optional modules skins",
        keywords = { "modules", "optional modules", "style modules", "rounded unitframes", "rounded frames", "portrait decoration", "portrait deco", "module style", "skins", "rounded", "rund" },
        priority = 70,
    },
    {
        label = "How do I show party or raid frames while solo?",
        answer = "Open Group Frames > Layout and check the solo/player visibility options. That is where MSUF controls whether party-style frames appear when you are alone.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General show solo show player party raid group frames visibility",
        keywords = { "show party frames while solo", "show raid frames while solo", "solo raid frames", "solo party frames", "always show party frames", "always show raid frames", "show player solo", "show self in party", "party frames when alone", "raid frames when alone" },
        priority = 90,
    },
    {
        label = "How do I hide myself from party or raid frames?",
        answer = "Open Group Frames > Layout. The General and Sorting sections control player/self visibility and how player units are ordered in group frames.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout > General",
        anchorText = "General Show player Player first in role Sorting party raid self visibility",
        keywords = { "hide myself from party", "hide player in party", "hide self in party frames", "show player in party frames", "player in raid frames", "self in party frames", "show player", "player first in role", "party contains me" },
        priority = 75,
    },
    {
        label = "How do I show only my HoTs or buffs on party frames?",
        answer = "Open Group Frames > Buffs & Debuffs. Use Buffs, custom buffs, and aura filters to prioritize your own HoTs, externals, and healer buffs.",
        pageKey = "gf_auras",
        target = "Opens: Group Frames > Buffs & Debuffs > Buffs",
        anchorText = "Buffs custom buffs own buffs only mine HoTs healer buffs externals group frames",
        keywords = { "show only my buffs party", "only my hots", "only my HoTs", "track my hots", "track my heals", "show my rejuv", "show my renew", "show my shields", "show externals", "own buffs party", "own buffs raid", "healer hots", "druid hots", "priest hots" },
        priority = 120,
    },
    {
        label = "How do I make my own buffs or debuffs bigger?",
        answer = "Open Unit Auras for unit-frame aura icon sizing and filters. For group frames, use Group Frames > Buffs & Debuffs and custom buff/debuff controls.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Caps & Icons",
        anchorText = "Caps & Icons icon size own buffs own debuffs custom buffs custom debuffs group buffs debuffs",
        keywords = { "make my buffs bigger", "make own buffs bigger", "make my debuffs bigger", "bigger own buffs", "bigger own debuffs", "my buffs bigger", "my debuffs bigger", "own aura size", "personal debuff size", "personal buff size" },
        priority = 95,
    },
    {
        label = "How do I move buff or debuff icons near a unit frame?",
        answer = "Open Unit Auras and use Display plus Caps & Icons for unit-frame aura placement. Buff/debuff icons are configured as aura layout, not moved through MSUF Edit Mode.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display Caps & Icons buffs debuffs position anchor rows spacing unit frame auras",
        keywords = { "move buffs", "move debuffs", "move buff icons", "move debuff icons", "buff icons next to unit frame", "debuff icons next to unit frame", "buffs under portrait", "debuffs under portrait", "unlock buffs debuffs", "buff debuff anchor", "anchor debuffs to buffs", "buffs on top", "debuffs on top" },
        priority = 110,
    },
    {
        label = "How do I add a specific boss debuff or custom aura?",
        answer = "Open Group Frames > Buffs & Debuffs for raid/party aura handling and Aura Utilities. Unit-frame aura filters are in Unit Auras.",
        pageKey = "gf_auras",
        target = "Opens: Group Frames > Buffs & Debuffs > Aura Utilities",
        anchorText = "Aura Utilities custom buffs custom debuffs boss debuffs spell id private auras raid debuffs",
        keywords = { "custom aura", "custom debuff", "custom buff", "boss debuff missing", "boss debuffs not showing", "raid debuff missing", "add boss debuff", "add spell id", "spell id", "spellid", "debuff stack count", "raid mechanic debuff", "healer custom auras" },
        priority = 125,
    },
    {
        label = "How do I show only dispellable debuffs?",
        answer = "Open Unit Auras for unit-frame debuff filtering. For party/raid dispels, use Group Frames > Indicators and Group Frames > Buffs & Debuffs.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators > Dispel / Status Icons",
        anchorText = "Indicators dispel magic curse poison disease debuffs debuff type border group frames",
        keywords = { "only dispellable debuffs", "dispellable debuffs", "dispel debuffs", "magic debuff", "curse debuff", "poison debuff", "disease debuff", "debuff type border", "debuff color border", "show dispels", "healer dispels" },
        priority = 110,
    },
    {
        label = "How do I move or resize target, focus, or boss castbars?",
        answer = "Use MSUF Edit Mode to drag supported castbars. Per-unit castbar enable/icon/text options are on each unit page; shared castbar style is in Global Style > Castbar.",
        pageKey = "home",
        target = "Opens: Dashboard > MSUF Edit Mode",
        anchorText = "MSUF Edit Mode move castbars target castbar focus castbar boss castbar player castbar resize",
        keywords = { "move target castbar", "move focus castbar", "move boss castbar", "move enemy castbar", "resize target castbar", "resize focus castbar", "target cast bar position", "focus cast bar position", "boss cast bar position", "castbar edit mode", "drag castbar" },
        priority = 115,
    },
    {
        label = "How do I stop castbars covering party or raid frames?",
        answer = "MSUF group frames do not use per-player castbars over the health frame. For MSUF castbar positioning, use MSUF Edit Mode and Global Style > Castbar.",
        pageKey = "opt_castbar",
        target = "Opens: Global Style > Castbar",
        anchorText = "Castbar position edit mode group frames party raid castbars over health",
        keywords = { "party castbar covering health", "raid castbar over frame", "castbar covers party frame", "castbar covers raid frame", "group castbar position", "party frame castbar", "raid frame castbar", "cast bars on raid frames" },
        priority = 70,
    },
    {
        label = "Why can I not unlock or drag buffs and debuffs?",
        answer = "MSUF Edit Mode moves frames and supported castbars. Aura icon placement is controlled from Unit Auras or Group Frames > Buffs & Debuffs.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display aura position buffs debuffs edit mode drag unlock frames",
        keywords = { "can't unlock buffs", "can't unlock debuffs", "cannot move buffs", "cannot move debuffs", "unlock buff frames", "unlock debuff frames", "drag buffs debuffs", "buffs not movable", "debuffs not movable", "lock frames buffs", "unlock frames buffs" },
        priority = 130,
    },
    {
        label = "How do I make raid frames cleaner for healing?",
        answer = "Use Group Frames > Layout for size and spacing, Buffs & Debuffs for aura clutter, and Indicators for fixed-position status icons.",
        pageKey = "gf_layout",
        target = "Opens: Group Frames > Layout / Buffs & Debuffs / Indicators",
        anchorText = "Layout Buffs & Debuffs Indicators healer clean raid frames HoTs custom auras fixed positions",
        keywords = { "clean raid frames", "healer raid frames", "minimal raid frames", "declutter raid frames", "fixed hots positions", "fixed aura positions", "healer hots indicators", "raid frame indicators", "too much information raid frames", "healing frames setup" },
        priority = 100,
    },
    {
        label = "How do I change dead, offline, AFK, or ready-check indicators?",
        answer = "Open Group Frames > Indicators for status icons, role/leader/assist, ready check, focus glow, and other group-frame state indicators.",
        pageKey = "gf_indicators",
        target = "Opens: Group Frames > Indicators > Status Icons",
        anchorText = "Status Icons ready check dead ghost offline afk dnd leader assist role icon",
        keywords = { "dead icon", "offline icon", "afk icon", "dnd icon", "ghost icon", "ready check icon", "leader icon", "assist icon", "status icons", "group status icon", "raid status icon" },
        priority = 85,
    },
    {
        label = "How do I hide realm names or shorten player names?",
        answer = "Open Global Style > Fonts > Name Shortening. It controls name shortening globally; unit text placement is on each unit page > Text.",
        pageKey = "opt_fonts",
        target = "Opens: Global Style > Fonts > Name Shortening",
        anchorText = "Name Shortening realm names short names player names font text",
        keywords = { "hide realm names", "remove realm names", "short names", "shorten player names", "names too long", "realm name showing", "server name showing", "name realm", "truncate names" },
        priority = 90,
    },
    {
        label = "How do I get class-colored health bars or names?",
        answer = "Open Global Style > Colors for class bar colors and unitframe colors. Group health colors are in Group Frames > Health & Text.",
        pageKey = "opt_colors",
        target = "Opens: Global Style > Colors > Class Bar Colors",
        anchorText = "Class Bar Colors Unitframe Colors Group Health Colors class colored names health bars",
        keywords = { "class colored health", "class colored names", "class color names", "class color health bars", "green health bars", "health bar class color", "target class color", "player class color", "raid class colors" },
        priority = 105,
    },
    {
        label = "How do I change click-casting so aura icons do not block heals?",
        answer = "Open Unit Auras > Display for click-through aura behavior, then use Gameplay for click-cast, mouseover, and targeting behavior.",
        pageKey = "auras2",
        target = "Opens: Unit Auras > Display",
        anchorText = "Display click-through auras Gameplay click cast mouseover healing party frames",
        keywords = { "auras block heals", "buffs block click casting", "debuffs block click cast", "can't heal through buffs", "mouseover heal blocked", "click cast blocked by aura", "heal mouseover auras", "party frame click through buffs" },
        priority = 115,
    },
    {
        label = "How do I open the MSUF options?",
        answer = "Use /msuf to open MSUF2. The Dashboard also contains reset, support, profile, and scale tools.",
        pageKey = "home",
        target = "Opens: Dashboard",
        anchorText = "Dashboard slash command msuf options menu support profiles reset",
        keywords = { "how to open msuf", "open msuf", "open options", "open addon options", "slash command", "/msuf", "msuf menu", "where is options", "addon options", "config menu", "configuration menu", "settings menu" },
        priority = 700,
    },
}

local SEARCH_EASTER_EGGS = {
    { name = "don lumen", result = "requested this feature" },
    { name = "Niuki", result = "Is the best Warlock in Retreat" },
    { name = "R41z0r", result = "He makes you better" },
    { name = "Unhalted", result = "South Africa ftw" },
    { name = "Hayato", result = "forgot to bind his heal spells" },
}

local function BuildSearchRecords()
    local pageInfos, pageInfoByKey = BuildSearchPageInfos()

    local records, seenRecords = {}, {}
    for i = 1, #pageInfos do
        local info = pageInfos[i]
        local pageParts = {}
        AddSearchText(pageParts, info.group)
        AddSearchText(pageParts, info.title)
        AddRawSearchText(pageParts, SEARCH_KEYWORDS[info.key])
        AddSearchRecord(records, seenRecords, info, info.label or info.title or info.key, nil, "page", pageParts)
    end

    for _, entry in pairs(_searchRegistry) do
        local info = pageInfoByKey[entry.pageKey] or {
            key = entry.pageKey,
            label = entry.pageKey,
            title = entry.pageKey,
            group = "",
        }
        local extra = {}
        AddValuesSearchText(extra, entry.values)
        if type(entry.keywords) == "string" then
            AddSearchText(extra, entry.keywords)
        elseif type(entry.keywords) == "table" then
            for i = 1, #entry.keywords do AddSearchText(extra, entry.keywords[i]) end
        end
        AddSearchText(extra, entry.help)
        local rec = AddSearchRecord(records, seenRecords, info, entry.label, entry.anchor, entry.kind or "control", extra)
        if rec then
            rec.answer = entry.help
        end
    end

    for i = 1, #SEARCH_FAQ do
        local faq = SEARCH_FAQ[i]
        local pageKey = faq.pageKey or "home"
        local info = pageInfoByKey[pageKey] or { key = pageKey, label = "FAQ", title = "FAQ", group = "" }
        local extra = { faq.answer, faq.target, faq.anchorText }
        for k = 1, #(faq.keywords or {}) do extra[#extra + 1] = faq.keywords[k] end
        local rec = AddSearchRecord(records, seenRecords, info, faq.label, nil, "faq", extra)
        if rec then
            rec.answer = faq.answer
            rec.target = faq.target
            rec.anchorFallback = faq.anchorText or faq.label
            rec.priority = tonumber(faq.priority) or 0
            rec.faq = true
        end
    end

    for i = 1, #SEARCH_EASTER_EGGS do
        local egg = SEARCH_EASTER_EGGS[i]
        local info = { key = "search", label = "", title = "", group = "" }
        local rec = AddSearchRecord(records, seenRecords, info, egg.name, nil, "easteregg", { egg.result, egg.name })
        if rec then
            rec.answer = egg.result
            rec.noOpen = true
            rec.priority = 1200
            rec.easterEgg = true
        end
    end

    return records
end

local SearchPages

local function RefreshSearchResultsPage()
    if M.activeKey ~= "search" then return end
    local query = TrimText(M.searchQuery or "")
    if query == "" or #NormalizeSearchText(query) < MIN_SEARCH_QUERY_LEN then return end
    M.searchResults = nil
    M.searchResultsQuery = nil
    M.searchResults = SearchPages(query)
    M.searchResultsQuery = query
    if M.InvalidatePage then M.InvalidatePage("search") end
    if M.SelectPage then M.SelectPage("search") end
end

local function FinishSearchBackgroundIndex()
    _searchIndexing = false
    _searchIndexQueue = nil
    local query = TrimText(M.searchQuery or "")
    local shouldRefresh = M.activeKey == "search" and query ~= "" and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    if shouldRefresh and _searchRecordsDirty then
        _searchRecords = BuildSearchRecords()
        _searchRecordsDirty = false
    end
    if shouldRefresh then RefreshSearchResultsPage() end
end

local function StartSearchBackgroundIndex()
    if _searchIndexing then return end
    if SearchCombatLocked() then return end
    if not (_G.C_Timer and _G.C_Timer.After) then return end
    if not (M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
    if not M.scrollChild then return end

    local pageInfos = BuildSearchPageInfos()
    local queue = {}
    for i = 1, #pageInfos do
        local info = pageInfos[i]
        local cached = M.cache and M.cache[info.key]
        if info.key ~= "search" and not (cached and cached.wrapper) then
            queue[#queue + 1] = info.key
        end
    end
    if #queue == 0 then return end

    _searchIndexing = true
    _searchIndexQueue = queue

    local function Step()
        if not _searchIndexing then return end
        if SearchCombatLocked() or not (M.frame and M.frame.IsShown and M.frame:IsShown()) then
            CancelSearchBackgroundIndex()
            return
        end

        local key = table.remove(_searchIndexQueue, 1)
        if key then
            BuildPageEntry(key, true)
            MarkSearchIndexDirty()
        end

        if _searchIndexQueue and #_searchIndexQueue > 0 then
            _G.C_Timer.After(SEARCH_BACKGROUND_STEP_SEC, Step)
        else
            FinishSearchBackgroundIndex()
        end
    end

    _G.C_Timer.After(0, Step)
end

local function GetSearchRecords()
    if _searchIndexing and _searchRecords then
        return _searchRecords
    end
    if not _searchRecords or _searchRecordsDirty then
        _searchRecords = BuildSearchRecords()
        _searchRecordsDirty = false
    end
    StartSearchBackgroundIndex()
    return _searchRecords
end

local function CurateSearchResults(results, supportQuestion)
    local topScore = results[1] and (tonumber(results[1].score) or 0) or 0
    local floorScore = SEARCH_MIN_RESULT_SCORE
    if topScore >= 600 then
        floorScore = math.max(floorScore, topScore * (supportQuestion and 0.70 or 0.42))
    elseif topScore >= 300 then
        floorScore = math.max(floorScore, topScore * 0.30)
    end

    local curated = {}
    for i = 1, #results do
        local rec = results[i]
        if rec and (tonumber(rec.score) or 0) >= floorScore then
            curated[#curated + 1] = rec
            if #curated >= SEARCH_MAX_RESULTS then break end
        end
    end
    return curated
end

function SearchPages(query)
    query = TrimText(query)
    if SearchCombatLocked() then
        CancelSearchBackgroundIndex()
        return {}
    end
    local normalized, clauses = BuildSearchQueryClauses(query)
    if #clauses == 0 then return {} end
    if #normalized < MIN_SEARCH_QUERY_LEN then return {} end

    local supportQuestion = SearchLooksLikeSupportQuestion(query)
    local results = {}
    local records = GetSearchRecords()
    for i = 1, #records do
        local rec = records[i]
        local score = 0
        local matched = true
        for c = 1, #clauses do
            local ok, clauseScore = SearchClauseScore(rec, clauses[c])
            if not ok then
                matched = false
                break
            end
            score = score + clauseScore
        end
        if matched then
            if rec.labelNorm == normalized or rec.titleNorm == normalized then score = score + 260 end
            if rec.labelNorm:sub(1, #normalized) == normalized then score = score + 130 end
            if rec.haystack and rec.haystack:find(normalized, 1, true) then score = score + 80 end
            if rec.kind == "section" then score = score + 70 end
            if rec.kind == "faq" then score = score + 55 end
            if supportQuestion then score = score + SearchSupportQuestionBoost(rec, clauses) end
            if rec.kind ~= "page" then score = score + 45 end
            if rec.kind == "slider" or rec.kind == "dropdown" or rec.kind == "toggle" then score = score + 25 end
            if rec.priority then score = score + rec.priority end
            rec.score = score
            results[#results + 1] = rec
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.hint or "") ~= (b.hint or "") then return tostring(a.hint or "") < tostring(b.hint or "") end
        if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
        return tostring(a.label) < tostring(b.label)
    end)
    return CurateSearchResults(results, supportQuestion)
end

local function SearchQueryReady(query)
    return #NormalizeSearchText(query or "") >= MIN_SEARCH_QUERY_LEN
end

local function ShowSearchPageForQuery(query)
    query = TrimText(query)
    if query ~= "" and M.activeKey ~= "search" then
        M.searchReturnKey = M.activeKey or M.searchReturnKey or "home"
    end
    M.InvalidatePage("search")
    if query ~= "" then
        M.SelectPage("search")
    elseif M.activeKey == "search" then
        M.SelectPage(M.searchReturnKey or "home")
    end
end

local function RunSearchInputQuery(query, openPage)
    query = TrimText(query)
    M.searchQuery = query
    M.searchResultsPending = nil

    if query == "" then
        M.searchResults = {}
        M.searchResultsQuery = ""
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    if SearchCombatLocked() then
        CancelSearchBackgroundIndex()
        M.searchResults = {}
        M.searchResultsQuery = query
        if openPage and M.activeKey ~= "search" then ShowSearchPageForQuery(query) end
        return
    end

    if not SearchQueryReady(query) then
        M.searchResults = {}
        M.searchResultsQuery = query
        if openPage then ShowSearchPageForQuery(query) end
        return
    end

    M.searchResults = SearchPages(query)
    M.searchResultsQuery = query
    if openPage then ShowSearchPageForQuery(query) end
end

local function ScheduleSearchInputQuery(searchBox, query)
    query = TrimText(query)
    _searchInputSerial = _searchInputSerial + 1
    local serial = _searchInputSerial

    M.searchQuery = query

    if query == "" or SearchCombatLocked() or not SearchQueryReady(query) then
        RunSearchInputQuery(query, true)
        return
    end

    M.searchResultsPending = true
    M.searchResultsQuery = query
    if M.activeKey ~= "search" then
        M.searchResults = {}
        ShowSearchPageForQuery(query)
    end

    local function RunLatest()
        if serial ~= _searchInputSerial then return end
        if searchBox and searchBox.GetText then
            local latest = TrimText(searchBox:GetText() or "")
            if latest ~= query then return end
        end
        RunSearchInputQuery(query, true)
    end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(SEARCH_INPUT_DEBOUNCE_SEC, RunLatest)
    else
        RunLatest()
    end
end

local function OpenSearchResults(query)
    _searchInputSerial = _searchInputSerial + 1
    RunSearchInputQuery(query, true)
end

local function ScoreAnchorText(text, query, fallback)
    local normalized = NormalizeSearchText(text)
    if normalized == "" then return 0 end
    local queryNorm, clauses = BuildSearchQueryClauses(query)
    if #clauses == 0 and fallback then queryNorm, clauses = BuildSearchQueryClauses(fallback) end
    if #clauses == 0 then return 0 end

    local score, matched = 0, 0
    if queryNorm ~= "" then
        if normalized == queryNorm then score = score + 900 end
        if normalized:find(queryNorm, 1, true) then score = score + 260 end
    end
    local tokens = BuildSearchTokenList(normalized)
    for i = 1, #clauses do
        local clause = clauses[i]
        local best = 0
        for k = 1, #clause.terms do
            local term = clause.terms[k]
            if normalized == term then
                best = math.max(best, 220)
            elseif normalized:sub(1, #term) == term then
                best = math.max(best, 130)
            elseif normalized:find(term, 1, true) then
                best = math.max(best, 70)
            elseif #term >= 5 and not term:find(" ", 1, true) then
                local maxDistance = (#term >= 8) and 2 or 1
                for t = 1, #tokens do
                    if math.abs(#tokens[t] - #term) <= maxDistance and SearchEditDistanceWithin(tokens[t], term, maxDistance) then
                        best = math.max(best, 24)
                        break
                    end
                end
            end
        end
        if best > 0 then
            score = score + best
            matched = matched + 1
        end
    end
    if matched == 0 then return 0 end
    if matched == #clauses then score = score + 180 else score = score - ((#clauses - matched) * 35) end
    if #normalized <= 42 then score = score + 30 end
    if #normalized > 120 then score = score - 40 end
    return score
end

local function CollectSearchAnchorCandidates(frame, out, depth)
    if not frame or depth > 16 then return end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
                local text = region:GetText()
                if text and text ~= "" then
                    out[#out + 1] = { region = region, text = text }
                end
            end
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            CollectSearchAnchorCandidates(children[i], out, depth + 1)
        end
    end
end

local function FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return nil end
    if preferredAnchor and preferredAnchor.GetTop then return preferredAnchor end

    local candidates = {}
    CollectSearchAnchorCandidates(wrapper, candidates, 1)

    local best, bestScore
    for i = 1, #candidates do
        local candidate = candidates[i]
        local score = ScoreAnchorText(candidate.text, query, fallback)
        if score > 0 and (not bestScore or score > bestScore) then
            best, bestScore = candidate, score
        end
    end
    return best and best.region or nil
end

local function OpenAnchorCollapsibles(region)
    local entries, seen = {}, {}
    local parent = region and region.GetParent and region:GetParent()
    while parent do
        local entry = parent._msuf2CollapsibleEntry
        if entry and not seen[entry] then
            seen[entry] = true
            entries[#entries + 1] = entry
        end
        parent = parent.GetParent and parent:GetParent() or nil
    end

    local opened = false
    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry and not entry.open and entry.header and entry.header.Click then
            entry.header:Click()
            opened = true
        end
    end
    return opened
end

local function ClampScrollOffset(offset)
    offset = math.max(0, tonumber(offset) or 0)
    local childH = (M.scrollChild and M.scrollChild.GetHeight and M.scrollChild:GetHeight()) or CONTENT_H
    local frameH = (M.scrollFrame and M.scrollFrame.GetHeight and M.scrollFrame:GetHeight()) or CONTENT_H
    local maxScroll = math.max(0, childH - frameH)
    if offset > maxScroll then offset = maxScroll end
    return offset
end

local function SearchAnchorOffset(wrapper, region)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return nil end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return nil end
    return ClampScrollOffset((wrapperTop - regionTop) - 42)
end

local function HighlightSearchAnchor(wrapper, region)
    if not (wrapper and region and wrapper.GetTop and region.GetTop) then return end
    local wrapperTop = wrapper:GetTop()
    local regionTop = region:GetTop()
    if not (wrapperTop and regionTop) then return end

    local offset = math.max(0, wrapperTop - regionTop)
    local highlight = wrapper._msuf2SearchHighlight
    if not highlight then
        highlight = CreateFrame("Frame", nil, wrapper)
        highlight:SetFrameLevel((wrapper.GetFrameLevel and wrapper:GetFrameLevel() or 1) + 40)
        local fill = highlight:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(0.20, 0.58, 1.00, 0.16)
        local top = highlight:CreateTexture(nil, "ARTWORK")
        top:SetHeight(1)
        top:SetPoint("TOPLEFT")
        top:SetPoint("TOPRIGHT")
        top:SetColorTexture(0.38, 0.78, 1.00, 0.65)
        local bottom = highlight:CreateTexture(nil, "ARTWORK")
        bottom:SetHeight(1)
        bottom:SetPoint("BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetColorTexture(0.38, 0.78, 1.00, 0.45)
        highlight._msuf2Anim = highlight:CreateAnimationGroup()
        local fade = highlight._msuf2Anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetStartDelay(0.75)
        fade:SetDuration(0.75)
        highlight._msuf2Anim:SetScript("OnFinished", function()
            if highlight then highlight:Hide() end
        end)
        wrapper._msuf2SearchHighlight = highlight
    end
    if highlight._msuf2Anim and highlight._msuf2Anim.Stop then highlight._msuf2Anim:Stop() end
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 8, -math.max(0, offset - 9))
    highlight:SetSize(math.max(220, (wrapper.GetWidth and wrapper:GetWidth() or CONTENT_W) - 28), 32)
    highlight:SetAlpha(1)
    highlight:Show()
    if highlight._msuf2Anim and highlight._msuf2Anim.Play then highlight._msuf2Anim:Play() end
end

local function RunSoon(fn)
    if SearchCombatLocked() then
        fn()
        return
    end
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, fn)
    else
        fn()
    end
end

local function ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor)
    if M.activeKey ~= pageKey then return end
    local entry = M.cache and M.cache[pageKey]
    local wrapper = entry and entry.wrapper
    if not wrapper then return end

    local region = FindSearchAnchor(pageKey, query, fallback, preferredAnchor)
    if not region then return end
    local opened = OpenAnchorCollapsibles(region)
    local function finish()
        local offset = SearchAnchorOffset(wrapper, region)
        if offset and M.scrollFrame and M.scrollFrame.SetVerticalScroll then
            M.scrollFrame:SetVerticalScroll(offset)
        end
        HighlightSearchAnchor(wrapper, region)
    end
    if opened then RunSoon(finish) else finish() end
end

local function OpenSearchTarget(pageKey, query, fallback, preferredAnchor)
    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
    M.SelectPage(pageKey)
    RunSoon(function() ScrollToSearchAnchor(pageKey, query, fallback, preferredAnchor) end)
end

local function BuildSearchPage(ctx)
    local root = ctx.wrapper
    local width = ctx.width
    local query = TrimText(M.searchQuery or "")
    local combatLocked = SearchCombatLocked() and true or false
    local queryReady = not combatLocked and #NormalizeSearchText(query) >= MIN_SEARCH_QUERY_LEN
    local results = M.searchResults or {}
    if M.searchResultsQuery ~= query and not M.searchResultsPending then
        results = combatLocked and {} or SearchPages(query)
        M.searchResults = results
        M.searchResultsQuery = query
    end

    local b = W.PageBuilder(ctx)
    b:Header("Search", query ~= "" and M.Format("Results for \"%s\"", query) or "Type in the search box on the left.", 78)

    local maxVisible = SEARCH_VISIBLE_RESULTS
    local visible = math.min(#results, maxVisible)
    local hasExpandedResult = false
    for i = 1, visible do
        if results[i] and (results[i].kind == "faq" or results[i].kind == "easteregg") then
            hasExpandedResult = true
            break
        end
    end
    local columns = (hasExpandedResult and 1) or (width >= 760 and 2 or 1)
    local gap = 12
    local colW = math.floor((width - 24 - gap * (columns - 1)) / columns)
    local rowH = hasExpandedResult and 62 or 30
    local resultTopY = _searchIndexing and -88 or -70
    local rows = math.max(3, math.ceil(math.max(visible, 1) / columns))
    local sectionH = math.max(160, 74 + rows * rowH + (_searchIndexing and 18 or 0))
    local sec = b:Section("Search Results", sectionH)

    if combatLocked then
        W.Text(sec, "Search is paused in combat.", 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "MSUF2 does not build or refresh the search index during combat.", 14, -70, width - 28, T.colors.dim)
    elseif query == "" then
        W.Text(sec, "Start typing to search every MSUF2 menu page.", 14, -44, width - 28, T.colors.muted)
    elseif not queryReady then
        W.Text(sec, M.Format("Type at least %d characters to search.", MIN_SEARCH_QUERY_LEN), 14, -44, width - 28, T.colors.muted)
    elseif M.searchResultsPending then
        W.Text(sec, M.Format("Searching for \"%s\"...", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, "Results update after you stop typing for a moment.", 14, -70, width - 28, T.colors.dim)
    elseif #results == 0 then
        W.Text(sec, M.Format("No results for \"%s\".", query), 14, -44, width - 28, T.colors.muted)
        W.Text(sec, _searchIndexing and "Still indexing menu pages..." or "Try a page name like bars, profiles, auras, castbar, colors, group, or target.", 14, -70, width - 28, T.colors.dim)
    else
        W.Text(sec, M.Format("Best %d match(es). Press Enter to open the first match.", visible), 14, -44, width - 28, T.colors.muted)
        if _searchIndexing then
            W.Text(sec, "Indexing more menu pages in the background.", 14, -62, width - 28, T.colors.dim)
        end
        for i = 1, visible do
            local rec = results[i]
            local col = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            local x = 14 + col * (colW + gap)
            local y = resultTopY - row * rowH
            local kind = CONTROL_KIND_LABEL[rec.kind or ""] or (rec.kind == "page" and "Page") or nil
            local prefix = rec.hint ~= "" and rec.hint or rec.group
            local text = prefix ~= "" and (ShortLabel(prefix, 42) .. " > " .. ShortLabel(rec.label, 38)) or rec.label
            if kind and rec.kind ~= "text" then text = text .. " [" .. kind .. "]" end
            local btn = T.Button(sec, text, colW, 22)
            btn:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
            local pageKey = rec.key
            local fallback = rec.anchorFallback or rec.label or rec.title
            local anchor = rec.anchor
            local noOpen = rec.noOpen
            btn:SetScript("OnClick", function()
                if noOpen then
                    if M.nav and M.nav.searchBox then M.nav.searchBox:ClearFocus() end
                    return
                end
                OpenSearchTarget(pageKey, query, fallback, anchor)
            end)
            if (rec.kind == "faq" or rec.kind == "easteregg") and rec.answer then
                W.Text(sec, ShortLabel(rec.answer, 132), x + 8, y - 24, colW - 16, T.colors.dim)
                if rec.target and rec.target ~= "" then
                    W.Text(sec, ShortLabel(rec.target, 112), x + 8, y - 42, colW - 16, T.colors.muted)
                end
            end
        end
        if #results > maxVisible then
            W.Text(sec, M.Format("Showing the best %d matches. Add one more word to narrow it further.", maxVisible), 14, resultTopY - rows * rowH, width - 28, T.colors.dim)
        end
    end

    local quick = b:Section("Support Search Examples", 150)
    local shortcuts = {
        { "Move Frames", "where do I move my unitframe" },
        { "Background", "change my backgrond" },
        { "Raid Frames", "move raid frames" },
        { "Text Size", "make text bigger" },
        { "Profiles", "import profile wago" },
        { "Castbar", "evoker castbar" },
        { "Buffs", "show only my buffs" },
        { "Blizzard", "hide blizzard frames" },
        { "Range Check", "unit frame range check" },
        { "Misc", "where is miscellaneous" },
        { "Performance", "why is msuf lagging" },
        { "Minimap", "where is the minimap icon setting" },
    }
    local buttonW = math.floor((width - 56) / 3)
    for i = 1, #shortcuts do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local searchQuery = shortcuts[i][2]
        local btn = T.Button(quick, shortcuts[i][1], buttonW, 22)
        btn:SetPoint("TOPLEFT", quick, "TOPLEFT", 14 + col * (buttonW + 14), -38 - row * 28)
        btn:SetScript("OnClick", function()
            if M.nav and M.nav.searchBox then
                M.nav.searchBox._msuf2SearchInternal = true
                M.nav.searchBox:SetText(searchQuery)
                M.nav.searchBox._msuf2SearchInternal = nil
                M.nav.searchBox:ClearFocus()
            end
            OpenSearchResults(searchQuery)
        end)
    end

    ctx:SetContentHeight(math.max(CONTENT_H, math.abs(b.y) + 42))
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

local function CreateNavButton(parent, key, label, indent)
    local btn = T.Button(parent, M.Tr(label), NAV_W - 38 - (indent or 0), NAV_BUTTON_H)
    btn:SetScript("OnClick", function() M.SelectPage(key) end)
    btn._msuf2SkipHistoryCheckpoint = true
    btn._msuf2NavIndent = indent or 0
    btn._msuf2RawLabel = label
    if T.AttachNavIcon then T.AttachNavIcon(btn, key, (indent or 0) > 0) end
    M.navButtons[key] = btn
    return btn
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
        _searchInputSerial = _searchInputSerial + 1
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
        _searchInputSerial = _searchInputSerial + 1
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
        _searchInputSerial = _searchInputSerial + 1
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
            btn._msuf2NavHeaderId = id
            btn._msuf2RawLabel = item.header
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("LEFT", 24, 0)
            btn._msuf2Label:SetPoint("RIGHT", -8, 0)
            btn._msuf2Label:SetJustifyH("LEFT")
            btn._msuf2Label:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.88)
            local arrow = btn:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(10, 10)
            arrow:SetPoint("LEFT", btn, "LEFT", 5, 0)
            arrow:SetTexture(T.media.collapseArrow)
            arrow:SetVertexColor(0.45, 0.55, 0.72, 1)
            btn._msuf2NavArrow = arrow
            btn:SetScript("OnClick", function(self)
                local groupId = self._msuf2NavHeaderId
                M.navHeaderState[groupId] = not M.navHeaderState[groupId]
                if parent._msuf2NavReflow then parent:_msuf2NavReflow() end
            end)
            btn._msuf2SkipHistoryCheckpoint = true
            M.navHeaders[id] = btn
            created[#created + 1] = { kind = "header", id = id, button = btn }
        elseif item.key then
            local indent = item.group and 12 or 0
            local btn = CreateNavButton(list, item.key, item.label, indent)
            if item.group then M.navGroupForKey[item.key] = item.group end
            created[#created + 1] = { kind = "page", group = item.group, button = btn }
            if item.key == "profiles" then
                created[#created + 1] = { kind = "history", frame = CreateHistoryControls(list) }
            end
        end
    end
    function parent:_msuf2NavReflow()
        local y = -4
        for i = 1, #created do
            local item = created[i]
            local btn = item.button
            if item.kind == "header" then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", list, "TOPLEFT", 12, y)
                if btn._msuf2NavArrow then
                    btn._msuf2NavArrow:SetRotation(M.navHeaderState[item.id] and (math.pi * 0.5) or 0)
                    btn._msuf2NavArrow:SetVertexColor(0.45, 0.55, 0.72, 1)
                end
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
    bar:SetFrameStrata("DIALOG")
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
    f:SetFrameStrata("DIALOG")
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
        proxy:SetFrameStrata("DIALOG")
        proxy:SetFrameLevel(f:GetFrameLevel() + 80)
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

local function BuildDashboardChangelog(parent, cardWidth)
    local data = GetBundledChangelog()
    local left, right = 14, 14
    local top = -130
    local headerH = 48
    local contentW = max(120, (cardWidth or 420) - left - right)
    local scrollW = max(80, (cardWidth or 420) - left - 44)

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

    local line = parent:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top + 4)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -right, top + 4)
    line:SetHeight(1)
    line:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.38)

    local header = CreateFrame("Button", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
    header:SetSize(contentW, headerH)

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
    arrow:SetPoint("TOPRIGHT", header, "TOPRIGHT", -54, -9)
    arrow:SetTexture(T.media.collapseArrow)

    local title = T.Font(header, "GameFontNormal", "Release Notes", T.colors.text)
    title:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -3)
    title:SetPoint("RIGHT", header, "RIGHT", -92, 0)
    title:SetJustifyH("LEFT")

    local current = data and (data.currentVersion or (data.entries[1] and data.entries[1].version)) or nil
    local range = data and (data.rangeLabel or current or "") or "No release notes bundled with this build."
    local subtitle = RawFont(header, "GameFontDisableSmall", range, T.colors.dim, 0)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    subtitle:SetJustifyH("LEFT")

    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.dim)
    hint:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -5)
    hint:SetJustifyH("RIGHT")

    local summary = RawFont(parent, "GameFontHighlightSmall", "", T.colors.muted, 0)
    summary:SetPoint("TOPLEFT", parent, "TOPLEFT", left + 24, top - headerH - 8)
    summary:SetWidth(max(80, contentW - 28))
    summary:SetJustifyH("LEFT")
    if summary.SetWordWrap then summary:SetWordWrap(true) end

    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        summary:SetText("No release notes bundled with this build.")
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end

    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", left + 2, top - headerH - 12)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -34, 70)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)

    local y = -2
    local function AddText(text, fontObject, color, indent, gap)
        local rawText = tostring(text or "")
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

    local function AddBullet(text)
        local dot = child:CreateTexture(nil, "ARTWORK")
        dot:SetSize(3, 3)
        dot:SetPoint("TOPLEFT", child, "TOPLEFT", 8, y - 6)
        dot:SetColorTexture(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], 0.82)
        return AddText(text, "GameFontHighlightSmall", T.colors.muted, 18, 5)
    end

    local entries = data.entries
    local maxEntries = min(#entries, 1)
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
                        AddText(tostring(section.title or ""), "GameFontNormalSmall", T.colors.accent2, 0, 4)
                        for bulletIndex = 1, #section.bullets do
                            AddBullet(tostring(section.bullets[bulletIndex] or ""))
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
    summary:SetText(M.Format("%s  -  %d sections. Click to view the bundled release notes.", currentLabel, sectionCount))

    local open = M.dashboardChangelogOpen == true
    local function PaintHeader(isOpen)
        if arrow.SetRotation then arrow:SetRotation(isOpen and (math.pi * 0.5) or 0) end
        if arrow.SetVertexColor then
            local c = isOpen and T.colors.accent or T.colors.accent2
            arrow:SetVertexColor(c[1], c[2], c[3], 0.95)
        end
        if headerBg.SetColorTexture then
            headerBg:SetColorTexture(0, 0, 0, 0)
        end
        if headerEdge.SetColorTexture then
            headerEdge:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], isOpen and 0.58 or 0.34)
        end
        hint:SetText(isOpen and "Hide" or "View")
    end
    local function RefreshOpenState()
        M.dashboardChangelogOpen = open
        scroll:SetShown(open)
        summary:SetShown(not open)
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
    end)
    header:SetScript("OnEnter", function()
        if headerBg.SetColorTexture then headerBg:SetColorTexture(1, 1, 1, 0.025) end
    end)
    header:SetScript("OnLeave", function()
        PaintHeader(open)
    end)
    RefreshOpenState()
end

local function BuildDashboard(ctx)
    local root = ctx.wrapper
    local width = ctx.width
    local gap = 14
    local x0 = 12
    local y = -12
    local colW = math.floor((width - gap) / 2)

    local function Card(title, x, top, w, h)
        local card = T.Panel(root, nil, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft)
        card:SetPoint("TOPLEFT", root, "TOPLEFT", x, top)
        card:SetSize(w, h)
        local label = T.Font(card, "GameFontNormal", title or "", T.colors.text)
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -12)
        card._msuf2Title = label
        return card
    end

    local function AddButton(parent, text, x, top, w, h, onClick)
        local btn = T.Button(parent, text, w, h or 22)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
        if onClick then btn:SetScript("OnClick", onClick) end
        return btn
    end

    local tip = Card("Dashboard", x0, y, width, 98)
    W.Text(tip, "Tip: Quick reset: If something feels off, try /msuf reset for frame positions.", 14, -42, width - 28, T.colors.muted)
    local actionW = math.floor((width - 40) / 2)
    local editMode = AddButton(tip, "Edit Mode: Off", 14, -64, actionW, 24, function()
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
        RefreshDashboardEditModeButton()
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end)
    M.dashboardEditModeButton = editMode
    if T.SkinPrimaryButton then T.SkinPrimaryButton(editMode) end
    RefreshDashboardEditModeButton()
    M.AddRefresher(ctx, RefreshDashboardEditModeButton)
    local reset = AddButton(tip, "Reset Positions", 26 + actionW, -64, actionW, 24, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "reset")
        end
    end)
    T.SkinDangerButton(reset)

    y = y - 110
    local quick = Card("Quick Navigation", x0, y, colW, 108)
    W.Text(quick, "Jump into the most-used MSUF sections.", 14, -36, colW - 28, T.colors.muted)
    local qW = math.floor((colW - 40) / 2)
    AddButton(quick, "Colors", 14, -62, qW, 20, function() M.SelectPage("opt_colors") end)
    AddButton(quick, "Gameplay", 26 + qW, -62, qW, 20, function() M.SelectPage("gameplay") end)
    AddButton(quick, "Unit Auras", 14, -88, qW, 20, function() M.SelectPage("auras2") end)
    AddButton(quick, "Class Resources", 26 + qW, -88, qW, 20, function() M.SelectPage("classpower") end)

    local profile = Card("Active Profile", x0 + colW + gap, y, colW, 108)
    local prof = tostring(_G.MSUF_ActiveProfile or "Default")
    local pText = T.Font(profile, "GameFontNormalLarge", prof, T.colors.text)
    pText:SetPoint("TOPLEFT", profile, "TOPLEFT", 14, -40)
    W.Text(profile, "Use the Profiles page for switching, export and import.", 14, -68, colW - 140, T.colors.muted)
    AddButton(profile, "Manage", colW - 114, -34, 100, 22, function() M.SelectPage("profiles") end)
    M.AddRefresher(ctx, function()
        pText:SetText(tostring(_G.MSUF_ActiveProfile or "Default"))
    end)

    y = y - 120
    local scaleCardH = 448
    local scale = Card("UI Scale", x0, y, colW, scaleCardH)
    local wago = Card("Wago Profiles", x0 + colW + gap, y, colW, scaleCardH)

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

    local pendingGlobalEnabled, pendingGlobalScale
    local globalStatus = W.Text(scale, "", 14, -54, colW - 28, T.colors.muted)
    local globalScale = W.Slider(scale, "Global UI Scale", 30, 150, 1, colW - 54)
    HideSliderValueBox(globalScale)
    globalScale:ClearAllPoints()
    globalScale:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -72)
    globalScale:SetPoint("RIGHT", scale, "RIGHT", -26, 0)
    globalScale._msuf2Title:ClearAllPoints()
    globalScale._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -34)
    EnablePercentWheel(globalScale, 30, 150, 1)

    local function RefreshGlobalScale()
        local _, ui = GlobalState()
        local selectedEnabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or ui.Enabled
        local selectedScale = Clamp(pendingGlobalScale or ui.Scale, 0.3, 1.5)
        local applied = ui.Enabled and (math.floor(ui.Scale * 100 + 0.5) .. "%") or "Off"
        local selected = selectedEnabled and (math.floor(selectedScale * 100 + 0.5) .. "%") or "Off"
        globalStatus:SetText(M.Format("Applied: %s   Selected: %s", applied, selected))
        SetSliderValueSafe(globalScale, SnapPct(selectedScale * 100, 30, 150, 1))
    end

    globalScale:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        local pct = SnapPct(value, 30, 150, 1)
        if pct ~= value then
            SetSliderValueSafe(self, pct)
        end
        pendingGlobalEnabled = true
        pendingGlobalScale = Clamp(pct / 100, 0.3, 1.5)
        RefreshGlobalScale()
    end)

    local function ApplyGlobalScale(enabled, value, preset)
        local g, ui = GlobalState()
        ui.Enabled = enabled == true
        ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
        g.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
        g.globalUiScaleValue = ui.Enabled and ui.Scale or nil
        pendingGlobalEnabled, pendingGlobalScale = nil, nil
        if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
            pcall(_G.MSUF_SetGlobalUiScale, ui.Scale, true)
        elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            pcall(_G.MSUF_ResetGlobalUiScale, true)
        end
        M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false })
        RefreshGlobalScale()
    end

    AddButton(scale, "1080p", 14, -104, 62, 18, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end)
    AddButton(scale, "1440p", 82, -104, 62, 18, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end)
    AddButton(scale, "4K", 150, -104, 48, 18, function() ApplyGlobalScale(true, 768 / 2160, "4k") end)
    AddButton(scale, "Pixel", 204, -104, 62, 18, function() ApplyGlobalScale(true, PixelScale(), "pixel") end)
    AddButton(scale, "Apply", 14, -128, 72, 20, function()
        local _, ui = GlobalState()
        local enabled = (pendingGlobalEnabled ~= nil) and pendingGlobalEnabled or ui.Enabled
        ApplyGlobalScale(enabled, pendingGlobalScale or ui.Scale, enabled and "custom" or "auto")
    end)
    AddButton(scale, "Revert", 94, -128, 72, 20, function()
        pendingGlobalEnabled, pendingGlobalScale = nil, nil
        RefreshGlobalScale()
    end)
    AddButton(scale, "Off", 174, -128, 58, 20, function()
        pendingGlobalEnabled = false
        RefreshGlobalScale()
    end)
    AddButton(scale, "UI Off", 240, -128, 72, 20, function() ApplyGlobalScale(false, nil, "auto") end)

    local pendingMsufScale
    local msufStatus = W.Text(scale, M.Format("Applied: %d%%  Selected: %d%%", 100, 100), 14, -168, colW - 28, T.colors.muted)
    scale._msuf2CursorY = -146
    local msufScale = W.Slider(scale, "MSUF Frame Scale", 25, 150, 5, colW - 54)
    HideSliderValueBox(msufScale)
    msufScale:ClearAllPoints()
    msufScale:SetPoint("TOPLEFT", msufStatus, "BOTTOMLEFT", 0, -8)
    msufScale:SetPoint("RIGHT", scale, "RIGHT", -26, 0)
    msufScale._msuf2Title:ClearAllPoints()
    msufScale._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -146)
    EnablePercentWheel(msufScale, 25, 150, 5)

    local msufApply, msufRevert
    local function AppliedMsufScale()
        local g = M.GetGeneralDB()
        return Clamp(tonumber(g.msufUiScale) or 1, 0.25, 1.5)
    end
    local function PendingMsufScale()
        return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 1.5)
    end
    local function RefreshMsufScale()
        local applied = AppliedMsufScale()
        local pending = PendingMsufScale()
        local changed = math.abs(applied - pending) > 0.001
        msufStatus:SetText(M.Format("Applied: %d%%  Selected: %d%%", math.floor(applied * 100 + 0.5), math.floor(pending * 100 + 0.5)))
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
    msufApply = AddButton(scale, "Apply", 14, -214, 72, 20, function()
        local g = M.GetGeneralDB()
        local scaleValue = PendingMsufScale()
        g.msufUiScale = scaleValue
        pendingMsufScale = nil
        if type(_G.MSUF_ApplyMsufScale) == "function" then
            pcall(_G.MSUF_ApplyMsufScale, scaleValue)
        end
        M.RequestGeneralApply("MSUF2_DASH_SCALE", { preview = true, applyAll = false })
        if type(_G.ApplyAllSettings) == "function" then pcall(_G.ApplyAllSettings) end
        RefreshMsufScale()
    end)
    msufRevert = AddButton(scale, "Revert", 94, -214, 72, 20, function()
        pendingMsufScale = nil
        RefreshMsufScale()
    end)
    M.AddRefresher(ctx, RefreshMsufScale)

    local pendingMenuScale
    local menuStatus = W.Text(scale, M.Format("Applied: %d%%  Selected: %d%%", 100, 100), 14, -286, colW - 28, T.colors.muted)
    scale._msuf2CursorY = -268
    local menuScale = W.Slider(scale, "MSUF Slash Menu Scale", 25, 150, 5, colW - 54)
    HideSliderValueBox(menuScale)
    menuScale:ClearAllPoints()
    menuScale:SetPoint("TOPLEFT", menuStatus, "BOTTOMLEFT", 0, -8)
    menuScale:SetPoint("RIGHT", scale, "RIGHT", -26, 0)
    menuScale._msuf2Title:ClearAllPoints()
    menuScale._msuf2Title:SetPoint("TOPLEFT", scale, "TOPLEFT", 14, -268)
    EnablePercentWheel(menuScale, 25, 150, 5)

    local menuApply, menuRevert
    local function AppliedMenuScale()
        local g = M.GetGeneralDB()
        return Clamp(tonumber(g.slashMenuScale) or 1, 0.25, 1.5)
    end
    local function PendingMenuScale()
        return Clamp(pendingMenuScale or AppliedMenuScale(), 0.25, 1.5)
    end
    local function RefreshMenuScale()
        local applied = AppliedMenuScale()
        local pending = PendingMenuScale()
        local changed = math.abs(applied - pending) > 0.001
        menuStatus:SetText(M.Format("Applied: %d%%  Selected: %d%%", math.floor(applied * 100 + 0.5), math.floor(pending * 100 + 0.5)))
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
    menuApply = AddButton(scale, "Apply", 14, -330, 72, 20, function()
        local g = M.GetGeneralDB()
        local scaleValue = PendingMenuScale()
        g.slashMenuScale = scaleValue
        pendingMenuScale = nil
        if M.frame and M.frame.SetScale then M.frame:SetScale(EffectiveMenuScale(scaleValue)) end
        RefreshMenuScale()
    end)
    menuRevert = AddButton(scale, "Revert", 94, -330, 72, 20, function()
        pendingMenuScale = nil
        RefreshMenuScale()
    end)
    RefreshGlobalScale()
    M.AddRefresher(ctx, RefreshGlobalScale)
    RefreshMsufScale()
    RefreshMenuScale()
    M.AddRefresher(ctx, RefreshMenuScale)

    W.Text(wago, "Browse shared MSUF imports on Wago.", 14, -36, colW - 28, T.colors.muted)
    local browse = AddButton(wago, "Browse Wago Profiles", 14, -64, colW - 42, 34, function()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Wago Profiles", "https://wago.io/search/imports/wow/msuf")
        end
    end)
    if browse._msuf2Label then browse._msuf2Label:SetFontObject("GameFontNormal") end
    if T.SkinPrimaryButton then T.SkinPrimaryButton(browse) end
    W.Text(wago, "Copies the Wago link so you can open it in your browser.", 14, -106, colW - 28, T.colors.muted)
    BuildDashboardChangelog(wago, colW)

    local function AddIconTooltip(frame, title, text)
        if type(_G.MSUF_AddTooltip) == "function" then
            _G.MSUF_AddTooltip(frame, title, text)
            return
        end
        frame:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(M.Tr(title or ""), 1, 1, 1)
            if text and text ~= "" then GameTooltip:AddLine(M.Tr(text), 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local links = {
        patreon = "https://www.patreon.com/cw/MidnightSimpleUnitframes",
        paypal = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ",
        kofi = "https://ko-fi.com/midnightsimpleunitframes#linkModal",
        github = "https://github.com/Mapkov2/MidnightSimpleUnitFrames",
    }
    local support = T.Font(wago, "GameFontDisableSmall", "Support MSUF Development", T.colors.muted)
    support:SetPoint("BOTTOMLEFT", wago, "BOTTOMLEFT", 14, 14)
    support:SetWidth(max(120, colW - 198))
    support:SetJustifyH("LEFT")
    local aboutVer
    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        aboutVer = _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
    end
    local aboutText = M.Tr("by Mapko")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        local displayVersion = aboutVer:match("^%d") and ("v" .. aboutVer) or aboutVer
        aboutText = M.Format("%s  -  by Mapko  -  with help from R41z0r", displayVersion)
    end
    local about = T.Font(wago, "GameFontDisableSmall", aboutText, T.colors.muted)
    about:SetPoint("BOTTOMLEFT", support, "TOPLEFT", 0, 4)
    about:SetWidth(max(120, colW - 28))
    about:SetJustifyH("LEFT")

    local iconRow = CreateFrame("Frame", nil, wago)
    iconRow:SetSize(160, 24)
    iconRow:SetPoint("BOTTOMRIGHT", wago, "BOTTOMRIGHT", -12, 12)
    local function CreateSupportIcon(texture, title, tooltip, url)
        local button = CreateFrame("Button", nil, iconRow)
        button:SetSize(22, 22)
        local tex = button:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. texture)
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        button:SetScript("OnClick", function()
            if type(_G.MSUF_ShowCopyLink) == "function" then
                _G.MSUF_ShowCopyLink(title, url)
            end
        end)
        AddIconTooltip(button, title, tooltip)
        return button
    end
    local icons = {
        { texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.", url = links.patreon },
        { texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.", url = links.paypal },
        { texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.", url = links.kofi },
        { texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.", url = links.github },
    }
    local previous
    for i = 1, #icons do
        local data = icons[i]
        local icon = CreateSupportIcon(data.texture, data.title, data.tooltip, data.url)
        if previous then
            icon:SetPoint("RIGHT", previous, "LEFT", -7, 0)
        else
            icon:SetPoint("RIGHT", iconRow, "RIGHT", 0, 0)
        end
        previous = icon
    end

    y = y - (scaleCardH + 12)
    local advanced = Card("Advanced", x0, y, width, 76)
    W.Text(advanced, "Fast access to recovery and support tools.", 14, -34, width - 28, T.colors.muted)
    AddButton(advanced, "Print Help", 14, -54, 100, 20, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help")
        end
    end)
    local factory = AddButton(advanced, "Factory Reset", 122, -54, 112, 20, function()
        if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
            pcall(_G.SlashCmdList["MIDNIGHTSUF"], "fullreset confirm")
        end
    end)
    T.SkinDangerButton(factory)
    AddButton(advanced, "Profiles", 242, -54, 100, 20, function() M.SelectPage("profiles") end)
    AddButton(advanced, "Discord", 350, -54, 100, 20, function()
        if type(_G.MSUF_ShowCopyLink) == "function" then
            _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/JQnhZXnTAK")
        end
    end)

    ctx:SetContentHeight(math.abs(y) + 100)
end

M.RegisterPage("search", { title = "Search", build = BuildSearchPage, version = 1 })
M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboard, version = 5 })

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
