local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
-- Menu2 dashboard: builds dashboard panels, summaries, and launcher actions.
-- UI construction stays here; profile/runtime mutations route through shared Menu2 helpers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
local T = M.Theme
local W = M.Widgets

-- Menu2 dashboard page.
-- Builds the home overview, recovery panels, changelog preview, and quick actions. Dashboard
-- widgets should call workflow/page helpers; profile/runtime mutation stays outside this file.
local floor = math.floor
local max = math.max
local min = math.min
local CreateFrame = _G.CreateFrame
local CreateColor = _G.CreateColor

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
    local slash = _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"]
    if type(slash) ~= "function" then return false end
    slash(message or "")
    return true
end
local function LoadedSuiteFactoryReset()
    local suite = _G.MSUFSuite
    return type(suite) == "table" and type(suite.Database) == "table"
        and type(suite.Database.StageFactoryReset) == "function"
end

local function RunSuiteFactoryReset()
    if DirectCombatLocked() or not LoadedSuiteFactoryReset() or type(_G.ReloadUI) ~= "function" then return false end
    local ok = _G.MSUFSuite.Database.StageFactoryReset()
    if not ok then return false end
    _G.ReloadUI()
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
    local suite = _G.MSUFSuite
    local getOverview = type(suite) == "table" and suite.GetOverview or nil
    if type(getOverview) ~= "function" then return nil end
    local overview = getOverview()
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
    local data = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(data) ~= "table" or type(data.entries) ~= "table" or type(data.entries[1]) ~= "table" then return nil end
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
local function BuildDashboardChangelog(parent, cardWidth, opts)
    opts = opts or {}
    local data = GetBundledChangelog()
    local top = opts.top or -130
    local headerH = 44
    local contentW = max(120, cardWidth or 420)
    local scrollW = max(80, contentW - 60)
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
    local header = PixelLayoutRegion(CreateFrame("Button", nil, parent))
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
    header:SetHeight(headerH)
    local arrow = PixelLayoutRegion(header:CreateTexture(nil, "OVERLAY"))
    arrow:SetSize(10, 10)
    arrow:SetPoint("LEFT", header, "LEFT", 16, 0)
    arrow:SetTexture(T.media.collapseArrow)
    local PaintHeaderTone = CreateDashboardAccordionTone(header, arrow)
    PaintHeaderTone(false, false)
    local title = T.Font(header, "GameFontNormal", opts.title or "Changelog", T.colors.text)
    title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
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
    local y = 0
    -- Release notes are long-form prose, so they run on the shared type roles (body/card/
    -- section) with real line spacing instead of the smallest Blizzard template. Roles keep
    -- the sizes identical at every UI and menu scale.
    local bodyColor = { T.colors.text[1], T.colors.text[2], T.colors.text[3], 0.94 }
    local function AddText(text, fontObject, color, indent, gap, translate, role)
        local rawText = tostring(text or "")
        if translate then rawText = M.Tr(rawText) end
        local fs = RawFont(child, fontObject or "GameFontHighlightSmall", rawText, color or T.colors.muted, 0, role or "body")
        indent = indent or 0
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, y)
        fs:SetWidth(max(40, scrollW - indent - 4))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        if fs.SetSpacing then fs:SetSpacing(3) end
        fs:SetText(rawText)
        -- GetStringHeight is the wrapped height; keep GetHeight in the mix so the added line
        -- spacing can never be measured away and let a long bullet collide with the next one.
        local h = max((fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0)
        if h < 12 then h = 14 end
        y = y - h - (gap or 4)
        return fs
    end
    local function AddBullet(value, dotColor, textColor, isHighlight)
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
        if isHighlight and link then
            local button = PixelLayoutRegion(CreateFrame("Button", nil, child))
            button:SetPoint("TOPLEFT", child, "TOPLEFT", 22, y)
            local linkWidth = max(40, scrollW - 32)
            button:SetWidth(linkWidth)
            local fs = RawFont(button, "GameFontHighlightSmall", M.Tr(text), T.colors.accent2 or T.colors.warning, 0, "body")
            fs:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            fs:SetWidth(linkWidth)
            fs:SetJustifyH("LEFT")
            if fs.SetWordWrap then fs:SetWordWrap(true) end
            if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
            if fs.SetSpacing then fs:SetSpacing(3) end
            local h = max((fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0, 14)
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
        return AddText(text, "GameFontHighlightSmall", textColor, 22, 9, true, "body")
    end
    local function AddRule()
        local rule = PixelLayoutRegion(child:CreateTexture(nil, "ARTWORK"))
        rule:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        rule:SetPoint("TOPRIGHT", child, "TOPRIGHT", -4, y)
        rule:SetHeight(1)
        rule:SetColorTexture(T.colors.borderSoft[1], T.colors.borderSoft[2], T.colors.borderSoft[3], 0.55)
        y = y - 1
    end
    local entries = data.entries
    local maxEntries = min(#entries, 4)
    for entryIndex = 1, maxEntries do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local date = tostring(entry.date or "")
            local heading = (date ~= "" and (version .. " - " .. date)) or version
            if entryIndex > 1 then
                y = y - 10
                AddRule()
                y = y - 12
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
                            AddBullet(
                                section.bullets[bulletIndex],
                                isHighlights and T.colors.accent2 or nil,
                                isHighlights and T.colors.text or nil,
                                isHighlights
                            )
                        end
                    end
                end
            end
        end
    end
    child:SetHeight(max(1, math.abs(y) + 8))
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
        open = not open
        RefreshOpenState()
        if type(opts.onToggle) == "function" then opts.onToggle(open) end
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
function Dashboard.PrepareSurfaceHelpers(state, root)
    local function Card(parent, title, x, y, w, h, bg, border)
        bg = bg or T.colors.panel2
        border = border or T.colors.cardBorder or T.colors.borderSoft
        local card = T.Panel(parent or root, nil, bg, border)
        if T.ApplyMaterial then
            T.ApplyMaterial(card, { bg = bg, border = border, glass = "card", gradient = "card" })
        elseif T.ApplySurface then
            T.ApplySurface(card, "card")
        end
        card:SetPoint("TOPLEFT", parent or root, "TOPLEFT", x, y)
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
    local function ApplyDashboardHeroGradient(card, w, h)
        if not (card and card.CreateTexture) or card._msuf2DashboardHeroGradient then return end
        card._msuf2DashboardHeroGradient = true
        local c = T.colors
        local wash = PixelLayoutRegion(card:CreateTexture(nil, "BACKGROUND", nil, 1))
        wash:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        wash:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(wash, "HORIZONTAL",
            { c.coreShadow[1], c.coreShadow[2], c.coreShadow[3], 0.00 },
            { c.coreRaised[1], c.coreRaised[2], c.coreRaised[3], 0.12 })
        local top = PixelLayoutRegion(card:CreateTexture(nil, "BACKGROUND", nil, 2))
        top:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        top:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
        top:SetHeight(max(54, min(96, floor((h or 190) * 0.42))))
        SetDashboardGradient(top, "VERTICAL",
            { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.055 },
            { c.coreShadow[1], c.coreShadow[2], c.coreShadow[3], 0.00 })
        local focus = PixelLayoutRegion(card:CreateTexture(nil, "BACKGROUND", nil, 3))
        focus:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -2)
        focus:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
        SetDashboardGradient(focus, "HORIZONTAL",
            { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.00 },
            { c.coreBlue[1], c.coreBlue[2], c.coreBlue[3], 0.035 })
    end
    local function Button(parent, text, x, y, w, h, onClick, skin, semanticPath, classification, exact)
        local btn = T.Button(parent, text or "", w, h or 24)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        T.CenterButtonLabel(btn)
        if skin == "primary" and T.SkinPrimaryButton then T.SkinPrimaryButton(btn) end
        if skin == "success" and T.SkinSuccessButton then T.SkinSuccessButton(btn) end
        if skin == "danger" and T.SkinDangerButton then T.SkinDangerButton(btn) end
        if onClick then btn:SetScript("OnClick", onClick) end
        RegisterDashboardControl(btn, DashboardMeta(semanticPath, classification or "action", exact), text, "button")
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
    local function AddTooltip(frame, title, text)
        return M.AddTooltip and M.AddTooltip(frame, title, text, {
            hook = true,
            titleAsLine = true,
            bodyColor = { 0.85, 0.85, 0.85 },
        }) or frame
    end
    state.Card, state.ApplyDashboardHeroGradient, state.Button, state.Kicker, state.Pill, state.AddTooltip =
        Card, ApplyDashboardHeroGradient, Button, Kicker, Pill, AddTooltip
end
function Dashboard.PrepareActionHelpers(state)
    local function IsDashboardEditModeActive()
        return M.IsMSUFEditModeActive(true)
    end
    local function IsDashboardEditModeCombatLocked()
        return M.IsEditModeCombatLocked(true)
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
        local active = IsDashboardEditModeActive()
        if (not active) and IsDashboardEditModeCombatLocked() then
            M.BlockCombatAction()
            RefreshDashboardEditModeButtonSafe()
            RefreshDashboardFrameStatus()
            return
        end
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then _G.MSUF_SetMSUFEditModeDirect(not active) end
        RefreshMenuFramePrioritySafe()
        C_Timer.After(0, RefreshMenuFramePrioritySafe)
        RefreshDashboardEditModeButtonSafe()
        RefreshDashboardFrameStatus()
    end
    M.ToggleDashboardEditMode = ToggleEditMode
    local iconDir = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"
    local function CopyWagoLink()
        _G.MSUF_ShowCopyLink("Wago MSUF Profiles", "https://wago.io/search/imports/wow/msuf")
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
        if slider and slider._msuf2Title then T.StyleFontString(slider._msuf2Title, T.colors.text, 3) end
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
            local v = _G.MSUF_GetPixelPerfectScale()
            if tonumber(v) then return Clamp(v, 0.3, 1.5) end
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
    local RunMSUFSlashCommand = DirectRunSlash
    state.RefreshDashboardEditModeButtonSafe, state.iconDir, state.CopyWagoLink, state.Percent, state.Clamp, state.SnapPct =
        RefreshDashboardEditModeButtonSafe, iconDir, CopyWagoLink, Percent, Clamp, SnapPct
    state.SetSliderValueSafe, state.HideSliderValueBox, state.EnablePercentWheel, state.PixelScale, state.GlobalState, state.RunMSUFSlashCommand =
        SetSliderValueSafe, HideSliderValueBox, EnablePercentWheel, PixelScale, GlobalState, RunMSUFSlashCommand
end
function Dashboard.BuildGuidedSetupLauncher(state, mainTop)
    local root, x0, mainW, Card, Kicker, Button, AddTooltip = state.root, state.x0, state.mainW, state.Card, state.Kicker, state.Button, state.AddTooltip
    local iconDir, CopyWagoLink = state.iconDir, state.CopyWagoLink
    -- Setup remains available after onboarding. Quick Setup is the default;
    -- the first route screen still offers the complete learning tour.
    -- launcher deliberately compact; the persistent progress bar itself lives
    -- in the window chrome while the tour is active.
    local tour = MSUF and MSUF.GuidedTour6
    local tourState = type(tour) == "table" and type(tour.GetState) == "function" and tour:GetState() or nil
    local tourActive = type(tourState) == "table" and tourState.status == "active"
    local tourCompleted = type(tourState) == "table" and tourState.status == "completed"
    local firstLoad = MSUF and MSUF.FirstLoad6
    local highlightGuidedSetup = type(firstLoad) == "table"
        and type(firstLoad.ShouldHighlightGuidedSetup) == "function"
        and firstLoad:ShouldHighlightGuidedSetup()
    local launcherNarrow = mainW < 520
    -- The Wago button rides along with the setup action: narrow stacks it below,
    -- wide seats it left of the action, so both reserve room in the same card.
    local launcherH = launcherNarrow and 162 or 78
    local launcher = Card(root, "", x0, mainTop, mainW, launcherH, T.colors.panel2, T.colors.borderSoft)
    Kicker(launcher, tourActive and "GUIDED SETUP IN PROGRESS" or (tourCompleted and "GUIDED SETUP COMPLETE" or "GUIDED SETUP"), 16, -14)
    local launcherTitle = tourActive and "Continue your MSUF setup"
        or (tourCompleted and "Review or run setup again" or "Get the essentials right in a few minutes")
    local title = T.Font(launcher, "GameFontNormal", launcherTitle, T.colors.text)
    title:SetPoint("TOPLEFT", launcher, "TOPLEFT", 16, -36)
    title:SetWidth(max(120, mainW - (launcherNarrow and 32 or 388)))
    title:SetJustifyH("LEFT")
    if tourActive then
        local current, total
        if type(M.GetGuidedTourStageProgress) == "function" then current, total = M.GetGuidedTourStageProgress() end
        total = max(1, tonumber(total) or tonumber(M.guidedTourStageCount) or 1)
        current = min(total, max(1, tonumber(current) or 1))
        local step = T.Font(launcher, "GameFontDisableSmall", M.Format("Step %d of %d", current, total), T.colors.muted)
        step:SetPoint("TOPLEFT", launcher, "TOPLEFT", 16, launcherNarrow and -72 or -56)
    end
    local actionText = tourActive and "Resume setup" or (tourCompleted and "Run setup again" or "Start Quick Setup")
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
    local wagoW = launcherNarrow and actionW or 150
    local wago = Button(launcher, "Wago Profiles",
        launcherNarrow and actionX or (mainW - 354),
        launcherNarrow and -126 or -27,
        wagoW, 30, CopyWagoLink, nil, "guided_setup.browse_wago_profiles", "action",
        { actionKey = "copy_wago_profiles_link",
          keywords = { "Browse Wago profiles", "Wago profile imports" },
          help = "Opens a copyable link to the MSUF profile imports on Wago." })
    local wagoIcon = PixelLayoutRegion(wago:CreateTexture(nil, "ARTWORK", nil, 3))
    wagoIcon:SetTexture(iconDir .. "Wago.png")
    wagoIcon:SetSize(22, 22)
    wagoIcon:SetPoint("LEFT", wago, "LEFT", 8, 0)
    if wago._msuf2Label then
        wago._msuf2Label:ClearAllPoints()
        wago._msuf2Label:SetPoint("LEFT", wagoIcon, "RIGHT", 6, 0)
        wago._msuf2Label:SetPoint("RIGHT", wago, "RIGHT", -10, 0)
        wago._msuf2Label:SetJustifyH("CENTER")
    end
    AddTooltip(wago, "Wago Profiles", "Browse Wago profiles")
    return launcherH
end
function Dashboard.BuildSearchHero(state, mainTop)
    local mainW = state.mainW
    local heroH = mainW < 390 and 174 or 156
    local hero = state.Card(state.root, "", state.x0, mainTop, mainW, heroH, T.colors.glassHost, T.colors.cardBorder)
    state.ApplyDashboardHeroGradient(hero, mainW, heroH)
    state.Kicker(hero, "MSUF", 22, -20)
    local title = T.Font(hero, "GameFontNormalLarge", "Find settings and help", T.colors.text)
    title:SetPoint("TOPLEFT", hero, "TOPLEFT", 22, -42)
    title:SetWidth(mainW - 44)
    W.Text(hero, "Search enabled features in your own words.", 22, -72, mainW - 44, T.colors.muted)
    state.Button(hero, "Search", 22, -heroH + 44, math.min(220, mainW - 44), 28, function()
        if DirectCombatLocked() then return end
        local box = M.nav and M.nav.searchBox
        if box and box.SetFocus then box:SetFocus() end
    end, "primary", "search.open", "navigation", { navigationKey = "search" })
    return heroH
end
--- Compact MSUF Suite card between the search hero and the collapsed cards.
--- It is built only while the Suite reports an overview, so nothing is promoted
--- when the Suite is not installed. Returns its height, 0 when there is no card.
function Dashboard.BuildSuiteCard(state, ctx, top)
    local overview = M.GetSuiteOverview()
    if not overview then return 0 end
    local root, x0, mainW, Card, Kicker, Button, AddTooltip = state.root, state.x0, state.mainW, state.Card, state.Kicker, state.Button, state.AddTooltip
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
    local title = T.Font(card, "GameFontNormal", "", T.colors.text)
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -34)
    title:SetWidth(textW)
    title:SetJustifyH("LEFT")
    local status = T.Font(card, "GameFontHighlightSmall", "", T.colors.ok or T.colors.accent)
    status:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -56)
    status:SetWidth(textW)
    status:SetJustifyH("LEFT")
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
            local suite = _G.MSUFSuite
            local installer = type(suite) == "table" and suite.Installer or nil
            local open = type(installer) == "table" and installer.Open or nil
            -- The setup window shares the menu's strata below its content, so
            -- the menu steps aside once the Suite confirms the window opened.
            if type(open) == "function" and open() == true then
                M.HideSlashMenuAndMinibar(M.frame)
            elseif M.ShowStatusFeedback then
                M.ShowStatusFeedback(M.Tr("Suite setup unavailable"), "danger", 1.4)
            end
        end, "primary", "suite.setup", "ephemeral",
            { help = "Opens the MSUF Suite setup: profile, modules and UI scaling." })
        AddTooltip(setup, "Set up Suite", "Opens the MSUF Suite setup: profile, modules and UI scaling.")
    end
    if pageKey then
        local open = Button(card, "Open Suite Modules", openX, openY, openW, 28, function()
            if M.BlockCombatAction and M.BlockCombatAction() then return end
            M.SelectPage(pageKey)
        end, (not needsSetup) and "primary" or nil, "suite.open_modules", "navigation",
            { navigationKey = pageKey, help = "Shows the Suite page that switches each optional module on or off." })
        AddTooltip(open, "Open Suite Modules", "Shows the Suite page that switches each optional module on or off.")
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
function Dashboard.PrepareDisclosure(state)
    local function DashboardDisclosure(parent, title, open, stateKey, width, fillPills, semanticPath)
        local head = PixelLayoutRegion(CreateFrame("Button", nil, parent))
        head:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        head:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        head:SetHeight(44)
        local arrow = PixelLayoutRegion(head:CreateTexture(nil, "OVERLAY"))
        arrow:SetTexture(T.media.collapseArrow)
        arrow:SetSize(10, 10)
        arrow:SetPoint("LEFT", head, "LEFT", 16, 0)
        local PaintHeaderTone = CreateDashboardAccordionTone(head, arrow)
        PaintHeaderTone(open, false)
        local label = T.Font(head, "GameFontNormal", title, T.colors.text)
        label:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
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
    state.DashboardDisclosure = DashboardDisclosure
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
function Dashboard.BuildRecoveryCard(state)
    local root, x0, Card, Pill, Button, AddTooltip = state.root, state.x0, state.Card, state.Pill, state.Button, state.AddTooltip
    local DashboardDisclosure, RunMSUFSlashCommand = state.DashboardDisclosure, state.RunMSUFSlashCommand
    local recoveryTop, recoveryW, recoveryH, recoveryOpen = state.recoveryTop, state.recoveryW, state.recoveryH, state.recoveryOpen
    local recoveryWrap = state.recoveryWrap
    local recovery = Card(root, "", x0, recoveryTop, recoveryW, recoveryH, T.colors.panel2, T.colors.borderSoft)
    local g = M.GetGeneralDB and M.GetGeneralDB() or {}
    DashboardDisclosure(recovery, "Display & recovery", recoveryOpen, "dashboardRecoveryOpen", recoveryW, function(head)
        if recoveryW >= 520 then Pill(head, "Factory reset hidden", recoveryW - 124, -11, 110, T.colors.accent2) end
    end, "display_recovery.disclosure")
    if recoveryOpen then
        W.Text(recovery, state.hasSuiteReset and "Fix positions, print help, or reset MSUF or Suite."
            or "Fix positions, print help, or reset MSUF.", 16, -60, recoveryW - 32, T.colors.muted)
        local resetPositions = Button(recovery, "Reset Positions", 16, -94, 118, 22, function()
            if not RunMSUFSlashCommand("reset") and M.ShowStatusFeedback then M.ShowStatusFeedback(M.Tr("Reset unavailable"), "danger", 1.4) end
        end, "primary", "display_recovery.reset_positions")
        AddTooltip(resetPositions, "Reset Positions", "Runs /msuf reset for frame positions and visibility.")
        local factoryY = recoveryWrap and -126 or -94
        --- "all" includes the diagnostic commands: someone who opened this card
        --- is usually troubleshooting and wants the complete list, not a subset.
        local printHelp = Button(recovery, "Print Help", 146, -94, 86, 22, function()
            if not RunMSUFSlashCommand("help all") and M.ShowStatusFeedback then
                M.ShowStatusFeedback(M.Tr("Help unavailable"), "danger", 1.4)
            end
        end, nil, "display_recovery.print_help")
        AddTooltip(printHelp, "Print Help", "Lists every MSUF slash command in chat, diagnostics included.")
        local msufX = recoveryWrap and 16 or (recoveryW - (state.hasSuiteReset and 336 or 168))
        local msufReset = Button(recovery, "MSUF Factory Reset", msufX, factoryY, 156, 22, function()
            if not ShowFactoryResetConfirm("msuf") and M.ShowStatusFeedback then
                M.ShowStatusFeedback(M.Tr("Reset unavailable"), "danger", 1.4)
            end
        end, "danger", "display_recovery.factory_reset_all", "action", { confirmRequired = true })
        AddTooltip(msufReset, "MSUF Factory Reset", "Deletes all MSUF profiles and settings after confirmation. Suite profiles are kept.")
        if state.hasSuiteReset then
            local suiteX = state.recoveryStacked and 16 or (recoveryWrap and 180 or (recoveryW - 168))
            local suiteY = state.recoveryStacked and -158 or factoryY
            local suiteReset = Button(recovery, "Suite Factory Reset", suiteX, suiteY, 156, 22, function()
                if not ShowFactoryResetConfirm("suite") and M.ShowStatusFeedback then
                    M.ShowStatusFeedback(M.Tr("Reset unavailable"), "danger", 1.4)
                end
            end, "danger", "display_recovery.suite_factory_reset", "action", { confirmRequired = true })
            AddTooltip(suiteReset, "Suite Factory Reset", "Deletes all Suite profiles and skin settings after confirmation. MSUF data stays intact.")
        elseif recoveryWrap then
            W.Text(recovery, "Factory reset affects every MSUF setting.", 160, -128, recoveryW - 176, T.colors.muted)
        end
    end
    state.g = g
