-- Menu2 one-time MSUF 6.0 dashboard scene.
--
-- This module owns presentation and navigation only. Install classification and
-- lifecycle persistence stay in MSUF.FirstLoad6; profile/runtime mutations stay
-- in their existing pages and APIs.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local CreateFrame = _G.CreateFrame
local floor = math.floor
local max = math.max
local min = math.min
local format = string.format

local InvokeLifecycleBoundary = M.InvokeBoundary or pcall

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(text) or text
end

local function Lifecycle()
    local firstLoad = MSUF and MSUF.FirstLoad6
    return type(firstLoad) == "table" and firstLoad or nil
end

local function CallLifecycle(firstLoad, method, ...)
    local fn = firstLoad and firstLoad[method]
    if type(fn) ~= "function" then return false end
    local called, result = InvokeLifecycleBoundary(fn, firstLoad, ...)
    return called and result ~= false, result
end

local function ShouldShow(firstLoad)
    local ok, shown = CallLifecycle(firstLoad, "ShouldShowDashboard")
    return ok and shown == true
end

local function FirstLoadState(firstLoad)
    local ok, state = CallLifecycle(firstLoad, "GetState")
    return ok and type(state) == "table" and state or {}
end

local function InstallKind(firstLoad, state)
    local ok, kind = CallLifecycle(firstLoad, "GetInstallKind")
    kind = ok and tostring(kind or "") or tostring(state and state.installKind or "")
    return kind == "upgrade" and "upgrade" or "fresh"
end

local function FirstLoadActionAvailability(firstLoad)
    local state = FirstLoadState(firstLoad)
    local status = tostring(state.status or "")
    if status == "completed" or status == "dismissed" then
        return false, Tr("First-load onboarding is already closed. Use Guided Setup on the Dashboard to run the tour again.")
    end
    -- Existing-profile upgrades are owned by the release highlight scene. Do
    -- not let stale Search/Assistant virtual actions bypass its explicit skip
    -- warning and close onboarding behind the user's back.
    local highlights = MSUF and MSUF.UpgradeHighlights
    if type(highlights) == "table" and type(highlights.ShouldShow) == "function" then
        local ok, shown = InvokeLifecycleBoundary(highlights.ShouldShow, highlights)
        if ok and shown == true then
            return false, Tr("Review or skip the release highlights on the Dashboard before using first-load actions.")
        end
    end
    if not ShouldShow(firstLoad) then
        return false, Tr("First-load actions are unavailable right now. Use Guided Setup on the Dashboard instead.")
    end
    return true
end

local function InvalidateHomeCache()
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
end

local function InvalidateHome()
    InvalidateHomeCache()
    if type(M.SelectPage) == "function" then M.SelectPage("home") end
end

local function CloseMenu()
    local frame = M.frame
    if type(M.HideSlashMenuAndMinibar) == "function" then
        M.HideSlashMenuAndMinibar(frame)
        return true
    end
    if frame and type(frame.Hide) == "function" then
        frame:Hide()
        return true
    end
    return false
end

local function BlockedByCombat()
    return type(M.BlockCombatAction) == "function" and M.BlockCombatAction() == true
end

local function ActiveProfileName()
    local name = tostring(_G.MSUF_ActiveProfile or "Default")
    return name ~= "" and name or "Default"
end

local function PlayerDisplayName()
    local name
    if type(_G.UnitName) == "function" then
        name = _G.UnitName("player")
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(name) then name = nil end
    if type(name) == "string" then name = name:match("^[^-]+") else name = nil end
    if not name or name == "" or name == "Unknown" then name = Tr("Player") end
    return name
end

local function RegisterControl(widget, suffix, label, classification, help)
    if not (widget and type(M.RegisterSearchWidget) == "function") then return widget end
    suffix = tostring(suffix or "action")
    local identity = "home.first_load_6." .. suffix
    M.RegisterSearchWidget(widget, {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = "home",
        classification = classification or "action",
        actionKey = (classification or "action") == "action" and ("first_load." .. suffix) or nil,
        label = Tr(label),
        kind = "button",
        help = Tr(help),
        historyMode = "none",
    })
    return widget
end

