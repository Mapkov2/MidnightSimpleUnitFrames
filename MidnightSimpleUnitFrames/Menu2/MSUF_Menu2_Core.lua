local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local T = M.Theme
local W = M.Widgets

M.pages = M.pages or {}
M.pageOrder = M.pageOrder or {}
M.cache = M.cache or {}

local floor = math.floor
local max = math.max

local DEFAULT_WINDOW_W, DEFAULT_WINDOW_H = 900, 650
local MIN_WINDOW_W, MIN_WINDOW_H = 760, 520
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

local function SetWindowMetrics(width, height)
    WINDOW_W = ClampNumber(width, MIN_WINDOW_W, MAX_WINDOW_W, DEFAULT_WINDOW_W)
    WINDOW_H = ClampNumber(height, MIN_WINDOW_H, MAX_WINDOW_H, DEFAULT_WINDOW_H)
    CONTENT_W = math.max(420, WINDOW_W - NAV_W - 24)
    CONTENT_H = math.max(320, WINDOW_H - 74)
end

local function RefreshWindowMetrics(frame)
    local width = (frame and frame.GetWidth and frame:GetWidth()) or WINDOW_W
    local height = (frame and frame.GetHeight and frame:GetHeight()) or WINDOW_H
    SetWindowMetrics(width, height)
end

local function ReadSavedWindowSize()
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return DEFAULT_WINDOW_W, DEFAULT_WINDOW_H end
    return ClampNumber(g.msuf2WindowW, MIN_WINDOW_W, MAX_WINDOW_W, DEFAULT_WINDOW_W),
        ClampNumber(g.msuf2WindowH, MIN_WINDOW_H, MAX_WINDOW_H, DEFAULT_WINDOW_H)
end

local function SaveWindowSize(frame)
    RefreshWindowMetrics(frame)
    local g = M.GetGeneralDB and M.GetGeneralDB()
    if type(g) ~= "table" then return end
    g.msuf2WindowW = WINDOW_W
    g.msuf2WindowH = WINDOW_H
end

local function ApplyScrollMetrics()
    if not M.scrollChild then return end
    local height = CONTENT_H
    local entry = M.activeKey and M.cache and M.cache[M.activeKey]
    if entry and tonumber(entry.height) then height = math.max(height, entry.height) end
    M.scrollChild:SetSize(CONTENT_W - 10, height)
    if entry and entry.wrapper then entry.wrapper:SetSize(CONTENT_W - 10, height) end
end

local function RebuildActivePageForResize(frame)
    local key = M.activeKey or "home"
    SaveWindowSize(frame)
    ApplyScrollMetrics()
    if M.InvalidatePage then M.InvalidatePage() end
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
    frame.title:SetText(title)
    if frame.subtitle then frame.subtitle:SetText("") end
    if frame.RefreshStatus then frame:RefreshStatus() end
end

local function UpdateNav(key)
    if not M.navButtons then return end
    local group = M.navGroupForKey and M.navGroupForKey[key]
    if group and M.navHeaderState and M.navHeaderState[group] == false then
        M.navHeaderState[group] = true
        if M.nav and M.nav._msuf2NavReflow then M.nav:_msuf2NavReflow() end
    end
    for pageKey, btn in pairs(M.navButtons) do
        if btn.SetActive then btn:SetActive(pageKey == key) end
    end
end

local function RunRefreshers(entry)
    if not entry or not entry.refreshers then return end
    for i = 1, #entry.refreshers do
        local fn = entry.refreshers[i]
        if type(fn) == "function" then pcall(fn) end
    end
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
        if M.scrollChild and M.scrollChild.SetHeight then M.scrollChild:SetHeight(height) end
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
    W.Text(sec, "Requested page: " .. tostring(requestedKey or "unknown"), 14, -68, ctx.width - 28, T.colors.dim)
    ctx:SetContentHeight(210)
end

function M.SelectPage(key)
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
        return true
    end

    HideAllCachedPages()

    local entry = M.cache[key]
    if not entry then
        local wrapper = CreateFrame("Frame", nil, M.scrollChild)
        wrapper:SetPoint("TOPLEFT", M.scrollChild, "TOPLEFT", 0, 0)
        wrapper:SetSize(CONTENT_W - 10, CONTENT_H)
        entry = { wrapper = wrapper, refreshers = {}, height = CONTENT_H, version = specVersion }
        M.cache[key] = entry

        local ctx = CreateContext(key, wrapper, entry)
        if spec and type(spec.build) == "function" then
            local ok, result = pcall(spec.build, ctx)
            if ok and tonumber(result) then ctx:SetContentHeight(result) end
        else
            BuildPlaceholderPage(ctx, key)
        end
    end

    M.activeKey = key
    if M.scrollFrame and M.scrollFrame.SetVerticalScroll then
        M.scrollFrame:SetVerticalScroll(0)
    end
    if M.scrollChild then
        M.scrollChild:SetHeight(entry.height or CONTENT_H)
    end
    entry.wrapper:Show()
    RunRefreshers(entry)
    SetTitle(key)
    UpdateNav(key)
    return true
