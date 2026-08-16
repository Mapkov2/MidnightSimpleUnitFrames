-- Menu2 full changelog page with direct links from release highlights to the
-- owning Menu2 controls. Full history is bundled only with the LoD Options
-- addon; core keeps its compact changelog payload for Assistant knowledge.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local T = M.Theme
local CreateFrame = _G.CreateFrame
local max = math.max
local tostring = tostring
local type = type

local function Tr(text)
    return type(M.Tr) == "function" and M.Tr(text) or tostring(text or "")
end

local function ChangelogData()
    local full = (type(MSUF) == "table" and MSUF.MSUF_FullChangelog) or _G.MSUF_FullChangelog
    if type(full) == "table" and type(full.entries) == "table" and type(full.entries[1]) == "table" then
        return full
    end
    local compact = (type(MSUF) == "table" and MSUF.MSUF_Changelog) or _G.MSUF_Changelog
    if type(compact) == "table" and type(compact.entries) == "table" and type(compact.entries[1]) == "table" then
        return compact
    end
end

local function BulletParts(value)
    if type(value) == "table" then
        return tostring(value.text or ""), type(value.link) == "table" and value.link or nil
    end
    return tostring(value or ""), nil
end

local function OpenMenuLink(link)
    if type(link) ~= "table" then return false end
    local pageKey = tostring(link.pageKey or "")
    local query = tostring(link.query or "")
    local label = tostring(link.label or query)
    local sectionId = tostring(link.sectionId or "")
    local controlId = tostring(link.controlId or "")
    if pageKey == "" or sectionId == "" or controlId == "" then return false end

    local bridge = M.SearchBridge
    if bridge and type(bridge.OpenSearchTarget) == "function" then
        local exactTarget = {
            pageKey = pageKey,
            sectionId = sectionId,
            controlId = controlId,
            settingKey = tostring(link.settingKey or ""),
            prepareKind = tostring(link.prepareKind or ""),
            prepareValue = tostring(link.prepareValue or ""),
        }
        local route = { accordion = { [pageKey .. ":" .. sectionId] = true } }
        local called, opened, focused, exact = bridge.OpenSearchTarget(
            pageKey, query ~= "" and query or label, label, nil, route, exactTarget)
        if called and opened == true and focused == true and exact == true then return true end
    end
    return false
end
M.OpenChangelogMenuLink = OpenMenuLink

local function RebuildKeepingScroll()
    if type(M.RebuildPageKeepingScroll) == "function" then
        M.RebuildPageKeepingScroll("changelog")
        return
    end
    if type(M.InvalidatePage) == "function" then M.InvalidatePage("changelog") end
    if type(M.SelectPage) == "function" then M.SelectPage("changelog") end
end