local function AddTooltip(widget, title, body)
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(widget, title, body, {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.88, 0.94 },
        })
    end
    return widget
end

local function SetTextLayout(fontString, width, justify)
    if not fontString then return fontString end
    fontString:SetWidth(max(1, width or 1))
    fontString:SetJustifyH(justify or "LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(true) end
    return fontString
end

local function CreateBackdropButton(parent, T, width, height, border, onClick)
    local template = _G.BackdropTemplateMixin and "BackdropTemplate" or nil
    local button = CreateFrame("Button", nil, parent, template)
    button:SetSize(width, height)
    button:RegisterForClicks("LeftButtonUp")
    local bg = T.colors.coreShadow or T.colors.bg
    local edge = border or T.colors.cardBorder or T.colors.borderSoft
    if type(T.ApplyMaterial) == "function" then
        T.ApplyMaterial(button, { bg = bg, border = edge, glass = "card", gradient = "card" })
    elseif type(T.ApplySurface) == "function" then
        if type(T.ApplyBackdrop) == "function" then T.ApplyBackdrop(button, bg, edge) end
        T.ApplySurface(button, "card")
    elseif type(T.ApplyBackdrop) == "function" then
        T.ApplyBackdrop(button, bg, edge)
    end

    local highlight = button:CreateTexture(nil, "HIGHLIGHT", nil, 2)
    highlight:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    highlight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    highlight:SetColorTexture(T.colors.coreBlue[1], T.colors.coreBlue[2], T.colors.coreBlue[3], 0.065)

    button:SetScript("OnEnter", function(self)
        if self.SetBackdropBorderColor then
            local c = T.colors.coreHot or T.colors.accent
            self:SetBackdropBorderColor(c[1], c[2], c[3], 0.96)
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 0.82) end
    end)
    button:SetScript("OnClick", function()
        if BlockedByCombat() then return end
        if type(onClick) == "function" then onClick() end
    end)
    return button
end

