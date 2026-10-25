-- Auras: Layout responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AurasParts
if not Parts then return end
local AURA_SORT_DIRECTION_VALUES = Parts.AURA_SORT_DIRECTION_VALUES
local AddTooltip = Parts.AddTooltip
local AppearanceThemeLane = Parts.AppearanceThemeLane
local ApplyService = Parts.ApplyService
local ApplyUnit = Parts.ApplyUnit
local AuraCatalogToken = Parts.AuraCatalogToken
local AuraControlMeta = Parts.AuraControlMeta
local AuraControlMetaAtVisiblePath = Parts.AuraControlMetaAtVisiblePath
local AuraSortMethodValues = Parts.AuraSortMethodValues
local AurasPage = Parts.AurasPage
local BindDropdown = Parts.BindDropdown
local BindSlider = Parts.BindSlider
local BindSwitch = Parts.BindSwitch
local BuildAuraStyleNav = Parts.BuildAuraStyleNav
local BuildUnitStyle = Parts.BuildUnitStyle
local ConfigureMaxDurationSlider = Parts.ConfigureMaxDurationSlider
local FinishPage = Parts.FinishPage
local GFAnchorValues = Parts.GFAnchorValues
local LaneDefaultMax = Parts.LaneDefaultMax
local LaneMaxKey = Parts.LaneMaxKey
local LaneSizeKey = Parts.LaneSizeKey
local Model = Parts.Model
local NormalizeAuraSortMethodForLane = Parts.NormalizeAuraSortMethodForLane
local QueueAurasPageRefresh = Parts.QueueAurasPageRefresh
local RequestUFPreviewRefresh = Parts.RequestUFPreviewRefresh
local SetCurrentLane = Parts.SetCurrentLane
local SetUnitLaneShown = Parts.SetUnitLaneShown
local Tr = Parts.Tr
local UnitLaneShown = Parts.UnitLaneShown
local VTP = Parts.VTP
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min
local pairs = Parts.pairs
local tostring = Parts.tostring
local type = Parts.type

local function BuildUnitOrdering(ctx, b, unit, lane)
    lane = lane == "debuff" and "debuff" or "buff"
    local section = b:Section("Ordering", 156)
    local width = section and (section._msuf2Width or section.GetWidth and section:GetWidth()) or b.width or 720
    local function OrderingSearchRouteMetadata(suffix)
        return {
            searchSettingKeys = { "auras3." .. tostring(unit) .. "." .. lane .. "." .. suffix },
        }
    end
    local function ReadSortMethod()
        local value = type(Model.ReadLaneStyleString) == "function"
            and Model.ReadLaneStyleString(unit, lane, "sortMethod", "DEFAULT") or "DEFAULT"
        return NormalizeAuraSortMethodForLane(lane, value)
    end
    local function ReadSortDirection()
        local reverse = false
        if type(Model.ReadLaneStyleBool) == "function" then
            reverse = Model.ReadLaneStyleBool(unit, lane, "sortReverse", false)
        elseif type(Model.ReadBool) == "function" then
            reverse = Model.ReadBool(unit, "sortReverse", false)
        end
        return reverse == true and "REVERSE" or "NORMAL"
    end
    local function ApplyOrdering(reason)
        ApplyUnit(ctx, unit, reason)
        ApplyService.Flush()
        local refreshOwnedPreview = ctx and ctx._msuf2RefreshUnitPreview
        if type(refreshOwnedPreview) == "function" then
            refreshOwnedPreview(reason)
        else
            RequestUFPreviewRefresh(reason)
        end
    end
    local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(lane), width - 48,
        ReadSortMethod,
        function(value)
            value = NormalizeAuraSortMethodForLane(lane, value)
            if type(Model.WriteLaneStyleString) == "function" then
                Model.WriteLaneStyleString(unit, lane, "sortMethod", value)
            end
            ApplyOrdering("AURAS3_SORT_METHOD")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken("AURAS3_SORT_METHOD"),
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-method",
            nil, OrderingSearchRouteMetadata("sortMethod")))
    AddTooltip(sortMethod, "Aura sorting", "Only relevant sorting methods are shown for buffs and debuffs.")
    local sortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, width - 48,
        ReadSortDirection,
        function(value)
            if type(Model.WriteLaneStyleBool) == "function" then
                Model.WriteLaneStyleBool(unit, lane, "sortReverse", value == "REVERSE")
            elseif type(Model.WriteBool) == "function" then
                Model.WriteBool(unit, "sortReverse", value == "REVERSE")
            end
            ApplyOrdering("AURAS3_SORT_DIRECTION")
        end,
        AuraControlMetaAtVisiblePath(ctx,
            "style.lane." .. AuraCatalogToken(lane) .. "." .. AuraCatalogToken("AURAS3_SORT_DIRECTION"),
            "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".ordering.sort-direction",
            nil, OrderingSearchRouteMetadata("sortReverse")))
    AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
