-- AdvancedColors: Host responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AdvancedColorsParts
local ApiCall = Parts.ApiCall
local ApiRGB = Parts.ApiRGB
local ApiSetRGB = Parts.ApiSetRGB
local ApplyAuraColors = Parts.ApplyAuraColors
local ApplyBossTargetHighlightColor = Parts.ApplyBossTargetHighlightColor
local ApplyCastbarColors = Parts.ApplyCastbarColors
local ApplyColors = Parts.ApplyColors
local ApplyGameplayColors = Parts.ApplyGameplayColors
local ApplyGlobalOutlineColor = Parts.ApplyGlobalOutlineColor
local ApplyScopedBarGradientColors = Parts.ApplyScopedBarGradientColors
local ApplyUnitframeColorWithReload = Parts.ApplyUnitframeColorWithReload
local Build = Parts.Build
local ButtonAt = Parts.ButtonAt
local COLOR_DATA = Parts.COLOR_DATA
local COLOR_PAINTER_CATEGORIES = Parts.COLOR_PAINTER_CATEGORIES
local CP = Parts.CP
local C_Timer = Parts.C_Timer
local ClassColorRGB = Parts.ClassColorRGB
local ClassDefaultRGB = Parts.ClassDefaultRGB
local ColorAPI = Parts.ColorAPI
local ColorValueAt = Parts.ColorValueAt
local CurrentApplyService = Parts.CurrentApplyService
local GeneralRGB = Parts.GeneralRGB
local GeneralRGBAlias = Parts.GeneralRGBAlias
local HighlightRGB = Parts.HighlightRGB
local PixelLayoutRegion = Parts.PixelLayoutRegion
local RequestGeneral = Parts.RequestGeneral
local SetAllPortraitRGB = Parts.SetAllPortraitRGB
local SetGeneralRGB = Parts.SetGeneralRGB
local SetGeneralRGBAlias = Parts.SetGeneralRGBAlias
local SetHighlightRGB = Parts.SetHighlightRGB
local SetTableRGB = Parts.SetTableRGB
local TableRGB = Parts.TableRGB
local W = Parts.W
local max = Parts.max

local function BuildColorPainter(ctx, b)
    local painter = M.ColorPainter
    if not (painter and type(painter.Build) == "function") then return end
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local _, state = painter.Build(ctx, b, COLOR_PAINTER_CATEGORIES)
    return state
end

-- One taxonomy: the painter tabs above decide which category of sections is
-- visible below the preview. Every legacy section id survives unchanged inside
-- its category, so search keywords, Search metadata and cross-page focus
-- requests keep working. Categories build lazily on first activation; hidden
-- (coverage/audit) builds materialize everything, matching the old groups.
local COLOR_CATEGORY_ORDER = { "unit", "group", "cast", "auras", "resources", "accessibility" }
COLOR_PAINTER_CATEGORIES[#COLOR_PAINTER_CATEGORIES + 1] = {
    key = "accessibility", title = "Color vision accessibility", shortTitle = "Color preset",
    subtitle = "Review accessibility changes", scopes = {},
}
local COLOR_CATEGORY_SECTIONS = {
    accessibility = { "workbench_accessibility" },
    unit = { "colors_appearance", "colors_bar_colors", "colors_bar_gradients", "colors_background",
        "colors_font", "colors_classes", "colors_unit", "colors_npc_type", "colors_highlight",
        "colors_texture_layer", "colors_gameplay", "colors_portrait", "colors_status_text" },
    group = { "colors_group_frames", "colors_group_frames_background", "colors_group_frames_state",
        "colors_group_frames_highlights", "colors_group_frames_healer_mana" },
    cast = { "colors_castbar", "colors_castbar_text" },
    auras = { "colors_auras" },
    resources = { "colors_power", "colors_class_power", "colors_resource_extras", "colors_resource_marks" },
}
local COLOR_SECTION_CATEGORY = {}
for categoryKey, sectionIds in pairs(COLOR_CATEGORY_SECTIONS) do
    for i = 1, #sectionIds do COLOR_SECTION_CATEGORY[sectionIds[i]] = categoryKey end
end

