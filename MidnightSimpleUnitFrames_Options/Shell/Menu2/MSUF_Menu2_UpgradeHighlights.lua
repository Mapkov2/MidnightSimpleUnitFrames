-- Interactive, non-destructive release highlights for existing profiles.
-- Lifecycle and release data live in State/MSUF_UpgradeHighlights.lua.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local CreateFrame = _G.CreateFrame
local floor = math.floor
local max = math.max
local min = math.min
local format = string.format
local tostring = tostring
local type = type

local PREVIEW_MAX_WIDTH = 320
local TOUR_BAND_GAP = 16
local TOUR_CONTROLS_LABEL_HEIGHT = 20

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(text) or text
end

-- Highlights can host a small group of live settings so the tour is something
-- you touch, not only read. The rows are registered by the page that owns the
-- settings, so reading, writing and applying a value stays in exactly one
-- place; only the row list crosses into the tour.
--
-- spec = { columns?, height, rows = function() return <W.SettingsRows rows> end,
--          after? = function(ctx, result) }  -- `height` is the grid alone.
local TOUR_CONTROLS = {}

function M.RegisterUpgradeTourControls(highlightId, spec)
    highlightId = tostring(highlightId or "")
    if highlightId == "" or type(spec) ~= "table" or type(spec.rows) ~= "function" then return false end
    TOUR_CONTROLS[highlightId] = spec
    return true
end

local function TourControls(item)
    local id = type(item) == "table" and item.id or nil
    local spec = type(id) == "string" and TOUR_CONTROLS[id] or nil
    if type(spec) ~= "table" then return nil end
    local W = M.Widgets
    if not (type(W) == "table" and type(W.SettingsRows) == "function") then return nil end
    return spec
end

-- A highlight's `preview` is a media key, not a path: the release registry in
-- State/ must stay free of menu art. PreviewHelpers owns the resolution.
local function PreviewSpec(item)
    local key = type(item) == "table" and item.preview or nil
    if type(key) ~= "string" then return nil end
    local helpers = M.PreviewHelpers
    local previews = type(helpers) == "table" and helpers.TourPreviews or nil
    local spec = type(previews) == "table" and previews[key] or nil
    if type(spec) ~= "table" or type(spec.texture) ~= "string" then return nil end
    return spec
end

local function Controller()
    local value = MSUF and MSUF.UpgradeHighlights
    return type(value) == "table" and value or nil
end

local function BlockedByCombat()
    return type(M.BlockCombatAction) == "function" and M.BlockCombatAction() == true
end

local function RefreshHome()
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if type(M.SelectPage) == "function" then M.SelectPage("home") end
end

function M.RestartUpgradeHighlightTour(source)
    if BlockedByCombat() then
        return false, "Leave combat, then ask me to restart the highlight tour again.",
            { noMutation = true, userFacingFailure = true }
    end
    local controller = Controller()
    if not (controller and type(controller.ResetCurrent) == "function" and type(controller.Start) == "function") then
        return false, "The upgrade highlight tour is not available in this menu build.",
            { noMutation = true, userFacingFailure = true }
    end
    if type(M.SetPageHistoryTourCue) == "function" then M.SetPageHistoryTourCue(false) end
    local reset, releaseKey = controller:ResetCurrent()
    if reset ~= true then
        return false, "I could not reset the upgrade highlight tour.",
            { noMutation = true, userFacingFailure = true }
    end
    local started = controller:Start()
    if started ~= true then
        return false, "I reset the upgrade highlights but could not start the tour.",
            { userFacingFailure = true }
    end
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    local opened = type(M.Open) == "function" and M.Open("home")
    if opened == false or opened == nil then
        return false, "The highlight tour was restarted, but I could not open its first page.",
            { userFacingFailure = true }
    end
    return true, "Restarted the " .. tostring(releaseKey or "current")
        .. " upgrade highlight tour at highlight 1.", { source = tostring(source or "assistant") }
end