end

local function BuildAuraStylePage(ctx)
    local b = W.PageBuilder(ctx)
    Model.EnsureDB()
    b:GlobalStyleHeader("Global Aura Appearance", "Global Appearance theme selected only by Aura type. All layout, filters, timers, text and effects stay "
        .. "scope-aware in the corresponding UnitFrame or GroupFrame.", 84)
    local container = BuildAuraStyleNav(ctx, b, "appearance")
    SetCurrentLane("auraStyleGFLane", AppearanceThemeLane(container))
    BuildUnitStyle(ctx, b, "appearance", {
        appearanceGlobalsOnly = true,
        previewContainer = container,
    })
    FinishPage(ctx, b)
end
local function BuildAuraStyleLanePage(ctx, lane)
    SetCurrentLane("auraStyleGFLane", lane)
    M.SetMenuStateValue("auraAppearanceContainer", lane)
    BuildAuraStylePage(ctx)
end
local function UniformChoiceWidths(values, width)
    for i = 1, #values do values[i].width = width end
    return values
end
local UNIT_AURA_CHOICE_WIDTH = 92
local UNIT_AURA_WORKSPACE_TABS = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Dots on target",
    UNIT_AURA_CHOICE_WIDTH)
M._unitAuraWorkspaceTabsPlayer = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3|custom4=Defensives",
    UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_WORKSPACE_TABS_PET = UniformChoiceWidths(VTP "buff=Buffs|debuff=Debuffs|custom1=Custom 1|custom2=Custom 2|custom3=Custom 3",
    UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOLS = UniformChoiceWidths(VTP "layout=Layout|behavior=Ordering|filters=Filters|blacklist=Blacklist|style=Style",
    UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_CUSTOM_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|whitelist=Whitelist|style=Style",
    UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_TARGET_DOT_TOOLS = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|dots=Dots|style=Style",
    UNIT_AURA_CHOICE_WIDTH)
M._unitAuraPlayerDefensiveTools = UniformChoiceWidths(VTP "setup=Setup|layout=Layout|behavior=Ordering|filters=Filters|defensives=Defensives|style=Style",
    UNIT_AURA_CHOICE_WIDTH)
local UNIT_AURA_NORMAL_TOOL_OK = { layout = true, behavior = true, filters = true, blacklist = true, style = true }
local UNIT_AURA_CUSTOM_TOOL_OK = { setup = true, behavior = true, whitelist = true, filters = true, layout = true, style = true }
local UNIT_AURA_TARGET_DOT_TOOL_OK = { setup = true, layout = true, behavior = true, filters = true, dots = true, style = true }
M._unitAuraPlayerDefensiveToolOK = { setup = true, layout = true, behavior = true, filters = true, defensives = true, style = true }

local function CurrentUnitAuraTool(unit, container)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then
        unitState = {}
        M.unitAuraToolSelection[unit] = unitState
    end
    local custom = tostring(container or ""):match("^custom") ~= nil
    local playerDefensives = unit == "player" and container == "custom4"
    local targetDots = unit ~= "player" and container == "custom4"
    local tool = unitState[container]
    local valid = playerDefensives and M._unitAuraPlayerDefensiveToolOK
        or (targetDots and UNIT_AURA_TARGET_DOT_TOOL_OK or (custom and UNIT_AURA_CUSTOM_TOOL_OK or UNIT_AURA_NORMAL_TOOL_OK))
    if not valid[tool] then
        tool = custom and "setup" or "layout"
        unitState[container] = tool
    end
    return tool
end

local function SetUnitAuraTool(unit, container, tool)
    M.unitAuraToolSelection = M.unitAuraToolSelection or {}
    local unitState = M.unitAuraToolSelection[unit]
    if type(unitState) ~= "table" then
        unitState = {}
        M.unitAuraToolSelection[unit] = unitState
    end
    unitState[container] = tool
end

local UNIT_AURA_TABS = { buff = true, debuff = true, custom1 = true, custom2 = true, custom3 = true, custom4 = true }
local function CurrentUnitAuraTab(unit)
    local tabs = M.unitAuraTabSelection
    local tab = tabs and tabs[unit] or "buff"
    if not UNIT_AURA_TABS[tab] or (unit == "pet" and tab == "custom4") then tab = "buff" end
    return tab
end
--- A normal lane tab also selects the lane the shared style and filter state
--- follow. The workspace sets it when it builds the tab and when a selector
--- shows that tab again, so a cached view leaves the same state as a build.
local function SelectUnitWorkspaceLanes(tab)
    if tab ~= "buff" and tab ~= "debuff" then return end
    SetCurrentLane("auraStyleGFLane", tab)
    SetCurrentLane("auraFilterLane", tab)
end
--- The unit page's aura workspace builds one container tab and one tool at a
--- time. Each pair is a declared view of the unit page (spec.variantKey): a
--- selector click shows that view's cached entry or builds it once.
local UNIT_AURA_VIEWS = {}
function M.UnitAuraWorkspaceView(unit)
    local tab = CurrentUnitAuraTab(unit)
    local tool = CurrentUnitAuraTool(unit, tab)
    local byTab = UNIT_AURA_VIEWS[tab]
    if not byTab then
        byTab = {}
        UNIT_AURA_VIEWS[tab] = byTab
    end
    local view = byTab[tool]
    if not view then
        view = tab .. ":" .. tool
        byTab[tool] = view
    end
    return view
end

local function BuildCompactUnitAuraLayout(ctx, b, unit, kind)
    local titleKey = kind == "debuff" and "Debuff Layout" or "Buff Layout"
    local title = Tr(titleKey)
    -- Stufe-1 pilot: this section renders through the uniform W.SettingsRows
    -- grid (fixed cell metrics, per-value reset) instead of hand-placed
    -- offsets. Control identities, setters and apply reasons are unchanged.
    local section = b:Section(titleKey, 208)
    M.AttachAuraFontsAndColors(section, title, unit)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local controls = {}
    local enable = BindSwitch(ctx, section, "Visible", 24, -62, 104,
        function() return UnitLaneShown(unit, kind) end,
        function(v) SetUnitLaneShown(ctx, unit, kind, v, "AURAS3_UNIT_PAGE_" .. (kind == "buff" and "BUFFS" or "DEBUFFS")) end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(kind) .. ".layout.visible", nil,
            "auras3." .. unit .. "." .. kind .. ".visible"))
    enable._msuf2GroupFrameGateAlwaysEnabled = true
    local function LaneMeta(row, pathSuffix)
        local meta = AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(kind) .. ".layout." .. pathSuffix)
        for key, value in pairs(meta) do
            if row[key] == nil then row[key] = value end
        end
        return row
    end
    local defaultAnchor = kind == "buff" and "BOTTOMRIGHT" or "TOPLEFT"
    local anchorRows = W.SettingsRows(ctx, section, {
        x = 24 + 126 + gap, y = -34, width = inner - 126 - gap, columns = 2, colGap = gap,
        rows = {
            LaneMeta({
                kind = "dropdown", label = "Anchor", id = "anchor",
                values = function()
                    return type(Model.AuraAnchorValues) == "function" and Model.AuraAnchorValues() or GFAnchorValues()
                end,
                get = function()
                    return type(Model.ReadLaneAnchor) == "function" and Model.ReadLaneAnchor(unit, kind) or defaultAnchor
                end,
                customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
                    if type(Model.WriteLaneAnchor) == "function" then
                        Model.WriteLaneAnchor(unit, kind, v)
                        ApplyUnit(ctx, unit, "AURAS3_UNIT_ANCHOR")
                    end
                end,
            }, "anchor"),
            LaneMeta({
                kind = "dropdown", label = "Growth", id = "growth",
                values = function()
                    return type(Model.LaneGrowthValues) == "function" and Model.LaneGrowthValues() or Model.GrowthValues()
                end,
                get = function()
                    return type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(unit, kind) or Model.ReadLaneGrowth(unit, kind)
                end,
                customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
                    if type(Model.WriteLaneGrowthPair) == "function" then Model.WriteLaneGrowthPair(unit, kind, v) else Model.WriteLaneGrowth(unit, kind, v) end
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_GROWTH", true)
                end,
            }, "growth"),
        },
    })
    local function NumberRow(label, id, semanticKey, minValue, maxValue, defaultValue, getValue, setValue)
        return LaneMeta({
            kind = "slider", label = label, id = id,
            min = minValue, max = maxValue, step = 1, default = defaultValue,
            get = getValue, set = setValue,
        }, AuraCatalogToken(semanticKey))
    end
    local numberRows = W.SettingsRows(ctx, section, {
        x = 24, y = -92, width = inner, columns = 4, colGap = gap,
        rows = {
            NumberRow("Max", "max", "max-icons", 0, 80, LaneDefaultMax(kind),
                function() return Model.ReadNumber(unit, LaneMaxKey(kind), LaneDefaultMax(kind), 0, 80) end,
                function(v)
                    Model.WriteNumber(unit, LaneMaxKey(kind), v, 0, 80)
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_MAX")
                end),
            NumberRow("Size", "size", "icon-size", 10, 80, 26,
                function() return Model.ReadNumber(unit, LaneSizeKey(kind), 26, 1, 128) end,
                function(v)
                    Model.WriteNumber(unit, LaneSizeKey(kind), v, 1, 128)
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_SIZE")
                end),
            NumberRow("Icon height (percent)", "heightPercent", "icon-height", 25, 200, 100,
                function() return Model.ReadLaneStyleNumber(unit, kind, "iconHeightPercent", 100, 25, 200) end,
                function(v)
                    Model.WriteLaneStyleNumber(unit, kind, "iconHeightPercent", v, 25, 200)
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_HEIGHT") end),
            NumberRow("Per row", "perRow", "per-row", 1, 40, nil,
                function() return Model.ReadLanePerRow(unit, kind) end,
                function(v)
                    Model.WriteLanePerRow(unit, kind, v)
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_PER_ROW")
                end),
            NumberRow("Gap", "gap", "spacing", 0, 12, 2,
                function() return Model.ReadLaneSpacing(unit, kind) end,
                function(v)
                    Model.WriteLaneSpacing(unit, kind, v)
                    ApplyUnit(ctx, unit, "AURAS3_UNIT_SPACING")
                end),
            NumberRow("Layer (0-30)", "layer", "layer", 0, 30, kind == "buff" and 5 or 6,
                function() return type(Model.ReadLaneLayer) == "function" and Model.ReadLaneLayer(unit, kind) or (kind == "buff" and 5 or 6) end,
                function(v)
                    if type(Model.WriteLaneLayer) == "function" then
                        Model.WriteLaneLayer(unit, kind, v)
                        ApplyUnit(ctx, unit, "AURAS3_UNIT_LAYER")
                    end
                end),
        },
    })
    local function CollectRows(result)
        if not result then return end
        for i = 1, #result.list do controls[#controls + 1] = AurasPage.Own(result.list[i]) end
        for i = 1, #result.resets do controls[#controls + 1] = result.resets[i] end
    end
    CollectRows(anchorRows)
    CollectRows(numberRows)
    local perRowControl = numberRows and numberRows.controls and numberRows.controls.perRow
    M.TrackRefresh(ctx, function()
        local shown = UnitLaneShown(unit, kind)
        W.SetControlEnabled(enable, true)
        W.SetControlsEnabled(controls, shown)
        local growth = type(Model.ReadLaneGrowthPair) == "function" and Model.ReadLaneGrowthPair(unit, kind)
            or Model.ReadLaneGrowth(unit, kind)
        growth = tostring(growth or ""):upper()
        if perRowControl then
            W.SetControlEnabled(perRowControl, shown and growth ~= "UP" and growth ~= "DOWN")
        end
    end)
end
local function CreateHidePermanentWriter(ctx, unit, lane)
    return function(value)
        if type(Model.WriteBlacklistHidePermanent) == "function"
        and Model.WriteBlacklistHidePermanent(unit, lane, value) then
            ApplyUnit(ctx, unit, "AURAS3_HIDE_PERMANENT", true)
        end
    end
end
-- Hide permanent opens both filter layouts; each layout keeps its own tooltip.
local function UnitHidePermanentSwitch(ctx, section, unit, lane, x, width)
    return BindSwitch(ctx, section, "Hide permanent", x, -42, width,
        function()
            return type(Model.ReadBlacklistHidePermanent) == "function"
                and Model.ReadBlacklistHidePermanent(unit, lane) == true
        end,
        CreateHidePermanentWriter(ctx, unit, lane),
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.hide-permanent", nil,
            "auras3." .. unit .. "." .. lane .. ".blacklist.hidePermanent"))
