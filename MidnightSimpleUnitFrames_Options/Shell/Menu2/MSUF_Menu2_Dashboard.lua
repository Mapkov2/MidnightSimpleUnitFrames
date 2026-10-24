-- Menu2 dashboard: builds dashboard panels, summaries, and launcher actions.
-- UI construction stays here; profile/runtime mutations route through shared Menu2 helpers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/MSUF_Menu2_Dashboard.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
local C_Timer = M.MenuTimer or C_Timer
local T = M.Theme
local W = M.Widgets

-- Menu2 dashboard page.
-- Builds the home overview, recovery panels, changelog preview, and quick actions. Dashboard
-- widgets should call workflow/page helpers; profile/runtime mutation stays outside this file.
local floor = math.floor
local max = math.max
local min = math.min
local CreateFrame = CreateFrame
local CreateColor = CreateColor

local NormalizeControlPath = M.NormalizeControlPath
local function DashboardMeta(semanticPath, classification, exact)
    local identity = table.concat({ "home", "dashboard", NormalizeControlPath(semanticPath) }, ".")
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        pageKey = "home",
        classification = classification or "setting",
    }
    if meta.classification == "ephemeral" then meta.ephemeral = true end
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    local disclosure = semanticPath:find("^scaling%.") and "dashboardScalingOpen"
        or semanticPath:find("^display_recovery%.") and "dashboardRecoveryOpen"
        or semanticPath:find("^support%.") and "dashboardSupportOpen"
    if disclosure and not semanticPath:find("%.disclosure$") then
        meta.searchPrepareKind, meta.searchPrepareValue = "dashboardDisclosure", disclosure
        meta.prepareExactSearchTarget = function()
            M.SetMenuStateValue(disclosure, true)
            return true
        end
    end
    return meta
end
local function RegisterDashboardControl(widget, meta, label, kind, values)
    if not (widget and type(meta) == "table" and type(M.RegisterSearchWidget) == "function") then return widget end
    local payload = {}
    for key, value in pairs(meta) do payload[key] = value end
    payload.label = label or payload.label
    payload.kind = kind or payload.kind
    payload.values = values or payload.values
    M.RegisterSearchWidget(widget, payload)
    return widget
end

local function DirectClamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local function DirectPercent(value, fallback)
    return math.floor(((tonumber(value) or fallback or 1) * 100) + 0.5)
end
local function DirectSnapPercent(value, minPercent, maxPercent, stepPercent)
    stepPercent = stepPercent or 1
    local percent = math.floor((tonumber(value) or 100) / stepPercent + 0.5) * stepPercent
    return DirectClamp(percent, minPercent, maxPercent)
end
local MENU_SCALE_REFERENCE = 0.80
local MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT, MENU_SCALE_STEP_PERCENT = 25, 200, 5
local MSUF_SCALE_MIN_PERCENT, MSUF_SCALE_MAX_PERCENT, MSUF_SCALE_STEP_PERCENT = 25, 200, 5
local function MenuScalePercentFromStored(value)
    local minStored = MENU_SCALE_REFERENCE * (MENU_SCALE_MIN_PERCENT / 100)
    local maxStored = MENU_SCALE_REFERENCE * (MENU_SCALE_MAX_PERCENT / 100)
    return DirectPercent(DirectClamp(tonumber(value) or MENU_SCALE_REFERENCE, minStored, maxStored) / MENU_SCALE_REFERENCE, 1)
end
local function MenuScaleStoredFromPercent(value)
    return (DirectSnapPercent(value, MENU_SCALE_MIN_PERCENT, MENU_SCALE_MAX_PERCENT, MENU_SCALE_STEP_PERCENT) / 100)
        * MENU_SCALE_REFERENCE
end
local function DirectCombatLocked()
    return M.IsConfigCombatLocked() == true
end
local function DirectRunSlash(message)
    local slash = SlashCmdList and SlashCmdList["MIDNIGHTSUF"]
    if type(slash) ~= "function" then return false end
    slash(message or "")
    return true
end
local function LoadedSuiteFactoryReset()
    return MSUF.SuiteLink.CanStageFactoryReset()
end

local function RunSuiteFactoryReset()
    if DirectCombatLocked() or not LoadedSuiteFactoryReset() or type(ReloadUI) ~= "function" then return false end
    local ok = MSUF.SuiteLink.StageFactoryReset()
    if not ok then return false end
    ReloadUI()
    return true
end

local function ShowFactoryResetConfirm(kind)
    if M.BlockCombatAction and M.BlockCombatAction() then return false end
    if kind == "suite" and not LoadedSuiteFactoryReset() then return false end
    local suiteReset = kind == "suite"
    local key = suiteReset and "MSUF2_SUITE_FACTORY_RESET_CONFIRM" or "MSUF2_FACTORY_RESET_CONFIRM"
    M.ShowPrompt(key, {
        text = M.Tr(suiteReset
            and "Factory reset MSUF Suite?\n\nAll Suite profiles and skin settings on this account will be deleted. MSUF settings stay intact. The UI will reload."
            or "Factory reset MSUF?\n\nAll MSUF profiles and settings on this account will be deleted. Suite profiles are kept, but the active Suite profile may follow MSUF back to Default. The UI will reload."),
        accept = YES or M.Tr("Yes"),
        cancel = NO or M.Tr("No"),
        onAccept = function()
            if M.BlockCombatAction and M.BlockCombatAction() then return end
            if suiteReset then
                RunSuiteFactoryReset()
            elseif M.StageFactoryReset() then
                ReloadUI()
            end
        end,
    })
    return true
end

--- Read-only view of the optional MSUF Suite: nil when the Suite is absent,
--- predates GetOverview or answers with anything but a table. Callers treat nil
--- as "not installed" and never promote the Suite then.
function M.GetSuiteOverview()
    local overview = MSUF.SuiteLink.GetOverview()
    return type(overview) == "table" and overview or nil
end

--- The Suite names its own module page; offer it only once this menu has the
--- page registered, so a stale key never lands the player on the Dashboard.
function M.GetSuiteModulesPageKey(overview)
    local pageKey = type(overview) == "table" and overview.pageKey or nil
    if type(pageKey) ~= "string" or pageKey == "" then return nil end
    return type(M.pages) == "table" and M.pages[pageKey] ~= nil and pageKey or nil
end

--- "MSUF Suite v1.2" when the Suite reports a version, "MSUF Suite" otherwise.
function M.FormatSuiteTitle(overview)
    local version = type(overview) == "table" and overview.version or nil
    if type(version) ~= "string" or version == "" then return M.Tr("MSUF Suite") end
    return M.Format("MSUF Suite %s", version:match("^%d") and ("v" .. version) or version)
end

local function GetBundledChangelog()
    -- Changelog data is bundled as static state. The dashboard renders it read-only and should
    -- tolerate older builds where no changelog table exists.
    local data = MSUF.MSUF_Changelog or MSUF.Require("MSUF_Changelog", FILE)
    if type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then return nil end
    return data
end
local function ThemeColor(name, fallback)
    local color = T and T.colors and T.colors[name]
    return color or fallback