local function ApplyTargetRoute(item)
    local route = type(item) == "table" and item.route or nil
    if type(route) ~= "table" then return end
    local unit = tostring(route.unit or "")
    if unit ~= "" and type(route.unitTextTab) == "string" then
        M.unitTextTabSelection = type(M.unitTextTabSelection) == "table" and M.unitTextTabSelection or {}
        M.unitTextTabSelection[unit] = route.unitTextTab
    end
    if unit ~= "" and type(route.unitCastbarTab) == "string" then
        M.unitCastbarTabSelection = type(M.unitCastbarTabSelection) == "table" and M.unitCastbarTabSelection or {}
        M.unitCastbarTabSelection[unit] = route.unitCastbarTab
    end
    if unit ~= "" and type(route.unitAuraTab) == "string" then
        M.unitAuraTabSelection = type(M.unitAuraTabSelection) == "table" and M.unitAuraTabSelection or {}
        M.unitAuraTabSelection[unit] = route.unitAuraTab
        if type(route.unitAuraTool) == "string" then
            M.unitAuraToolSelection = type(M.unitAuraToolSelection) == "table" and M.unitAuraToolSelection or {}
            local tools = M.unitAuraToolSelection[unit]
            if type(tools) ~= "table" then tools = {}; M.unitAuraToolSelection[unit] = tools end
            tools[route.unitAuraTab] = route.unitAuraTool
        end
    end
    -- Sections open through the shared menu focus request, not by writing
    -- accordion state directly. The direct write was persistent, so every
    -- section an earlier highlight had opened stayed open: the HP Text card
    -- landed on the Auras section the first card opened, and the Portrait card
    -- landed on Text. A focus-opened section also scrolls into view, flashes
    -- its header, and closes again on the next navigation.
    if type(route.accordion) == "string" and route.accordion ~= "" then
        local pageKey, sectionId = route.accordion:match("^([^:]+):(.+)$")
        if pageKey and sectionId then
            _G.MSUF_EM2_MenuFocusRequest = {
                pageKey = pageKey,
                sectionId = sectionId,
                explicit = true,
                consumed = false,
            }
        end
    end
end
M.ApplyUpgradeHighlightTargetRoute = ApplyTargetRoute

local function OpenPage(item)
    local pageKey = type(item) == "table" and item.pageKey or item
    ApplyTargetRoute(item)
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("home") end
    if type(item) == "table" and type(item.route) == "table" and type(M.InvalidatePage) == "function" then
        M.InvalidatePage(pageKey)
    end
    -- A refused page change (combat) must not leave the focus request armed, or
    -- it fires at the next unrelated navigation.
    if type(M.SelectPage) == "function" and M.SelectPage(pageKey or "home") == false then
        _G.MSUF_EM2_MenuFocusRequest = nil
    end
end

local function SetTextLayout(fontString, width, justify)
    if not fontString then return fontString end
    fontString:SetWidth(max(1, width or 1))
    fontString:SetJustifyH(justify or "LEFT")
    if fontString.SetWordWrap then fontString:SetWordWrap(true) end
    if fontString.SetNonSpaceWrap then fontString:SetNonSpaceWrap(true) end
    return fontString
end

local function RegisterControl(widget, releaseKey, suffix, label, help)
    if not (widget and type(M.RegisterSearchWidget) == "function") then return widget end
    local safeRelease = tostring(releaseKey or "release"):gsub("[^%w]+", "_"):lower()
    local identity = "home.upgrade_highlights." .. safeRelease .. "." .. tostring(suffix or "action")
    M.RegisterSearchWidget(widget, {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = "home",
        classification = "action",
        actionKey = "upgrade_highlights." .. safeRelease .. "." .. tostring(suffix or "action"),
        label = Tr(label),
        kind = "button",
        help = help and Tr(help) or nil,
        historyMode = "none",
    })
    return widget
end

local function AddTooltip(widget, title, body)
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(widget, Tr(title), Tr(body), {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.88, 0.94 },
        })
    end
    return widget
end

local function Button(parent, T, releaseKey, suffix, label, x, y, width, onClick, role, help)
    local button = T.Button(parent, Tr(label), width, 26)
    button._msuf2SkipHistoryCheckpoint = true
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if type(T.CenterButtonLabel) == "function" then T.CenterButtonLabel(button) end
    if role == "primary" and type(T.SkinPrimaryButton) == "function" then
        T.SkinPrimaryButton(button)
    elseif role == "danger" and type(T.SkinDangerButton) == "function" then
        T.SkinDangerButton(button)
    end
    button:SetScript("OnClick", function()
        if BlockedByCombat() then return end
        if type(onClick) == "function" then onClick() end
    end)
    RegisterControl(button, releaseKey, suffix, label, help)
    if help then AddTooltip(button, label, help) end
    return button