end
function Dashboard.BuildScalingCard(state, ctx)
    local root, x0, Card, Pill, DashboardDisclosure = state.root, state.x0, state.Card, state.Pill, state.DashboardDisclosure
    local GlobalState, Percent, g = state.GlobalState, state.Percent, state.g
    local scalingTop, recoveryW, scalingH, scalingOpen = state.scalingTop, state.recoveryW, state.scalingH, state.scalingOpen
    local scaling = Card(root, "", x0, scalingTop, recoveryW, scalingH, T.colors.panel2, T.colors.borderSoft)
    DashboardDisclosure(scaling, "Scaling", scalingOpen, "dashboardScalingOpen", recoveryW, function(scaleHead)
        if recoveryW < 520 then return end
        local _, ui = GlobalState()
        local uiValue = ui.Enabled and M.Format("%d%%", Percent(ui.Scale, 1)) or M.Tr("Off")
        Pill(scaleHead, M.Format("UI %s", uiValue), recoveryW - 250, -11, 64)
        Pill(scaleHead, M.Format("Menu %d%%", MenuScalePercentFromStored(g.slashMenuScale)), recoveryW - 180, -11, 76)
        Pill(scaleHead, M.Format("Frames %d%%", Percent(g.msufUiScale, 1)), recoveryW - 98, -11, 84)
    end, "scaling.disclosure")
    if scalingOpen then Dashboard.BuildScalingColumns(state, ctx, scaling) end