local function CreateIconWell(parent, T, navKey, size, x, y)
    size = size or 34
    local well = T.Panel(parent, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    well:SetSize(size, size)
    well:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if type(T.ApplySurface) == "function" then T.ApplySurface(well, "card") end
    local icon = well:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(floor(size * 0.48), floor(size * 0.48))
    icon:SetPoint("CENTER", well, "CENTER", 0, 0)
    local grid = T.navIconGrid and T.navIconGrid[navKey]
    if grid and T.media and T.media.navIcons then
        icon:SetTexture(T.media.navIcons)
        icon:SetTexCoord(grid[1] / 8, (grid[1] + 1) / 8, grid[2] / 8, (grid[2] + 1) / 8)
    elseif T.media and T.media.logo then
        icon:SetTexture(T.media.logo)
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end
    local c = T.navIconColors and T.navIconColors[navKey] or T.colors.coreHot or T.colors.accent
    icon:SetVertexColor(c[1], c[2], c[3], 0.98)
    return well
end

local function CreateWelcomeMark(parent, T, size, top)
    local mark = T.Panel(parent, nil, T.colors.coreRaised or T.colors.panel2, T.colors.coreHot or T.colors.accent)
    mark:SetSize(size, size)
    mark:SetPoint("TOP", parent, "TOP", 0, top)
    if type(T.ApplySurface) == "function" then T.ApplySurface(mark, "card") end
    if type(T.ApplyNeonEdge) == "function" then T.ApplyNeonEdge(mark, "ambient", { variant = "card" }) end
    local logo = mark:CreateTexture(nil, "ARTWORK", nil, 3)
    logo:SetSize(floor(size * 0.68), floor(size * 0.68))
    logo:SetPoint("CENTER", mark, "CENTER", 0, 0)
    logo:SetTexture(T.media and T.media.logo or "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga")
    logo:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    logo:SetVertexColor(0.78, 0.90, 1.00, 1)
    return mark
end

local function CreateVersionRow(parent, T, text, contentWidth, top)
    local rowWidth = min(contentWidth, text:find("UPGRADED", 1, true) and 240 or 210)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(rowWidth, 20)
    row:SetPoint("TOP", parent, "TOP", 0, top)
    local label = T.Font(row, "GameFontDisableSmall", Tr(text), T.colors.coreHot or T.colors.accent)
    label:SetAllPoints(row)
    label:SetJustifyH("CENTER")
    return row
end

local function CreateProtectionPanel(parent, T, contentWidth, top, compact, installKind, profileName)
    local itemHeight = compact and 42 or 58
    local panelHeight = compact and (itemHeight * 3) or itemHeight
    local panel = T.Panel(parent, nil, T.colors.coreShadow or T.colors.bg, T.colors.borderSoft)
    panel:SetSize(contentWidth, panelHeight)
    panel:SetPoint("TOP", parent, "TOP", 0, top)
    if type(T.ApplySurface) == "function" then T.ApplySurface(panel, "card") end
    local specs
    if installKind == "upgrade" then
        specs = {
            { "STATUS", "Profile unchanged", true, true },
            { "PROFILE", profileName, false, false },
            { "APPLIED SO FAR", "No changes", false, true },
        }
    else
        specs = {
            { "STATUS", "Frames ready", true, true },
            { "PROFILE", profileName, false, false },
            { "APPLIED SO FAR", "No changes", false, true },
        }
    end
    local itemWidth = compact and contentWidth or floor(contentWidth / 3)
    for i = 1, #specs do
        local spec = specs[i]
        local item = CreateFrame("Frame", nil, panel)
        item:SetSize(itemWidth, itemHeight)
        if compact then
            item:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -((i - 1) * itemHeight))
        else
            local x = (i - 1) * itemWidth
            item:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
        end
        local label = T.Font(item, "GameFontDisableSmall", Tr(spec[1]), T.colors.muted)
        label:SetPoint("TOPLEFT", item, "TOPLEFT", 16, -8)
        local valueText = spec[4] == false and spec[2] or Tr(spec[2])
        local value = T.Font(item, "GameFontNormalSmall", valueText, spec[3] and T.colors.ok or T.colors.text)
        value:SetPoint("TOPLEFT", item, "TOPLEFT", 16, -28)
        value:SetPoint("RIGHT", item, "RIGHT", -12, 0)
        value:SetJustifyH("LEFT")
        if i > 1 then
            local divider = panel:CreateTexture(nil, "ARTWORK", nil, 2)
            divider:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.76)
            if compact then
                divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -((i - 1) * itemHeight))
                divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -((i - 1) * itemHeight))
                divider:SetHeight(1)
            else
                divider:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * itemWidth, -8)
                divider:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", (i - 1) * itemWidth, 8)
                divider:SetWidth(1)
            end
        end
    end
    return panel, panelHeight
end