end
local function CreateDashboardAccordionTone(header, arrow)
    local headerActiveBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
    local headerActiveDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
    local headerBg = W.CreateAccordionRoundedRegions(header, "BACKGROUND", 0)
    local headerActiveFrom = { headerActiveBlue[1], headerActiveBlue[2], headerActiveBlue[3], 0.62 }
    local headerActiveTo = { headerActiveDeep[1], headerActiveDeep[2], headerActiveDeep[3], 0.56 }
    local headerOpenHighlight = W.CreateAccordionOpenHighlight(header, headerActiveFrom, headerActiveTo)
    local PaintHeaderBorder = W.CreateAccordionBorder(header)
    local function Refresh(open, hover)
        PaintHeaderBorder(open, hover)
        local headerSurface = ThemeColor("coreSurface", { 0.014, 0.038, 0.072, 1.00 })
        local headerRaised = ThemeColor("coreRaised", { 0.026, 0.070, 0.110, 1.00 })
        headerActiveBlue = ThemeColor("coreGlow", { 0.231, 0.510, 0.965, 1.00 })
        headerActiveDeep = ThemeColor("coreBlue", { 0.141, 0.365, 0.741, 1.00 })
        headerActiveFrom[1], headerActiveFrom[2], headerActiveFrom[3] = headerActiveBlue[1], headerActiveBlue[2], headerActiveBlue[3]
        headerActiveTo[1], headerActiveTo[2], headerActiveTo[3] = headerActiveDeep[1], headerActiveDeep[2], headerActiveDeep[3]
        if headerOpenHighlight.SetColors then headerOpenHighlight:SetColors(headerActiveFrom, headerActiveTo) end
        headerOpenHighlight:SetShown(open)
        headerBg:SetAlpha(open and 0 or 1)
        T.ApplyCollapseVisual(arrow, nil, open)
        if open then arrow:SetVertexColor(1, 1, 1, 0.98) end
        local color = hover and headerRaised or headerSurface
        headerBg:SetColorTexture(color[1], color[2], color[3], hover and 0.78 or 0.58)
    end
    return Refresh
end
--- Dashboard disclosures change card heights, so they toggle by rebuilding the
--- whole page. Keep the viewport so the clicked header stays under the cursor.
local function RebuildDashboardPage()
    M.RebuildPageKeepingScroll("home")
end
local function RawFont(parentFrame, template, text, color, bump, role)
    local fs = PixelLayoutRegion(parentFrame:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall"))
    if T.StyleFontString then
        T.StyleFontString(fs, color or T.colors.muted, bump or 0, role)
    elseif color and fs.SetTextColor then
        fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
    fs:SetText(tostring(text or ""))
    return fs
end
local function WordWrap(fs)
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
end
local function WrapLeft(fs, width)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    WordWrap(fs)
    if fs.SetSpacing then fs:SetSpacing(3) end
end
local function StringHeight(fs)
    return max((fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0)
end
--- Accordion header row (arrow, tone, title) shared by the changelog and the disclosures.
local function AccordionHead(parent, top, open, title)
    local head = PixelLayoutRegion(CreateFrame("Button", nil, parent))
    head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
    head:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
    head:SetHeight(44)
    local arrow = PixelLayoutRegion(head:CreateTexture(nil, "OVERLAY"))
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
    arrow:SetTexture(T.media.collapseArrow)
    local PaintHeaderTone = CreateDashboardAccordionTone(head, arrow)
    PaintHeaderTone(open, false)
    local label = T.Font(head, "GameFontNormal", title, T.colors.text)
    label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
    return head, arrow, PaintHeaderTone, label
end
-- Release notes are long-form prose, so they run on the shared type roles (body/card/
-- section) with real line spacing instead of the smallest Blizzard template. Roles keep
-- the sizes identical at every UI and menu scale. Returns the final vertical offset.
local function FillChangelog(child, scrollW, entries)
    local y = 0
    local bodyColor = { T.colors.text[1], T.colors.text[2], T.colors.text[3], 0.94 }
    local function AddText(text, fontObject, color, indent, gap, translate, role)
        local rawText = tostring(text or "")
        if translate then rawText = M.Tr(rawText) end
        local fs = RawFont(child, fontObject or "GameFontHighlightSmall", rawText, color or T.colors.muted, 0, role or "body")
        indent = indent or 0
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, y)
        WrapLeft(fs, max(40, scrollW - indent - 4))
        fs:SetText(rawText)
        -- GetStringHeight is the wrapped height; keep GetHeight in the mix so the added line
        -- spacing can never be measured away and let a long bullet collide with the next one.
        local h = StringHeight(fs)
        if h < 12 then h = 14 end
        y = y - h - (gap or 4)
        return fs
    end
    local function AddBullet(value, dotColor, textColor)
        local text, link
        if type(value) == "table" then
            text = tostring(value.text or "")
            link = type(value.link) == "table" and value.link or nil
        else
            text = tostring(value or "")
        end
        dotColor = dotColor or T.colors.accent
        textColor = textColor or bodyColor
        local dot = PixelLayoutRegion(child:CreateTexture(nil, "ARTWORK"))
        dot:SetSize(5, 5)
        dot:SetPoint("TOPLEFT", child, "TOPLEFT", 9, y - 6)
        dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.95)
        if not link then return AddText(text, "GameFontHighlightSmall", textColor, 22, 9, true, "body") end
        local button = PixelLayoutRegion(CreateFrame("Button", nil, child))
        button:SetPoint("TOPLEFT", child, "TOPLEFT", 22, y)
        local linkWidth = max(40, scrollW - 32)
        button:SetWidth(linkWidth)
        local fs = RawFont(button, "GameFontHighlightSmall", M.Tr(text), T.colors.accent2 or T.colors.warning, 0, "body")
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        WrapLeft(fs, linkWidth)
        local h = max(StringHeight(fs), 14)
        button:SetHeight(h)
        local PaintFeatureLink = T.StyleFeatureLink(button, fs) or nil
        button:SetScript("OnClick", function()
            if type(M.OpenChangelogMenuLink) == "function" then M.OpenChangelogMenuLink(link) end
        end)
        button:SetScript("OnEnter", function()
            if PaintFeatureLink then PaintFeatureLink(true) end
        end)
        button:SetScript("OnLeave", function()
            if PaintFeatureLink then PaintFeatureLink(false) end
        end)
        y = y - h - 9
        return button
    end
    for entryIndex = 1, min(#entries, 4) do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local date = tostring(entry.date or "")
            local heading = (date ~= "" and (version .. " - " .. date)) or version
            if entryIndex > 1 then
                y = y - 10
                local rule = PixelLayoutRegion(child:CreateTexture(nil, "ARTWORK"))
                rule:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
                rule:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, y)
                rule:SetHeight(1)
                rule:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.55)
                y = y - 13
            end
            AddText(heading, "GameFontNormal", T.colors.accent, 0, 10, false, "section")
            local sections = entry.sections
            if type(sections) == "table" then
                for sectionIndex = 1, #sections do
                    local section = sections[sectionIndex]
                    if type(section) == "table" and type(section.bullets) == "table" and #section.bullets > 0 then
                        if sectionIndex > 1 then y = y - 8 end
                        local sectionTitle = tostring(section.title or "")
                        local isHighlights = sectionTitle == "Highlights"
                        AddText(sectionTitle, "GameFontNormalSmall", isHighlights and T.colors.accent or T.colors.accent2, 0, 7, true, "card")
                        for bulletIndex = 1, #section.bullets do
                            AddBullet(section.bullets[bulletIndex], isHighlights and T.colors.accent2 or nil, isHighlights and T.colors.text or nil)
                        end
                    end
                end
            end
        end
    end
    return y
end
local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local top = opts.top or -130
    local headerH = 44
    local scrollW = max(80, max(120, cardWidth or 420) - 60)
    local header, arrow, PaintHeaderTone, title = AccordionHead(parent, top, false, opts.title or "Changelog")
    title:SetPoint("RIGHT", header, "RIGHT", -94, 0)
    title:SetJustifyH("LEFT")
    local hint = T.Font(header, "GameFontDisableSmall", "", T.colors.muted, "caption")
    hint:SetPoint("RIGHT", header, "RIGHT", -16, 0)
    hint:SetJustifyH("RIGHT")
    if not data then
        header:EnableMouse(false)
        hint:SetText("")
        RawFont(parent, "GameFontHighlightSmall", M.Tr("No release notes bundled with this build."), T.colors.muted, 0, "body")
            :SetPoint("TOPLEFT", parent, "TOPLEFT", 16, top - headerH - 8)
        if arrow.SetVertexColor then arrow:SetVertexColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], 0.55) end
        return
    end
    local scroll = PixelLayoutRegion(CreateFrame("ScrollFrame", nil, parent))
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, top - headerH - 12)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -36, opts.bottom or 72)
    local child = PixelLayoutRegion(CreateFrame("Frame", nil, scroll))
    child:SetSize(scrollW, 1)
    scroll:SetScrollChild(child)
    child:SetHeight(max(1, math.abs(FillChangelog(child, scrollW, data.entries)) + 8))
    T.StyleScrollFrame(scroll, parent)
    local open = M.dashboardChangelogOpen == true
    RegisterDashboardControl(header, DashboardMeta("changelog.disclosure", "ephemeral", {
        help = "Shows or hides the bundled MSUF release notes.",
    }), opts.title or "Changelog", "button")
    local function PaintHeader(isOpen)
        PaintHeaderTone(isOpen, false)
        hint:SetText(isOpen and "Hide" or "View")
    end
    local function RefreshOpenState()
        M.SetMenuStateValue("dashboardChangelogOpen", open)
        scroll:SetShown(open)
        PaintHeader(open)
        if open then
            if scroll._msuf2RefreshScrollBar then scroll:_msuf2RefreshScrollBar() end
        elseif scroll._msuf2ScrollBar then
            scroll._msuf2ScrollBar:Hide()
        end
    end
    header:SetScript("OnClick", function()
        M.SetMenuStateValue("dashboardChangelogOpen", not open)
        if type(opts.onToggle) == "function" then opts.onToggle(not open) end
    end)
    header:SetScript("OnEnter", function()
        PaintHeaderTone(open, true)
    end)
    header:SetScript("OnLeave", function()
        PaintHeader(open)
    end)
    RefreshOpenState()