end
function Dashboard.BuildScalingColumns(state, ctx, scaling)
    local recoveryW, scalingColumns, Button, Percent, Clamp = state.recoveryW, state.scalingColumns, state.Button, state.Percent, state.Clamp
    local SnapPct, SetSliderValueSafe, HideSliderValueBox = state.SnapPct, state.SetSliderValueSafe, state.HideSliderValueBox
    local EnablePercentWheel, PixelScale, GlobalState = state.EnablePercentWheel, state.PixelScale, state.GlobalState
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
        local selectedEnabled = pendingGlobalEnabled
        if selectedEnabled == nil then selectedEnabled = enabled end
        local selectedScale = Clamp(pendingGlobalScale or appliedScale, 0.3, 1.5)
        return selectedEnabled, selectedScale, enabled, appliedScale
    end
    local function AppliedMsufScale()
        local dbScale = M.GetGeneralDB()
        return Clamp(tonumber(dbScale.msufUiScale) or 1, 0.25, 2.0)
    end
    local function PendingMsufScale()
        return Clamp(pendingMsufScale or AppliedMsufScale(), 0.25, 2.0)
    end
    local function AppliedMenuScale()
        local dbScale = M.GetGeneralDB()
        return MenuScalePercentFromStored(dbScale.slashMenuScale) / 100
    end
    local function PendingMenuScale()
        return Clamp(pendingMenuScale or AppliedMenuScale(), MENU_SCALE_MIN_PERCENT / 100, MENU_SCALE_MAX_PERCENT / 100)
    end
    local function BuildScaleSlider(parent, label, x, top, width, minPct, maxPct, stepPct, semanticPath, settingKey)
        local slider = W.Slider(parent, label, minPct, maxPct, stepPct, width)
        HideSliderValueBox(slider)
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top - 64)
        if slider._msuf2SetLayoutWidth then slider:_msuf2SetLayoutWidth(width) end
        if slider._msuf2Title then
            slider._msuf2Title:ClearAllPoints()
            slider._msuf2Title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
            slider._msuf2Title:SetWidth(width)
        end
        EnablePercentWheel(slider, minPct, maxPct, stepPct)
        RegisterDashboardControl(slider, DashboardMeta(semanticPath, settingKey and "setting" or "ephemeral", {
            help = "Selects a pending scale percentage; use Apply to commit it.",
            settingKey = settingKey,
        }), label, "slider")
        return slider
    end
    local function BuildSimpleScaleColumn(opts)
        W.Text(scaling, opts.help, opts.x, opts.top - 20, colW, T.colors.muted)
        local status = W.Text(scaling, "", opts.x, opts.top - 40, colW, T.colors.muted)
        local Refresh
        local slider = BuildScaleSlider(scaling, opts.label, opts.x, opts.top, colW, opts.minPct, opts.maxPct, opts.stepPct,
            opts.semanticPath .. ".percent", opts.settingKey)
        local apply, revert
        Refresh = function()
            local applied = opts.applied()
            local pending = opts.pending()
            local changed = math.abs(applied - pending) > 0.001
            T.SetTranslatedText(status, M.Format("Applied: %d%%  Selected: %d%%", Percent(applied, 1), Percent(pending, 1)))
            SetSliderValueSafe(slider, SnapPct(pending * 100, opts.minPct, opts.maxPct, opts.stepPct))
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
            local pct = SnapPct(value, opts.minPct, opts.maxPct, opts.stepPct)
            if pct ~= value then SetSliderValueSafe(self, pct) end
            opts.set(Clamp(pct / 100, opts.minPct / 100, opts.maxPct / 100))
            Refresh()
        end)
        apply = Button(scaling, "Apply", opts.x, opts.top - 100, 72, 20, function()
            opts.apply(opts.pending())
            Refresh()
        end, "primary", opts.semanticPath .. ".apply")
        revert = Button(scaling, "Revert", opts.x + 82, opts.top - 100, 72, 20, function()
            opts.clear()
            Refresh()
        end, nil, opts.semanticPath .. ".revert_pending", "ephemeral")
        return Refresh
    end
    W.Text(scaling, "Changes the global WoW UI scale through MSUF presets.", globalX, globalTop - 20, colW, T.colors.muted)
    local globalStatus = W.Text(scaling, "", globalX, globalTop - 40, colW, T.colors.muted)
    local RefreshGlobalScale, ApplyGlobalScale
    local globalScale = BuildScaleSlider(scaling, "Global UI Scale", globalX, globalTop, colW, 30, 150, 1,
        "scaling.global_ui.percent", "general.globalUiScale")
    local globalApply, globalRevert
    RefreshGlobalScale = function()
        local selectedEnabled, selectedScale, appliedEnabled, appliedScale = SelectedGlobalScale()
        local applied = appliedEnabled and (Percent(appliedScale, 1) .. "%") or M.Tr("Off")
        local selected = selectedEnabled and (Percent(selectedScale, 1) .. "%") or M.Tr("Off")
        local changed = (selectedEnabled ~= appliedEnabled) or math.abs(selectedScale - appliedScale) > 0.001
        T.SetTranslatedText(globalStatus, M.Format("Applied: %s   Selected: %s", applied, selected))
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
    ApplyGlobalScale = function(enabled, value, preset)
        local dbScale, ui = GlobalState()
        ui.Enabled = enabled == true
        ui.Scale = Clamp(value or ui.Scale, 0.3, 1.5)
        dbScale.globalUiScalePreset = preset or (ui.Enabled and "custom" or "auto")
        dbScale.globalUiScaleValue = ui.Enabled and ui.Scale or nil
        pendingGlobalEnabled, pendingGlobalScale = nil, nil
        if ui.Enabled and type(_G.MSUF_SetGlobalUiScale) == "function" then
            _G.MSUF_SetGlobalUiScale(ui.Scale, true)
        elseif (not ui.Enabled) and type(_G.MSUF_ResetGlobalUiScale) == "function" then
            _G.MSUF_ResetGlobalUiScale(true)
        end
        if M.RequestGeneralApply then M.RequestGeneralApply("MSUF2_DASH_GLOBAL_SCALE", { preview = true, applyAll = false }) end
        RefreshGlobalScale()
    end
    Button(scaling, "1080p", globalX, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1080, "1080p") end,
        nil, "scaling.global_ui.preset.1080p")
    Button(scaling, "1440p", globalX + 60, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, 768 / 1440, "1440p") end,
        nil, "scaling.global_ui.preset.1440p")
    Button(scaling, "4K", globalX + 120, globalTop - 100, 42, 20, function() ApplyGlobalScale(true, 768 / 2160, "4k") end,
        nil, "scaling.global_ui.preset.4k")
    Button(scaling, "Pixel", globalX + 170, globalTop - 100, 52, 20, function() ApplyGlobalScale(true, PixelScale(), "pixel") end,
        nil, "scaling.global_ui.preset.pixel")
    globalApply = Button(scaling, "Apply", globalX, globalTop - 126, 72, 20, function()
        local selectedEnabled, selectedScale = SelectedGlobalScale()
        ApplyGlobalScale(selectedEnabled, selectedScale, selectedEnabled and "custom" or "auto")
    end, "primary", "scaling.global_ui.apply")
    globalRevert = Button(scaling, "Revert", globalX + 82, globalTop - 126, 72, 20, function()
        pendingGlobalEnabled, pendingGlobalScale = nil, nil
        RefreshGlobalScale()
    end, nil, "scaling.global_ui.revert_pending", "ephemeral")
    Button(scaling, "Off", globalX + 164, globalTop - 126, 52, 20, function()
        pendingGlobalEnabled = false
        RefreshGlobalScale()
    end, nil, "scaling.global_ui.select_off", "ephemeral")
    local RefreshMsufScale = BuildSimpleScaleColumn({
        x = msufX, top = msufTop, label = "MSUF Frame Scale", settingKey = "general.msufUiScale", help = "Changes the actual MSUF unit frames in-game.",
        semanticPath = "scaling.msuf_frames",
        minPct = MSUF_SCALE_MIN_PERCENT, maxPct = MSUF_SCALE_MAX_PERCENT, stepPct = MSUF_SCALE_STEP_PERCENT,
        applied = AppliedMsufScale,
        pending = PendingMsufScale,
        set = function(value) pendingMsufScale = value end,
        clear = function() pendingMsufScale = nil end,
        apply = function(scaleValue)
            local dbScale = M.GetGeneralDB()
            dbScale.msufUiScale = scaleValue
            pendingMsufScale = nil
            if type(_G.MSUF_ApplyMsufScale) == "function" then _G.MSUF_ApplyMsufScale(scaleValue) end
            if M.RequestGeneralApply then
                M.RequestGeneralApply("MSUF2_DASH_MSUF_SCALE", { preview = true, applyAll = false, notify = false })
            end
        end,
    })
    local RefreshMenuScale = BuildSimpleScaleColumn({
        x = menuX, top = menuTop, label = "MSUF Menu Scale", settingKey = "general.slashMenuScale", help = "Changes only this configuration menu window.",
        semanticPath = "scaling.menu",
        minPct = MENU_SCALE_MIN_PERCENT, maxPct = MENU_SCALE_MAX_PERCENT, stepPct = MENU_SCALE_STEP_PERCENT,
        applied = AppliedMenuScale,
        pending = PendingMenuScale,
        set = function(value) pendingMenuScale = value end,
        clear = function() pendingMenuScale = nil end,
        apply = function(scaleValue)
            local dbScale = M.GetGeneralDB()
            dbScale.slashMenuScale = MenuScaleStoredFromPercent(scaleValue * 100)
            pendingMenuScale = nil
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
    local root, x0, Card, changelogTop, recoveryW, changelogH = state.root, state.x0, state.Card, state.changelogTop, state.recoveryW, state.changelogH
    local changelog = Card(root, "", x0, changelogTop, recoveryW, changelogH, T.colors.panel2, T.colors.borderSoft)
    BuildDashboardChangelog(changelog, recoveryW, {
        title = "Changelog",
        sectionHeader = true,
        top = 0,
        bottom = 18,
        hideSummaryWhenClosed = true,
        onToggle = function()
            RebuildDashboardPage()
        end,
    })
end
function Dashboard.BuildSupportCard(state)
    local root, x0, Card, AddTooltip, iconDir, supportTop = state.root, state.x0, state.Card, state.AddTooltip, state.iconDir, state.supportTop
    local recoveryW = state.recoveryW
    local supportCompact = recoveryW < 560
    local supportH = supportCompact and 116 or 78
    local support = Card(root, "", x0, supportTop, recoveryW, supportH, T.colors.panel2, T.colors.borderSoft)
    local supportTitle = T.Font(support, "GameFontNormal", "How to support MSUF", T.colors.text)
    supportTitle:SetPoint("TOPLEFT", support, "TOPLEFT", 16, -16)
    local supportTextW = max(160, recoveryW - (supportCompact and 32 or 230))
    local supportDesc = W.Text(support, "If MSUF helps your UI, support links are one click away.", 16, -42, supportTextW, T.colors.muted)
    if supportDesc.SetWordWrap then supportDesc:SetWordWrap(true) end
    if supportDesc.SetNonSpaceWrap then supportDesc:SetNonSpaceWrap(true) end
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
    local supportDescH = (supportDesc.GetStringHeight and supportDesc:GetStringHeight()) or 0
    if supportDescH < 12 then supportDescH = 12 end
    local aboutY = -44 - supportDescH - 4
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
    local supportLinks = {
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
    local iconRow = PixelLayoutRegion(CreateFrame("Frame", nil, support))
    iconRow:SetSize(168, 24)
    if supportCompact then
        iconRow:SetPoint("BOTTOMLEFT", support, "BOTTOMLEFT", 16, 12)
    else
        iconRow:SetPoint("RIGHT", support, "RIGHT", -16, 0)
    end
    local previous
    for i = 1, #supportLinks do
        local data = supportLinks[i]
        local btn = PixelLayoutRegion(CreateFrame("Button", nil, iconRow))
        btn:SetSize(24, 24)
        local tex = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
        tex:SetAllPoints()
        tex:SetTexture(iconDir .. data.texture)
        local hover = PixelLayoutRegion(btn:CreateTexture(nil, "HIGHLIGHT"))
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.10)
        btn:SetScript("OnClick", function()
            _G.MSUF_ShowCopyLink(data.title, data.url)
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
    if M.BuildUpgradeHighlightDashboardScene(ctx) == true then
        return
    end
    if M.BuildFirstLoadDashboardScene(ctx) == true then
        return
    end
    local root = ctx.wrapper
    local width = ctx.width or 760
    local x0, y0 = 12, -12
    local layoutW = max(1, width - x0)
    local mainW = layoutW
    local state = { root = root, x0 = x0, layoutW = layoutW, mainW = mainW }
    Dashboard.PrepareSurfaceHelpers(state, root)
    Dashboard.PrepareActionHelpers(state)
    M.dashboardEditModeButton = nil
    M.TrackRefresh(ctx, state.RefreshDashboardEditModeButtonSafe)
    local mainTop = y0

    local launcherH = Dashboard.BuildGuidedSetupLauncher(state, mainTop)

    mainTop = mainTop - launcherH - 10
    local heroH = Dashboard.BuildSearchHero(state, mainTop)
    local featureBlockBottom = mainTop - heroH
    local suiteH = Dashboard.BuildSuiteCard(state, ctx, featureBlockBottom - 10)
    if suiteH > 0 then featureBlockBottom = featureBlockBottom - 10 - suiteH end
    Dashboard.PrepareDisclosure(state)
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
