-- Interactive, non-destructive release highlights for existing profiles.
-- Lifecycle and release data live in State/MSUF_UpgradeHighlights.lua.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", "Shell/Menu2/MSUF_Menu2_UpgradeHighlights.lua")
local ExportPublic = MSUF.ExportPublic
local CreateFrame = CreateFrame
local floor = math.floor
local max = math.max
local min = math.min
local format = string.format
local tostring = tostring
local type = type

local PREVIEW_MAX_WIDTH = 320
local TOUR_BAND_GAP = 16
local TOUR_CONTROLS_LABEL_HEIGHT = 20

local Tr = M.Tr

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
    if not (type(W) == "table") then return nil end
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
    return M.BlockCombatAction() == true
end

local function RefreshHome()
    M.InvalidatePage("home")
    M.SelectPage("home")
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
            if type(tools) ~= "table" then
                tools = {}
                M.unitAuraToolSelection[unit] = tools
            end
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
            ExportPublic("MSUF_EM2_MenuFocusRequest", {
                pageKey = pageKey,
                sectionId = sectionId,
                explicit = true,
                consumed = false,
            })
        end
    end
end

local function OpenPage(item)
    local pageKey = type(item) == "table" and item.pageKey or item
    ApplyTargetRoute(item)
    M.InvalidatePage("home")
    if type(item) == "table" and type(item.route) == "table" then
        M.InvalidatePage(pageKey)
    end
    -- A refused page change (combat) must not leave the focus request armed, or
    -- it fires at the next unrelated navigation.
    if M.SelectPage(pageKey or "home") == false then
        ExportPublic("MSUF_EM2_MenuFocusRequest", nil)
    end
end

local SetTextLayout = M.Widgets.SetTextLayout

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
    local button = T.Button(parent, label, width, 26)
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

--- Font string anchored at (x, y) from `point` of its parent, wrapped to `width` when given.
local function Text(parent, T, template, text, color, point, x, y, width, justify)
    local fs = T.Font(parent, template, text, color)
    fs:SetPoint(point, parent, point, x, y)
    if width then SetTextLayout(fs, width, justify) end
    return fs
end

--- Click handler: run a lifecycle step on the controller, then rebuild Home.
local function HomeAction(method)
    return function()
        local controller = Controller()
        controller[method](controller)
        RefreshHome()
    end
end

--- Centres one or two action buttons under the scene (stacked when compact). Each spec is
--- { suffix, label, onClick, role, help }; `widths` are the compact cap and the wide width.
--- Returns the y of the last button row.
local function ButtonRow(scene, T, releaseKey, top, compact, contentWidth, widths, first, second)
    local sceneWidth, gap = scene:GetWidth(), 12
    local function Make(spec, x, y, width)
        Button(scene, T, releaseKey, spec[1], spec[2], x, y, width, spec[3], spec[4], spec[5])
    end
    if compact then
        local width = min(widths[1], contentWidth)
        local x = floor((sceneWidth - width) / 2)
        if first then
            Make(first, x, top, width)
            top = top - 36
        end
        Make(second, x, top, width)
        return top
    end
    local width = widths[2]
    local x
    if first then
        x = floor((sceneWidth - (width * 2) - gap) / 2)
        Make(first, x, top, width)
        x = x + width + gap
    else
        x = floor((sceneWidth - width) / 2)
    end
    Make(second, x, top, width)
    return top
end

--- Sizes the scene to its last element and tells the page about its content height.
local function FinishScene(ctx, scene, sceneTop, lastTop, pad)
    local height = math.abs(lastTop) + pad
    scene:SetHeight(height)
    ctx:SetContentHeight(height + math.abs(sceneTop) + 24)
end

local function CreateIconWell(parent, T, navKey, size, x, y)
    local well = T.Panel(parent, nil, T.colors.pillBaseSolid or T.colors.panel2, T.colors.pillEdge or T.colors.borderSoft)
    well:SetSize(size, size)
    well:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if type(T.ApplySurface) == "function" then T.ApplySurface(well, "card") end
    local icon = PixelLayoutRegion(well:CreateTexture(nil, "ARTWORK", nil, 2))
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
    local scene = M.Widgets.OnboardingScene(ctx.wrapper, T, sceneX, sceneTop, sceneWidth, 260)
    return scene, sceneWidth, contentWidth, contentWidth < 660, sceneTop
end

local function Header(scene, T, releaseKey, title, copy, contentWidth)
    local kicker = Text(scene, T, "GameFontDisableSmall", "", T.colors.coreHot or T.colors.accent, "TOP", 0, -32, contentWidth, "CENTER")
    T.SetTranslatedText(kicker, format(Tr("UPGRADED TO MSUF %s"), releaseKey))
    Text(scene, T, "GameFontNormalHuge", title, T.colors.title or T.colors.text, "TOP", 0, -64, contentWidth, "CENTER")
    Text(scene, T, "GameFontHighlight", copy, T.colors.muted, "TOP", 0, -106, min(680, contentWidth), "CENTER")
