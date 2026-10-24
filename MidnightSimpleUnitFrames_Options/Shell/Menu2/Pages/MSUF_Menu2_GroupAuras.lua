local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group Auras page.
-- Builds party/raid aura lane controls. Auras3 refreshes native 12.1 container layout
-- after these settings change; Blizzard owns live filtering, assignment, and icon updates.
local W = M.Widgets
local Schema, ROW_OPTIONS = M.ControlSchema, M.ControlSchema.UnitOptions()
local T = M.Theme or {}
local GP = M.GroupPage or {}
local floor = math.floor
local max = math.max

local VT = M.ValueTextList
local C_Timer = M.MenuTimer or C_Timer
local RefreshGFPreview, AURA_ANCHORS, STATUS_ICON_ANCHORS = GP.RefreshGFPreview, GP.AURA_ANCHORS, GP.STATUS_ICON_ANCHORS
local SPELL_GROWTH_VALUES, ScopeSection, CurrentScope, AuraGroup = GP.SPELL_GROWTH_VALUES, GP.ScopeSection, GP.CurrentScope, GP.AuraGroup
local AurasRoot, QueueGroupApply, RefreshContext = GP.AurasRoot, GP.QueueGF, GP.RefreshContext
local function QueueGF(scope, mode)
    AurasRoot(scope, true)
    if QueueGroupApply then QueueGroupApply(scope, mode) end
end
local SetOptionEnabled, SetOptionsEnabled = GP.SetOptionEnabled, GP.SetOptionsEnabled
local FinalizeScopePage, SetSectionBadgesAndStatus, OnOffBadge = GP.FinalizeScopePage, GP.SetSectionBadgesAndStatus, GP.OnOffBadge
local BadgeNumber, OptionText = GP.BadgeNumber, GP.OptionText
AURA_ANCHORS = AURA_ANCHORS or {}
STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS or {}
SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES or {}
SetSectionBadgesAndStatus = SetSectionBadgesAndStatus or M.Noop
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = function(values, value, fallback)
    values = type(values) == "function" and values() or values
    if type(values) == "table" then
        for i = 1, #values do
            local row = values[i]
            if row and row.value == value then return row.text or row.label or tostring(value) end
        end
    end
    return fallback or tostring(value or "")
end
local function ThemeColor(key, fallback)
    local colors = T and T.colors
    return colors and colors[key] or fallback
end
local AuraCatalogToken = M.AuraCatalogToken
-- The shared Aura metadata owner (AuraControls loads after this page and is read
-- at build time) with this page's fallback page key.
local function AuraControlMeta(ctx, path, classification, routeContract)
    return M.AuraControls.AuraControlMeta(ctx, path, classification, routeContract, "gf_auras")
end
local function RegisterAuraControl(ctx, widget, label, kind, path, classification, navigationKey)
    if not widget or type(M.RegisterSearchWidget) ~= "function" then return widget end
    local meta = AuraControlMeta(ctx, path, classification)
    meta.label = label
    meta.kind = kind
    if classification == "navigation" then meta.navigationKey = navigationKey end
    M.RegisterSearchWidget(widget, meta)
    -- A selector bar keeps its native GetValue/SetValue/values in the declaration.
    if kind == "segment" then return Schema.ScopeOwner(widget, "groups", "menuState") end
    Schema.Owned(widget, "groups", classification == "navigation" and "navigation" or "menuState")
    return widget