end
local function StartGuidedSetupFromDashboard(restart)
    if type(M.StartGuidedTour) ~= "function" then return false end
    return M.StartGuidedTour({ source = "dashboard", restart = restart == true, mode = "quick" })
end
-- Setup stays available after onboarding, but a stray click on the completed
-- card should not drop the user back into the walkthrough. Only the restart
-- path asks; resuming an active tour and the very first run stay one click.
local function ConfirmGuidedSetupRestart()
    M.ShowPrompt("MSUF2_GUIDED_SETUP_RESTART_CONFIRM", {
        text = M.Tr("Run the guided setup again? The walkthrough starts over at the first step."),
        onAccept = function() StartGuidedSetupFromDashboard(true) end,
    })
    return true
end
-- The home page is assembled by Dashboard.Build from one stage per card. Stages
-- share one per-build `state` table (helpers, geometry, disclosure flags) and run
-- in the order the cards used to be built inline.
local Dashboard = {}
local function Card(parent, title, x, y, w, h, bg, border)
    bg = bg or T.colors.panel2
    border = border or T.colors.cardBorder or T.colors.borderSoft
    local card = T.Panel(parent, nil, bg, border)
    if T.ApplyMaterial then
        T.ApplyMaterial(card, { bg = bg, border = border, glass = "card", gradient = "card" })
    elseif T.ApplySurface then
        T.ApplySurface(card, "card")
    end
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    card:SetSize(w, h)
    if title and title ~= "" then
        local label = T.Font(card, "GameFontNormal", title, T.colors.text)
        label:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -16)
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
        if texture.SetVertexColor then texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
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
local function HeroLayer(card, sublevel, corner, orientation, from, fromA, to, toA)
    local layer = PixelLayoutRegion(card:CreateTexture(nil, "BACKGROUND", nil, sublevel))
    layer:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
    if corner == "TOPRIGHT" then
        layer:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
    else
        layer:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
    end
    SetDashboardGradient(layer, orientation, { from[1], from[2], from[3], fromA }, { to[1], to[2], to[3], toA })
    return layer
end
local function ApplyDashboardHeroGradient(card, h)
    if not (card and card.CreateTexture) or card._msuf2DashboardHeroGradient then return end
    card._msuf2DashboardHeroGradient = true
    local c = T.colors
    HeroLayer(card, 1, "BOTTOMRIGHT", "HORIZONTAL", c.coreShadow, 0, c.coreRaised, 0.12)
    HeroLayer(card, 2, "TOPRIGHT", "VERTICAL", c.coreBlue, 0.055, c.coreShadow, 0)
        :SetHeight(max(54, min(96, floor((h or 190) * 0.42))))
    HeroLayer(card, 3, "BOTTOMRIGHT", "HORIZONTAL", c.coreBlue, 0, c.coreBlue, 0.035)
end
local function AddTooltip(frame, title, text)
    return M.AddTooltip and M.AddTooltip(frame, title, text, {
        hook = true,
        titleAsLine = true,
        bodyColor = { 0.85, 0.85, 0.85 },
    }) or frame
end
local SKIN_BUTTON = { primary = "SkinPrimaryButton", success = "SkinSuccessButton", danger = "SkinDangerButton" }
local function Button(parent, text, x, y, w, h, onClick, skin, semanticPath, classification, exact, tip)
    local btn = T.Button(parent, text or "", w, h or 24)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    T.CenterButtonLabel(btn)
    local skinner = SKIN_BUTTON[skin] and T[SKIN_BUTTON[skin]]
    if skinner then skinner(btn) end
    if onClick then btn:SetScript("OnClick", onClick) end
    RegisterDashboardControl(btn, DashboardMeta(semanticPath, classification or "action", exact), text, "button")
    if tip then AddTooltip(btn, text, tip) end
    return btn
end
local function Kicker(parent, text, x, y, color)
    local fs = T.Font(parent, "GameFontDisableSmall", "", color or T.colors.accent)
    T.SetTranslatedText(fs, string.upper(M.Tr(text or "")))
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -16)
    return fs
end
local function Pill(parent, text, x, y, w, color)
    local pill = T.Panel(parent, nil, T.colors.pillBaseSolid, T.colors.pillEdge)
    pill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    pill:SetSize(w or 82, 20)
    local label = T.Font(pill, "GameFontDisableSmall", text or "", color or T.colors.muted)
    label:SetPoint("CENTER", pill, "CENTER", 0, 0)
    label:SetJustifyH("CENTER")
    pill._msuf2Label = label
    return pill
end
--- Wrapped text label at an absolute offset of its parent (width and justify optional).
local function Label(parent, template, text, color, x, y, width, justify)
    local fs = T.Font(parent, template, text, color)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if width then fs:SetWidth(width) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end
local ICON_DIR = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
local function CopyLink(title, url)
    MSUF.Require("MSUF_ShowCopyLink", FILE)(title, url)
end
local function RefreshDashboardEditModeButtonSafe() M.RefreshDashboardEditModeButton() end
local function RefreshMenuFramePrioritySafe() M.RefreshMenuFramePriority() end
local function RefreshDashboardFrameStatus()
    local f = M.frame
    if f and f.RefreshStatus then
        f:RefreshStatus()
    end
end
local function ToggleEditMode()
    local active = M.IsMSUFEditModeActive(true)
    if (not active) and M.IsEditModeCombatLocked(true) then
        M.BlockCombatAction()
        RefreshDashboardEditModeButtonSafe()
        RefreshDashboardFrameStatus()
        return
    end
    MSUF.Require("MSUF_SetMSUFEditModeDirect", FILE)(not active)
    RefreshMenuFramePrioritySafe()
    C_Timer.After(0, RefreshMenuFramePrioritySafe)
    RefreshDashboardEditModeButtonSafe()
    RefreshDashboardFrameStatus()
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
    if slider and slider._msuf2Title then T.StyleFontString(slider._msuf2Title, T.colors.text, 3) end
end
local function EnablePercentWheel(slider, minPct, maxPct, stepPct)
    if not slider then return end
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not delta then return end
        local value = tonumber((self.GetValue and self:GetValue()) or 100) or 100
        value = value + ((delta > 0) and stepPct or -stepPct)
        self:SetValue(DirectSnapPercent(value, minPct, maxPct, stepPct))
    end)
end
local function PixelScale()
    local v = MSUF.Require("MSUF_GetPixelPerfectScale", FILE)()
    if tonumber(v) then return DirectClamp(v, 0.3, 1.5) end
    if type(GetPhysicalScreenSize) == "function" then
        local _, h = GetPhysicalScreenSize()
        h = tonumber(h)
        if h and h > 0 then return DirectClamp(768 / h, 0.3, 1.5) end
    end
    return 1