end
-- Native classification filters per lane: label, filter key, tooltip and the
-- keys an enabled filter clears. Read-only; the switches below iterate them.
local UNIT_AURA_FILTER_SPECS = {
    buff = {
        { "Only mine", "onlyMine", "Only auras applied by the player." },
        { "Important", "onlyImportant", "Only auras Blizzard flags as important." },
        { "Applicable by me", "raid", "Helpful auras your character can apply (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Buff filter." },
        { "Also include nameplate-only", "includeNameplateOnly",
            "Broadens the selected filter to also admit Buffs Blizzard marks nameplate-only; it is not a standalone only-filter." },
        { "Dispellable / stealable by group", "includeDispellable", "Helpful enemy auras someone in your group can dispel, purge, or steal." },
        { "Any dispel / steal type", "dispellableAny", "Helpful enemy auras with any dispel type, even when your group cannot remove them." },
        { "External defensive", "externalDefensive", "External defensive Buffs." },
        { "Big defensive", "bigDefensive", "MSUF's curated major-defensive Spell-ID list on friendly frames; Blizzard's safe native classification is used "
            .. "where exact identity filtering is restricted." },
        { "Cancelable", "cancelable", "Only cancelable Buffs.", { "notCancelable" } },
        { "Not cancelable", "notCancelable", "Only non-cancelable Buffs.", { "cancelable" } },
    },
    debuff = {
        { "Only mine", "onlyMine", "Only Debuffs applied by the player.", { "nonPlayer" } },
        { "Important", "onlyImportant", "Only Debuffs Blizzard flags as important." },
        { "Dispellable by me", "raid", "Harmful auras your character can dispel (Blizzard RAID token)." },
        { "Raid combat", "raidInCombat", "Blizzard's in-combat raid Debuff filter." },
        { "Also include nameplate-only", "includeNameplateOnly",
            "Broadens the selected filter to also admit Debuffs Blizzard marks nameplate-only; it is not a standalone only-filter." },
        { "Dispellable by group", "includeDispellable", "Debuffs someone in your group can dispel." },
        { "Any dispel type", "dispellableAny", "Debuffs with a dispel type, even when your group cannot remove them." },
        { "Crowd control", "crowdControl", "Crowd-control Debuffs." },
        { "Non-player auras", "nonPlayer", "Only Debuffs not caused by any player or player pet.", { "onlyMine" } },
    },
}
-- Classic keeps the supported ownership filters and Hide permanent.
local function BuildClassicUnitAuraFilters(ctx, section, unit, lane, colW, gap)
    local onlyMine = BindSwitch(ctx, section, "Only mine", 24, -42, colW,
        function()
            return Model.LaneFiltersEnabled(unit, lane)
                and Model.ReadFilter(unit, lane, "onlyMine", false) == true
        end,
        function(value)
            if value == true and Model.LaneFiltersEnabled(unit, lane) ~= true then
                Model.SetLaneFiltersEnabled(unit, lane, true)
            end
            -- The supported ownership filters are mutually exclusive on Classic too.
            if value == true and lane == "debuff" then Model.WriteFilter(unit, lane, "nonPlayer", false) end
            Model.WriteFilter(unit, lane, "onlyMine", value == true)
            ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_onlyMine", true)
        end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.only-mine", nil,
            "auras3." .. unit .. "." .. lane .. ".filter.onlyMine"))
    M.AuraControls.AddCasterFilterTooltip(onlyMine, lane)
    if lane == "debuff" then
        BindSwitch(ctx, section, "Non-Player Auras", 24 + 2 * (colW + gap), -42, colW,
            function()
                return Model.LaneFiltersEnabled(unit, lane) and Model.ReadFilter(unit, lane, "nonPlayer", false) == true
            end,
            function(value)
                if value == true then
                    Model.SetLaneFiltersEnabled(unit, lane, true)
                    Model.WriteFilter(unit, lane, "onlyMine", false)
                end
                Model.WriteFilter(unit, lane, "nonPlayer", value == true)
                ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_nonPlayer", true)
            end,
            AuraControlMeta(ctx, "unit-workspace.lane.debuff.filters.non-player", nil,
                "auras3." .. unit .. ".debuff.filter.nonPlayer"))
    end
    local hidePermanent = UnitHidePermanentSwitch(ctx, section, unit, lane, 24 + colW + gap, colW)
    AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration.")
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(onlyMine, true)
        W.SetControlEnabled(hidePermanent, true)
    end)