-- A category builder may return a continuation function (which may return
-- another one): EnsureCategoryBuilt runs the first slice synchronously and the
-- continuations on following short ticks. The unit category is the default
-- Colors entry view and was the single largest chunk of the entry frame; its
-- later stages hold only default-collapsed sections, so they can fill in
-- below the visible content without moving anything the user already sees.
local COLOR_CATEGORY_BUILDERS = {
    accessibility = function(ctx, inner) M.ProfileWorkbenchUI.Colors(ctx, inner) end,
    unit = function(ctx, inner)
        Build.Appearance(ctx, inner)
        Build.BarColors(ctx, inner)
        Build.BarGradients(ctx, inner)
        return function()
            Build.Background(ctx, inner)
            Build.Font(ctx, inner)
            Build.StatusText(ctx, inner)
            Build.Classes(ctx, inner)
            return function()
                Build.Unit(ctx, inner)
                Build.Highlight(ctx, inner)
                Build.Gameplay(ctx, inner)
                Build.Portrait(ctx, inner)
            end
        end
    end,
    group = function(ctx, inner)
        CP.BuildGroupFrameColors(ctx, inner)
    end,
    cast = Build.Castbar,
    auras = Build.Aura,
    resources = function(ctx, inner)
        CP.BuildPowerAndClassPowerColors(ctx, inner, { ButtonAt = ButtonAt })
    end,
}

local function PendingColorFocusCategory(ctx)
    local request = MSUF.PublicGlobals.MSUF_EM2_MenuFocusRequest
    if type(request) ~= "table" or request.explicit ~= true or request.consumed == true then return nil end
    if request.pageKey and tostring(request.pageKey) ~= tostring(ctx and ctx.key or "") then return nil end
    return COLOR_SECTION_CATEGORY[tostring(request.sectionId or "")]
end