end
local function GlobalState()
    local g = M.GetGeneralDB()
    g.UIScale = (type(g.UIScale) == "table") and g.UIScale or { Enabled = false, Scale = 1 }
    local ui = g.UIScale
    ui.Enabled = ui.Enabled == true
    ui.Scale = DirectClamp(ui.Scale, 0.3, 1.5)
    return g, ui
end
--- Kicker, title and action label of the setup launcher for the tour status.
local function LauncherTexts(active, completed)
    if active then return "GUIDED SETUP IN PROGRESS", "Continue your MSUF setup", "Resume setup" end
    if completed then return "GUIDED SETUP COMPLETE", "Review or run setup again", "Run setup again" end
    return "GUIDED SETUP", "Get the essentials right in a few minutes", "Start Quick Setup"
end
function Dashboard.BuildGuidedSetupLauncher(state, mainTop, ctx)
    local root, x0, mainW = state.root, state.x0, state.mainW
    -- Setup remains available after onboarding. Quick Setup is the default;
    -- the first route screen still offers the complete learning tour.
    -- launcher deliberately compact; the persistent progress bar itself lives
    -- in the window chrome while the tour is active.
    local tour = MSUF.GuidedTour6
    local tourState = type(tour) == "table" and type(tour.GetState) == "function" and tour:GetState() or nil
    local tourActive = type(tourState) == "table" and tourState.status == "active"
    local tourCompleted = type(tourState) == "table" and tourState.status == "completed"
    local firstLoad = MSUF.FirstLoad6
    local highlightGuidedSetup = type(firstLoad) == "table"
        and type(firstLoad.ShouldHighlightGuidedSetup) == "function"
        and firstLoad:ShouldHighlightGuidedSetup()
    local launcherNarrow = mainW < 520
    -- The Wago button rides along with the setup action: narrow stacks it below,
    -- wide seats it left of the action, so both reserve room in the same card.
    local launcherH = launcherNarrow and 162 or 78
    local launcher = Card(root, "", x0, mainTop, mainW, launcherH, T.colors.panel2, T.colors.borderSoft)
    local kickerText, launcherTitle, actionText = LauncherTexts(tourActive, tourCompleted)
    local kicker = Kicker(launcher, kickerText, 16, -14)
    local title = Label(launcher, "GameFontNormal", launcherTitle, T.colors.text, 16, -36,
        max(120, mainW - (launcherNarrow and 32 or 388)), "LEFT")
    local step = Label(launcher, "GameFontDisableSmall", "", T.colors.muted, 16, launcherNarrow and -72 or -56)
    local actionX = launcherNarrow and 16 or (mainW - 196)
    local actionY = launcherNarrow and -92 or -27
    local actionW = launcherNarrow and min(196, mainW - 32) or 180
    local action = Button(launcher, actionText, actionX, actionY, actionW, 30, function()
        if M.BlockCombatAction and M.BlockCombatAction() then return end
        if tourActive and type(M.ResumeGuidedTour) == "function" then
            M.ResumeGuidedTour()
        elseif tourCompleted then
            ConfirmGuidedSetupRestart()
        else
            StartGuidedSetupFromDashboard(false)
        end
    end, highlightGuidedSetup and "success" or "primary", "guided_setup.start_or_resume", "action", { actionKey = "guided_setup" })
    T.AttachNavIcon(action, "home", false, true)
    local wago = Button(launcher, "Wago Profiles",
        launcherNarrow and actionX or (mainW - 354),
        launcherNarrow and -126 or -27,
        launcherNarrow and actionW or 150, 30,
        function() CopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf") end,
        nil, "guided_setup.browse_wago_profiles", "action",
        { actionKey = "copy_wago_profiles_link",
          keywords = { "Browse Wago profiles", "Wago profile imports" },
          help = "Opens a copyable link to the MSUF profile imports on Wago." }, "Browse Wago profiles")
    local wagoIcon = PixelLayoutRegion(wago:CreateTexture(nil, "ARTWORK", nil, 3))
    wagoIcon:SetTexture(ICON_DIR .. "Wago.png")
    wagoIcon:SetSize(22, 22)
    wagoIcon:SetPoint("LEFT", wago, "LEFT", 8, 0)
    if wago._msuf2Label then
        wago._msuf2Label:ClearAllPoints()
        wago._msuf2Label:SetPoint("LEFT", wagoIcon, "RIGHT", 6, 0)
        wago._msuf2Label:SetPoint("RIGHT", wago, "RIGHT", -10, 0)
        wago._msuf2Label:SetJustifyH("CENTER")
    end
    local function RefreshLauncher()
        local currentState = tour and tour:GetState()
        tourActive = currentState and currentState.status == "active"
        tourCompleted = currentState and currentState.status == "completed"
        local kickerNow, titleNow, actionNow = LauncherTexts(tourActive, tourCompleted)
        T.SetTranslatedText(kicker, string.upper(M.Tr(kickerNow)))
        T.SetTranslatedText(title, M.Tr(titleNow))
        action:SetText(M.Tr(actionNow), true)
        local highlighted = firstLoad and firstLoad.ShouldHighlightGuidedSetup and firstLoad:ShouldHighlightGuidedSetup()
        T.ApplyButtonRole(action, highlighted and "success" or "primary")
        step:SetShown(tourActive == true)
        if tourActive then
            local current, total = M.GetGuidedTourStageProgress()
            total = max(1, tonumber(total) or 1)
            current = min(total, max(1, tonumber(current) or 1))
            T.SetTranslatedText(step, M.Format("Step %d of %d", current, total))
        end
    end
    ctx:AddRefresher(RefreshLauncher)
    ctx.entry.guidedSetupLauncher = action
    RefreshLauncher()
    return launcherH
end
--- The Dashboard's own search field: typed into directly, the way the Assistant
--- card took a question. Matches show under it while typing (the navigation
--- search palette and index), Enter opens the selected one and falls back to
--- the full results page, which the navigation search then shows the query for.
--- Returns the field and its submit function.
function Dashboard.BuildSearchInput(hero, x, y, w, h)
    local bridge = M.SearchBridge
    local input = PixelLayoutRegion(CreateFrame("EditBox", nil, hero, "InputBoxScriptTemplate"))
    input:SetFontObject("ChatFontNormal")
    input:SetPoint("TOPLEFT", hero, "TOPLEFT", x, y)
    input:SetSize(w, h)
    input:EnableMouse(true)
    input:SetAutoFocus(false)
    input:SetMaxLetters(60)
    input:SetTextInsets(10, 10, 0, 0)
    T.SkinEditBox(input)
    T.StyleFontString(input, T.colors.text, 2)
    input._msuf2RoundedEditFill, input._msuf2RoundedEditEdge =
        T.CreateSuperellipseLayers(input, "_msuf2DashboardSearchEdit", 2, "BACKGROUND", "BORDER")
    input:_msuf2PaintEditBox(false)
    local hint = PixelLayoutRegion(input:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    hint:SetPoint("LEFT", input, "LEFT", 11, 0)
    hint:SetPoint("RIGHT", input, "RIGHT", -10, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    T.StyleFontString(hint, T.colors.searchPlaceholder or T.colors.muted, 2)
    input._msuf2SearchPlaceholder = hint
    bridge.UpdateSearchPlaceholder(input)
    local palette = M.CreateNavSearchPalette(hero, input, true)
    local function ShowMatches()
        local query = M.TrimText(input:GetText() or "")
        bridge.ScheduleSearchInputQuery(input, query, false, function(latest) palette:Refresh(latest, false) end)
        palette:Refresh(query, M.searchResultsPending == true)
    end
    local function Submit()
        local query = M.TrimText(input:GetText() or "")
        if query == "" then
            input:SetFocus()
            return
        end
        bridge.BumpSearchInputSerial()
        bridge.RunSearchInputQuery(query, false)
        palette:Refresh(query, false)
        if palette:OpenSelected(query) then return end
        palette:Hide()
        input:ClearFocus()
        bridge.RunSearchQuery(query)
    end
    input:SetScript("OnTextChanged", function(self, userInput)
        bridge.UpdateSearchPlaceholder(self)
        if userInput then ShowMatches() end
    end)
    input:HookScript("OnEditFocusGained", function(self)
        bridge.UpdateSearchPlaceholder(self)
        if M.TrimText(self:GetText() or "") ~= "" then ShowMatches() end
    end)
    input:HookScript("OnEditFocusLost", bridge.UpdateSearchPlaceholder)
    input:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" or key == "DOWN" then palette:MoveSelection(key == "UP" and -1 or 1) end
    end)
    input:SetScript("OnEnterPressed", Submit)
    input:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        palette:Hide()
        self:ClearFocus()
    end)
    -- The start page opens empty again, like the Assistant input after a send.
    hero:HookScript("OnHide", function()
        if palette:IsShown() then palette:Hide() end
        input:SetText("")
    end)
    return input, Submit