end
local MUTED = ThemeColor("muted", { 0.55, 0.66, 0.82, 0.92 })
local GF_AURA_WORKSPACE_TOOLS = {
    { value = "layout", text = "Layout" },
    { value = "behavior", text = "Ordering" },
    { value = "filters", text = "Filters" },
    { value = "blacklist", text = "Blacklist" },
    { value = "style", text = "Style" },
}
local GF_AURA_EXTERNAL_TOOLS = {
    { value = "layout", text = "Layout" },
    { value = "behavior", text = "Ordering" },
    { value = "style", text = "Style" },
}
local GF_AURA_WORKSPACE_LANES = {
    { value = "buff", text = "Buffs" },
    { value = "debuff", text = "Debuffs" },
    { value = "externals", text = "External Defensives" },
}
-- PTR 6 permits exact SpellID candidate filters for every non-secret aura.
-- Helpful auras on friendly group units were already eligible; NeverSecret
-- harmful auras such as Sated/Exhaustion are now eligible there as well.
local GF_AURA_BLACKLIST_AVAILABLE = true
local GF_AURA_WORKSPACE_TOOL_OK = { layout = true, behavior = true, filters = true, blacklist = GF_AURA_BLACKLIST_AVAILABLE, style = true }
local GF_AURA_EXTERNAL_TOOL_OK = { layout = true, behavior = true, style = true }
local function AuraWorkspaceTools(lane)
    return lane == "externals" and GF_AURA_EXTERNAL_TOOLS or GF_AURA_WORKSPACE_TOOLS
end
local function AuraWorkspaceToolAllowed(lane, tool)
    local allowed = lane == "externals" and GF_AURA_EXTERNAL_TOOL_OK or GF_AURA_WORKSPACE_TOOL_OK
    return allowed[tool] == true
end
-- The per-scope tool selection record, created on first use.
local function AuraToolScopeState(scope)
    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
    local scopeState = M.gfAuraToolSelection[scope]
    if type(scopeState) ~= "table" then
        scopeState = {}
        M.gfAuraToolSelection[scope] = scopeState
    end
    return scopeState
end
local function CurrentAuraWorkspaceTool(scope, lane)
    local scopeState = AuraToolScopeState(scope)
    local tool = scopeState[lane]
    if not AuraWorkspaceToolAllowed(lane, tool) then
        tool = tool == "blacklist" and "filters" or "layout"
        if not AuraWorkspaceToolAllowed(lane, tool) then tool = "layout" end
        scopeState[lane] = tool
    end
    return tool
end
local function SetAuraWorkspaceTool(scope, lane, tool)
    AuraToolScopeState(scope)[lane] = AuraWorkspaceToolAllowed(lane, tool) and tool or "layout"
end
local function CurrentAuraWorkspaceLane(scope)
    M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
    local lane = M.gfAuraLaneSelection[scope]
    if lane ~= "buff" and lane ~= "debuff" and lane ~= "externals" then
        lane = "buff"
        M.gfAuraLaneSelection[scope] = lane
    end
    return lane
end
local function SetAuraWorkspaceLane(scope, lane)
    M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
    M.gfAuraLaneSelection[scope] = (lane == "debuff" and "debuff") or (lane == "externals" and "externals") or "buff"
end
--- The workspace builds one scope, lane and tool at a time. Each combination
--- is a declared view of the page (spec.variantKey), so a lane or tool click
--- shows that view's cached entry or builds it once.
local function RebuildGroupAuraPage(ctx)
    M.RebuildPageKeepingScroll((ctx and ctx.key) or M.activeKey or "gf_auras")
end
local GROUP_AURA_VIEWS = {}
local GROUP_AURA_VIEW_STATE = { gfScope = true, gfAuraLaneSelection = true, gfAuraToolSelection = true }
local function GroupAuraWorkspaceView()
    local scope = tostring(CurrentScope())
    local lane = CurrentAuraWorkspaceLane(scope)
    local tool = CurrentAuraWorkspaceTool(scope, lane)
    local id = scope .. ":" .. lane
    local byLane = GROUP_AURA_VIEWS[id]
    if not byLane then
        byLane = {}
        GROUP_AURA_VIEWS[id] = byLane
    end
    local view = byLane[tool]
    if not view then
        view = id .. ":" .. tool
        byLane[tool] = view
    end
    return view
end
local function MeasureWorkspaceBar(values, width, centerY)
    return W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, {
        width = width,
        labelWidth = 72,
        centerY = centerY,
    })
end
-- A workspace selector bar; a new choice stores the view state and rebuilds.
local function WorkspaceSelectorBar(ctx, section, values, width, label, centerY, current, select)
    return W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = width,
        label = label,
        labelWidth = 72,
        centerY = centerY,
        getValue = current,
        setValue = function(value)
            if current() == value then return end
            select(value)
            RebuildGroupAuraPage(ctx)
        end,
    })