end

local function SummaryRow(parent, T, item, number, x, y, width, compact)
    local height = compact and 58 or 48
    local row = T.Panel(parent, nil, T.colors.coreShadow or T.colors.bg, T.colors.borderSoft)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    row:SetSize(width, height)
    if type(T.ApplySurface) == "function" then T.ApplySurface(row, "card") end

    CreateIconWell(row, T, item.icon, 32, 10, -8)
    Text(row, T, "GameFontDisableSmall", format("%02d", number), T.colors.coreHot or T.colors.accent, "TOPLEFT", 52, -8)
    Text(row, T, "GameFontHighlight", item.title, T.colors.text, "TOPLEFT", 78, -8, width - 90, "LEFT")
    if not compact then
        Text(row, T, "GameFontDisableSmall", item.summary, T.colors.dim, "TOPLEFT", 80, -28, width - 90, "LEFT")
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

    local profile = tostring(MSUF_ActiveProfile or "Default")
    -- Highlight cards now host live controls, so the old absolute promise
    -- ("no settings will be changed") would be a lie the moment someone uses
    -- one. The tour still never writes a value on its own.
    Text(scene, T, "GameFontDisableSmall",
        format(Tr("CURRENT PROFILE: %s - NOTHING CHANGES UNTIL YOU CHANGE IT"), profile), T.colors.ok or T.colors.coreHot,
        "TOP", 0, -154, contentWidth, "CENTER")

    local listTop = -188
    local gap = 8
    local rowHeight = compact and 60 or 48
    for i = 1, count do
        SummaryRow(scene, T, spec.highlights[i], i, floor((scene:GetWidth() - contentWidth) / 2),
            listTop - ((i - 1) * (rowHeight + gap)), contentWidth, compact)
    end

    local buttonsTop = ButtonRow(scene, T, releaseKey, listTop - (count * rowHeight) - ((count - 1) * gap) - 20, compact, contentWidth,
        { 260, 212 },
        { "start", format(Tr("Start %d-highlight tour"), count), HomeAction("Start"), "primary",
            "Review the release highlights without changing your current profile." },
        { "skip_request", "Continue with current profile", HomeAction("RequestSkip"), nil,
            "Review exactly what you would skip before closing the tour." })

    local hintTop = buttonsTop - 44
    Text(scene, T, "GameFontDisableSmall", "About two minutes. You can leave at any point and configure each area later.", T.colors.dim,
        "TOP", 0, hintTop, contentWidth, "CENTER")
    FinishScene(ctx, scene, sceneTop, hintTop, 36)
end