end
--- The search card greets by the player's local time of day: morning from 5,
--- midday from 12, afternoon from 14, evening from 18 and night from 22 until 5.
--- Each greeting is one translated sentence with the character name in it.
local SEARCH_GREETINGS = {
    { from = 22, key = "Up late, %s?" },
    { from = 18, key = "Good evening, %s" },
    { from = 14, key = "Good afternoon, %s" },
    { from = 12, key = "Good day, %s" },
    { from = 5, key = "Good morning, %s" },
}

function Dashboard.SearchGreetingKey(hour)
    hour = tonumber(hour)
    if not hour then return nil end
    hour = floor(hour) % 24
    for index = 1, #SEARCH_GREETINGS do
        local greeting = SEARCH_GREETINGS[index]
        if hour >= greeting.from then return greeting.key end
    end
    return SEARCH_GREETINGS[1].key
end

local function LocalHour()
    return type(date) == "function" and tonumber(date("%H")) or nil
end

function Dashboard.SearchGreeting(hour)
    local key = Dashboard.SearchGreetingKey(hour or LocalHour())
    local playerName = M.PlayerDisplayName
    local name = type(playerName) == "function" and playerName() or nil
    if not key or type(name) ~= "string" or name == "" then return M.Tr("Find settings and help") end
    return M.Format(key, name)
end

function Dashboard.BuildSearchHero(state, mainTop, ctx)
    local mainW = state.mainW
    local heroH = mainW < 390 and 174 or 156
    local hero = Card(state.root, "", state.x0, mainTop, mainW, heroH, T.colors.glassHost, T.colors.cardBorder)
    ApplyDashboardHeroGradient(hero, heroH)
    Kicker(hero, "MSUF", 22, -20)
    local title = Label(hero, "GameFontNormalLarge", "", T.colors.text, 22, -42, mainW - 44, "LEFT")
    hero._msuf2SearchGreeting = title
    local function RefreshGreeting() T.SetTranslatedText(title, Dashboard.SearchGreeting()) end
    RefreshGreeting()
    if ctx and ctx.AddRefresher then ctx:AddRefresher(RefreshGreeting) end
    W.Text(hero, "Search enabled features in your own words.", 22, -72, mainW - 44, T.colors.muted)
    local submitW = 96
    local inputY = -heroH + 52
    local _, submit = Dashboard.BuildSearchInput(hero, 22, inputY, max(120, mainW - 54 - submitW), 30)
    Button(hero, "Search", mainW - 22 - submitW, inputY, submitW, 30, function()
        if DirectCombatLocked() then return end
        submit()
    end, "primary", "search.open", "navigation", { navigationKey = "search" })
    return heroH
end
--- Compact MSUF Suite card between the search hero and the collapsed cards.
--- It is built only while the Suite reports an overview, so nothing is promoted
--- when the Suite is not installed. Returns its height, 0 when there is no card.
function Dashboard.BuildSuiteCard(state, ctx, top)
    local overview = M.GetSuiteOverview()
    if not overview then return 0 end
    local root, x0, mainW = state.root, state.x0, state.mainW
    local pageKey = M.GetSuiteModulesPageKey(overview)
    local needsSetup = overview.needsSetup == true
    local openW, setupW, gap = 170, 130, 10
    local both = pageKey ~= nil and needsSetup
    local rowW = (pageKey and openW or 0) + (needsSetup and setupW or 0) + (both and gap or 0)
    local textW = mainW - 32 - (rowW > 0 and (rowW + 16) or 0)
    -- Wide cards seat the buttons right of the text; narrow ones move them
    -- below it, one per line when the pair does not fit side by side.
    local stacked = rowW > 0 and textW < 240
    local column = stacked and both and rowW > mainW - 32
    if stacked then textW = mainW - 32 end
    textW = max(120, textW)
    local card = Card(root, "", x0, top, mainW, 100, T.colors.panel2, T.colors.borderSoft)
    Kicker(card, "MSUF SUITE", 16, -14)
    local title = Label(card, "GameFontNormal", "", T.colors.text, 16, -34, textW, "LEFT")
    local status = Label(card, "GameFontHighlightSmall", "", T.colors.ok or T.colors.accent, 16, -56, textW, "LEFT")
    local about = W.Text(card, "Optional modules beyond unit frames: action bars, bags, chat, minimap and more.", 16, -74, textW, T.colors.muted)
    if about.SetWordWrap then about:SetWordWrap(true) end
    local aboutH = max(12, (about.GetStringHeight and about:GetStringHeight()) or 0)
    local textBottom = 74 + aboutH
    local buttonY = stacked and -(textBottom + 12) or -34
    local cardH = max(100, stacked and (textBottom + 12 + (column and 62 or 28) + 14) or (textBottom + 16))
    card:SetHeight(cardH)
    local openX = (not stacked) and (mainW - 16 - openW) or ((both and not column) and (16 + setupW + gap) or 16)
    local openY = column and (buttonY - 34) or buttonY
    local setup
    if needsSetup then
        setup = Button(card, "Set up Suite", stacked and 16 or (mainW - 16 - rowW), buttonY, setupW, 28, function()
            if M.BlockCombatAction and M.BlockCombatAction() then return end
            -- The setup window shares the menu's strata below its content, so
            -- the menu steps aside once the Suite confirms the window opened.
            if MSUF.SuiteLink.OpenInstaller() == true then
                M.HideSlashMenuAndMinibar(M.frame)
            elseif M.ShowStatusFeedback then
                M.ShowStatusFeedback(M.Tr("Suite setup unavailable"), "danger", 1.4, true)
            end
        end, "primary", "suite.setup", "ephemeral",
            { help = "Opens the MSUF Suite setup: profile, modules and UI scaling." },
            "Opens the MSUF Suite setup: profile, modules and UI scaling.")
    end
    if pageKey then
        Button(card, "Open Suite Modules", openX, openY, openW, 28, function()
            if M.BlockCombatAction and M.BlockCombatAction() then return end
            M.SelectPage(pageKey)
        end, (not needsSetup) and "primary" or nil, "suite.open_modules", "navigation",
            { navigationKey = pageKey, help = "Shows the Suite page that switches each optional module on or off." },
            "Shows the Suite page that switches each optional module on or off.")
    end
    local function Refresh()
        local live = M.GetSuiteOverview() or overview
        title:SetText(M.FormatSuiteTitle(live))
        local total, enabled = tonumber(live.total), tonumber(live.enabled)
        status:SetText((total and enabled) and M.Format("%d of %d modules on", floor(enabled), floor(total)) or "")
        if setup then setup:SetShown(live.needsSetup == true) end
    end
    Refresh()
    M.TrackRefresh(ctx, Refresh)
    return cardH
end
local function DashboardDisclosure(parent, title, open, stateKey, width, fillPills, semanticPath)
    local head, _, PaintHeaderTone = AccordionHead(parent, 0, open, title)
    if type(fillPills) == "function" then fillPills(head, width) end
    head:SetScript("OnClick", function()
        M.SetMenuStateValue(stateKey, not open)
        RebuildDashboardPage()
    end)
    head:SetScript("OnEnter", function()
        PaintHeaderTone(open, true)
    end)
    head:SetScript("OnLeave", function()
        PaintHeaderTone(open, false)
    end)
    RegisterDashboardControl(head, DashboardMeta(semanticPath, "ephemeral", {
        help = M.Format("Shows or hides the %s dashboard section.", tostring(title)),
    }), title, "button")
    return head