end

local function CreateNavButton(parent, key, label, indent)
    local btn = T.Button(parent, label, NAV_W - 24 - (indent or 0), NAV_BUTTON_H)
    btn:SetScript("OnClick", function() M.SelectPage(key) end)
    btn._msuf2NavIndent = indent or 0
    if T.AttachNavIcon then T.AttachNavIcon(btn, key, (indent or 0) > 0) end
    M.navButtons[key] = btn
    return btn
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
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search:SetTextInsets(6, 6, 0, 0)
    T.SkinEditBox(search)
    if search.Instructions then search.Instructions:SetText("Search settings...") end
    parent.searchBox = search

    local created = {}
    for i = 1, #NAV do
        local item = NAV[i]
        if item.header then
            local id = item.id or item.header
            if M.navHeaderState[id] == nil then M.navHeaderState[id] = item.defaultOpen ~= false end
            local btn = T.Button(parent, string.upper(item.header), NAV_W - 24, NAV_BUTTON_H)
            btn._msuf2NavHeaderId = id
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
            M.navHeaders[id] = btn
            created[#created + 1] = { kind = "header", id = id, button = btn }
        elseif item.key then
            local indent = item.group and 12 or 0
            local btn = CreateNavButton(parent, item.key, item.label, indent)
            if item.group then M.navGroupForKey[item.key] = item.group end
            created[#created + 1] = { kind = "page", group = item.group, button = btn }
        end
    end
    function parent:_msuf2NavReflow()
        local y = -38
        for i = 1, #created do
            local item = created[i]
            local btn = item.button
            if item.kind == "header" then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
                if btn._msuf2NavArrow then
                    btn._msuf2NavArrow:SetRotation(M.navHeaderState[item.id] and (math.pi * 0.5) or 0)
                    btn._msuf2NavArrow:SetVertexColor(0.45, 0.55, 0.72, 1)
                end
                y = y - NAV_BUTTON_STEP
            elseif not item.group or M.navHeaderState[item.group] then
                btn:Show()
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12 + (btn._msuf2NavIndent or 0), y)
                y = y - NAV_BUTTON_STEP
            else
                btn:Hide()
            end
        end
    end
    parent:_msuf2NavReflow()
end

local function BuildWindow()
    if M.frame then return M.frame end

    SetWindowMetrics(ReadSavedWindowSize())
    local f = T.Panel(UIParent, "MSUF2_Window", T.colors.bg, T.colors.border)
    f:SetSize(WINDOW_W, WINDOW_H)
    f:SetPoint("CENTER", UIParent, "CENTER", -60, 10)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WINDOW_W, MIN_WINDOW_H, MAX_WINDOW_W, MAX_WINDOW_H)
    else
        if f.SetMinResize then f:SetMinResize(MIN_WINDOW_W, MIN_WINDOW_H) end
        if f.SetMaxResize then f:SetMaxResize(MAX_WINDOW_W, MAX_WINDOW_H) end
    end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnSizeChanged", function(self)
        RefreshWindowMetrics(self)
        ApplyScrollMetrics()
    end)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "MSUF2_Window")
    end

    local title = T.Font(f, "GameFontDisableSmall", "MSUF", T.colors.accent)
    title:SetPoint("TOPLEFT", 12, -6)
    title:SetAlpha(0.50)
    f.title = title

    local subtitle = T.Font(f, "GameFontDisableSmall", "", T.colors.muted)
    subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -48, -14)
    subtitle:SetJustifyH("RIGHT")
    subtitle:Hide()
    f.subtitle = subtitle

    local close = T.CloseButton(f)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and f.StartSizing then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
        RebuildActivePageForResize(f)
    end)
    grip:SetScript("OnHide", function()
        if f.StopMovingOrSizing then f:StopMovingOrSizing() end
    end)
    f.resizeGrip = grip

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    f.content = content

    local nav = T.Panel(content, nil, T.colors.panelNav or T.colors.panel, T.colors.borderSoft)
    nav:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    nav:SetWidth(NAV_W)
    f.nav = nav
    BuildNav(nav)

    local host = T.Panel(content, nil, T.colors.panel, T.colors.borderSoft)
    host:SetPoint("TOPLEFT", nav, "TOPRIGHT", 8, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    f.host = host
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
        local edit = "Off"
        if type(_G.MSUF_IsMSUFEditModeActive) == "function" and _G.MSUF_IsMSUFEditModeActive() then
            edit = "On"
        elseif _G.MSUF_UnitEditModeActive then
            edit = "On"
        end
        sbProfile:SetText("|cff4a90d9Profile:|r |cffccd8e8" .. profile .. "|r  |cff3a4a66\194\183|r")
        if edit == "On" then
            sbEdit:SetText("|cff4ade80Edit: On|r  |cff3a4a66\194\183|r")
        else
            sbEdit:SetText("|cff5a6a88Edit: Off|r  |cff3a4a66\194\183|r")
        end
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            sbCombat:SetText("|cffef4444In Combat|r")
        else
            sbCombat:SetText("|cff22c55eOut of Combat|r")
        end
        local ver = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata and _G.C_AddOns.GetAddOnMetadata("MidnightSimpleUnitFrames", "Version")
        if type(ver) == "string" and ver ~= "" then
            sbVersion:SetText((ver:sub(1, 1) == "v") and ver or ("v" .. ver))
        else
            sbVersion:SetText("v5.0 Beta 1")
        end
    end
    status:RegisterEvent("PLAYER_REGEN_DISABLED")
    status:RegisterEvent("PLAYER_REGEN_ENABLED")
    status:SetScript("OnEvent", function()
        if f and f:IsShown() then f:RefreshStatus() end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, host, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 0)
    f.scrollFrame = scroll
    M.scrollFrame = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W - 10, CONTENT_H)
    scroll:SetScrollChild(child)
    M.scrollChild = child

    M.frame = f
    return f
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
    local editMode = AddButton(tip, "Toggle Edit Mode", 14, -64, actionW, 24, function()
        if _G.InCombatLockdown and _G.InCombatLockdown() then return end
        local active = (_G.MSUF_IsMSUFEditModeActive and _G.MSUF_IsMSUFEditModeActive()) or _G.MSUF_UnitEditModeActive
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(not active)
        end
        if M.frame and M.frame.RefreshStatus then M.frame:RefreshStatus() end
    end)
    if T.SkinPrimaryButton then T.SkinPrimaryButton(editMode) end
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
        globalStatus:SetText("Applied: " .. applied .. "   Selected: " .. selected)
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
    local msufStatus = W.Text(scale, "Applied: 100%  Selected: 100%", 14, -168, colW - 28, T.colors.muted)
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
        msufStatus:SetText(string.format("Applied: %d%%  Selected: %d%%", math.floor(applied * 100 + 0.5), math.floor(pending * 100 + 0.5)))
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
    local menuStatus = W.Text(scale, "Applied: 100%  Selected: 100%", 14, -286, colW - 28, T.colors.muted)
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
        menuStatus:SetText(string.format("Applied: %d%%  Selected: %d%%", math.floor(applied * 100 + 0.5), math.floor(pending * 100 + 0.5)))
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

    local function AddIconTooltip(frame, title, text)
        if type(_G.MSUF_AddTooltip) == "function" then
            _G.MSUF_AddTooltip(frame, title, text)
            return
        end
        frame:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(title or "", 1, 1, 1)
            if text and text ~= "" then GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true) end
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
    local aboutText = "by Mapko"
    if type(aboutVer) == "string" and aboutVer ~= "" then
        aboutText = "v" .. aboutVer .. "  -  by Mapko  -  with help from R41z0r"
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