-- The category host is one frame under the painter tabs that holds a lazily built
-- container per category; H carries the page build state the steps share.
local Host = {}
-- The Suite category exists only while the Suite addon offers Colors sections.
function Host.RegisterSuite()
    local suiteLink = MSUF.SuiteLink
    if not suiteLink.HasColorsCategory() or COLOR_CATEGORY_BUILDERS.suite then return end
    COLOR_PAINTER_CATEGORIES[#COLOR_PAINTER_CATEGORIES + 1] = {
        key = "suite", title = "UI Suite", shortTitle = "Suite",
        subtitle = "Minimap, action bars, damage meter and skin colors.",
        pickerNote = "Suite modules and their shared skin palette.",
    }
    COLOR_CATEGORY_ORDER[#COLOR_CATEGORY_ORDER + 1] = "suite"
    COLOR_CATEGORY_SECTIONS.suite = {
        "colors_suite_minimap", "colors_suite_actionbars", "colors_suite_damageMeter", "colors_suite_skin",
    }
    for _, sectionId in ipairs(COLOR_CATEGORY_SECTIONS.suite) do COLOR_SECTION_CATEGORY[sectionId] = "suite" end
    COLOR_CATEGORY_BUILDERS.suite = function(colorCtx, inner)
        suiteLink.BuildColorsCategory(colorCtx, inner)
    end
end
function Host.New(ctx, b)
    if not b._collapsibleStartY then b._collapsibleStartY = b.y end
    local frame = PixelLayoutRegion(CreateFrame("Frame", nil, b.parent))
    frame:SetSize(b.width, 1)
    frame:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    local entry = { kind = "section", frame = frame, height = 1, gap = 12 }
    b.layoutEntries[#b.layoutEntries + 1] = entry
    b.y = b.y - 1 - 12
    local categories = {}
    for i = 1, #COLOR_CATEGORY_ORDER do
        local categoryKey = COLOR_CATEGORY_ORDER[i]
        local container = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        container:SetHeight(1)
        container:Hide()
        categories[categoryKey] = { key = categoryKey, container = container, height = 1 }
    end
    return { ctx = ctx, b = b, frame = frame, entry = entry, categories = categories }
end
function Host.UpdateHeight(H, layoutOpts)
    local active = H.categories[H.activeKey]
    local height = max(1, tonumber(active and active.height) or 1)
    H.entry.height = height
    if H.frame:GetHeight() ~= height then H.frame:SetHeight(height) end
    H.b:RequestRelayoutCollapsibles(layoutOpts)
end
-- A live stage timer finishes the build on its own tick, so an activation
-- (the page show in the entry frame, painter refreshes) leaves the later
-- stages to it. A cancelled or refused timer (menu hidden, combat) resumes
-- one stage, as before; callers that need the sections now (paint, focus,
-- hidden builds) pass now and run every remaining stage.
function Host.Resume(category, now)
    local task = category.resumeTask
    if not now and type(task) == "table" and task.active == true then return end
    repeat
        local resume = category.resumeStage
        if not resume then return end
        category.resumeStage = nil
        resume()
    until not now
end
-- The painter's category switch, or a direct activation while it is not wired.
function Host.Select(H, categoryKey)
    if H.painter then
        H.painter.ShowCategory(categoryKey)
    else
        Host.Activate(H, categoryKey)
    end
end
function Host.Finish(H, build)
    build.category.built = true
    build.category.building = nil
    for i = 1, #build.inner.collapsibles do
        build.inner.collapsibles[i]._msuf2EnsureVisible = function() Host.Select(H, build.key) end
    end
end
-- A builder may return a continuation (which may return another one):
-- later stages run on short ticks so the entry frame only pays for the
-- first slice. Without a timer every stage runs inline, so tests and
-- degraded clients keep the old fully synchronous behavior.
function Host.RunStage(H, build, stage)
    local ctx, category, refreshers = H.ctx, build.category, build.refreshers
    local refreshStart = type(refreshers) == "table" and #refreshers or 0
    local wasBuilding = ctx and ctx._msuf2Building
    if ctx then ctx._msuf2Building = true end
    local entry = ctx.entry
    local wasIncomplete = entry._msuf2BuildIncomplete
    entry._msuf2BuildIncomplete = true
    local nextStage = stage(ctx, build.inner)
    entry._msuf2BuildIncomplete = wasIncomplete
    if ctx then ctx._msuf2Building = wasBuilding end

    build.inner:RelayoutCollapsibles()
    if not wasBuilding and type(refreshers) == "table" then
        for i = refreshStart + 1, #refreshers do
            local refresh = refreshers[i]
            if type(refresh) == "function" then refresh() end
        end
        -- The current outer relayout reads the updated host height after
        -- this callback, so its pending marker has already been satisfied.
        H.b._msuf2RelayoutPending = nil
    end
    if type(nextStage) == "function" then
        if C_Timer and type(C_Timer.After) == "function" then
            -- Combat quiescence may cancel the tracked timer; the
            -- resume hook lets the next Host.Ensure call pick
            -- the build back up instead of leaving it half-finished.
            category.resumeStage = function() Host.RunStage(H, build, nextStage) end
            category.resumeTask = C_Timer.After(0.02, function()
                if H.categories[build.key] ~= category or category.resumeStage == nil then return end
                category.resumeStage = nil
                Host.RunStage(H, build, nextStage)
            end)
            return
        end
        return Host.RunStage(H, build, nextStage)
    end
    Host.Finish(H, build)
end
function Host.Ensure(H, categoryKey, now)
    local category = H.categories[categoryKey]
    if not category or category.built then return category end
    if category.building then
        Host.Resume(category, now)
        return category
    end
    category.building = true
    category.container._msuf2ExactTabView = {
        kind = "colorsPainterCategory", value = categoryKey,
        select = function()
            Host.Select(H, categoryKey)
        end,
    }
    local ctx = H.ctx
    local refreshers = ctx and ctx.refreshers
    local inner = W.PageBuilder(ctx, {
        parent = category.container,
        width = H.b.width,
        contentX = 0,
        topInset = 0,
        onContentHeight = function(height, layoutOpts)
            height = max(1, tonumber(height) or 1)
            if category.height == height then return end
            category.height = height
            if H.activeKey == categoryKey then Host.UpdateHeight(H, layoutOpts) end
        end,
    })
    Host.RunStage(H, { category = category, key = categoryKey, inner = inner, refreshers = refreshers },
        COLOR_CATEGORY_BUILDERS[categoryKey])
    if now then Host.Resume(category, true) end
    return category
end
function Host.Activate(H, categoryKey)
    if not H.categories[categoryKey] then categoryKey = COLOR_CATEGORY_ORDER[1] end
    Host.Ensure(H, categoryKey)
    H.activeKey = categoryKey
    -- Cached page/search/pin lifecycles can leave a locally hidden active
    -- container behind.  Reconcile every time, including same-category
    -- activation, instead of relying on the key having changed.
    if H.frame.Show then H.frame:Show() end
    for key, category in pairs(H.categories) do
        category.container:SetShown(key == categoryKey)
    end
    Host.UpdateHeight(H)
end

local function BuildColors(ctx)
    Host.RegisterSuite()
    if ctx and ctx.wrapper then ctx.wrapper._msuf2SuppressContextColorShortcuts = true end
    local b = W.PageBuilder(ctx)
    -- Painter callbacks from a previous build of this page must never fire
    -- into stale closures while this build is in progress.
    M.ColorsOnPainterCategory = nil
    M.ColorsSetPainterCategory = nil
    M.ColorsEnsureCategoryBuilt = nil
    if ctx and ctx.entry then ctx.entry._msuf2HealthBackgroundInlinePreviewRefresh = nil end
    b:GlobalStyleHeader("Colors", "Frame, group-frame, bar, aura, castbar and resource colors.", 72)
    local painter = BuildColorPainter(ctx, b)

    local H = Host.New(ctx, b)
    H.painter = painter
    local function ActivateCategory(categoryKey) Host.Activate(H, categoryKey) end
    local function EnsureCategory(sectionId)
        local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
        if categoryKey then Host.Ensure(H, categoryKey, true) end
    end
    if painter then painter.OnCategory = ActivateCategory end
    -- Normal and maximized pages are cached separately. External color/search
    -- entry points must follow the visible entry each time either returns.
    local function BindColorPage()
        M.ColorsOnPainterCategory = ActivateCategory
        M.ColorsSetPainterCategory = painter and painter.ShowCategory
        M.ColorsEnsureCategoryBuilt = EnsureCategory
    end
    BindColorPage()
    ctx.wrapper:HookScript("OnShow", BindColorPage)
    M.TrackRefresh(ctx, BindColorPage)
    if ctx.entry then
        ctx.entry._msuf2ResolveMissingSection = function(sectionId)
            local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
            if not categoryKey then return nil end
            Host.Select(H, categoryKey)
            Host.Ensure(H, categoryKey, true)
            local sections = ctx.entry.sections
            return sections and sections[tostring(sectionId)]
        end
    end
    if ctx.hiddenBuild then
        for i = 1, #COLOR_CATEGORY_ORDER do Host.Ensure(H, COLOR_CATEGORY_ORDER[i], true) end
    end
    local initialKey = PendingColorFocusCategory(ctx)
    if not initialKey then
        local persisted = M.colorsPainterCategory
        initialKey = H.categories[persisted] and persisted or COLOR_CATEGORY_ORDER[1]
    end
    -- The painter's ShowCategory ends in ActivateCategory itself.
    Host.Select(H, initialKey)
    b:RelayoutCollapsibles()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 23 })