end
function Dashboard.ResolveCardStack(state, featureBlockBottom)
    local layoutW = state.layoutW
    local recoveryW = layoutW
    local recoveryOpen = M.dashboardRecoveryOpen == true
    local hasSuiteReset = LoadedSuiteFactoryReset()
    -- The reset buttons move together to a second row when the first row
    -- cannot hold both without colliding with Print Help.
    local recoveryWrap = recoveryW < (hasSuiteReset and 590 or 420)
    local recoveryStacked = hasSuiteReset and recoveryW < 352
    local recoveryH = recoveryOpen and (recoveryStacked and 186 or (recoveryWrap and 154 or 122)) or 42
    local changelogOpen = M.dashboardChangelogOpen == true
    local changelogH = changelogOpen and 420 or 42
    local scalingOpen = M.dashboardScalingOpen == true
    local scalingColumns = (recoveryW >= 960) and 3 or ((recoveryW >= 680) and 2 or 1)
    local scalingH = scalingOpen and ((scalingColumns == 3) and 250 or ((scalingColumns == 2) and 382 or 548)) or 42
    --- Card order top to bottom: Changelog, Scaling, Display & recovery, Support. The
    --- cards are still built in their old order below, so the whole top chain has to be
    --- resolved here where every height is known.
    local changelogTop = featureBlockBottom - 16
    local scalingTop = changelogTop - changelogH - 10
    local recoveryTop = scalingTop - scalingH - 10
    local supportTop = recoveryTop - recoveryH - 10
    state.recoveryW, state.recoveryOpen, state.recoveryWrap, state.recoveryH, state.hasSuiteReset, state.recoveryStacked =
        recoveryW, recoveryOpen, recoveryWrap, recoveryH, hasSuiteReset, recoveryStacked
    state.changelogOpen, state.changelogH, state.scalingOpen, state.scalingColumns, state.scalingH =
        changelogOpen, changelogH, scalingOpen, scalingColumns, scalingH
    state.changelogTop, state.scalingTop, state.recoveryTop, state.supportTop = changelogTop, scalingTop, recoveryTop, supportTop
end
local function FeedbackUnless(ok, text)
    if not ok and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr(text), "danger", 1.4, true) end
end
function Dashboard.BuildRecoveryCard(state)
    local recoveryTop, recoveryW, recoveryH, recoveryOpen = state.recoveryTop, state.recoveryW, state.recoveryH, state.recoveryOpen
    local recoveryWrap = state.recoveryWrap
    local recovery = Card(state.root, "", state.x0, recoveryTop, recoveryW, recoveryH, T.colors.panel2, T.colors.borderSoft)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    DashboardDisclosure(recovery, "Display & recovery", recoveryOpen, "dashboardRecoveryOpen", recoveryW, function(head)
        if recoveryW >= 520 then Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2) end
    end, "display_recovery.disclosure")
    if recoveryOpen then
        W.Text(recovery, state.hasSuiteReset and "Fix positions, print help, or reset MSUF or Suite."
            or "Fix positions, print help, or reset MSUF.", 16, -60, recoveryW - 32, T.colors.muted)
        Button(recovery, "Reset Positions", 16, -94, 118, 22, function()
            FeedbackUnless(DirectRunSlash("reset"), "Reset unavailable")
        end, "primary", "display_recovery.reset_positions", nil, nil, "Runs /msuf reset for frame positions and visibility.")
        local factoryY = recoveryWrap and -126 or -94
        --- "all" includes the diagnostic commands: someone who opened this card
        --- is usually troubleshooting and wants the complete list, not a subset.
        Button(recovery, "Print Help", 146, -94, 86, 22, function()
            FeedbackUnless(DirectRunSlash("help all"), "Help unavailable")
        end, nil, "display_recovery.print_help", nil, nil, "Lists every MSUF slash command in chat, diagnostics included.")
        local msufX = recoveryWrap and 16 or (recoveryW - (state.hasSuiteReset and 336 or 168))
        Button(recovery, "MSUF Factory Reset", msufX, factoryY, 156, 22, function()
            FeedbackUnless(ShowFactoryResetConfirm("msuf"), "Reset unavailable")
        end, "danger", "display_recovery.factory_reset_all", "action", { confirmRequired = true },
            "Deletes all MSUF profiles and settings after confirmation. Suite profiles are kept.")
        if state.hasSuiteReset then
            local suiteX = state.recoveryStacked and 16 or (recoveryWrap and 180 or (recoveryW - 168))
            local suiteY = state.recoveryStacked and -158 or factoryY
            Button(recovery, "Suite Factory Reset", suiteX, suiteY, 156, 22, function()
                FeedbackUnless(ShowFactoryResetConfirm("suite"), "Reset unavailable")
            end, "danger", "display_recovery.suite_factory_reset", "action", { confirmRequired = true },
                "Deletes all Suite profiles and skin settings after confirmation. MSUF data stays intact.")
        elseif recoveryWrap then
            W.Text(recovery, "Factory reset affects every MSUF setting.", 160, -128, recoveryW - 176, T.colors.muted)
        end
    end
    state.g = g
end
function Dashboard.BuildScalingCard(state, ctx)
    local g = state.g
    local recoveryW, scalingOpen = state.recoveryW, state.scalingOpen
    local scaling = Card(state.root, "", state.x0, state.scalingTop, recoveryW, state.scalingH, T.colors.panel2, T.colors.borderSoft)
    DashboardDisclosure(scaling, "Scaling", scalingOpen, "dashboardScalingOpen", recoveryW, function(scaleHead)
        if recoveryW < 520 then return end
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", DirectPercent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", MenuScalePercentFromStored(g.slashMenuScale)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", DirectPercent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
    end, "scaling.disclosure")
    if scalingOpen then Dashboard.BuildScalingColumns(state, ctx, scaling) end