local function CreateRouteCard(parent, T, data, x, top, width, height, compact)
    local border = data.recommended and (T.colors.accent or T.colors.coreBlue) or (T.colors.cardBorder or T.colors.borderSoft)
    local card = CreateBackdropButton(parent, T, width, height, border, data.onClick)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
    if data.recommended and type(T.ApplyNeonEdge) == "function" then
        T.ApplyNeonEdge(card, "ambient", { variant = "card" })
    end
    if data.recommended then
        -- Straddles the top border so the recommendation reads at a glance,
        -- like a pricing-card ribbon.
        local pill = T.Panel(card, nil, T.colors.coreRaised or T.colors.panel2, T.colors.accent or T.colors.coreBlue)
        local pillText = T.Font(pill, "GameFontDisableSmall", Tr("RECOMMENDED"), T.colors.accent or T.colors.coreBlue)
        pillText:SetPoint("CENTER", pill, "CENTER", 0, 0)
        pill:SetSize(floor((pillText:GetStringWidth() or 84) + 20), 20)
        pill:SetPoint("CENTER", card, "TOP", 0, 0)
        pill:SetFrameLevel(card:GetFrameLevel() + 5)
    end

    if compact then
        CreateIconWell(card, T, data.icon, 30, 14, -34)
        local meta = T.Font(card, "GameFontDisableSmall", Tr(data.meta), T.colors.coreHot or T.colors.accent)
        meta:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -12)
        meta:SetPoint("RIGHT", card, "RIGHT", -16, 0)
        meta:SetJustifyH("LEFT")
        local title = T.Font(card, "GameFontNormal", Tr(data.title), T.colors.text)
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -36)
        title:SetPoint("RIGHT", card, "RIGHT", -16, 0)
        title:SetJustifyH("LEFT")
        local body = T.Font(card, "GameFontHighlightSmall", Tr(data.body), T.colors.muted)
        body:SetPoint("TOPLEFT", card, "TOPLEFT", 56, -56)
        SetTextLayout(body, width - 68, "LEFT")
    else
        local timing = T.Font(card, "GameFontDisableSmall", Tr(data.timing), T.colors.muted)
        timing:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -16)
        timing:SetJustifyH("RIGHT")
        local meta = T.Font(card, "GameFontDisableSmall", Tr(data.meta), T.colors.coreHot or T.colors.accent)
        meta:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
        meta:SetPoint("RIGHT", timing, "LEFT", -8, 0)
        meta:SetJustifyH("LEFT")
        CreateIconWell(card, T, data.icon, 34, 16, -42)
        local title = T.Font(card, "GameFontNormal", Tr(data.title), T.colors.text)
        title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -88)
        SetTextLayout(title, width - 32, "LEFT")
        local body = T.Font(card, "GameFontHighlightSmall", Tr(data.body), T.colors.muted)
        body:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -112)
        SetTextLayout(body, width - 32, "LEFT")
    end

    RegisterControl(card, data.id, data.title, "action", data.body)
    local tooltipBody = Tr(data.body)
    if data.hint then tooltipBody = tooltipBody .. "\n\n" .. Tr(data.hint) end
    AddTooltip(card, Tr(data.title), tooltipBody)
    if type(T.PlayMotion) == "function" then
        T.PlayMotion(card, "controlFocusIn", { fromAlpha = 0.20, toAlpha = 1, duration = 0.22 })
    end
    return card
end

local function CreateFooterButton(parent, T, label, x, top, width, onClick, id)
    local button = T.Button(parent, Tr(label), width, 24)
    button._msuf2SkipHistoryCheckpoint = true
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    button:SetScript("OnClick", function()
        if BlockedByCombat() then return end
        if type(onClick) == "function" then onClick() end
    end)
    RegisterControl(button, id, label, "action")
    return button
end

local function OpenProfileImport(firstLoad)
    -- This scene is a one-time route chooser, not the import workflow itself.
    -- Choosing this route retires the welcome scene; a successful import later
    -- completes the lifecycle, and a cancelled import simply lands on the
    -- normal Dashboard with its own Guided Setup entry point.
    CallLifecycle(firstLoad, "Start", "import")
    InvalidateHomeCache()
    if type(M.SetMenuStateValue) == "function" then
        M.SetMenuStateValue("profileImportCreateNew", true)
    else
        M.profileImportCreateNew = true
    end
    local accordion
    if type(M.GetPersistentMenuStateTable) == "function" then
        accordion = M.GetPersistentMenuStateTable("accordionState")
    else
        M.accordionState = type(M.accordionState) == "table" and M.accordionState or {}
        accordion = M.accordionState
    end
    accordion["profiles:profiles_io"] = true

    local route = {
        state = { profileImportCreateNew = true },
        accordion = { ["profiles:profiles_io"] = true },
    }
    local bridge = M.SearchBridge
    local called, opened
    if bridge and type(bridge.OpenSearchTarget) == "function" then
        called, opened = bridge.OpenSearchTarget("profiles", "Profile string", "Profile string", nil, route)
    end
    if not called or opened == false then
        if type(M.SelectPage) == "function" then M.SelectPage("profiles") end
    end
    return true
end