end
local function AuraWorkspaceLayout(lane, width)
    local sectionW = tonumber(width) or 720
    local containerCenterY = -28
    local containerMetrics = MeasureWorkspaceBar(GF_AURA_WORKSPACE_LANES, sectionW, containerCenterY)
    local toolCenterY = math.min(-62, ((containerMetrics and containerMetrics.bottomY) or -40) - 22)
    local toolMetrics = MeasureWorkspaceBar(AuraWorkspaceTools(lane), sectionW, toolCenterY)
    local footerY = ((toolMetrics and toolMetrics.bottomY) or (toolCenterY - 12)) - 2
    return {
        containerCenterY = containerCenterY,
        toolCenterY = toolCenterY,
        footerY = footerY,
        height = math.max(104, math.abs(footerY) + 28),
    }
end
local function BuildAuraWorkspaceTabs(ctx, section, scope, lane, width, layout)
    local sectionW = tonumber(width) or 720
    layout = layout or AuraWorkspaceLayout(lane, sectionW)
    local laneBar = WorkspaceSelectorBar(ctx, section, GF_AURA_WORKSPACE_LANES, sectionW, "Container:", layout.containerCenterY,
        function() return CurrentAuraWorkspaceLane(scope) end,
        function(value) SetAuraWorkspaceLane(scope, value) end)
    RegisterAuraControl(ctx, laneBar, "Container", "segment", "group-workspace.container-selector", "ephemeral")
    local toolBar = WorkspaceSelectorBar(ctx, section, AuraWorkspaceTools(lane), sectionW, "Edit:", layout.toolCenterY,
        function() return CurrentAuraWorkspaceTool(scope, lane) end,
        function(value) SetAuraWorkspaceTool(scope, lane, value) end)
    local exactKind = "groupAuraWorkspace"
    local exactViews = lane == "buff" and {
        party_buff_filters = {
            scope = "party",
            lane = "buff",
            tool = "filters",
            settingKey = "gf_party.auras.buff.filterToken",
        },
    } or nil
    RegisterAuraControl(ctx, toolBar, "Edit", "segment",
        "group-workspace.lane." .. AuraCatalogToken(lane, "lane") .. ".tool-selector",
        "ephemeral")
    if exactViews then
        local exactContracts = {}
        for value, view in pairs(exactViews) do exactContracts[value] = view.settingKey end
        toolBar._msuf2ExactTargetKinds = { [exactKind] = true }
        toolBar._msuf2ExactTargetContracts = { [exactKind] = exactContracts }
        toolBar._msuf2PrepareExactSearchTarget = function(_, exactTarget)
            if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= exactKind then return false end
            local view = exactViews[tostring(exactTarget.prepareValue or "")]
            if not view then return false end
            M.SetMenuStateValue("gfScope", view.scope)
            SetAuraWorkspaceLane(view.scope, view.lane)
            SetAuraWorkspaceTool(view.scope, view.lane, view.tool)
            return true
        end
    end
    if not GF_AURA_BLACKLIST_AVAILABLE then
        for i = 1, #(toolBar.buttons or {}) do
            local button = toolBar.buttons[i]
            if button and button._msuf2Value == "blacklist" and button.SetEnabled then
                button:SetEnabled(false)
                break
            end
        end
    end
    local sharedLane = lane == "debuff" and "debuff" or "buff"
    local openStyle = T.Button(section, "Global Aura Appearance", 170, 22)
    openStyle:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, layout.footerY)
    if T.CenterButtonLabel then T.CenterButtonLabel(openStyle) end
    openStyle:SetScript("OnClick", function()
        M.SetMenuStateValue("auraAppearanceContainer", sharedLane)
        M.SetMenuStateValue("auraStyleGFLane", sharedLane)
        if M.SelectPage then M.SelectPage("auras3_styling") end
    end)
    RegisterAuraControl(ctx, openStyle, "Global Aura Appearance", "button", "group-workspace.open-aura-style", "navigation", "auras3_styling")
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(openStyle, "Global Aura Appearance",
            "Opens the global Aura icon theme: border, shadow, colors, lane padding and " ..
                "native Player weapon enchants. This GroupFrame's individual Style stays here.",
            { hook = true, titleAsLine = true })
    end
    W.Text(section, M.Format("Ordering and individual Style are edited here. Global icon theme: %s.", M.NavPath("auras3_styling")),
        16, layout.footerY - 8, sectionW - 198, MUTED)
