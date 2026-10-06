local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
-- Menu2 full changelog page with direct links from release highlights to the
-- owning Menu2 controls. Full history is bundled only with the LoD Options
-- addon; core keeps its compact changelog payload for the menu.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local T = M.Theme
local CreateFrame = _G.CreateFrame
local max = math.max
local tostring = tostring
local type = type

local Tr = M.Tr

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

-- The optional Suite owns its release history and exposes it from its core addon.
local function SuiteChangelogData()
    local data = MSUF.SuiteLink.GetChangelog()
    if type(data) == "table" and type(data.entries) == "table" and type(data.entries[1]) == "table" then
        return data
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
    M.RebuildPageKeepingScroll("changelog")
end

local function BuildFullChangelog(ctx)
    local suiteData = SuiteChangelogData()
    local source = M.changelogSource == "suite" and suiteData and "suite" or "msuf"
    local data = source == "suite" and suiteData or ChangelogData()
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
        local button = PixelLayoutRegion(CreateFrame("Button", nil, root))
        button:SetPoint("TOPLEFT", root, "TOPLEFT", x or 18, y)
        local linkWidth = max(80, availableWidth or contentWidth)
        button:SetWidth(linkWidth)
        local fs = T.Font(button, "GameFontHighlightSmall", text, T.colors.accent2 or T.colors.warning, "body")
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        fs:SetWidth(linkWidth)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        if fs.SetSpacing then fs:SetSpacing(3) end
        local height = max(14, (fs.GetStringHeight and fs:GetStringHeight()) or 0, (fs.GetHeight and fs:GetHeight()) or 0)
        button:SetHeight(height)
        local PaintFeatureLink = T.StyleFeatureLink(button, fs) or nil
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

    AddText("See New Features", "GameFontNormalHuge", T.colors.title or T.colors.text, 18, contentWidth, 8, "title")
    if suiteData then
        local tabWidth = math.min(164, math.floor((contentWidth - 8) / 2))
        for index, tab in ipairs({ { key = "msuf", label = "MSUF" }, { key = "suite", label = "MSUF Suite" } }) do
            local tabKey = tab.key
            local button = T.Button(root, tab.label, tabWidth, 30)
            button:SetPoint("TOPLEFT", root, "TOPLEFT", 18 + (index - 1) * (tabWidth + 8), y)
            if T.CenterButtonLabel then T.CenterButtonLabel(button) end
            if source == tabKey and T.SkinPrimaryButton then T.SkinPrimaryButton(button) end
            button:SetScript("OnClick", function()
                if M.BlockCombatAction() then return end
                if M.changelogSource == tabKey then return end
                M.changelogSource = tabKey
                RebuildKeepingScroll()
                if type(M.MarkChangelogSeen) == "function" then M.MarkChangelogSeen(tabKey) end
            end)
        end
        y = y - 42
    end
    if source == "msuf" then
        AddText("Browse releases from 6.02 onward. Highlight links open the matching feature directly in the MSUF menu.",
            "GameFontHighlightSmall", T.colors.muted, 18, contentWidth, 18, "body")
    end

    if not data then
        AddText("No release notes bundled with this build.", "GameFontHighlight", T.colors.muted, 18, contentWidth, 10, "body")
        ctx:SetContentHeight(math.abs(y) + 36)
        return
    end

    local entries = data.entries
    local selectedField = source == "suite" and "suiteChangelogSelectedVersion" or "changelogSelectedVersion"
    local selectedVersion = tostring(M[selectedField] or data.currentVersion or entries[1].version or "")
    local selectedFound = false
    for i = 1, #entries do
        if tostring(entries[i].version or "") == selectedVersion then selectedFound = true; break end
    end
    if not selectedFound then selectedVersion = tostring(entries[1].version or "") end
    M[selectedField] = selectedVersion

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
                if M[selectedField] == targetVersion then return end
                M[selectedField] = targetVersion
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
                        local sectionTitle = source == "suite" and section.title == "Changes" and "Changelog" or section.title
                        AddText(sectionTitle or "", "GameFontNormal", isHighlights and T.colors.accent or T.colors.accent2,
                            34, contentWidth - 32, 8, "section")
                        for bulletIndex = 1, #section.bullets do
                            local text, link = BulletParts(section.bullets[bulletIndex])
                            local dot = PixelLayoutRegion(root:CreateTexture(nil, "ARTWORK"))
                            dot:SetSize(5, 5)
                            dot:SetPoint("TOPLEFT", root, "TOPLEFT", 44, y - 6)
                            local dotColor = isHighlights and T.colors.accent2 or T.colors.accent
                            dot:SetColorTexture(dotColor[1], dotColor[2], dotColor[3], 0.95)
                            if isHighlights and link then
                                AddLinkedText(text, link, 58, contentWidth - 56, 7)
                            else
                                AddText(text, "GameFontHighlightSmall", T.colors.text, 58, contentWidth - 56, 7, "body")
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