end
-- One native classification switch of a lane (spec from UNIT_AURA_FILTER_SPECS).
local function UnitAuraFilterSwitch(ctx, section, unit, lane, specs, spec, x, y, width)
    local settingContract = "auras3." .. unit .. "." .. lane .. ".filter." .. spec[2]
    if lane == "debuff" and spec[2] == "raid" then
        settingContract = {
            searchSettingKeys = {
                "auras3." .. unit .. ".debuff.filter.raid",
                "auras3." .. unit .. ".debuff.filter.exclusive",
            },
        }
    end
    local control = BindSwitch(ctx, section, spec[1], x, y, width,
        function()
            if spec[2] == "raid" and Model.ReadFilter(unit, lane, "exclusive", "none") == "raid" then
                return true
            end
            return Model.ReadFilter(unit, lane, spec[2], false) == true
        end,
        function(value)
            local key = spec[2]
            local modifier = key == "onlyMine" or key == "includeNameplateOnly"
            if value == true and not modifier then
                -- Blizzard joins native filter tokens as an intersection.
                -- Present classification choices as one active selector so
                -- the switch UI cannot accidentally build empty AND chains;
                -- caster and nameplate inclusion remain explicit modifiers.
                for j = 1, #specs do
                    local otherKey = specs[j][2]
                    if otherKey ~= key and otherKey ~= "onlyMine" and otherKey ~= "includeNameplateOnly" then
                        Model.WriteFilter(unit, lane, otherKey, false)
                    end
                end
            end
            if value == true and type(spec[4]) == "table" then for j = 1, #spec[4] do Model.WriteFilter(unit, lane, spec[4][j], false) end end
            -- Older profiles stored the same RAID token in a second
            -- Exclusive dropdown. Fold it into the visible Raid switch so
            -- the legacy restriction can also be turned off here.
            if key == "raid" or (value == true and not modifier) then
                Model.WriteFilter(unit, lane, "exclusive", "none")
            end
            Model.WriteFilter(unit, lane, spec[2], value)
            ApplyUnit(ctx, unit, "AURAS3_FILTER_" .. lane .. "_" .. spec[2], true)
            if not modifier or spec[4] then QueueAurasPageRefresh(ctx, "auras-filter-conflict") end
        end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters." .. AuraCatalogToken(spec[2]), nil,
            settingContract))
    AddTooltip(control, spec[1], spec[3])
    return control