end
local function NativeAuraKey(groupKey)
    if groupKey == "buff" then return "buffs" end
    if groupKey == "externals" then return "externals" end
    return "debuffs"
end
local GroupAuraSettingKeys = M.GroupAuraSettingKeys
local function AllGroupAuraSettingKeys(suffix)
    suffix = tostring(suffix or "")
    return { "gf_party" .. suffix, "gf_raid" .. suffix, "gf_mythicraid" .. suffix }
end
local function LaneBackendEnabled(scope, groupKey)
    local root = AurasRoot and AurasRoot(scope)
    local group = AuraGroup(scope, groupKey)
    if not root then return group.enabled ~= false end
    return root.enabled ~= false and group.enabled ~= false
end
-- These controls keep their live preview/release setters. The shared binder
-- owns their typed declarations, native input, history and combat refusal.
local function BindAuraWidget(ctx, widget, kind, get, set, fallback, meta)
    local low, high
    if kind == "slider" then low, high = widget:GetMinMaxValues() end
    Schema.Bind(ctx, widget, {
        id = meta.controlId, kind = kind, scope = "groups", applyDomain = "auras",
        get = get, set = set, customSetReason = "Resolves the active group aura lane and updates its runtime and layout companions.",
        meta = meta, range = low and { low, high, 1 },
        defaultSource = function() return fallback end,
    })
    widget._msuf2ControlSchema.labelKey = widget._msuf2RuntimeControlRecord.label
    return widget
end
local function BindAuraRootEnabled(ctx, widget)
    local scope = CurrentScope()
    BindAuraWidget(ctx, widget, "toggle",
        function()
            local root = AurasRoot and AurasRoot(CurrentScope())
            return not root or root.enabled ~= false
        end,
        function(value)
            local activeScope = CurrentScope()
            local root = AurasRoot and AurasRoot(activeScope)
            if not root then return end
            root.enabled = value and true or false
            if QueueGF then QueueGF(activeScope, "auras") end
            RefreshContext(ctx)
        end,
        nil, AuraControlMeta(ctx, "group-workspace.root.enabled", nil, {
            searchSettingKeys = GroupAuraSettingKeys(scope, ".auras.enabled"),
        }))
    return widget
end
local function BindAuraLaneEnabled(ctx, widget, groupKey)
    local scope = CurrentScope()
    BindAuraWidget(ctx, widget, "toggle",
        function()
            return LaneBackendEnabled(CurrentScope(), groupKey)
        end,
        function(v)
            local scope = CurrentScope()
            local root = AurasRoot and AurasRoot(scope)
            local group = AuraGroup(scope, groupKey)
            local enabled = v and true or false
            if root then
                root.enabled = true
                root.blizzardTypes = root.blizzardTypes or {}
                root.blizzardTypes[NativeAuraKey(groupKey)] = false
            end
            group.enabled = enabled
            if QueueGF then QueueGF(scope, "auras") end
            RefreshContext(ctx)
        end,
        nil, AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(groupKey, "lane") .. ".enabled", nil, {
            searchSettingKeys = GroupAuraSettingKeys(scope,
                ".auras." .. groupKey .. ".enabled"),
        }))
    return widget
end
local CreateNestedGroupAuraBuilder = W.CreateNestedAuraBuilder

local function PrepareWorkspaceSearch(ctx)
    local scope = CurrentScope()
    local lane = CurrentAuraWorkspaceLane(scope)
    local tool = CurrentAuraWorkspaceTool(scope, lane)
    M.AuraControls.ConfigureSearchView(ctx, "groupAuraWorkspace", scope .. "_" .. lane .. "_" .. tool)
    return scope, lane, tool
