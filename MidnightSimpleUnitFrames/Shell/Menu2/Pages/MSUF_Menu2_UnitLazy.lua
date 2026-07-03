local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local UnitPage = M.UnitPage or {}
M.UnitPage = UnitPage

-- Lazy section registry for unit pages.
-- Lets large Unit page sections register themselves independently, then builds only the
-- sections supported by the current unit. This keeps Menu2 load/rebuild cost manageable.
UnitPage._sectionRegistry = UnitPage._sectionRegistry or {}
UnitPage._sectionIds = UnitPage._sectionIds or {}
local UNIT_SECTION_REGISTRY = UnitPage._sectionRegistry
local UNIT_SECTION_IDS = UnitPage._sectionIds
for i = 1, #UNIT_SECTION_REGISTRY do
    local item = UNIT_SECTION_REGISTRY[i]
    if item and item.id then UNIT_SECTION_IDS[item.id] = i end
end
local function UnitSectionSupportsUnit(spec, unit)
    if type(spec) ~= "table" then return false end
    local units = spec.units
    if units == nil then return true end
    if type(units) == "function" then return units(unit) and true or false end
    if type(units) == "table" then return units[unit] == true end
    return false
end
function UnitPage.RegisterSection(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.build) ~= "function" then return false end
    spec.order = tonumber(spec.order) or 100
    local index = UNIT_SECTION_IDS[spec.id]
    if index then
        UNIT_SECTION_REGISTRY[index] = spec
    else
        UNIT_SECTION_REGISTRY[#UNIT_SECTION_REGISTRY + 1] = spec
        UNIT_SECTION_IDS[spec.id] = #UNIT_SECTION_REGISTRY
    end
    table.sort(UNIT_SECTION_REGISTRY, function(a, b)
        local ao = tonumber(a and a.order) or 100
        local bo = tonumber(b and b.order) or 100
        if ao == bo then return tostring(a and a.id or "") < tostring(b and b.id or "") end
        return ao < bo
    end)
    for i = 1, #UNIT_SECTION_REGISTRY do
        local item = UNIT_SECTION_REGISTRY[i]
        if item and item.id then UNIT_SECTION_IDS[item.id] = i end
    end
    return true
end
local function ResolveLazyValue(value, ctx, builder, unit, spec)
    if type(value) == "function" then return value(ctx, builder, unit, spec) end
    return value
end
local function ResolveLazyMeta(ctx, builder, unit, spec)
    local sectionId = ResolveLazyValue(spec.sectionId or spec.id, ctx, builder, unit, spec)
    local title = ResolveLazyValue(spec.title, ctx, builder, unit, spec)
    local height = ResolveLazyValue(spec.height, ctx, builder, unit, spec)
    if type(sectionId) ~= "string" or sectionId == "" then return nil end
    if type(title) ~= "string" or title == "" then return nil end
    height = tonumber(height)
    if not height then
        -- autoHeight sections declare no height: the shell gets a provisional
        -- one and the build fn corrects it via builder:FinishSection.
        if spec.autoHeight ~= true then return nil end
        height = 120
    end
    return sectionId, title, height, ResolveLazyValue(spec.defaultOpen, ctx, builder, unit, spec) == true
end
local function BuildRegisteredSectionLazy(ctx, builder, unit, spec)
    if ctx and ctx.entry and ctx.entry.hiddenBuild then return spec.build(ctx, builder, unit, spec) end
    local sectionId, title, height, defaultOpen = ResolveLazyMeta(ctx, builder, unit, spec)
    if not sectionId then return spec.build(ctx, builder, unit, spec) end
    local shellBody = builder:CollapsibleSection(sectionId, title, height, defaultOpen)
    local shellEntry = shellBody and shellBody._msuf2CollapsibleEntry
    local shellRefresh
    local built = false
    local building = false
    local LazyRefresh
    local function RefreshNewControls(fromIndex)
        local refreshers = ctx and ctx.refreshers
        if type(refreshers) ~= "table" then return end
        fromIndex = tonumber(fromIndex) or #refreshers
        for i = fromIndex + 1, #refreshers do
            local fn = refreshers[i]
            if type(fn) == "function" then fn() end
        end
    end
    local function BuildContent()
        if built or building or not shellBody then return end
        building = true
        local proxy = setmetatable({}, { __index = builder })
        function proxy:CollapsibleSection()
            return shellBody
        end
        local refreshStart = ctx and ctx.refreshers and #ctx.refreshers or 0
        spec.build(ctx, proxy, unit, spec)
        building = false
        built = true
        if shellEntry then
            RefreshNewControls(refreshStart)
            local refresh = shellEntry._msuf2RefreshState
            if type(refresh) == "function" and refresh ~= LazyRefresh then refresh(shellEntry) end
            local relayout = shellEntry.builder
            if shellEntry.open and relayout and relayout.RelayoutCollapsibles then
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        if shellEntry.open and relayout.RelayoutCollapsibles then relayout:RelayoutCollapsibles() end
                    end)
                else
                    relayout:RelayoutCollapsibles()
                end
            end
        end
    end
    LazyRefresh = function(entryArg)
        local builtNow = false
        if shellEntry and shellEntry.open and not built then
            BuildContent()
            builtNow = true
        end
        local current = shellEntry and shellEntry._msuf2RefreshState
        if current and current ~= LazyRefresh and not builtNow then return current(entryArg or shellEntry) end
        if shellRefresh and not builtNow then return shellRefresh(entryArg or shellEntry) end
    end
    if shellEntry and type(spec.prepareShell) == "function" then
        local refresh = spec.prepareShell(ctx, shellBody, unit, spec)
        if type(refresh) == "function" then shellRefresh = refresh end
    end
    if not shellEntry or shellEntry.open then
        BuildContent()
    else
        shellEntry._msuf2RefreshState = LazyRefresh
    end
    return true
end
function UnitPage.BuildSectionLazy(ctx, builder, unit, spec)
    if type(spec) ~= "table" or type(spec.build) ~= "function" then return false end
    return BuildRegisteredSectionLazy(ctx, builder, unit, spec)
end
function UnitPage.BuildRegisteredSections(ctx, builder, unit, placement)
    for i = 1, #UNIT_SECTION_REGISTRY do
        local spec = UNIT_SECTION_REGISTRY[i]
        if spec
            and spec.placement == placement
            and UnitSectionSupportsUnit(spec, unit)
        then
            if spec.lazy ~= false then
                BuildRegisteredSectionLazy(ctx, builder, unit, spec)
            else
                spec.build(ctx, builder, unit, spec)
            end
        end
    end
end
UnitPage.UnitSectionSupportsUnit = UnitSectionSupportsUnit
