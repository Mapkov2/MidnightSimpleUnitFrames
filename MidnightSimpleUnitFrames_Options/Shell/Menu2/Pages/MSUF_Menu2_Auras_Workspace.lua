-- Auras: Workspace responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AurasParts
if not Parts then return end
local AuraCatalogToken = Parts.AuraCatalogToken
local ActionButton = Parts.ActionButton
local AddTooltip = Parts.AddTooltip
local AurasPage = Parts.AurasPage
local BuildAuraStyleLanePage = Parts.BuildAuraStyleLanePage
local BuildAuraStylePage = Parts.BuildAuraStylePage
local BuildCompactUnitAuraBlacklist = Parts.BuildCompactUnitAuraBlacklist
local BuildCompactUnitAuraFilters = Parts.BuildCompactUnitAuraFilters
local BuildCompactUnitAuraLayout = Parts.BuildCompactUnitAuraLayout
local BuildUnitOrdering = Parts.BuildUnitOrdering
local BuildUnitStyle = Parts.BuildUnitStyle
local CreateNestedAuraBuilder = Parts.CreateNestedAuraBuilder
local CurrentAuraStyleContainer = Parts.CurrentAuraStyleContainer
local CurrentUnitAuraTab = Parts.CurrentUnitAuraTab
local CurrentUnitAuraTool = Parts.CurrentUnitAuraTool
local FinishPage = Parts.FinishPage
local Model = Parts.Model
local Rebuild = Parts.Rebuild
local RegisterAuraChoiceBar = Parts.RegisterAuraChoiceBar
local RegisterAuraControl = Parts.RegisterAuraControl
local RequestUFPreviewRefresh = Parts.RequestUFPreviewRefresh
local SelectPage = Parts.SelectPage
local SelectUnitWorkspaceLanes = Parts.SelectUnitWorkspaceLanes
local SetCurrentLane = Parts.SetCurrentLane
local SetUnitAuraTool = Parts.SetUnitAuraTool
local T = Parts.T
local Tr = Parts.Tr
local UNIT_AURA_CUSTOM_TOOLS = Parts.UNIT_AURA_CUSTOM_TOOLS
local UNIT_AURA_DISPEL_WARNING = Parts.UNIT_AURA_DISPEL_WARNING
local UNIT_AURA_NORMAL_TOOLS = Parts.UNIT_AURA_NORMAL_TOOLS
local UNIT_AURA_TARGET_DOT_TOOLS = Parts.UNIT_AURA_TARGET_DOT_TOOLS
local UNIT_AURA_WORKSPACE_TABS = Parts.UNIT_AURA_WORKSPACE_TABS
local UNIT_AURA_WORKSPACE_TABS_PET = Parts.UNIT_AURA_WORKSPACE_TABS_PET
local UnitAuraSensorEnabled = Parts.UnitAuraSensorEnabled
local UnitDispelRequested = Parts.UnitDispelRequested
local W = Parts.W
local abs = Parts.abs
local max = Parts.max
local min = Parts.min
local pairs = Parts.pairs
local tonumber = Parts.tonumber
local tostring = Parts.tostring
local type = Parts.type

local function UnitCustomContainerContract(unit)
    local customContainerPatterns = {}
    for i = 1, #M._customContainerSearchSuffixes do
        local suffix = M._customContainerSearchSuffixes[i]
        customContainerPatterns[i] = "^auras3%." .. tostring(unit):gsub("([^%w])", "%%%1") .. "%.custom%d+%."
            .. tostring(suffix):gsub("([^%w])", "%%%1") .. "$"
    end
    return {
        searchSettingKeyPatterns = customContainerPatterns,
    }