end
-- Fixed, read-only UI layout fallbacks; saved aura values keep their own owner.
local AURA_LAYOUT_DEFAULTS = {
    buff = { anchor = "BOTTOMRIGHT", growth = "LEFTUP", size = 22, perRow = 4, max = 6, spacing = 1, layer = 5 },
    externals = { anchor = "CENTER", growth = "RIGHTDOWN", size = 28, perRow = 3, max = 2, spacing = 1, layer = 7 },
    debuff = { anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6 },
}
local function CombatLocked()
    if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() == true end
    return InCombatLockdown and InCombatLockdown() or false
end
local function RefreshAuraPreviews(scope)
    if CombatLocked() then return false end
    RefreshGFPreview(scope, { auraOnly = true })
    return true
end
local function LaneLayoutMeta(ctx, lane, path, routeContract)
    return AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. path, nil, routeContract)
end
local function BindLiveAuraSlider(ctx, widget, scope, lane, key, fallback, meta)
    local pendingApply, pendingScope, pendingAuras, releaseScheduled
    local function RefreshPreviewOnly()
        RefreshAuraPreviews(pendingScope or scope)
    end
    local function FlushRuntime()
        if not pendingApply then return end
        if CombatLocked() then
            releaseScheduled = nil
            return false
        end
        local applyScope = pendingScope or scope
        local current = pendingAuras == AurasRoot(applyScope)
        pendingApply, pendingScope, pendingAuras, releaseScheduled = nil, nil, nil, nil
        if current then QueueGF(applyScope, "auras") end
        return true
    end
    local function ScheduleRelease()
        if not pendingApply or releaseScheduled then return end
        if CombatLocked() then return end
        releaseScheduled = true
        -- Tracked Menu2 timer only (file-local proxy above). A raw global
        -- timer callback outlives the combat teardown that hides this page,
        -- so the runtime apply would still fire after the menu quiesced on
        -- PLAYER_REGEN_DISABLED.
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, FlushRuntime)
        else
            FlushRuntime()
        end
    end
    meta = meta or LaneLayoutMeta(ctx, lane, AuraCatalogToken(key))
    meta.step, meta.roundStep = 1, true
    BindAuraWidget(ctx, widget, "slider",
        function() return tonumber(AuraGroup(CurrentScope(), lane)[key]) or fallback end,
        function(value)
            local activeScope = CurrentScope()
            value = floor((tonumber(value) or fallback or 0) + 0.5)
            local group = AuraGroup(activeScope, lane)
            if group[key] == value then return end
            group[key] = value
            pendingAuras = AurasRoot(activeScope, true)
            pendingApply = true
            pendingScope = activeScope
            -- Preview each edit immediately; apply live frames once on release.
            RefreshPreviewOnly()
            if widget._msuf2SliderActive == true or releaseScheduled then
                return
            else
                FlushRuntime()
            end
        end,
        fallback, meta)
    widget:HookScript("OnMouseUp", ScheduleRelease)
    widget:HookScript("OnHide", FlushRuntime)
    -- If combat interrupts a drag, MenuRuntime cancels the release timer
    -- and hides the page. Retain the pending OOC apply locally and flush it
    -- only when the user next opens this control after combat.
    widget:HookScript("OnShow", FlushRuntime)
    return widget
end
local function BindLiveAuraDropdown(ctx, widget, scope, lane, key, fallback, meta)
    BindAuraWidget(ctx, widget, "dropdown",
        function() return AuraGroup(CurrentScope(), lane)[key] or fallback end,
        function(value)
            if CombatLocked() then return end
            local activeScope = CurrentScope()
            local group = AuraGroup(activeScope, lane)
            value = value or fallback
            if group[key] == value then return end
            group[key] = value
            AurasRoot(activeScope, true)
            RefreshAuraPreviews(activeScope)
            QueueGF(activeScope, "auras")
            if key == "growth" then RefreshContext(ctx) end
        end,
        nil, meta or LaneLayoutMeta(ctx, lane, AuraCatalogToken(key)))
    return widget