end

local function BuildCompactUnitAuraFilters(ctx, b, unit, lane)
    local section = b:Section(lane == "debuff" and "Debuff Filters" or "Buff Filters",
        M.CLASSIC_AURA_FILTERS_REDUCED == true and 118 or 256)
    local w = section._msuf2Width or b.width or 720
    local inner = w - 48
    local gap = 12
    local colW = floor((inner - gap * 3) / 4)
    local filterControls = {}
    if M.CLASSIC_AURA_FILTERS_REDUCED == true then
        BuildClassicUnitAuraFilters(ctx, section, unit, lane, colW, gap)
        return
    end
    local enabled = BindSwitch(ctx, section, "Enable filters", 24, -42, colW,
        function() return Model.LaneFiltersEnabled(unit, lane) end,
        function(value)
            Model.SetLaneFiltersEnabled(unit, lane, value)
            ApplyUnit(ctx, unit, "AURAS3_FILTER_ENABLE", true)
        end,
        AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.enabled", nil,
            "auras3." .. unit .. "." .. lane .. ".filtersEnabled"))
    AddTooltip(enabled, "Enable filters",
        "Turns aura classification filters on or off for this exact lane. Big Defensive uses MSUF's curated list on friendly frames.")
    local hidePermanent = UnitHidePermanentSwitch(ctx, section, unit, lane, 24 + colW + gap, colW)
    AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration, even when Blizzard token filters are disabled.")
    local maxDuration
    if M.CLASSIC_AURA_FILTERS_REDUCED ~= true then
        maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24, -174, 0, 180, 1, inner,
            function()
                return type(Model.ReadBlacklistMaxDuration) == "function"
                    and Model.ReadBlacklistMaxDuration(unit, lane) or 0
            end,
            function(value)
                if type(Model.WriteBlacklistMaxDuration) == "function"
                    and Model.WriteBlacklistMaxDuration(unit, lane, value) then
                    ApplyUnit(ctx, unit, "AURAS3_" .. tostring(lane):upper() .. "_MAX_DURATION", true)
                end
            end,
            AuraControlMeta(ctx, "unit-workspace.lane." .. AuraCatalogToken(lane) .. ".filters.max-duration", nil, {})))
    end
    local specs = UNIT_AURA_FILTER_SPECS[lane == "buff" and "buff" or "debuff"]
    for i = 1, #specs do
        local col = ((i - 1) % 4)
        local row = floor((i - 1) / 4)
        filterControls[#filterControls + 1] = UnitAuraFilterSwitch(ctx, section, unit, lane, specs, specs[i],
            24 + col * (colW + gap), -78 - row * 32, colW)
    end
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(enabled, true)
        W.SetControlEnabled(hidePermanent, true)
        W.SetControlEnabled(maxDuration, true)
        W.SetControlsEnabled(filterControls, Model.LaneFiltersEnabled(unit, lane))
    end)