end
-- prepareValue -> { tab, tool, representative settingKey }. Changelog
-- highlights and search deep-links use these to open the exact
-- workspace view instead of flashing an unrelated control.
local function AttachUnitWorkspaceExactViews(containerBar, unit)
    local exactKind = "unitAuraWorkspace"
    local exactViews = {
        buff_layout = { tab = "buff", tool = "layout",
            settingKey = "auras3." .. tostring(unit) .. ".buff.visible" },
        custom1_reminder = { tab = "custom1", tool = "setup",
            settingKey = "auras3." .. tostring(unit) .. ".custom1.placed.reminderEnabled" },
    }
    if unit ~= "player" then
        exactViews.custom4_behavior = { tab = "custom4", tool = "behavior",
            settingKey = "auras3." .. tostring(unit) .. ".custom4.placed.sortMethod" }
        exactViews.debuff_blacklist = { tab = "debuff", tool = "blacklist",
            settingKey = "auras3." .. tostring(unit) .. ".debuff.blacklist.hidePermanent" }
    end
    local exactContracts = {}
    for value, view in pairs(exactViews) do exactContracts[value] = view.settingKey end
    containerBar._msuf2ExactTargetKinds = { [exactKind] = true }
    containerBar._msuf2ExactTargetContracts = {
        [exactKind] = exactContracts,
    }
    containerBar._msuf2PrepareExactSearchTarget = function(_, exactTarget)
        if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= exactKind then
            return false
        end
        local view = exactViews[tostring(exactTarget.prepareValue or "")]
        if not view then return false end
        local alreadySelected = M.unitAuraTabSelection[unit] == view.tab
            and CurrentUnitAuraTool(unit, view.tab) == view.tool
        if not alreadySelected then
            M.unitAuraTabSelection[unit] = view.tab
            SetUnitAuraTool(unit, view.tab, view.tool)
        end
        return true
    end
end
-- The workspace footer: the way to the global Aura Appearance and the hint,
-- which warns while Dispel needs this frame's disabled Aura sensor.
local function BuildUnitWorkspaceFooter(ctx, top, unit, currentTab, normalLane, footerY, sectionW)
    local openStyle = ActionButton(top, "Global Aura Appearance", 170, "normal")
    openStyle:SetPoint("TOPRIGHT", top, "TOPRIGHT", -16, footerY)
    openStyle:SetScript("OnClick", function()
        local previewContainer = currentTab == "custom4"
            and (unit == "player" and "playerDefensives" or "targetDots")
            or currentTab
        M.SetMenuStateValue("auraAppearanceContainer", previewContainer)
        if normalLane then SetCurrentLane("auraStyleGFLane", currentTab) end
        SelectPage("auras3_styling")
    end)
    RegisterAuraControl(ctx, openStyle, "Global Aura Appearance", "button", "unit-workspace.open-aura-style", "navigation", "auras3_styling")
    AddTooltip(openStyle, "Global Aura Appearance",
        "Opens the global Aura icon appearance: shape, border, shadow, colors and native Player weapon enchants. This frame's container Style stays here.")
    local workspaceHintText = M.Format("Aura Options, Ordering and Aura Style belong to this UnitFrame. Global icon appearance: %s.",
        M.NavPath("auras3_styling"))
    local workspaceHint = W.Text(top, workspaceHintText, 16, footerY - 8, sectionW - 198, T.colors.muted)
    M.TrackRefresh(ctx, function()
        T.SetTranslatedText(workspaceHint, normalLane and UnitDispelRequested(unit) and not UnitAuraSensorEnabled(unit)
            and Tr(UNIT_AURA_DISPEL_WARNING)
            or workspaceHintText)
    end)