end
--- One scale column: help line, status line, percent slider and an Apply / Revert pair.
--- `spec` names the paths and bounds, the shared `pending` table with the column's `key`
--- (and `enableKey` for the global on/off choice), and either selected() -> selected on,
--- selected scale, applied on, applied scale (the global column) or applied() and
--- current() -> scale (the percent columns); apply(); revert(). `presets` ({ text, dx,
--- width, key, run }) and `extra(buttonsTop, Refresh)` add the global column's own buttons.
--- The refresh and the drag hook read and write those directly: a slider drag step makes
--- no call through a spec wrapper.
local function BuildScaleColumn(scaling, colW, spec)
    local x, top, minPct, maxPct, stepPct = spec.x, spec.top, spec.minPct, spec.maxPct, spec.stepPct
    W.Text(scaling, spec.help, x, top - 20, colW, T.colors.muted)
    local status = W.Text(scaling, "", x, top - 40, colW, T.colors.muted)
    local slider = W.Slider(scaling, spec.label, minPct, maxPct, stepPct, colW)
    HideSliderValueBox(slider)
    slider:ClearAllPoints()
    slider:SetPoint("TOPLEFT", scaling, "TOPLEFT", x, top - 64)
    if slider._msuf2SetLayoutWidth then slider:_msuf2SetLayoutWidth(colW) end
    if slider._msuf2Title then
        slider._msuf2Title:ClearAllPoints()
        slider._msuf2Title:SetPoint("TOPLEFT", scaling, "TOPLEFT", x, top)
        slider._msuf2Title:SetWidth(colW)
    end
    EnablePercentWheel(slider, minPct, maxPct, stepPct)
    RegisterDashboardControl(slider, DashboardMeta(spec.semanticPath .. ".percent", spec.settingKey and "setting" or "ephemeral", {
        help = "Selects a pending scale percentage; use Apply to commit it.",
        settingKey = spec.settingKey,
    }), spec.label, "slider")
    local apply, revert
    local selected, appliedScale, currentScale = spec.selected, spec.applied, spec.current
    local pending, pendingKey, enableKey = spec.pending, spec.key, spec.enableKey
    local function Refresh()
        local text, percent, changed
        if selected then
            local selectedEnabled, selectedScale, appliedEnabled, appliedValue = selected()
            local appliedText = appliedEnabled and (DirectPercent(appliedValue, 1) .. "%") or M.Tr("Off")
            local selectedText = selectedEnabled and (DirectPercent(selectedScale, 1) .. "%") or M.Tr("Off")
            text, percent = M.Format("Applied: %s   Selected: %s", appliedText, selectedText), selectedScale * 100
            changed = (selectedEnabled ~= appliedEnabled) or math.abs(selectedScale - appliedValue) > 0.001
        else
            local applied, current = appliedScale(), currentScale()
            text = M.Format("Applied: %d%%  Selected: %d%%", DirectPercent(applied, 1), DirectPercent(current, 1))
            percent, changed = current * 100, math.abs(applied - current) > 0.001
        end
        T.SetTranslatedText(status, text)
        SetSliderValueSafe(slider, DirectSnapPercent(percent, minPct, maxPct, stepPct))
        if apply then
            if changed then apply:Enable() else apply:Disable() end
            if apply.SetActive then apply:SetActive(changed) end
        end
        if revert then
            if changed then revert:Enable() else revert:Disable() end
        end
    end
    slider:HookScript("OnValueChanged", function(self, value)
        if self._msuf2Refreshing then return end
        local pct = DirectSnapPercent(value, minPct, maxPct, stepPct)
        if pct ~= value then SetSliderValueSafe(self, pct) end
        if enableKey then pending[enableKey] = true end
        pending[pendingKey] = DirectClamp(pct / 100, minPct / 100, maxPct / 100)
        Refresh()
    end)
    local presets = spec.presets or {}
    for i = 1, #presets do
        local preset = presets[i]
        Button(scaling, preset[1], x + preset[2], top - 100, preset[3], 20, function()
            preset[5]()
            Refresh()
        end, nil, spec.semanticPath .. ".preset." .. preset[4])
    end
    local buttonsTop = top - (#presets > 0 and 126 or 100)
    apply = Button(scaling, "Apply", x, buttonsTop, 72, 20, function()
        spec.apply()
        Refresh()
    end, "primary", spec.semanticPath .. ".apply")
    revert = Button(scaling, "Revert", x + 82, buttonsTop, 72, 20, function()
        spec.revert()
        Refresh()
    end, nil, spec.semanticPath .. ".revert_pending", "ephemeral")
    if spec.extra then spec.extra(buttonsTop, Refresh) end
    return Refresh
end
function Dashboard.BuildScalingColumns(state, ctx, scaling)
    local recoveryW, scalingColumns = state.recoveryW, state.scalingColumns
    W.Text(scaling, "Use sliders for exact scale changes. Apply commits the selected value; Revert returns to the active value.", 16, -60, recoveryW - 32, T.colors.muted)
    -- The selections not applied yet: globalEnabled, global, msuf and menu.
    local pending = {}
    local colGap = 24
    local colW = (scalingColumns == 3) and floor((recoveryW - 32 - (colGap * 2)) / 3)
        or ((scalingColumns == 2) and floor((recoveryW - 32 - colGap) / 2) or (recoveryW - 32))
    local msufX = scalingColumns >= 2 and (16 + colW + colGap) or 16
    local msufTop = scalingColumns >= 2 and -94 or -242
    local menuX = (scalingColumns == 3) and (16 + ((colW + colGap) * 2)) or 16
    local menuTop = (scalingColumns == 3) and -94 or ((scalingColumns == 2) and -242 or -390)
    local function SelectedGlobalScale()
        local _, ui = GlobalState()
        local enabled, appliedScale = ui.Enabled, DirectClamp(ui.Scale, 0.3, 1.5)
        local selectedEnabled = pending.globalEnabled
        if selectedEnabled == nil then selectedEnabled = enabled end
        return selectedEnabled, DirectClamp(pending.global or appliedScale, 0.3, 1.5), enabled, appliedScale
    end
    local function AppliedMsufScale()
        return DirectClamp(tonumber(M.GetGeneralDB().msufUiScale) or 1, 0.25, 2.0)
    end
    local function PendingMsufScale()
        return DirectClamp(pending.msuf or AppliedMsufScale(), 0.25, 2.0)
    end
    local function AppliedMenuScale()
        return MenuScalePercentFromStored(M.GetGeneralDB().slashMenuScale) / 100
    end
    local function PendingMenuScale()
        return DirectClamp(pending.menu or AppliedMenuScale(), MENU_SCALE_MIN_PERCENT / 100, MENU_SCALE_MAX_PERCENT / 100)
    end
    local function ApplyGlobalScale(enabled, value, preset)
        local dbScale, ui = GlobalState()
        ui.Enabled = enabled == true
        ui.Scale = DirectClamp(value or ui.Scale, 0.3, 1.5)
        dbScale.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
        dbScale.globalUiScaleValue = ui.Enabled and ui.Scale or nil
        pending.globalEnabled, pending.global = nil, nil
        if ui.Enabled then
            local setScale = MSUF.Optional("MSUF_SetGlobalUiScale")
            if type(setScale) == "function" then setScale(ui.Scale, true) end
        else
            MSUF.Require("MSUF_ResetGlobalUiScale", FILE)(true)
        end
        if M.RequestGeneralDomains then M.RequestGeneralDomains("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false }) end
    end
    local RefreshGlobalScale = BuildScaleColumn(scaling, colW, {
        x = 16, top = -94, label = "Global UI Scale", settingKey = "general.globalUiScale",
        help = "Changes the global WoW UI scale through MSUF presets.",
        semanticPath = "scaling.global_ui", minPct = 30, maxPct = 150, stepPct = 1,
        pending = pending, key = "global", enableKey = "globalEnabled", selected = SelectedGlobalScale,
        apply = function()
            local selectedEnabled, selectedScale = SelectedGlobalScale()
            ApplyGlobalScale(selectedEnabled, selectedScale, selectedEnabled and "custom" or "auto")
        end,
        revert = function() pending.globalEnabled, pending.global = nil, nil end,
        presets = {
            { "1080p", 0, 52, "1080p", function() ApplyGlobalScale(true, 768 / 1080, "1080p") end },
            { "1440p", 60, 52, "1440p", function() ApplyGlobalScale(true, 768 / 1440, "1440p") end },
            { "4K", 120, 42, "4k", function() ApplyGlobalScale(true, 768 / 2160, "4k") end },
            { "Pixel", 170, 52, "pixel", function() ApplyGlobalScale(true, PixelScale(), "pixel") end },
        },
        extra = function(buttonsTop, Refresh)
            Button(scaling, "Off", 16 + 164, buttonsTop, 52, 20, function()
                pending.globalEnabled = false
                Refresh()
            end, nil, "scaling.global_ui.select_off", "ephemeral")
        end,
    })
    local RefreshMsufScale = BuildScaleColumn(scaling, colW, {
        x = msufX, top = msufTop, label = "MSUF Frame Scale", settingKey = "general.msufUiScale", help = "Changes the actual MSUF unit frames in-game.",
        semanticPath = "scaling.msuf_frames",
        minPct = MSUF_SCALE_MIN_PERCENT, maxPct = MSUF_SCALE_MAX_PERCENT, stepPct = MSUF_SCALE_STEP_PERCENT,
        pending = pending, key = "msuf", applied = AppliedMsufScale, current = PendingMsufScale,
        revert = function() pending.msuf = nil end,
        apply = function()
            local scaleValue = PendingMsufScale()
            M.GetGeneralDB().msufUiScale = scaleValue
            pending.msuf = nil
            MSUF.Require("MSUF_ApplyMsufScale", FILE)(scaleValue)
            if M.RequestGeneralDomains then
                M.RequestGeneralDomains("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false, notify = false })
            end
        end,
    })
    local RefreshMenuScale = BuildScaleColumn(scaling, colW, {
        x = menuX, top = menuTop, label = "MSUF Menu Scale", settingKey = "general.slashMenuScale", help = "Changes only this configuration menu window.",
        semanticPath = "scaling.menu",
        minPct = MENU_SCALE_MIN_PERCENT, maxPct = MENU_SCALE_MAX_PERCENT, stepPct = MENU_SCALE_STEP_PERCENT,
        pending = pending, key = "menu", applied = AppliedMenuScale, current = PendingMenuScale,
        revert = function() pending.menu = nil end,
        apply = function()
            local scaleValue = PendingMenuScale()
            local dbScale = M.GetGeneralDB()
            dbScale.slashMenuScale = MenuScaleStoredFromPercent(scaleValue * 100)
            pending.menu = nil
            if M.frame and M.ApplyMenuFrameScale then M.ApplyMenuFrameScale(M.frame)
            elseif M.frame and M.frame.SetScale then
                local storedScale = dbScale.slashMenuScale
                M.frame:SetScale((M.GetEffectiveMenuScale and M.GetEffectiveMenuScale(storedScale)) or storedScale)
            end
        end,
    })
    M.TrackRefresh(ctx, RefreshGlobalScale)
    M.TrackRefresh(ctx, RefreshMsufScale)
    M.TrackRefresh(ctx, RefreshMenuScale)
end
function Dashboard.BuildChangelogCard(state)
    local recoveryW = state.recoveryW
    local changelog = Card(state.root, "", state.x0, state.changelogTop, recoveryW, state.changelogH, T.colors.panel2, T.colors.borderSoft)
    BuildDashboardChangelog(changelog, recoveryW, {
        title = "Changelog",
        sectionHeader = true,
        top = 0,
        bottom = 18,
        hideSummaryWhenClosed = true,
        onToggle = RebuildDashboardPage,
    })
end
local SUPPORT_LINKS = {
    { key = "discord", texture = "Discord.png", title = "Discord", tooltip = "Copy Discord Link", url = "https://discord.gg/2Gf9b2Wprz" },
    { key = "patreon", texture = "Patreon.png", title = "Patreon", tooltip = "Click to copy the Patreon support link.",
        url = "https://www.patreon.com/cw/MidnightSimpleUnitframes" },
    { key = "paypal", texture = "PayPal.png", title = "PayPal", tooltip = "Click to copy the PayPal support link.",
        url = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ" },
    { key = "kofi", texture = "Ko-Fi.png", title = "Ko-fi", tooltip = "Click to copy the Ko-fi link.",
        url = "https://ko-fi.com/midnightsimpleunitframes#linkModal" },
    { key = "github", texture = "GitHub.png", title = "GitHub", tooltip = "Click to copy the GitHub repository link.",
        url = "https://github.com/Mapkov2/MidnightSimpleUnitFrames" },
}
--- Wrapped string height, at least one text line (12) tall.
local function WrappedHeight(fs)
    local h = (fs.GetStringHeight and fs:GetStringHeight()) or 0
    return h < 12 and 12 or h
end
function Dashboard.BuildSupportCard(state)
    local recoveryW = state.recoveryW
    local supportCompact = recoveryW < 560
    local supportH = supportCompact and 116 or 78
    local support = Card(state.root, "", state.x0, state.supportTop, recoveryW, supportH, T.colors.panel2, T.colors.borderSoft)
    local supportTitle = Label(support, "GameFontNormal", "How to support MSUF", T.colors.text, 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    WordWrap(supportDesc)
    -- One shared accessor, MSUF.GetAddonVersion from Game/Shared/Initialize.lua:
    -- the core resolves it once from the TOC this client loaded, so the Options
    -- package never reports its own "## Version" here.
    local getVersion = MSUF.GetAddonVersion
    local aboutVer = type(getVersion) == "function" and getVersion() or nil
    local aboutText = M.Tr("by Mapko with the help from R41z0r, Lead QA: Aur0r4")
    if type(aboutVer) == "string" and aboutVer ~= "" then
        local displayVersion = aboutVer:match("^%d") and ("v" .. aboutVer) or aboutVer
        aboutText = M.Format(M.Tr("%s  -  by Mapko with the help from R41z0r, Lead QA: Aur0r4"), displayVersion)
    end
    local aboutY = -44 - WrappedHeight(supportDesc) - 4
    local supportAbout = W.Text(support, aboutText, 16, aboutY, supportTextW, T.colors.muted)
    WordWrap(supportAbout)
    local supportTextBottom = math.abs(aboutY - WrappedHeight(supportAbout))
    supportH = max(supportH, floor(supportTextBottom + (supportCompact and 48 or 14)))
    support:SetHeight(supportH)
    local iconRow = PixelLayoutRegion(CreateFrame("Frame", nil, support))
    iconRow:SetSize(168, 24)
    if supportCompact then
        iconRow:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 16, 12)
    else
        iconRow:SetPoint("RIGHT", support, "RIGHT", -16, 0)
    end
    local previous
    for i = 1, #SUPPORT_LINKS do
        local data = SUPPORT_LINKS[i]
        local btn = PixelLayoutRegion(CreateFrame("Button", nil, iconRow))
        btn:SetSize(24, 24)
        local tex = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
        tex:SetAllPoints()
        tex:SetTexture(ICON_DIR .. data.texture)
        local hover = PixelLayoutRegion(btn:CreateTexture(nil, "HIGHLIGHT"))
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        btn:SetScript("OnClick", function()
            CopyLink(data.title, data.url)
        end)
        AddTooltip(btn, data.title, data.tooltip)
        RegisterDashboardControl(btn, DashboardMeta("support.link." .. tostring(data.title), "action", {
            actionKey = "copy_support_link",
            actionFixedArgs = { link = data.key },
            anchor = supportTitle,
            keywords = { data.tooltip, "How to support MSUF", "support links", data.url },
            help = data.tooltip,
        }), data.title, "button")
        if previous then
            btn:SetPoint("LEFT", previous, "RIGHT", 12, 0)
        else
            btn:SetPoint("LEFT", iconRow, "LEFT", 0, 0)
        end
        previous = btn
    end
    return supportH
end
function Dashboard.Build(ctx)
    if M.BuildUpgradeHighlightDashboardScene(ctx) == true then return end
    if M.BuildFirstLoadDashboardScene(ctx) == true then return end
    local x0, y0 = 12, -12
    local layoutW = max(1, (ctx.width or 760) - x0)
    local state = { root = ctx.wrapper, x0 = x0, layoutW = layoutW, mainW = layoutW }
    M.ToggleDashboardEditMode = ToggleEditMode
    M.dashboardEditModeButton = nil
    M.TrackRefresh(ctx, RefreshDashboardEditModeButtonSafe)
    local mainTop = y0
    local launcherH = Dashboard.BuildGuidedSetupLauncher(state, mainTop, ctx)
    mainTop = mainTop - launcherH - 10
    local heroH = Dashboard.BuildSearchHero(state, mainTop, ctx)
    local featureBlockBottom = mainTop - heroH
    local suiteH = Dashboard.BuildSuiteCard(state, ctx, featureBlockBottom - 10)
    if suiteH > 0 then featureBlockBottom = featureBlockBottom - 10 - suiteH end
    Dashboard.ResolveCardStack(state, featureBlockBottom)
    Dashboard.BuildRecoveryCard(state)
    Dashboard.BuildScalingCard(state, ctx)
    Dashboard.BuildChangelogCard(state)
    local supportH = Dashboard.BuildSupportCard(state)
    local bottom = state.supportTop - supportH
    ctx:SetContentHeight(math.abs(bottom) + 42)
end
-- Each combination of open disclosures is one cached Dashboard view, so a
-- disclosure toggle switches views instead of building a new frame tree
-- (review C5.2). Index bits: recovery 1, changelog 2, scaling 4.
local DASHBOARD_VIEWS = { [0] = "---", "r--", "-c-", "rc-", "--s", "r-s", "-cs", "rcs" }
local function DashboardViewKey()
    return DASHBOARD_VIEWS[(M.dashboardRecoveryOpen == true and 1 or 0)
        + (M.dashboardChangelogOpen == true and 2 or 0)
        + (M.dashboardScalingOpen == true and 4 or 0)]
end
M.RegisterPage("home", { title = "MSUF Menu", build = Dashboard.Build, version = 10, variantKey = DashboardViewKey })