end

local function CreateIconWell(parent, T, navKey, size, x, y)
    local well = T.Panel(parent, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    well:SetSize(size, size)
    well:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if type(T.ApplySurface) == "function" then T.ApplySurface(well, "card") end
    local icon = well:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetSize(floor(size * 0.52), floor(size * 0.52))
    icon:SetPoint("CENTER", well, "CENTER", 0, 0)
    local grid = T.navIconGrid and T.navIconGrid[navKey]
    if grid and T.media and T.media.navIcons then
        icon:SetTexture(T.media.navIcons)
        icon:SetTexCoord(grid[1] / 8, (grid[1] + 1) / 8, grid[2] / 8, (grid[2] + 1) / 8)
    else
        icon:SetTexture(T.media and T.media.logo or "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\MSUF_MinimapIcon.tga")
        icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
    end
    local color = T.navIconColors and T.navIconColors[navKey] or T.colors.coreHot or T.colors.accent
    icon:SetVertexColor(color[1], color[2], color[3], 0.98)
    return well
end

local function CreateScene(ctx, T)
    local width = max(320, tonumber(ctx.width) or 760)
    local sceneX, sceneTop = 12, -12
    local sceneWidth = max(288, width - sceneX)
    local contentWidth = min(720, max(280, sceneWidth - 40))
    local scene = CreateFrame("Frame", nil, ctx.wrapper)
    scene:SetPoint("TOPLEFT", ctx.wrapper, "TOPLEFT", sceneX, sceneTop)
    scene:SetWidth(sceneWidth)

    local wash = scene:CreateTexture(nil, "BACKGROUND", nil, 0)
    wash:SetPoint("TOPLEFT", scene, "TOPLEFT", 0, 0)
    wash:SetPoint("TOPRIGHT", scene, "TOPRIGHT", 0, 0)
    wash:SetHeight(260)
    wash:SetTexture((T.media and T.media.gradV) or "Interface\\Buttons\\WHITE8X8")
    wash:SetVertexColor(T.colors.coreBlue[1], T.colors.coreBlue[2], T.colors.coreBlue[3], 0.055)
    return scene, sceneWidth, contentWidth, contentWidth < 660, sceneTop
end

local function Header(scene, T, releaseKey, title, copy, contentWidth)
    local kicker = T.Font(scene, "GameFontDisableSmall", format(Tr("UPGRADED TO MSUF %s"), releaseKey), T.colors.coreHot or T.colors.accent)
    kicker:SetPoint("TOP", scene, "TOP", 0, -32)
    SetTextLayout(kicker, contentWidth, "CENTER")

    local heading = T.Font(scene, "GameFontNormalHuge", Tr(title), T.colors.title or T.colors.text)
    heading:SetPoint("TOP", scene, "TOP", 0, -64)
    SetTextLayout(heading, contentWidth, "CENTER")

    local body = T.Font(scene, "GameFontHighlight", Tr(copy), T.colors.muted)
    body:SetPoint("TOP", scene, "TOP", 0, -106)
    SetTextLayout(body, min(680, contentWidth), "CENTER")
end

local function SummaryRow(parent, T, item, number, x, y, width, compact)
    local height = compact and 58 or 48
    local row = T.Panel(parent, nil, T.colors.coreShadow or T.colors.bg, T.colors.borderSoft)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    row:SetSize(width, height)
    if type(T.ApplySurface) == "function" then T.ApplySurface(row, "card") end

    CreateIconWell(row, T, item.icon, 32, 10, -8)
    local numberText = T.Font(row, "GameFontDisableSmall", format("%02d", number), T.colors.coreHot or T.colors.accent)
    numberText:SetPoint("TOPLEFT", row, "TOPLEFT", 52, -8)
    local title = T.Font(row, "GameFontHighlight", Tr(item.title), T.colors.text)
    title:SetPoint("TOPLEFT", row, "TOPLEFT", 78, -8)
    SetTextLayout(title, width - 90, "LEFT")
    if not compact then
        local copy = T.Font(row, "GameFontDisableSmall", Tr(item.summary), T.colors.dim)
        copy:SetPoint("TOPLEFT", row, "TOPLEFT", 80, -28)
        SetTextLayout(copy, width - 90, "LEFT")
    end
    return height
end

local function RemainingHighlights(spec, record)
    local remaining = {}
    local outcomes = type(record.outcomes) == "table" and record.outcomes or {}
    for i = 1, #spec.highlights do
        local item = spec.highlights[i]
        if outcomes[item.id] == nil then remaining[#remaining + 1] = item end
    end
    return remaining
end

local function BuildLanding(ctx, scene, T, releaseKey, spec, record, contentWidth, compact, sceneTop)
    local count = #spec.highlights
    Header(scene, T, releaseKey, spec.title,
        format(Tr("Your current profile stays unchanged. Review %d new highlights and choose only what you want to configure."), count),
        contentWidth)

    local profile = tostring(_G.MSUF_ActiveProfile or "Default")
    -- Highlight cards now host live controls, so the old absolute promise
    -- ("no settings will be changed") would be a lie the moment someone uses
    -- one. The tour still never writes a value on its own.
    local safety = T.Font(scene, "GameFontDisableSmall",
        format(Tr("CURRENT PROFILE: %s - NOTHING CHANGES UNTIL YOU CHANGE IT"), profile), T.colors.ok or T.colors.coreHot)
    safety:SetPoint("TOP", scene, "TOP", 0, -154)
    SetTextLayout(safety, contentWidth, "CENTER")

    local listTop = -188
    local gap = 8
    local rowHeight = compact and 60 or 48
    for i = 1, count do
        SummaryRow(scene, T, spec.highlights[i], i, floor((scene:GetWidth() - contentWidth) / 2),
            listTop - ((i - 1) * (rowHeight + gap)), contentWidth, compact)
    end

    local buttonsTop = listTop - (count * rowHeight) - ((count - 1) * gap) - 20
    if compact then
        local buttonWidth = min(260, contentWidth)
        local x = floor((scene:GetWidth() - buttonWidth) / 2)
        Button(scene, T, releaseKey, "start", format(Tr("Start %d-highlight tour"), count), x, buttonsTop, buttonWidth,
            function() Controller():Start(); RefreshHome() end, "primary",
            "Review the release highlights without changing your current profile.")
        Button(scene, T, releaseKey, "skip_request", "Continue with current profile", x, buttonsTop - 36, buttonWidth,
            function() Controller():RequestSkip(); RefreshHome() end, nil,
            "Review exactly what you would skip before closing the tour.")
        buttonsTop = buttonsTop - 36
    else
        local primaryWidth, secondaryWidth, gapWidth = 212, 212, 12
        local x = floor((scene:GetWidth() - primaryWidth - secondaryWidth - gapWidth) / 2)
        Button(scene, T, releaseKey, "start", format(Tr("Start %d-highlight tour"), count), x, buttonsTop, primaryWidth,
            function() Controller():Start(); RefreshHome() end, "primary",
            "Review the release highlights without changing your current profile.")
        Button(scene, T, releaseKey, "skip_request", "Continue with current profile", x + primaryWidth + gapWidth, buttonsTop, secondaryWidth,
            function() Controller():RequestSkip(); RefreshHome() end, nil,
            "Review exactly what you would skip before closing the tour.")
    end

    local hintTop = buttonsTop - 44
    local hint = T.Font(scene, "GameFontDisableSmall", Tr("About two minutes. You can leave at any point and configure each area later."), T.colors.dim)
    hint:SetPoint("TOP", scene, "TOP", 0, hintTop)
    SetTextLayout(hint, contentWidth, "CENTER")
    local height = math.abs(hintTop) + 36
    scene:SetHeight(height)
    ctx:SetContentHeight(height + math.abs(sceneTop) + 24)
end

local function Progress(scene, T, count, current, contentWidth, top)
    local gap = 8
    local segmentWidth = floor((contentWidth - ((count - 1) * gap)) / count)
    local x = floor((scene:GetWidth() - contentWidth) / 2)
    for i = 1, count do
        local active = i <= current
        local color = active and (T.colors.coreHot or T.colors.accent) or (T.colors.borderSoft or T.colors.dim)
        local segment = scene:CreateTexture(nil, "ARTWORK", nil, 2)
        segment:SetPoint("TOPLEFT", scene, "TOPLEFT", x + ((i - 1) * (segmentWidth + gap)), top)
        segment:SetSize(segmentWidth, 3)
        segment:SetColorTexture(color[1], color[2], color[3], active and 0.92 or 0.34)
    end
end

-- Non-interactive mock of the layer sub-menu for the linkless layer card:
-- a dummy 0-30 slider plus a miniature Layer Overview stack, built entirely
-- from already-localized strings. Purely decorative, no mouse handling.
local function BuildLayerDummyPreview(card, T, x, width)
    local panel = T.Panel(card, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    panel:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", x, 16)
    panel:SetSize(width, 76)
    if type(T.ApplySurface) == "function" then T.ApplySurface(panel, "card") end

    local half = floor(width / 2)
    local accent = T.colors.coreHot or T.colors.accent
    local label = T.Font(panel, "GameFontDisableSmall", Tr("Layer (0-30)"), T.colors.muted)
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)

    local trackWidth = max(56, half - 58)
    local track = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    track:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -40)
    track:SetSize(trackWidth, 4)
    local trackColor = T.colors.borderSoft
    track:SetColorTexture(trackColor[1], trackColor[2], trackColor[3], 0.9)

    local fillWidth = floor(trackWidth * 0.4)
    local fill = panel:CreateTexture(nil, "ARTWORK", nil, 2)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetSize(fillWidth, 4)
    fill:SetColorTexture(accent[1], accent[2], accent[3], 0.95)

    local knob = panel:CreateTexture(nil, "ARTWORK", nil, 3)
    knob:SetSize(10, 14)
    knob:SetPoint("CENTER", track, "LEFT", fillWidth, 0)
    knob:SetColorTexture(accent[1], accent[2], accent[3], 1)

    local value = T.Font(panel, "GameFontHighlightSmall", "12", T.colors.text)
    value:SetPoint("LEFT", track, "RIGHT", 10, 0)

    local overviewX = half + 12
    local overviewTitle = T.Font(panel, "GameFontDisableSmall", Tr("Layer Overview"), T.colors.muted)
    overviewTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", overviewX, -12)
    local rows = { { "18", "Text" }, { "12", "Auras" }, { "5", "Border" } }
    for i = 1, #rows do
        local y = -28 - ((i - 1) * 15)
        local num = T.Font(panel, "GameFontHighlightSmall", rows[i][1], accent)
        num:SetPoint("TOPLEFT", panel, "TOPLEFT", overviewX, y)
        local name = T.Font(panel, "GameFontHighlightSmall", Tr(rows[i][2]), T.colors.text)
        name:SetPoint("TOPLEFT", panel, "TOPLEFT", overviewX + 26, y)
    end
    return panel
end

-- Live settings inside the highlight card. W.SettingsRows uses the same widget
-- constructors and binders the real pages use, so these controls inherit the
-- page behavior wholesale: combat gating, Undo/Redo, and the owning page's
-- apply path. The tour never writes a value on its own.
local function BuildTourControls(ctx, card, T, spec, x, y, width)
    local rows = spec.rows()
    if type(rows) ~= "table" or #rows == 0 then return false end
    local hint = T.Font(card, "GameFontDisableSmall", Tr("TRY IT RIGHT HERE"), T.colors.coreHot or T.colors.accent)
    hint:SetPoint("TOPLEFT", card, "TOPLEFT", x, y)
    SetTextLayout(hint, width, "LEFT")
    local result = M.Widgets.SettingsRows(ctx, card, {
        x = x,
        y = y - TOUR_CONTROLS_LABEL_HEIGHT,
        width = width,
        columns = max(1, tonumber(spec.columns) or 1),
        rows = rows,
    })
    -- Gating is page knowledge (which control depends on which master), so the
    -- registering page wires it here rather than the tour guessing at it.
    if type(spec.after) == "function" then spec.after(ctx, result) end
    return true
end

local function BuildActive(ctx, scene, T, releaseKey, spec, record, contentWidth, compact, sceneTop)
    local count = #spec.highlights
    local index = max(1, min(count, tonumber(record.index) or 1))
    local item = spec.highlights[index]
    Header(scene, T, releaseKey, format(Tr("Highlight %d of %d"), index, count), "", contentWidth)
    Progress(scene, T, count, index, contentWidth, -156)

    local cardTop = -184
    local hasLayerPreview = item.id == "frame_layers"
    local textX = compact and 20 or 88
    local textWidth = compact and (contentWidth - 40) or (contentWidth - 112)
    local previewSpec = PreviewSpec(item)
    local previewWidth = previewSpec and min(PREVIEW_MAX_WIDTH, max(160, textWidth)) or 0
    local previewHeight = previewSpec and floor(previewWidth / (previewSpec.aspect or 2) + 0.5) or 0
    local controlsSpec = TourControls(item)
    -- The rows always get the full text column: a side-by-side split next to the
    -- screenshot leaves roughly 130px per column, which is not enough for a
    -- toggle label like "Mouseover highlights".
    local controlsHeight = controlsSpec
        and (TOUR_CONTROLS_LABEL_HEIGHT + max(40, tonumber(controlsSpec.height) or 120)) or 0
    local bandHeight = previewHeight + controlsHeight
        + ((previewSpec and controlsSpec) and TOUR_BAND_GAP or 0)
    local cardHeight = (compact and 280 or 240) + (hasLayerPreview and 96 or 0)
        + (bandHeight > 0 and (bandHeight + 16) or 0)
    local card = T.Panel(scene, nil, T.colors.coreShadow or T.colors.bg, T.colors.cardBorder or T.colors.borderSoft)
    card:SetPoint("TOPLEFT", scene, "TOPLEFT", floor((scene:GetWidth() - contentWidth) / 2), cardTop)
    card:SetSize(contentWidth, cardHeight)
    if type(T.ApplySurface) == "function" then T.ApplySurface(card, "card") end
    CreateIconWell(card, T, item.icon, compact and 44 or 52, 20, -20)

    local titleTop = compact and -80 or -24
    local title = T.Font(card, "GameFontNormalLarge", Tr(item.title), T.colors.title or T.colors.text)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", textX, titleTop)
    SetTextLayout(title, textWidth, "LEFT")

    local summary = T.Font(card, "GameFontHighlight", Tr(item.summary), T.colors.muted)
    summary:SetPoint("TOPLEFT", card, "TOPLEFT", textX, titleTop - 40)
    SetTextLayout(summary, textWidth, "LEFT")

    local why = T.Font(card, "GameFontDisableSmall", Tr("WHY IT MATTERS"), T.colors.coreHot or T.colors.accent)
    why:SetPoint("TOPLEFT", card, "TOPLEFT", textX, titleTop - 104)
    local impact = T.Font(card, "GameFontHighlight", Tr(item.impact), T.colors.text)
    impact:SetPoint("TOPLEFT", card, "TOPLEFT", textX, titleTop - 124)
    SetTextLayout(impact, textWidth, "LEFT")
    if hasLayerPreview then
        BuildLayerDummyPreview(card, T, textX, textWidth)
    end
    local bandTop = -(cardHeight - bandHeight - 16)
    if previewSpec and type(M.Widgets) == "table" and type(M.Widgets.PreviewImage) == "function" then
        M.Widgets.PreviewImage(card, previewSpec, textX, bandTop, previewWidth)
    end
    if controlsSpec then
        local controlsTop = previewSpec and (bandTop - previewHeight - TOUR_BAND_GAP) or bandTop
        BuildTourControls(ctx, card, T, controlsSpec, textX, controlsTop, textWidth)
    end

    local buttonsTop = cardTop - cardHeight - 20
    local buttonY = buttonsTop
    local function ConfigureCurrent()
        local openAssistant = item.id == "assistant"
        if openAssistant then
            -- Home normally rebuilds straight back into the still-active
            -- highlight tour. Bypass that scene for exactly this rebuild so
            -- the Dashboard can create its cold Assistant card before the LoD
            -- bridge starts the runtime. The next normal Home build resumes
            -- the tour at the following highlight.
            M._upgradeHighlightAssistantDetour = true
        end
        Controller():Advance("opened")
        OpenPage(item)
        if item.id == "page_history"
            and type(M.SetPageHistoryTourCue) == "function"
        then
            M.SetPageHistoryTourCue(true)
        end
        -- The Assistant remains load-on-demand. Only its explicit final
        -- highlight action promotes the normal Home card and loads runtime.
        if openAssistant then
            -- A refused/redundant page rebuild must not leak the one-shot
            -- bypass into a later unrelated Home navigation.
            M._upgradeHighlightAssistantDetour = nil
            if type(M.StartNewAssistantTask) == "function" then
                M.StartNewAssistantTask()
                return
            end
            local assistant = MSUF and MSUF.Assistant
            if type(assistant) == "table" and type(assistant.StartNewTaskWithRuntime) == "function" then
                assistant.StartNewTaskWithRuntime("upgrade-highlights")
            end
        -- Edit Mode has no page to land on, so its action starts the mode
        -- itself. `M.ToggleDashboardEditMode` is not an option here: it is
        -- created inside the Dashboard build, which early-returns into this
        -- scene, so it does not exist while the tour owns Home. The shared
        -- lifecycle setter is file scope, is a no-op when the mode already
        -- runs, and shows the standard combat-lock message on its own.
        elseif item.id == "edit_mode" then
            if type(M.SetMSUFEditModeActive) == "function" then
                M.SetMSUFEditModeActive(true, nil, { source = "upgrade_highlights" })
            end
        end
    end
    -- Linkless cards (inline dummy preview instead of a route) offer only the
    -- review flow, so "Next" takes over the primary role there.
    local nextLabel = index == count and "Finish tour" or "Next highlight"
    local nextRole = item.action and nil or "primary"
    local function AdvanceReviewed()
        Controller():Advance("reviewed")
        RefreshHome()
    end
    if compact then
        local w = min(250, contentWidth)
        local x = floor((scene:GetWidth() - w) / 2)
        if item.action then
            Button(scene, T, releaseKey, "configure_" .. item.id, item.action, x, buttonY, w,
                ConfigureCurrent, "primary", item.impact)
            buttonY = buttonY - 36
        end
        Button(scene, T, releaseKey, "next_" .. item.id, nextLabel, x, buttonY, w,
            AdvanceReviewed, nextRole, "Mark this highlight as reviewed and continue.")
    else
        local w, gap = 172, 12
        local x
        if item.action then
            x = floor((scene:GetWidth() - (w * 2) - gap) / 2)
            Button(scene, T, releaseKey, "configure_" .. item.id, item.action, x, buttonY, w,
                ConfigureCurrent, "primary", item.impact)
            x = x + w + gap
        else
            x = floor((scene:GetWidth() - w) / 2)
        end
        Button(scene, T, releaseKey, "next_" .. item.id, nextLabel, x, buttonY, w,
            AdvanceReviewed, nextRole, "Mark this highlight as reviewed and continue.")
    end

    local utilityTop = buttonY - 44
    local backWidth, skipWidth = 92, 104
    local utilityX = floor((scene:GetWidth() - backWidth - skipWidth - 12) / 2)
    local back = Button(scene, T, releaseKey, "back", "Back", utilityX, utilityTop, backWidth,
        function() Controller():Back(); RefreshHome() end, nil)
    if index <= 1 and type(back.Disable) == "function" then back:Disable() end
    Button(scene, T, releaseKey, "skip_request", "Skip tour", utilityX + backWidth + 12, utilityTop, skipWidth,
        function() Controller():RequestSkip(); RefreshHome() end, nil,
        "See the remaining highlights before deciding to skip them.")

    local height = math.abs(utilityTop) + 48
    scene:SetHeight(height)
    ctx:SetContentHeight(height + math.abs(sceneTop) + 24)
end

local function BuildSkipWarning(ctx, scene, T, releaseKey, spec, record, contentWidth, compact, sceneTop)
    local remaining = RemainingHighlights(spec, record)
    local count = #remaining
    Header(scene, T, releaseKey, format(Tr("Skip %d remaining highlights?"), count),
        format(Tr("Your profile will stay safe, but you will leave these %d new configuration areas unexplored:"), count),
        contentWidth)

    local listTop = -174
    local rowHeight, gap = compact and 44 or 40, 8
    for i = 1, count do
        local item = remaining[i]
        local row = T.Panel(scene, nil, T.colors.coreShadow or T.colors.bg, T.colors.borderSoft)
        row:SetPoint("TOPLEFT", scene, "TOPLEFT", floor((scene:GetWidth() - contentWidth) / 2), listTop - ((i - 1) * (rowHeight + gap)))
        row:SetSize(contentWidth, rowHeight)
        if type(T.ApplySurface) == "function" then T.ApplySurface(row, "card") end
        local marker = T.Font(row, "GameFontHighlight", format("%d.", i), T.colors.coreHot or T.colors.accent)
        marker:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -12)
        local text = T.Font(row, "GameFontHighlight", Tr(item.missed), T.colors.text)
        text:SetPoint("TOPLEFT", row, "TOPLEFT", 40, -12)
        SetTextLayout(text, contentWidth - 52, "LEFT")
    end

    local buttonsTop = listTop - (count * rowHeight) - (max(0, count - 1) * gap) - 24
    if compact then
        local w = min(270, contentWidth)
        local x = floor((scene:GetWidth() - w) / 2)
        Button(scene, T, releaseKey, "cancel_skip", "Show me the highlights", x, buttonsTop, w,
            function() Controller():CancelSkip(); RefreshHome() end, "primary")
        Button(scene, T, releaseKey, "confirm_skip", format(Tr("Skip all %d and continue"), count), x, buttonsTop - 36, w,
            function() Controller():ConfirmSkip(); RefreshHome() end, "danger")
        buttonsTop = buttonsTop - 36
    else
        local w, gapWidth = 212, 12
        local x = floor((scene:GetWidth() - (w * 2) - gapWidth) / 2)
        Button(scene, T, releaseKey, "cancel_skip", "Show me the highlights", x, buttonsTop, w,
            function() Controller():CancelSkip(); RefreshHome() end, "primary")
        Button(scene, T, releaseKey, "confirm_skip", format(Tr("Skip all %d and continue"), count), x + w + gapWidth, buttonsTop, w,
            function() Controller():ConfirmSkip(); RefreshHome() end, "danger")
    end

    local noteTop = buttonsTop - 44
    local note = T.Font(scene, "GameFontDisableSmall", Tr("Skipping closes this release tour only. Every setting remains available in Menu2."), T.colors.dim)
    note:SetPoint("TOP", scene, "TOP", 0, noteTop)
    SetTextLayout(note, contentWidth, "CENTER")
    local height = math.abs(noteTop) + 36
    scene:SetHeight(height)
    ctx:SetContentHeight(height + math.abs(sceneTop) + 24)
end

function M.BuildUpgradeHighlightDashboardScene(ctx)
    if M._upgradeHighlightAssistantDetour == true then
        M._upgradeHighlightAssistantDetour = nil
        return false
    end
    local controller = Controller()
    if not controller or type(controller.ShouldShow) ~= "function" or not controller:ShouldShow() then return false end
    local T = M.Theme
    if not (ctx and ctx.wrapper and T and type(T.Panel) == "function" and type(T.Font) == "function" and type(T.Button) == "function") then
        return false
    end

    local releaseKey, spec, record = controller:GetCurrent()
    if not (releaseKey and type(spec) == "table" and type(record) == "table") then return false end
    local scene, _, contentWidth, compact, sceneTop = CreateScene(ctx, T)
    if record.status == "skip_warning" then
        BuildSkipWarning(ctx, scene, T, releaseKey, spec, record, contentWidth, compact, sceneTop)
    elseif record.status == "active" then
        BuildActive(ctx, scene, T, releaseKey, spec, record, contentWidth, compact, sceneTop)
    else
        BuildLanding(ctx, scene, T, releaseKey, spec, record, contentWidth, compact, sceneTop)
    end
    return true
end