M.RegisterPage("home", { title = "MSUF Menu", build = BuildDashboard, version = 2 })

local function ApplyMenuFrameScale(frame)
    if not (frame and frame.SetScale) then return end
    local g = M.GetGeneralDB()
    frame:SetScale(EffectiveMenuScale(g.slashMenuScale))
end

M.GetEffectiveMenuScale = EffectiveMenuScale

function M.Open(pageKey)
    local f = BuildWindow()
    ApplyMenuFrameScale(f)
    f:Show()
    M.SelectPage(pageKey or M.activeKey or "home")
end

function M.Toggle(pageKey)
    local f = BuildWindow()
    if f:IsShown() and (not pageKey or pageKey == M.activeKey) then
        f:Hide()
    else
        M.Open(pageKey)
    end
end

function M.InvalidatePage(key)
    if key then
        local entry = M.cache[key]
        if entry and entry.wrapper then
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        M.cache[key] = nil
    else
        for k in pairs(M.cache) do M.InvalidatePage(k) end
    end
end

_G.MSUF2_Open = function(pageKey) M.Open(pageKey) end
_G.MSUF2_Toggle = function(pageKey) M.Toggle(pageKey) end

SLASH_MSUF2OPTIONS1 = "/msuf2"
SlashCmdList["MSUF2OPTIONS"] = function(msg)
    msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = msg:lower()
    M.Open(ALIASES[msg] or msg or "home")
end
