local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local C_Timer = M.MenuTimer or _G.C_Timer
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
-- Hidden search-index page steps used to build every section synchronously,
-- which made each background index step a frame hitch. Each hidden section's
-- content now becomes one small queued slice instead. Combat postpones the
-- queue with zero in-combat work (resume rides a single PLAYER_REGEN_ENABLED
-- event), a replaced page entry drops its pending jobs, and environments
-- without a timer drain synchronously so tests keep seeing fully built
-- hidden pages.
local HIDDEN_SECTION_STEP_SEC = 0.2
local hiddenSectionQueue = {}
local hiddenSectionPumpScheduled = false
local hiddenQueueCombatFrame
local PumpHiddenSectionQueue
local function EnsureCombatResume()
    if hiddenQueueCombatFrame then return end
    local frame = _G.CreateFrame and _G.CreateFrame("Frame")
    if not frame then return end
    hiddenQueueCombatFrame = frame
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function()
        -- Combat quiescence may have cancelled a scheduled pump tick, which
        -- would leave the scheduled flag stuck; reset it so the drain chain
        -- restarts. A surviving tick alongside the restart only drains faster.
        hiddenSectionPumpScheduled = false
        PumpHiddenSectionQueue()
    end)
end
PumpHiddenSectionQueue = function()
    if #hiddenSectionQueue == 0 or hiddenSectionPumpScheduled then return end
    if not (C_Timer and C_Timer.After) then
        while #hiddenSectionQueue > 0 do
            local job = table.remove(hiddenSectionQueue, 1)
            job()
        end
        return
    end
    local inCombat = _G.InCombatLockdown
    if type(inCombat) == "function" and inCombat() then
        EnsureCombatResume()
        return
    end
    hiddenSectionPumpScheduled = true
    C_Timer.After(HIDDEN_SECTION_STEP_SEC, function()
        hiddenSectionPumpScheduled = false
        local combatCheck = _G.InCombatLockdown
        if type(combatCheck) == "function" and combatCheck() then
            EnsureCombatResume()
            return
        end
        local job = table.remove(hiddenSectionQueue, 1)
        if job then job() end
        PumpHiddenSectionQueue()
    end)
end
local function QueueHiddenSectionBuild(job)
    hiddenSectionQueue[#hiddenSectionQueue + 1] = job
    PumpHiddenSectionQueue()
end
-- Closed sections of visited pages also enqueue their content so search
-- coverage never depends on the user opening every section — but without an
-- immediate pump: the cold page frame must stay shell-only (asserted by
-- group_layout_cold_path_smoke), so these jobs only start draining once the
-- search surface actually pumps the queue.
local function QueueDeferredSectionBuild(job)
    hiddenSectionQueue[#hiddenSectionQueue + 1] = job
end
UnitPage.PumpBackgroundSections = function() PumpHiddenSectionQueue() end
local function BuildRegisteredSectionLazy(ctx, builder, unit, spec)
    local hidden = ctx and ctx.entry and ctx.entry.hiddenBuild and true or false
    local sectionId, title, height, defaultOpen = ResolveLazyMeta(ctx, builder, unit, spec)
    if not sectionId then return spec.build(ctx, builder, unit, spec) end
    local shellBody = builder:CollapsibleSection(sectionId, title, height, defaultOpen)
    local shellEntry = shellBody and shellBody._msuf2CollapsibleEntry
    local searchRouteOpen = false
    local pendingSearchSections = M._msuf2SearchRouteOpenSections
    if shellEntry and type(pendingSearchSections) == "table"
        and pendingSearchSections[shellEntry.stateKey] == true
    then
        searchRouteOpen = true
        pendingSearchSections[shellEntry.stateKey] = nil
    end
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
        -- Deferred builds run outside BuildPageEntry, where the search build
        -- key is no longer set; registrations must never fall back to
        -- whichever page happens to be active by the time the timer fires.
        local previousBuildKey = M._msuf2SearchBuildKey
        if ctx and ctx.key then M._msuf2SearchBuildKey = ctx.key end
        local buildOK, buildError = pcall(spec.build, ctx, proxy, unit, spec)
        M._msuf2SearchBuildKey = previousBuildKey
        building = false
        if not buildOK then error(buildError, 0) end
        built = true
        if shellEntry then
            RefreshNewControls(refreshStart)
            local refresh = shellEntry._msuf2RefreshState
            if type(refresh) == "function" and refresh ~= LazyRefresh then refresh(shellEntry) end
            local relayout = shellEntry.builder
            if shellEntry.open and relayout and relayout.RelayoutCollapsibles then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
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
    if hidden then
        -- Search-index builds need every section's controls, but not inside
        -- the indexer's synchronous page step: each section becomes one queued
        -- slice. A page entry that was replaced or invalidated in the meantime
        -- drops its pending job. prepareShell stays visible-only, matching the
        -- previous hidden-build behavior.
        if searchRouteOpen then
            BuildContent()
        else
            local queuedEntry = ctx.entry
            QueueHiddenSectionBuild(function()
                if M.cache and M.cache[ctx.key] ~= queuedEntry then return end
                BuildContent()
            end)
        end
        return true
    end
    if shellEntry and type(spec.prepareShell) == "function" then
        local refresh = spec.prepareShell(ctx, shellBody, unit, spec)
        if type(refresh) == "function" then shellRefresh = refresh end
    end
    if not shellEntry then
        BuildContent()
    elseif shellEntry.open then
        -- The shell already reserves the declared height, so an open section's
        -- content can build one frame later without moving layout — this keeps
        -- the section-heavy cold page builds out of a single frame. LazyRefresh
        -- stays installed as the correctness valve: any state refresh that
        -- fires earlier (search navigation, assistant flows, toggle handlers)
        -- still builds the content immediately, and environments without a
        -- timer keep building inline.
        shellEntry._msuf2RefreshState = LazyRefresh
        if searchRouteOpen then
            BuildContent()
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if built or building then return end
                if shellBody and shellBody.IsShown and not shellBody:IsShown() then return end
                BuildContent()
            end)
        else
            BuildContent()
        end
    else
        shellEntry._msuf2RefreshState = LazyRefresh
        -- Search must find controls in sections the user never opens: the
        -- content fills in from search-driven background slices. LazyRefresh
        -- stays the fast path — a user expand before the slice builds
        -- immediately, and the queued job then no-ops on the built check.
        local queuedEntry = ctx and ctx.entry
        QueueDeferredSectionBuild(function()
            if queuedEntry and M.cache and M.cache[ctx.key] ~= queuedEntry then return end
            BuildContent()
        end)
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