-- Helpers the sibling files (Group, Resources, Context) pick from M.ColorsPage
-- when they load right after this page.
CP.CurrentApplyService = CurrentApplyService
CP.RequestGeneral = RequestGeneral
CP.ApplyColors = ApplyColors
CP.ApplyUnitframeColorWithReload = ApplyUnitframeColorWithReload
CP.ApplyCastbarColors = ApplyCastbarColors
CP.ApplyBossTargetHighlightColor = ApplyBossTargetHighlightColor
CP.ApplyGameplayColors = ApplyGameplayColors
CP.ApplyAuraColors = ApplyAuraColors
CP.ApplyScopedBarGradientColors = ApplyScopedBarGradientColors
CP.ApplyGlobalOutlineColor = ApplyGlobalOutlineColor
CP.ColorAPI = ColorAPI
CP.ApiCall = ApiCall
CP.ApiRGB = ApiRGB
CP.ApiSetRGB = ApiSetRGB
CP.GeneralRGB = GeneralRGB
CP.SetGeneralRGB = SetGeneralRGB
CP.GeneralRGBAlias = GeneralRGBAlias
CP.SetGeneralRGBAlias = SetGeneralRGBAlias
CP.TableRGB = TableRGB
CP.SetTableRGB = SetTableRGB
CP.HighlightRGB = HighlightRGB
CP.SetHighlightRGB = SetHighlightRGB
CP.ColorValueAt = ColorValueAt
CP.ClassDefaultRGB = ClassDefaultRGB
CP.ClassColorRGB = ClassColorRGB
CP.SetAllPortraitRGB = SetAllPortraitRGB
CP.COLOR_DATA = COLOR_DATA
CP.COLOR_POWER_TOKENS = COLOR_DATA.POWER_TOKENS
CP.COLOR_CP_TOKENS = COLOR_DATA.CP_TOKENS
CP.COLOR_PAINTER_CATEGORIES = COLOR_PAINTER_CATEGORIES

-- Explicit load-time exports for the following responsibility modules.