end
-- The unit blacklist editor shares one record B between its manual-entry block,
-- the live-scan block and the preset/list block; the late-bound refreshers
-- (refreshList, renderVerify, refreshLiveBlock, nonPresetHint) live on B.

-- Explicit load-time exports for the following responsibility modules.
Parts.BuildAuraStyleLanePage = BuildAuraStyleLanePage
Parts.BuildAuraStylePage = BuildAuraStylePage
Parts.BuildCompactUnitAuraFilters = BuildCompactUnitAuraFilters
Parts.BuildCompactUnitAuraLayout = BuildCompactUnitAuraLayout
Parts.BuildUnitOrdering = BuildUnitOrdering
Parts.CurrentUnitAuraTab = CurrentUnitAuraTab
Parts.CurrentUnitAuraTool = CurrentUnitAuraTool
Parts.SelectUnitWorkspaceLanes = SelectUnitWorkspaceLanes
Parts.SetUnitAuraTool = SetUnitAuraTool
Parts.UNIT_AURA_CUSTOM_TOOLS = UNIT_AURA_CUSTOM_TOOLS
Parts.UNIT_AURA_NORMAL_TOOLS = UNIT_AURA_NORMAL_TOOLS
Parts.UNIT_AURA_TARGET_DOT_TOOLS = UNIT_AURA_TARGET_DOT_TOOLS
Parts.UNIT_AURA_WORKSPACE_TABS = UNIT_AURA_WORKSPACE_TABS
Parts.UNIT_AURA_WORKSPACE_TABS_PET = UNIT_AURA_WORKSPACE_TABS_PET