end
local function BuildExternalFilterSection(ctx, auraBuilder)
    local filterSection = auraBuilder:Section("External Defensive Filtering", 88)
    local filterWidth = filterSection._msuf2Width or auraBuilder.width or 720
    local autoMeta = AuraControlMeta(ctx, "group-workspace.lane.externals.auto-blacklist-buffs", nil, {
        -- One stable catalog identity covers every scope captured by search.
        searchSettingKeys = AllGroupAuraSettingKeys(".auras.externals.autoBlacklistBuffs"),
    })
    local autoBlacklist = Schema.Build(ctx, filterSection, {{ "switch", "autoBlacklist", true,
        { "Auto-blacklist from Buffs", 24, -50, filterWidth - 48 },
        meta = autoMeta, scope = "groups", domain = "auras", get = function()
            return AuraGroup(CurrentScope(), "externals").autoBlacklistBuffs ~= false
        end, customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(value)
            local activeScope = CurrentScope()
            AuraGroup(activeScope, "externals").autoBlacklistBuffs = value == true
            if QueueGF then QueueGF(activeScope, "auras") end
            RefreshContext(ctx)
        end,
    }}, ROW_OPTIONS).autoBlacklist
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(autoBlacklist, "Auto-blacklist from Buffs",
            "While External Defensives is visible and Max is above 0, hides every aura Blizzard classifies as EXTERNAL_DEFENSIVE from the normal Buffs " ..
                "container. If External Defensives is disabled, those auras remain visible in Buffs.",
            { hook = true, titleAsLine = true })
    end