function M.ExecuteFirstLoadDashboardAction(action)
    action = tostring(action or "")
    local firstLoad = Lifecycle()
    if not firstLoad then return false, Tr("The first-load lifecycle is not available.") end
    local available, unavailableMessage = FirstLoadActionAvailability(firstLoad)
    if not available then return false, unavailableMessage end
    if action == "personalize" then
        if type(M.StartGuidedTour) == "function" then
            local started = M.StartGuidedTour({ source = "first_load", mode = "quick" })
            if started then return true, Tr("Quick Setup started.") end
        end
        CallLifecycle(firstLoad, "Complete", "personalize_fallback")
        InvalidateHomeCache()
        if type(M.SelectPage) == "function" then M.SelectPage("uf_player") end
        return true, Tr("Opened Player settings.")
    elseif action == "import_profile" then
        OpenProfileImport(firstLoad)
        return true, Tr("Opened safe new-profile import.")
    elseif action == "use_defaults" then
        local installKind = InstallKind(firstLoad, FirstLoadState(firstLoad))
        CallLifecycle(firstLoad, "Complete", installKind == "upgrade" and "current_profile" or "defaults")
        -- Replace the one-time scene immediately with the normal Dashboard.
        -- Rebuilding `home` after the terminal state is persisted guarantees
        -- the cached welcome wrapper cannot survive the defaults choice.
        InvalidateHome()
        return true, installKind == "upgrade"
            and Tr("Continued with the current profile.")
            or Tr("Kept the current/default setup.")
    elseif action == "whats_new" then
        CallLifecycle(firstLoad, "DeferForSession", "changelog")
        if type(M.SetMenuStateValue) == "function" then
            M.SetMenuStateValue("dashboardChangelogOpen", true)
        else
            M.dashboardChangelogOpen = true
        end
        InvalidateHome()
        return true, Tr("Opened the MSUF 6.0 changelog.")
    elseif action == "not_now" then
        CallLifecycle(firstLoad, "DeferForSession", "not_now")
        InvalidateHomeCache()
        if not CloseMenu() and type(M.SelectPage) == "function" then M.SelectPage("home") end
        return true, Tr("Closed the first-time setup. Start Guided Setup from the Dashboard anytime.")
    elseif action == "full_settings" then
        CallLifecycle(firstLoad, "Dismiss", "full_settings")
        InvalidateHome()
        return true, Tr("Opened the full MSUF settings.")
    end
    return false, Tr("Unknown first-load action.")
end

local FIRST_LOAD_VIRTUAL_ACTIONS = {
    { suffix = "personalize", label = "Personalize with guided setup" },
    { suffix = "import_profile", label = "Import a profile" },
    { suffix = "use_defaults", label = "Use the current defaults" },
    { suffix = "whats_new", label = "What is new in 6.0" },
    { suffix = "not_now", label = "Not now" },
    { suffix = "full_settings", label = "Open full settings" },
}

local function FirstLoadVirtualSetter(suffix)
    return function()
        local ok, message = M.ExecuteFirstLoadDashboardAction(suffix)
        if ok ~= true then error(message or Tr("First-load action failed."), 2) end
        return true, message
    end
end

local function RegisterFirstLoadVirtualControls()
    if type(M.RegisterVirtualRuntimeControl) ~= "function" then return false end
    for i = 1, #FIRST_LOAD_VIRTUAL_ACTIONS do
        local spec = FIRST_LOAD_VIRTUAL_ACTIONS[i]
        local suffix = spec.suffix
        local identity = "home.first_load_6." .. suffix
        M.RegisterVirtualRuntimeControl({
            controlId = "menu2." .. identity,
            identityKey = identity,
            controlPath = identity:gsub("%.", "/"),
            pageKey = "home",
            classification = "action",
            actionKey = "first_load." .. suffix,
            label = Tr(spec.label),
            kind = "button",
            historyMode = "none",
            command = {
                kind = "button",
                actionKey = "first_load." .. suffix,
                historyMode = "none",
                blockCombat = BlockedByCombat,
                set = FirstLoadVirtualSetter(suffix),
            },
        }, "first-load-virtual")
    end
    return true
end

RegisterFirstLoadVirtualControls()