end
-- The selected tool of a Buffs/Debuffs lane, or the Custom container workspace.
local function BuildUnitWorkspaceTool(ctx, auraBuilder, unit, currentTab, currentTool, normalLane)
    if normalLane then
        SelectUnitWorkspaceLanes(currentTab)
        if currentTool == "style" then
            BuildUnitStyle(ctx, auraBuilder, unit, { embeddedUnitPreview = true })
        elseif currentTool == "behavior" then
            BuildUnitOrdering(ctx, auraBuilder, unit, currentTab)
        elseif currentTool == "filters" then
            BuildCompactUnitAuraFilters(ctx, auraBuilder, unit, currentTab)
        elseif currentTool == "blacklist" then
            BuildCompactUnitAuraBlacklist(ctx, auraBuilder, unit, currentTab)
        else
            BuildCompactUnitAuraLayout(ctx, auraBuilder, unit, currentTab)
        end
    elseif type(M.BuildAuras3CompactCustomWorkspace) == "function" then
        M.BuildAuras3CompactCustomWorkspace(ctx, auraBuilder, unit, tonumber(currentTab:match("(%d)$")) or 1, currentTool)
    end
end
local function MeasureWorkspaceBar(values, width, centerY)
    return W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, {
        width = width,
        labelWidth = 72,
        centerY = centerY,
    })
end

local function BuildUnitAuraWorkspace(ctx, builder, unit)
    if not Model.UnitSupported(unit) then return end
    -- Custom container writes call this on every slider tick: one call, inline.
    ctx._auraAppearancePreviewRefresh = function(reason)
        local refreshOwnedPreview = ctx._msuf2RefreshUnitPreview
        if type(refreshOwnedPreview) == "function" then
            refreshOwnedPreview(reason or "AURAS3_UNIT_STYLE_DUMMY")
        else
            RequestUFPreviewRefresh("AURAS3_UNIT_STYLE_DUMMY")
        end
    end
    M.unitAuraTabSelection = M.unitAuraTabSelection or {}
    local workspaceTabs = unit == "player" and M._unitAuraWorkspaceTabsPlayer
        or (unit == "pet" and UNIT_AURA_WORKSPACE_TABS_PET or UNIT_AURA_WORKSPACE_TABS)
    local function CurrentTab() return CurrentUnitAuraTab(unit) end
    local currentTab = CurrentTab()
    local normalLane = currentTab == "buff" or currentTab == "debuff"
    local currentTool = CurrentUnitAuraTool(unit, currentTab)
    M.AuraControls.ConfigureSearchView(ctx, "unitAuraWorkspace", currentTab .. "_" .. currentTool)
    local customContainerContract = UnitCustomContainerContract(unit)
    local outer = AurasPage.Section(builder, "auras", "Auras", 120, false)
    local auraBuilder = CreateNestedAuraBuilder(ctx, builder, outer)
    ctx:TrackPageAreaContentLayout(auraBuilder)
    local sectionW = auraBuilder.width or 720
    local tools = normalLane and UNIT_AURA_NORMAL_TOOLS
        or (currentTab == "custom4"
            and (unit == "player" and M._unitAuraPlayerDefensiveTools or UNIT_AURA_TARGET_DOT_TOOLS)
            or UNIT_AURA_CUSTOM_TOOLS)
    local containerCenterY = -28
    local containerMetrics = MeasureWorkspaceBar(workspaceTabs, sectionW, containerCenterY)
    local toolCenterY = min(-62, ((containerMetrics and containerMetrics.bottomY) or -40) - 22)
    local toolMetrics = MeasureWorkspaceBar(tools, sectionW, toolCenterY)
    local footerY = ((toolMetrics and toolMetrics.bottomY) or (toolCenterY - 12)) - 2
    local top = auraBuilder:Section("", max(104, abs(footerY) + 28))
    if top.title then top.title:Hide() end
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, top, "Aura container and tools", "unit_aura_tools")
    end
    local containerBar = RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = workspaceTabs,
        width = sectionW,
        label = "Container:",
        labelWidth = 72,
        centerY = containerCenterY,
        getValue = CurrentTab,
        setValue = function(value)
            M.unitAuraTabSelection[unit] = value
            SelectUnitWorkspaceLanes(CurrentTab())
            Rebuild(ctx)
        end,
    }), workspaceTabs, "unit-workspace.container-selector", customContainerContract)
    if containerBar then AttachUnitWorkspaceExactViews(containerBar, unit) end
    RegisterAuraChoiceBar(ctx, W.ScopeOverrideBar(ctx, top, {
        values = tools,
        width = sectionW,
        label = "Edit:",
        labelWidth = 72,
        centerY = toolCenterY,
        getValue = function() return CurrentUnitAuraTool(unit, currentTab) end,
        setValue = function(value)
            SetUnitAuraTool(unit, currentTab, value)
            SelectUnitWorkspaceLanes(currentTab)
            Rebuild(ctx)
        end,
    }), tools, "unit-workspace.tool-selector")
    BuildUnitWorkspaceFooter(ctx, top, unit, currentTab, normalLane, footerY, sectionW)

    BuildUnitWorkspaceTool(ctx, auraBuilder, unit, currentTab, currentTool, normalLane)
    M.ProfileWorkbenchUI.Aura(ctx, auraBuilder, unit, currentTab)