local function BuildFullChangelog(ctx)
    local data = ChangelogData()
    local root = ctx.wrapper
    local width = max(320, tonumber(ctx.width) or 760)
    local contentWidth = max(280, width - 36)
    local y = -18

    local function AddText(text, template, color, x, availableWidth, gap, role)
        local fs = T.Font(root, template or "GameFontHighlightSmall", text, color or T.colors.text, role)
        fs:SetPoint("TOPLEFT", root, "TOPLEFT", x or 18, y)
        fs:SetWidth(max(80, availableWidth or contentWidth))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        if fs.SetSpacing then fs:SetSpacing(3) end
        local height = max(14, (fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0)
        y = y - height - (gap or 6)
        return fs, height
    end

    local function AddLinkedText(text, link, x, availableWidth, gap)
        local button = CreateFrame("Button", nil, root)
        button:SetPoint("TOPLEFT", root, "TOPLEFT", x or 18, y)
        local linkWidth = max(80, availableWidth or contentWidth)
        button:SetWidth(linkWidth)
        local fs = T.Font(button, "GameFontHighlightSmall", Tr(text), T.colors.accent2 or T.colors.warning, "body")
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        fs:SetWidth(linkWidth)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        if fs.SetSpacing then fs:SetSpacing(3) end
        local height = max(14, (fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0)
        button:SetHeight(height)
        local PaintFeatureLink = type(T.StyleFeatureLink) == "function" and T.StyleFeatureLink(button, fs) or nil
        button:SetScript("OnClick", function()
            if not OpenMenuLink(link) and type(M.ShowStatusFeedback) == "function" then
                M.ShowStatusFeedback(Tr("Menu link unavailable"), "danger", 1.6)
            end
        end)
        button:SetScript("OnEnter", function()
            if PaintFeatureLink then PaintFeatureLink(true) end
        end)
        button:SetScript("OnLeave", function()
            if PaintFeatureLink then PaintFeatureLink(false) end
        end)
        if type(M.AddTooltip) == "function" then
            M.AddTooltip(button, Tr(link.label or link.query or ""), Tr("Opens and highlights this feature's setting."), { hook = true })
        end
        y = y - height - (gap or 7)
        return button
    end

    AddText(Tr("See New Features"), "GameFontNormalHuge", T.colors.title or T.colors.text, 18, contentWidth, 8, "title")
    AddText(Tr("Browse releases from 6.02 onward. Highlight links open the matching feature directly in the MSUF menu."),
        "GameFontHighlightSmall", T.colors.muted, 18, contentWidth, 18, "body")

    if not data then
        AddText(Tr("No release notes bundled with this build."), "GameFontHighlight", T.colors.muted, 18, contentWidth, 10, "body")
        ctx:SetContentHeight(math.abs(y) + 36)
        return
    end

    local entries = data.entries
    local selectedVersion = tostring(M.changelogSelectedVersion or data.currentVersion or entries[1].version or "")
    local selectedFound = false
    for i = 1, #entries do
        if tostring(entries[i].version or "") == selectedVersion then selectedFound = true; break end
    end
    if not selectedFound then selectedVersion = tostring(entries[1].version or "") end
    M.changelogSelectedVersion = selectedVersion

    for entryIndex = 1, #entries do
        local entry = entries[entryIndex]
        if type(entry) == "table" then
            local version = tostring(entry.version or "")
            local targetVersion = version
            local date = tostring(entry.date or "")
            local selected = version == selectedVersion
            local heading = date ~= "" and (version .. "  -  " .. date) or version
            local header = T.Button(root, heading, contentWidth, 34)
            header:SetPoint("TOPLEFT", root, "TOPLEFT", 18, y)
            if T.CenterButtonLabel then T.CenterButtonLabel(header) end
            if selected and T.SkinPrimaryButton then T.SkinPrimaryButton(header) end
            header:SetScript("OnClick", function()
                if M.changelogSelectedVersion == targetVersion then return end
                M.changelogSelectedVersion = targetVersion
                RebuildKeepingScroll()
            end)
            if type(M.RegisterSearchWidget) == "function" then
                local token = version:gsub("[^%w]+", "_"):lower()
                M.RegisterSearchWidget(header, {
                    controlId = "menu2.changelog.release." .. token,
                    identityKey = "changelog.release." .. token,
                    controlPath = "changelog/release/" .. token,
                    pageKey = "changelog",
                    classification = "ephemeral",
                    ephemeral = true,
                    label = heading,
                    kind = "button",
                    help = Tr("Shows this bundled release entry."),
                    historyMode = "none",
                })
            end
            y = y - 42

            if selected and type(entry.sections) == "table" then
                for sectionIndex = 1, #entry.sections do
                    local section = entry.sections[sectionIndex]
                    if type(section) == "table" and type(section.bullets) == "table" and #section.bullets > 0 then
                        local isHighlights = tostring(section.title or ""):lower() == "highlights"
                        AddText(Tr(section.title or ""), "GameFontNormal", isHighlights and T.colors.accent or T.colors.accent2,
                            34, contentWidth - 32, 8, "section")
                        for bulletIndex = 1, #section.bullets do
                            local text, link = BulletParts(section.bullets[bulletIndex])
                            local dot = root:CreateTexture(nil, "ARTWORK")
                            dot:SetSize(5, 5)
                            dot:SetPoint("TOPLEFT", root, "TOPLEFT", 44, y - 6)
                            local dotColor = isHighlights and T.colors.accent2 or T.colors.accent
                            dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.95)
                            if isHighlights and link then
                                AddLinkedText(text, link, 58, contentWidth - 56, 7)
                            else
                                AddText(Tr(text), "GameFontHighlightSmall", T.colors.text, 58, contentWidth - 56, 7, "body")
                            end
                        end
                        y = y - 4
                    end
                end
                y = y - 8
            end
        end
    end

    ctx:SetContentHeight(math.abs(y) + 36)
end

function M.OpenSeeNewFeatures()
    local data = ChangelogData()
    if data and data.currentVersion then M.changelogSelectedVersion = tostring(data.currentVersion) end
    if type(M.SelectPage) == "function" then return M.SelectPage("changelog") end
    return false
end

M.RegisterPage("changelog", { title = "See New Features", build = BuildFullChangelog, version = 1 })