end
-- One live lane-layout row: the schema creates and places it, and the live
-- slider/dropdown binder (preview per edit, runtime apply on release) owns input.
local function BuildLaneLayoutRow(L, kind, key, fallback, args, place, path, routeContract)
    local bindLive = kind == "slider" and BindLiveAuraSlider or BindLiveAuraDropdown
    local widget = Schema.Build(L.ctx, L.section, {{ kind, key, fallback, args, place, bind = function(control)
        bindLive(L.ctx, control, L.scope, L.lane, key, fallback,
            LaneLayoutMeta(L.ctx, L.lane, path or AuraCatalogToken(key), routeContract))
    end }}, ROW_OPTIONS)[key]
    L.controls[#L.controls + 1] = widget
    return widget
end
local function BuildLaneLayoutSection(ctx, auraBuilder, scope, lane)
    local anchors = (#STATUS_ICON_ANCHORS > 0 and STATUS_ICON_ANCHORS) or AURA_ANCHORS
    local growthValues = VT("RIGHTDOWN", "Right then Down", "LEFTDOWN", "Left then Down",
        "RIGHTUP", "Right then Up", "LEFTUP", "Left then Up",
        "UP", "Up (Single Column)", "DOWN", "Down (Single Column)")
    local defaults = AURA_LAYOUT_DEFAULTS[lane] or AURA_LAYOUT_DEFAULTS.debuff
    local title = lane == "debuff" and "Debuff Layout"
        or (lane == "externals" and "External Defensive Layout" or "Buff Layout")
    local section = auraBuilder:Section(title, 202)
    local w = section._msuf2Width or auraBuilder.width or 720
    local inner, gap = w - 48, 10
    local controls = {}
    local L = { ctx = ctx, section = section, scope = scope, lane = lane, controls = controls }
    local enable = Schema.Build(ctx, section, {{ "switch", "laneEnabled", nil,
        { "Visible", 24, -62, 104 }, bind = function(widget) BindAuraLaneEnabled(ctx, widget, lane) end }}, ROW_OPTIONS).laneEnabled
    enable._msuf2GroupFrameGateAlwaysEnabled = true
    local dropdownW = max(180, floor((inner - 126 - gap * 2) / 2))
    local anchorX = 24 + 126 + gap
    local growthX = anchorX + dropdownW + gap
    local function Dropdown(label, x, values, key, fallback, y, width)
        width = width or dropdownW
        local routeContract
        if lane == "externals" and key == "growth" then
            routeContract = {
                searchSettingKeys = GroupAuraSettingKeys(scope, ".auras.externals.growth"),
            }
        end
        return BuildLaneLayoutRow(L, "dropdown", key, fallback, { label, values, width },
            { x, y or -34, width, "LEFT" }, nil, routeContract)
    end
    Dropdown("Anchor", anchorX, anchors, "anchor", defaults.anchor)
    Dropdown("Growth", growthX, growthValues, "growth", defaults.growth)
    local col4 = floor((inner - gap * 3) / 4)
    local function Slider(label, col, y, minValue, maxValue, key, fallback)
        local routeContract
        if lane == "externals" and (key == "layer" or key == "max") then
            routeContract = {
                searchSettingKeys = GroupAuraSettingKeys(scope, ".auras.externals." .. key),
            }
        end
        return BuildLaneLayoutRow(L, "slider", key, fallback, { label, minValue, maxValue, 1, col4 },
            { 24 + (col - 1) * (col4 + gap), y, col4 }, nil, routeContract)
    end
    Slider("Max", 1, -92, 0, 20, "max", defaults.max)
    Slider("Size", 2, -92, 8, 80, "size", defaults.size)
    Slider("Layer (0-30)", 3, -92, 0, 30, "layer", defaults.layer)
    local perRowControl = Slider("Per row", 1, -146, 1, 20, "perRow", defaults.perRow)
    Slider("Gap", 2, -146, 0, 12, "spacing", defaults.spacing)
    BuildLaneLayoutRow(L, "slider", "iconScale", 100, { "Icon Scale (%)", 20, 300, 1, col4 },
        { 24 + 2 * (col4 + gap), -146, col4 }, "icon-scale", {
            searchSettingKeys = GroupAuraSettingKeys(scope, ".auras." .. tostring(lane) .. ".iconScale"),
        })
    M.TrackRefresh(ctx, function()
        local shown = LaneBackendEnabled(CurrentScope(), lane)
        SetOptionEnabled(enable, true)
        SetOptionsEnabled(controls, shown)
        local growth = tostring(AuraGroup(CurrentScope(), lane).growth or defaults.growth):upper()
        SetOptionEnabled(perRowControl, shown and growth ~= "UP" and growth ~= "DOWN")
    end)
end
local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.SelectPage(ctx.key) end
    local scope, lane, tool = PrepareWorkspaceSearch(ctx)

    local outer = Schema.Section(b:CollapsibleSection("auras", "Auras", 120, false), "groups")
    local auraBuilder = CreateNestedGroupAuraBuilder(ctx, b, outer)
    local workspaceLayout = AuraWorkspaceLayout(lane, auraBuilder.width or 720)
    local top = auraBuilder:Section("", workspaceLayout.height)
    if top.title then top.title:Hide() end
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, top, "Aura lane and tools", "group_aura_tools")
    end
    BuildAuraWorkspaceTabs(ctx, top, scope, lane, top._msuf2Width or auraBuilder.width or 720, workspaceLayout)
    if type(M.AttachAuraFontsAndColors) == "function" then
        M.AttachAuraFontsAndColors(top, M.Format("Auras"), scope)
    end

    Schema.Build(ctx, outer, {{ "sectionSwitch", "rootEnabled", nil, { "Enable group auras" },
        bind = function(widget) BindAuraRootEnabled(ctx, widget) end }}, ROW_OPTIONS)

    if tool == "layout" and lane == "externals" then BuildExternalFilterSection(ctx, auraBuilder) end

    if tool == "layout" then
        BuildLaneLayoutSection(ctx, auraBuilder, scope, lane)
    elseif type(M.BuildAuras3GroupLaneWorkspace) == "function" then
        M.BuildAuras3GroupLaneWorkspace(ctx, auraBuilder, scope, lane, { tool = tool, compact = true })
    end

    if GP.BuildSpellIndicatorsSection then GP.BuildSpellIndicatorsSection(ctx, b, RefreshPage) end
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 33,
    variantKey = GroupAuraWorkspaceView, viewStateKeys = GROUP_AURA_VIEW_STATE })
