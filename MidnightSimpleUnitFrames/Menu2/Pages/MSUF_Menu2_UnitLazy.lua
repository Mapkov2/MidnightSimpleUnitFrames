local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local UnitPage = M.UnitPage or {}
M.UnitPage = UnitPage

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

local LAZY_SECTION_ABORT = "__MSUF_UNIT_LAZY_SECTION_ABORT__"

local function BuildRegisteredSectionLazy(ctx, builder, unit, spec)
    if ctx and ctx.entry and ctx.entry.hiddenBuild then
        return spec.build(ctx, builder, unit, spec)
    end

    local shellBody, shellEntry
    local built = false
    local building = false
    local LazyRefresh

    local function RefreshNewControls(fromIndex)
        local refreshers = ctx and ctx.refreshers
        if type(refreshers) ~= "table" then return end
        fromIndex = tonumber(fromIndex) or #refreshers
        for i = fromIndex + 1, #refreshers do
            local fn = refreshers[i]
            if type(fn) == "function" then pcall(fn) end
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
        local ok, err = pcall(spec.build, ctx, proxy, unit, spec)
        building = false
        if not ok and err ~= LAZY_SECTION_ABORT then
            built = false
            error(err)
        end
        built = true
        if ok and shellEntry then
            RefreshNewControls(refreshStart)
            local refresh = shellEntry._msuf2RefreshState
            if type(refresh) == "function" and refresh ~= LazyRefresh then
                pcall(refresh, shellEntry)
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
        if current and current ~= LazyRefresh and not builtNow then
            return pcall(current, entryArg or shellEntry)
        end
    end

    local proxy = setmetatable({}, { __index = builder })
    function proxy:CollapsibleSection(id, title, height, defaultOpen)
        shellBody = builder:CollapsibleSection(id, title, height, defaultOpen)
        shellEntry = shellBody and shellBody._msuf2CollapsibleEntry
        if not shellEntry or shellEntry.open then
            return shellBody
        end

        shellEntry._msuf2RefreshState = LazyRefresh
        error(LAZY_SECTION_ABORT, 0)
    end

    local refreshStart = ctx and ctx.refreshers and #ctx.refreshers or 0
    local ok, err = pcall(spec.build, ctx, proxy, unit, spec)
    if ok then RefreshNewControls(refreshStart) end
    if ok or err == LAZY_SECTION_ABORT then return true end
    error(err)
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