end
function M.BuildAuras3UnitSection(ctx, builder, unit, sectionUX)
    if not Model.UnitSupported(unit) then return end
    return M.BuildPageArea(ctx, builder, unit, {
        id = "auras", selector = M.UnitAuraWorkspaceView, values = Parts.UnitAuraWorkspaceValues(unit),
        build = BuildUnitAuraWorkspace, sectionUX = sectionUX,
    })
end
local function BuildMovedAuraPage(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Aura Controls moved to Frames",
        "Layout, filters, lists and every container-specific Style live in each frame. Frames > Auras owns only the global icon theme.", 96)
    local section = b:Section("Open a Frame", 190)
    local w = section._msuf2Width or b.width or 720
    local pages = {
        { "Player", "uf_player" }, { "Pet", "uf_pet" }, { "Target", "uf_target" }, { "Focus", "uf_focus" },
        { "Boss", "uf_boss" }, { "Group Frames", "gf_auras" },
    }
    local x = 24
    for i = 1, #pages do
        local page = pages[i]
        local button = ActionButton(section, page[1], i == #pages and 132 or 92)
        button:SetPoint("TOPLEFT", section, "TOPLEFT", x, -60)
        button:SetScript("OnClick", function() if M.SelectPage then M.SelectPage(page[2]) end end)
        RegisterAuraControl(ctx, button, page[1], "button", "moved-page.open." .. AuraCatalogToken(page[2]), "navigation", page[2])
        x = x + (i == #pages and 144 or 104)
    end
    W.Text(section, "Open the frame and expand Auras. Buffs and Debuffs contain their own layout, filters, blacklists and Style; Custom 1-3, Defensive Buffs "
        .. "and Dots on target expose controls appropriate to their content.", 24, -118, w - 48, T.colors.muted)
    FinishPage(ctx, b)
end

-- Old content/filter routes remain as compatibility landings. The Buff/Debuff
-- aliases open the matching global Appearance preview; individual Style stays on the
-- selected UnitFrame or GroupFrame page.
M.RegisterPage("auras3_buffs", { title = "Global Aura Appearance: Buffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "buff") end, version = 25 })
M.RegisterPage("auras3_debuffs", { title = "Global Aura Appearance: Debuffs", build = function(ctx) BuildAuraStyleLanePage(ctx, "debuff") end, version = 25 })
M.RegisterPage("auras3_custom", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 2 })
-- Each container is a declared view: the Aura type selector shows its cached
-- entry or builds it once (spec.variantKey).
M.RegisterPage("auras3_styling", { title = "Aura Style", build = BuildAuraStylePage, version = 53,
    variantKey = function() return CurrentAuraStyleContainer("appearance") end,
    viewStateKeys = { auraStyleContainer = true, auraAppearanceContainer = true, auraStyleGFLane = true } })
M.RegisterPage("auras3_filters", { title = "MSUF Auras", build = BuildMovedAuraPage, version = 31 })

M.AurasPage = AurasPage

-- Explicit load-time exports for the following responsibility modules.