local function CurrentChangelogVersion(source)
    local data
    if source == "suite" then data = SuiteChangelogData() else data = ChangelogData() end
    if type(data) ~= "table" then return "" end
    local version = tostring(data.currentVersion or "")
    if version ~= "" then return version end
    local first = type(data.entries) == "table" and data.entries[1] or nil
    return type(first) == "table" and tostring(first.version or "") or ""
end

-- Account-wide on purpose: a profile switch must not resurrect release notes
-- the player has already read. Re-resolved on every call because profile repair
-- and a full reset replace the SavedVariables root (see MSUF_UpgradeHighlights).
local function SeenStore(create)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then
        if not create then return nil end
        gdb = {}
        _G.MSUF_GlobalDB = gdb
    end
    if type(gdb.global) ~= "table" then
        if not create then return nil end
        gdb.global = {}
    end
    return gdb.global
end

--- True while the bundled release has never been opened through the toolbar.
--- Drives the Blizzard NEW badge on the See New Features button.
function M.HasUnseenChangelog()
    local store = SeenStore(false)
    local msuf = CurrentChangelogVersion("msuf")
    local suite = CurrentChangelogVersion("suite")
    return (msuf ~= "" and tostring(store and store.seenChangelogVersion or "") ~= msuf)
        or (suite ~= "" and tostring(store and store.seenSuiteChangelogVersion or "") ~= suite)
end

local function HasUnseenSource(source)
    local version = CurrentChangelogVersion(source)
    if version == "" then return false end
    local store = SeenStore(false)
    local field = source == "suite" and "seenSuiteChangelogVersion" or "seenChangelogVersion"
    return tostring(store and store[field] or "") ~= version
end

function M.MarkChangelogSeen(source)
    source = source == "suite" and "suite" or "msuf"
    local version = CurrentChangelogVersion(source)
    if version == "" then return false end
    local store = SeenStore(true)
    if type(store) ~= "table" then return false end
    local field = source == "suite" and "seenSuiteChangelogVersion" or "seenChangelogVersion"
    if tostring(store[field] or "") == version then return false end
    store[field] = version
    if type(M.RefreshSeeNewFeaturesBadge) == "function" then M.RefreshSeeNewFeaturesBadge() end
    return true
end

function M.OpenSeeNewFeatures()
    if M.BlockCombatAction() then return false end
    local source = HasUnseenSource("msuf") and "msuf"
        or HasUnseenSource("suite") and "suite"
        or (M.changelogSource == "suite" and SuiteChangelogData() and "suite") or "msuf"
    M.changelogSource = source
    local data = source == "suite" and SuiteChangelogData() or ChangelogData()
    if data and data.currentVersion then
        M[source == "suite" and "suiteChangelogSelectedVersion" or "changelogSelectedVersion"] = tostring(data.currentVersion)
    end
    M.InvalidatePage("changelog")
    if M.SelectPage("changelog") then
        M.MarkChangelogSeen(source)
        return true
    end
    return false
end

-- One cached view per notes source and selected release: picking a release
-- again shows the view built for it instead of a new frame tree (review C5.2).
local CHANGELOG_VIEWS = { msuf = {}, suite = {} }
local function ChangelogViewKey()
    local source = M.changelogSource == "suite" and "suite" or "msuf"
    local selected = M[source == "suite" and "suiteChangelogSelectedVersion" or "changelogSelectedVersion"]
    if selected == nil then return source end
    local views = CHANGELOG_VIEWS[source]
    local view = views[selected]
    if not view then
        view = source .. "|" .. tostring(selected)
        views[selected] = view
    end
    return view
end
M.RegisterPage("changelog", { title = "See New Features", build = BuildFullChangelog, version = 1, variantKey = ChangelogViewKey })