local function Progress(scene, T, count, current, contentWidth, top)
    local gap = 8
    local segmentWidth = floor((contentWidth - ((count - 1) * gap)) / count)
    local x = floor((scene:GetWidth() - contentWidth) / 2)
    for i = 1, count do
        local active = i <= current
        local color = active and (T.colors.coreHot or T.colors.accent) or (T.colors.borderSoft or T.colors.dim)
        local segment = PixelLayoutRegion(scene:CreateTexture(nil, "ARTWORK", nil, 2))
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
    Text(panel, T, "GameFontDisableSmall", "Layer (0-30)", T.colors.muted, "TOPLEFT", 14, -12)

    local trackWidth = max(56, half - 58)
    local track = PixelLayoutRegion(panel:CreateTexture(nil, "ARTWORK", nil, 1))
    track:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -40)
    track:SetSize(trackWidth, 4)
    local trackColor = T.colors.borderSoft
    track:SetColorTexture(trackColor[1], trackColor[2], trackColor[3], 0.9)

    local fillWidth = floor(trackWidth * 0.4)
    local fill = PixelLayoutRegion(panel:CreateTexture(nil, "ARTWORK", nil, 2))
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetSize(fillWidth, 4)
    fill:SetColorTexture(accent[1], accent[2], accent[3], 0.95)

    local knob = PixelLayoutRegion(panel:CreateTexture(nil, "ARTWORK", nil, 3))
    knob:SetSize(10, 14)
    knob:SetPoint("CENTER", track, "LEFT", fillWidth, 0)
    knob:SetColorTexture(accent[1], accent[2], accent[3], 1)

    local value = T.Font(panel, "GameFontHighlightSmall", "12", T.colors.text)
    value:SetPoint("LEFT", track, "RIGHT", 10, 0)

    local overviewX = half + 12
    Text(panel, T, "GameFontDisableSmall", "Layer Overview", T.colors.muted, "TOPLEFT", overviewX, -12)
    local rows = { { "18", "Text" }, { "12", "Auras" }, { "5", "Border" } }
    for i = 1, #rows do
        local y = -28 - ((i - 1) * 15)
        Text(panel, T, "GameFontHighlightSmall", rows[i][1], accent, "TOPLEFT", overviewX, y)
        Text(panel, T, "GameFontHighlightSmall", rows[i][2], T.colors.text, "TOPLEFT", overviewX + 26, y)
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
    Text(card, T, "GameFontDisableSmall", "TRY IT RIGHT HERE", T.colors.coreHot or T.colors.accent, "TOPLEFT", x, y, width, "LEFT")
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
    Text(card, T, "GameFontNormalLarge", item.title, T.colors.title or T.colors.text, "TOPLEFT", textX, titleTop, textWidth, "LEFT")
    Text(card, T, "GameFontHighlight", item.summary, T.colors.muted, "TOPLEFT", textX, titleTop - 40, textWidth, "LEFT")
    Text(card, T, "GameFontDisableSmall", "WHY IT MATTERS", T.colors.coreHot or T.colors.accent, "TOPLEFT", textX, titleTop - 104)
    Text(card, T, "GameFontHighlight", item.impact, T.colors.text, "TOPLEFT", textX, titleTop - 124, textWidth, "LEFT")
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

    local function ConfigureCurrent()
        Controller():Advance("opened")
        OpenPage(item)
        if item.id == "page_history" then
            M.SetPageHistoryTourCue(true)
        end
        -- Edit Mode has no page to land on, so its action starts the mode
        -- itself. `M.ToggleDashboardEditMode` is not an option here: it is
        -- created inside the Dashboard build, which early-returns into this
        -- scene, so it does not exist while the tour owns Home. The shared
        -- lifecycle setter is file scope, is a no-op when the mode already
        -- runs, and shows the standard combat-lock message on its own.
        if item.id == "edit_mode" then
            if type(M.SetMSUFEditModeActive) == "function" then
                M.SetMSUFEditModeActive(true, nil, { source = "upgrade_highlights" })
            end
        end
    end
    -- Linkless cards (inline dummy preview instead of a route) offer only the
    -- review flow, so "Next" takes over the primary role there.
    local nextLabel = index == count and "Finish tour" or "Next highlight"
    local function AdvanceReviewed()
        Controller():Advance("reviewed")
        RefreshHome()
    end
    local buttonY = ButtonRow(scene, T, releaseKey, cardTop - cardHeight - 20, compact, contentWidth, { 250, 172 },
        item.action and { "configure_" .. item.id, item.action, ConfigureCurrent, "primary", item.impact } or nil,
        { "next_" .. item.id, nextLabel, AdvanceReviewed, (not item.action) and "primary" or nil,
            "Mark this highlight as reviewed and continue." })

    local utilityTop = buttonY - 44
    local backWidth, skipWidth = 92, 104
    local utilityX = floor((scene:GetWidth() - backWidth - skipWidth - 12) / 2)
    local back = Button(scene, T, releaseKey, "back", "Back", utilityX, utilityTop, backWidth, HomeAction("Back"), nil)
    if index <= 1 and type(back.Disable) == "function" then back:Disable() end
    Button(scene, T, releaseKey, "skip_request", "Skip tour", utilityX + backWidth + 12, utilityTop, skipWidth,
        HomeAction("RequestSkip"), nil, "See the remaining highlights before deciding to skip them.")

    FinishScene(ctx, scene, sceneTop, utilityTop, 48)
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
        Text(row, T, "GameFontHighlight", format("%d.", i), T.colors.coreHot or T.colors.accent, "TOPLEFT", 12, -12)
        Text(row, T, "GameFontHighlight", item.missed, T.colors.text, "TOPLEFT", 40, -12, contentWidth - 52, "LEFT")
    end

    local buttonsTop = ButtonRow(scene, T, releaseKey, listTop - (count * rowHeight) - (max(0, count - 1) * gap) - 24, compact,
        contentWidth, { 270, 212 },
        { "cancel_skip", "Show me the highlights", HomeAction("CancelSkip"), "primary" },
        { "confirm_skip", format(Tr("Skip all %d and continue"), count), HomeAction("ConfirmSkip"), "secondary" })

    local noteTop = buttonsTop - 44
    Text(scene, T, "GameFontDisableSmall", "Skipping closes this release tour only. Every setting remains available in Menu2.", T.colors.dim,
        "TOP", 0, noteTop, contentWidth, "CENTER")
    FinishScene(ctx, scene, sceneTop, noteTop, 36)
end

function M.BuildUpgradeHighlightDashboardScene(ctx)
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