function M.BuildFirstLoadDashboardScene(ctx)
    RegisterFirstLoadVirtualControls()
    local firstLoad = Lifecycle()
    if not firstLoad or not ShouldShow(firstLoad) then return false end
    local T, W = M.Theme, M.Widgets
    if not (ctx and ctx.wrapper and T and W and type(T.Panel) == "function" and type(T.Font) == "function" and type(T.Button) == "function") then
        return false
    end

    local state = FirstLoadState(firstLoad)
    local installKind = InstallKind(firstLoad, state)
    local profileName = ActiveProfileName()
    local width = max(320, tonumber(ctx.width) or 760)
    local sceneX, sceneTop = 12, -12
    local sceneWidth = max(288, width - sceneX)
    local contentWidth = min(720, max(280, sceneWidth - 40))
    local compact = contentWidth < 660
    local scene = CreateFrame("Frame", nil, ctx.wrapper)
    scene:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", sceneX, sceneTop)
    scene:SetWidth(sceneWidth)

    local wash = scene:CreateTexture(nil, "BACKGROUND", nil, 0)
    wash:SetPoint("TOPLEFT", scene, "TOPLEFT", 0, 0)
    wash:SetPoint("TOPRIGHT", scene, "TOPRIGHT", 0, 0)
    wash:SetHeight(compact and 290 or 340)
    wash:SetTexture((T.media and T.media.gradV) or "Interface\\Buttons\\WHITE8X8")
    wash:SetVertexColor(T.colors.coreBlue[1], T.colors.coreBlue[2], T.colors.coreBlue[3], 0.055)

    local markSize = compact and 60 or 72
    local markTop = compact and -24 or -34
    local welcomeMark = CreateWelcomeMark(scene, T, markSize, markTop)
    if type(T.PlayMotion) == "function" then
        T.PlayMotion(welcomeMark, "controlFocusIn", { fromAlpha = 0.18, toAlpha = 1, duration = 0.24 })
    end

    local versionTop = compact and -96 or -126
    local kicker = installKind == "upgrade" and "UPGRADED TO MSUF 6.0" or "FIRST START \194\183 MSUF 6.0"
    CreateVersionRow(scene, T, kicker, contentWidth, versionTop)

    local titleTop = compact and -130 or -160
    local titleText = installKind == "upgrade"
        and format(Tr("Welcome back, %s"), PlayerDisplayName())
        or format(Tr("Welcome, %s"), PlayerDisplayName())
    local title = T.Font(scene, "GameFontNormalHuge", titleText, T.colors.title or T.colors.text)
    title:SetPoint("TOP", scene, "TOP", 0, titleTop)
    SetTextLayout(title, contentWidth, "CENTER")
    if type(T.PlayMotion) == "function" then
        T.PlayMotion(title, "controlFocusIn", { fromAlpha = 0.24, toAlpha = 1, duration = 0.22 })
    end

    local copyTop = compact and -174 or -208
    local copyText
    if installKind == "upgrade" then
        copyText = "Your current frames stay active. Follow the complete guided setup, import a profile safely, or keep playing with your existing setup."
    else
        copyText = "Your frames are ready now. Follow the complete guided setup, import a profile, or start playing with the defaults."
    end
    copyText = Tr(copyText)
    local copy = type(W.LabelAt) == "function"
        and W.LabelAt(scene, copyText, 0, copyTop, min(700, contentWidth), "GameFontHighlight", T.colors.muted)
        or T.Font(scene, "GameFontHighlight", copyText, T.colors.muted)
    copy:ClearAllPoints()
    copy:SetPoint("TOP", scene, "TOP", 0, copyTop)
    SetTextLayout(copy, min(700, contentWidth), "CENTER")

    local protectionTop = compact and -240 or -278
    local _, protectionHeight = CreateProtectionPanel(scene, T, contentWidth, protectionTop, compact, installKind, profileName)
    local routeTop = protectionTop - protectionHeight - (compact and 18 or 24)
    local cardGap = 12
    local cardHeight = compact and 104 or 154
    local cardWidth = compact and contentWidth or floor((contentWidth - (cardGap * 2)) / 3)

    -- Fresh installs benefit most from the tour; upgraders usually just want
    -- to keep what they have, so the recommendation follows the install kind.
    local recommendGuided = installKind ~= "upgrade"
    local routes = {
        {
            id = "personalize", meta = "QUICK SETUP", timing = "~5 min", icon = "opt_bars",
            recommended = recommendGuided,
            title = "Start Quick Setup",
            body = "Set the essentials first: placement, frame basics, text, auras, and shared style.",
            hint = "You can choose the Complete Tour on the next screen. A restore point is saved first.",
            onClick = function() M.ExecuteFirstLoadDashboardAction("personalize") end,
        },
        {
            id = "import_profile", meta = "EXISTING SETUP", timing = "~2 min", icon = "profiles",
            title = "Import a profile",
            body = "Review an import in a new profile before switching to it.",
            hint = "Your current profile stays untouched until you switch.",
            onClick = function() M.ExecuteFirstLoadDashboardAction("import_profile") end,
        },
        {
            id = "use_defaults",
            meta = installKind == "upgrade" and "CURRENT PROFILE" or "ZERO SETUP",
            timing = "Instant", icon = "gameplay",
            recommended = not recommendGuided,
            title = installKind == "upgrade" and "Continue with current profile" or "Play with defaults",
            body = installKind == "upgrade"
                and "Close onboarding and keep your current profile exactly as it is."
                or "Close onboarding without applying or resetting anything.",
            hint = "You can change everything later in the full settings.",
            onClick = function() M.ExecuteFirstLoadDashboardAction("use_defaults") end,
        },
    }
    for i = 1, #routes do
        local x = compact and floor((sceneWidth - cardWidth) / 2)
            or floor((sceneWidth - contentWidth) / 2) + ((i - 1) * (cardWidth + cardGap))
        local top = compact and (routeTop - ((i - 1) * (cardHeight + cardGap))) or routeTop
        CreateRouteCard(scene, T, routes[i], x, top, cardWidth, cardHeight, compact)
    end

    local routeGridHeight = compact and ((cardHeight * 3) + (cardGap * 2)) or cardHeight
    local footerTop = routeTop - routeGridHeight - 18
    local footerButtons = {
        { "What is new in 6.0", 132, function() M.ExecuteFirstLoadDashboardAction("whats_new") end, "whats_new" },
        { "Not now", 74, function() M.ExecuteFirstLoadDashboardAction("not_now") end, "not_now" },
        { "Open full settings", 126, function() M.ExecuteFirstLoadDashboardAction("full_settings") end, "full_settings" },
    }
    local footerHeight
    if compact then
        local buttonWidth = min(220, contentWidth)
        local buttonX = floor((sceneWidth - buttonWidth) / 2)
        for i = 1, #footerButtons do
            local item = footerButtons[i]
            CreateFooterButton(scene, T, item[1], buttonX, footerTop - ((i - 1) * 32), buttonWidth, item[3], item[4])
        end
        footerHeight = 88
    else
        local total = footerButtons[1][2] + footerButtons[2][2] + footerButtons[3][2] + 16
        local x = floor((sceneWidth - total) / 2)
        for i = 1, #footerButtons do
            local item = footerButtons[i]
            CreateFooterButton(scene, T, item[1], x, footerTop, item[2], item[3], item[4])
            x = x + item[2] + 8
        end
        footerHeight = 24
    end

    local footnoteTop = footerTop - footerHeight - 14
    local footnoteText = installKind == "upgrade"
        and format(Tr("Profile: %s - Current setup stays active. Guided Setup saves a restore point."), profileName)
        or format(Tr("Profile: %s - No changes yet. Guided Setup saves a restore point."), profileName)
    local footnote = T.Font(scene, "GameFontDisableSmall", footnoteText, T.colors.dim)
    footnote:SetPoint("TOP", scene, "TOP", 0, footnoteTop)
    SetTextLayout(footnote, contentWidth, "CENTER")

    -- Closing the window without a choice keeps the scene armed; say so instead
    -- of surprising the player when it comes back after the next open.
    local hintTop = footnoteTop - 18
    local hint = T.Font(scene, "GameFontDisableSmall", Tr("Pick any option to continue - this page will not show again."), T.colors.dim)
    hint:SetPoint("TOP", scene, "TOP", 0, hintTop)
    SetTextLayout(hint, contentWidth, "CENTER")

    local sceneHeight = math.abs(hintTop) + 36
    scene:SetHeight(sceneHeight)
    ctx:SetContentHeight(sceneHeight + math.abs(sceneTop) + 24)
    return true
end
