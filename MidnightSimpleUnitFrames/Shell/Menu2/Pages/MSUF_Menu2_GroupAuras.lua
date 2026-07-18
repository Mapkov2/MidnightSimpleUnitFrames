local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Group Auras page.
-- Builds party/raid aura lane controls. Auras3 refreshes native 12.1 container layout
-- after these settings change; Blizzard owns live filtering, assignment, and icon updates.
local W = M.Widgets
local T = M.Theme or {}
local GP = M.GroupPage or {}
local floor, ceil, abs = math.floor, math.ceil, math.abs
local max = math.max
local min = math.min
local C_Timer = M.MenuTimer or _G.C_Timer
local VT = M.ValueTextList
local AccessibleNumber = M.AccessibleNumber or function(value, fallback)
    fallback = tonumber(fallback) or 0
    local canaccessvalue = _G.canaccessvalue
    if type(canaccessvalue) == "function" and canaccessvalue(value) ~= true then return fallback end
    local issecretvalue = _G.issecretvalue
    if type(issecretvalue) == "function" and issecretvalue(value) == true then return fallback end
    return tonumber(value) or fallback
end
local AURA_ANCHORS, STATUS_ICON_ANCHORS, SPELL_GROWTH_VALUES, ScopeSection, CurrentScope, AuraGroup, AurasRoot, QueueGF, RefreshContext, BindNestedSlider, BindNestedDropdown, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, OnOffBadge, BadgeNumber, OptionText = M.Pick(GP, [[AURA_ANCHORS STATUS_ICON_ANCHORS SPELL_GROWTH_VALUES ScopeSection CurrentScope AuraGroup AurasRoot QueueGF RefreshContext BindNestedSlider BindNestedDropdown SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus OnOffBadge BadgeNumber OptionText]])
AURA_ANCHORS = AURA_ANCHORS or {}
STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS or {}
SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES or {}
SetSectionBadgesAndStatus = SetSectionBadgesAndStatus or M.Noop
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber
OptionText = OptionText or function(values, value, fallback)
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
local function AuraCatalogToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "control")
end
local function AuraCatalogPageKey(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "gf_auras")
end
local function AuraControlMeta(ctx, path, classification, assistantContract)
    path = tostring(path or "control"):lower():gsub("[^%w%._/-]+", "-")
    path = path:gsub("/", "."):gsub("^%.+", ""):gsub("%.+$", "")
    local pageKey = AuraCatalogPageKey(ctx and ctx.key or M.activeKey, "gf_auras")
    local identity = "auras." .. path
    local meta = {
        controlId = "menu2." .. pageKey .. "." .. identity,
        pageKey = pageKey,
        identityKey = identity,
        controlPath = "auras/" .. path:gsub("%.", "/"),
        classification = classification or "setting",
        ephemeral = classification == "ephemeral" or nil,
    }
    if type(assistantContract) == "string" and assistantContract ~= "" then
        meta.settingKey = assistantContract
    elseif type(assistantContract) == "table" then
        meta.settingKey = assistantContract.settingKey
        meta.assistantDisposition = assistantContract.assistantDisposition
        meta.assistantDispositionReason = assistantContract.assistantDispositionReason
        meta.assistantSettingKeys = assistantContract.assistantSettingKeys
        meta.assistantSettingKeyPatterns = assistantContract.assistantSettingKeyPatterns
    end
    if meta.classification == "setting" or meta.classification == "action" then
        meta.assistantDisposition = meta.assistantDisposition or "dynamic"
        meta.assistantDispositionReason = meta.assistantDispositionReason
            or "This control targets the currently selected Group scope and Aura lane."
    end
    return meta
end
local function RegisterAuraControl(ctx, widget, label, kind, path, classification, navigationKey)
    if not widget or type(M.RegisterSearchWidget) ~= "function" then return widget end
    local meta = AuraControlMeta(ctx, path, classification)
    meta.label = label
    meta.kind = kind
    if classification == "navigation" then meta.navigationKey = navigationKey end
    M.RegisterSearchWidget(widget, meta)
    return widget
end
local MUTED = ThemeColor("muted", { 0.55, 0.66, 0.82, 0.92 })
local GF_AURA_WORKSPACE_TOOLS = {
    { value = "layout", text = "Layout" },
    { value = "filters", text = "Filters" },
    { value = "blacklist", text = "Blacklist" },
}
local GF_AURA_WORKSPACE_LANES = {
    { value = "buff", text = "Buffs" },
    { value = "debuff", text = "Debuffs" },
    { value = "externals", text = "External Defensives" },
}
-- Native 12.1 AuraContainers do not currently expose a working SpellID blacklist
-- path. Keep the workspace visible so the missing feature is explicit, but do not
-- let stale menu state or a click open controls that cannot affect live auras.
local GF_AURA_BLACKLIST_AVAILABLE = false
local GF_AURA_WORKSPACE_TOOL_OK = { layout = true, filters = true, blacklist = GF_AURA_BLACKLIST_AVAILABLE }
local function CurrentAuraWorkspaceTool(scope, lane)
    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
    local scopeState = M.gfAuraToolSelection[scope]
    if type(scopeState) ~= "table" then scopeState = {}; M.gfAuraToolSelection[scope] = scopeState end
    local tool = scopeState[lane]
    if lane == "externals" then tool = "layout" end
    if not GF_AURA_WORKSPACE_TOOL_OK[tool] then
        tool = tool == "blacklist" and "filters" or "layout"
        scopeState[lane] = tool
    end
    return tool
end
local function SetAuraWorkspaceTool(scope, lane, tool)
    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
    local scopeState = M.gfAuraToolSelection[scope]
    if type(scopeState) ~= "table" then scopeState = {}; M.gfAuraToolSelection[scope] = scopeState end
    scopeState[lane] = GF_AURA_WORKSPACE_TOOL_OK[tool] and tool or "layout"
end
local function CurrentAuraWorkspaceLane(scope)
    M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
    local lane = M.gfAuraLaneSelection[scope]
    if lane ~= "buff" and lane ~= "debuff" and lane ~= "externals" then lane = "buff"; M.gfAuraLaneSelection[scope] = lane end
    return lane
end
local function SetAuraWorkspaceLane(scope, lane)
    M.gfAuraLaneSelection = M.gfAuraLaneSelection or {}
    M.gfAuraLaneSelection[scope] = (lane == "debuff" and "debuff") or (lane == "externals" and "externals") or "buff"
end
local groupAuraRebuildSerial = 0
local function RestoreGroupAuraScroll(offset, key, serial)
    if M.activeKey ~= key or serial ~= groupAuraRebuildSerial then return end
    local scroll = M.scrollFrame
    if not (scroll and scroll.SetVerticalScroll) then return end
    -- The themed setter already clamps against its accessible cached range.
    -- Avoid GetVerticalScrollRange here: Midnight may return a secret number.
    scroll:SetVerticalScroll(AccessibleNumber(offset, 0))
    if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(scroll) end
end
local function RebuildGroupAuraPage(ctx)
    local key = (ctx and ctx.key) or M.activeKey or "gf_auras"
    if not (M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
    local offset = AccessibleNumber(M.scrollFrame and M.scrollFrame.GetVerticalScroll and M.scrollFrame:GetVerticalScroll() or 0, 0)
    groupAuraRebuildSerial = groupAuraRebuildSerial + 1
    local serial = groupAuraRebuildSerial
    M.InvalidatePage(key)
    M.activeKey = nil
    M.SelectPage(key)
    RestoreGroupAuraScroll(offset, key, serial)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() RestoreGroupAuraScroll(offset, key, serial) end)
        C_Timer.After(0.05, function() RestoreGroupAuraScroll(offset, key, serial) end)
    end
end
local function BuildAuraWorkspaceTabs(ctx, section, scope, lane, width)
    local sectionW = tonumber(width) or 720
    local laneBar = W.ScopeOverrideBar(ctx, section, {
        values = GF_AURA_WORKSPACE_LANES,
        width = sectionW,
        label = "Container:",
        labelWidth = 72,
        centerY = -28,
        getValue = function() return CurrentAuraWorkspaceLane(scope) end,
        setValue = function(value)
            if CurrentAuraWorkspaceLane(scope) == value then return end
            SetAuraWorkspaceLane(scope, value)
            RebuildGroupAuraPage(ctx)
        end,
    })
    RegisterAuraControl(ctx, laneBar, "Container", "segment", "group-workspace.container-selector", "ephemeral")
    local toolBar = W.ScopeOverrideBar(ctx, section, {
        values = lane == "externals" and { GF_AURA_WORKSPACE_TOOLS[1] } or GF_AURA_WORKSPACE_TOOLS,
        width = sectionW,
        label = "Edit:",
        labelWidth = 72,
        centerY = -62,
        getValue = function() return CurrentAuraWorkspaceTool(scope, lane) end,
        setValue = function(value)
            if CurrentAuraWorkspaceTool(scope, lane) == value then return end
            SetAuraWorkspaceTool(scope, lane, value)
            RebuildGroupAuraPage(ctx)
        end,
    })
    RegisterAuraControl(ctx, toolBar, "Edit", "segment",
        "group-workspace.lane." .. AuraCatalogToken(lane, "lane") .. ".tool-selector", "ephemeral")
    if not GF_AURA_BLACKLIST_AVAILABLE then
        for i = 1, #(toolBar.buttons or {}) do
            local button = toolBar.buttons[i]
            if button and button._msuf2Value == "blacklist" and button.SetEnabled then
                button:SetEnabled(false)
                break
            end
        end
    end
    if lane ~= "externals" then
        local openStyle = T.Button(section, "More Aura Options", 150, 22)
        openStyle:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, -76)
        if T.CenterButtonLabel then T.CenterButtonLabel(openStyle) end
        openStyle:SetScript("OnClick", function()
            local styleScope = scope == "mythicraid" and "raid" or scope
            M.SetMenuStateValue("auraScope", styleScope)
            M.SetMenuStateValue("auraStyleGFScope", styleScope)
            M.SetMenuStateValue("auraStyleContainer", lane)
            M.SetMenuStateValue("auraStyleGFLane", lane)
            if M.SelectPage then M.SelectPage("auras3_styling") end
        end)
        RegisterAuraControl(ctx, openStyle, "More Aura Options", "button", "group-workspace.open-aura-style", "navigation", "auras3_styling")
        if type(M.AddTooltip) == "function" then
            M.AddTooltip(openStyle, "More Aura Options",
                "Opens the complete Aura Style page for icon appearance, cooldown and stack text, duration bars, and colors.",
                { hook = true, titleAsLine = true })
        end
        local hint = GF_AURA_BLACKLIST_AVAILABLE
            and "All icon styling: Appearance > Auras."
            or "Blacklist is unavailable in WoW 12.1. All icon styling: Appearance > Auras."
        W.Text(section, hint, 16, -84, sectionW - 198, MUTED)
    else
        W.Text(section, "External defensives use their dedicated layout below.", 16, -84, sectionW - 32, MUTED)
    end
end
local function NativeAuraKey(groupKey)
    if groupKey == "buff" then return "buffs" end
    if groupKey == "externals" then return "externals" end
    return "debuffs"
end
local function GroupAuraSettingKeys(scope, suffix)
    suffix = tostring(suffix or "")
    if scope == "party" then return { "gf_party" .. suffix } end
    return { "gf_raid" .. suffix, "gf_mythicraid" .. suffix }
end
local function LaneBackendEnabled(scope, groupKey)
    local root = AurasRoot and AurasRoot(scope)
    local group = AuraGroup(scope, groupKey)
    if not root then return group.enabled ~= false end
    return root.enabled ~= false and group.enabled ~= false
end
local function BindAuraRootEnabled(ctx, widget)
    local scope = CurrentScope()
    M.BindBoolWidget(ctx, widget,
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
            M.CallIf(RefreshContext, ctx)
        end,
        AuraControlMeta(ctx, "group-workspace.root.enabled", nil, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "This master switch targets the selected Group scope's persisted Aura backend gate.",
            assistantSettingKeys = GroupAuraSettingKeys(scope, ".auras.enabled"),
        }))
    return widget
end
local function BindAuraLaneEnabled(ctx, widget, groupKey)
    local scope = CurrentScope()
    M.BindBoolWidget(ctx, widget,
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
            M.CallIf(RefreshContext, ctx)
        end,
        AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(groupKey, "lane") .. ".enabled", nil, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "Visible targets the selected Group scope and Aura lane and also activates the Aura backend when enabled.",
            assistantSettingKeys = GroupAuraSettingKeys(scope,
                ".auras." .. groupKey .. ".enabled"),
        }))
    return widget
end
local function CreateNestedGroupAuraBuilder(ctx, parentBuilder, body)
    local entry = body and body._msuf2CollapsibleEntry
    if not (entry and W.PageBuilder) then return parentBuilder end
    local bodyWidth = body._msuf2Width or parentBuilder.width or 720
    local nestedCtx = setmetatable({
        wrapper = body,
        width = max(320, bodyWidth - 24),
        key = ctx and ctx.key,
        entry = ctx and ctx.entry,
        _msuf2ContentX = 12,
        _msuf2TopInset = 0,
    }, { __index = ctx })
    function nestedCtx:SetContentHeight(height)
        height = max(80, ceil(tonumber(height) or 80))
        if entry.contentHeight == height then return end
        entry.contentHeight = height
        body:SetHeight(height)
        if parentBuilder.RequestRelayoutCollapsibles then parentBuilder:RequestRelayoutCollapsibles() end
    end
    local nestedBuilder = W.PageBuilder(nestedCtx)
    entry._msuf2SettleContentLayout = function()
        if nestedBuilder.RelayoutCollapsibles then nestedBuilder:RelayoutCollapsibles() end
        nestedCtx:SetContentHeight(abs(nestedBuilder.y) + 42)
    end
    return nestedBuilder
end

local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.CallIf(M.SelectPage, ctx.key) end
    local scope = CurrentScope()
    local lane = CurrentAuraWorkspaceLane(scope)
    local tool = CurrentAuraWorkspaceTool(scope, lane)
    local anchors = (#STATUS_ICON_ANCHORS > 0 and STATUS_ICON_ANCHORS) or AURA_ANCHORS
    local growthValues = VT("RIGHTDOWN", "Right then Down", "LEFTDOWN", "Left then Down",
        "RIGHTUP", "Right then Up", "LEFTUP", "Left then Up",
        "UP", "Up (Single Column)", "DOWN", "Down (Single Column)")
    local defaults = lane == "buff"
        and { anchor = "BOTTOMRIGHT", growth = "LEFTUP", size = 22, perRow = 4, max = 6, spacing = 1, layer = 5 }
        or lane == "externals"
        and { anchor = "CENTER", growth = "RIGHTDOWN", size = 28, perRow = 3, max = 2, spacing = 1, layer = 7 }
        or { anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6 }

    local outer = b:CollapsibleSection("auras", "Auras", 120, false)
    local auraBuilder = CreateNestedGroupAuraBuilder(ctx, b, outer)
    local top = auraBuilder:Section("", 104)
    if top.title then top.title:Hide() end
    if W.RegisterGuidedRegion then
        W.RegisterGuidedRegion(ctx, top, "Aura lane and tools", "group_aura_tools")
    end
    BuildAuraWorkspaceTabs(ctx, top, scope, lane, top._msuf2Width or auraBuilder.width or 720)

    local rootSection = auraBuilder:Section("Group Aura Visibility", 132)
    local rootWidth = rootSection._msuf2Width or auraBuilder.width or 720
    local rootEnabled = BindAuraRootEnabled(ctx,
        W.SwitchAt(rootSection, "Enable group auras", 24, -50, rootWidth - 48))
    rootEnabled._msuf2GroupFrameGateAlwaysEnabled = true
    local rootZoom = BindNestedSlider(ctx,
        W.Slider(rootSection, "Icon Zoom (%)", 100, 200, 1, min(320, rootWidth - 48)),
        function() return AurasRoot(CurrentScope()) end, "iconZoom", 100, "auras",
        AuraControlMeta(ctx, "group-workspace.root.icon_zoom", nil, {
            assistantDisposition = "dynamic",
            assistantDispositionReason = "Icon Zoom targets every Aura icon in the selected Group scope.",
            assistantSettingKeys = GroupAuraSettingKeys(scope, ".auras.iconZoom"),
        }))
    W.MoveWidget(rootZoom, rootSection, 24, -88, min(320, rootWidth - 48), "LEFT")

    if tool == "layout" then
        local title = lane == "debuff" and "Debuff Layout"
            or (lane == "externals" and "External Defensive Layout" or "Buff Layout")
        local section = auraBuilder:Section(title, 190)
        local w = section._msuf2Width or auraBuilder.width or 720
        local inner, gap = w - 48, 10
        local controls = {}
        local enable = BindAuraLaneEnabled(ctx, W.SwitchAt(section, "Visible", 24, -62, 104), lane)
        enable._msuf2GroupFrameGateAlwaysEnabled = true
        local dropdownW = max(180, floor((inner - 126 - gap * 2) / 2))
        local anchorX = 24 + 126 + gap
        local growthX = anchorX + dropdownW + gap
        local function Dropdown(label, x, values, key, fallback)
            local widget = BindNestedDropdown(ctx, W.Dropdown(section, label, values, dropdownW),
                function() return AuraGroup(CurrentScope(), lane) end, key, fallback, "auras",
                AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. AuraCatalogToken(key)))
            W.MoveWidget(widget, section, x, -34, dropdownW, "LEFT")
            controls[#controls + 1] = widget
            return widget
        end
        Dropdown("Anchor", anchorX, anchors, "anchor", defaults.anchor)
        Dropdown("Growth", growthX, growthValues, "growth", defaults.growth)
        local col4 = floor((inner - gap * 3) / 4)
        local function Slider(label, col, y, minValue, maxValue, key, fallback)
            local assistantContract
            if lane == "externals" and key == "layer" then
                assistantContract = {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "Layer targets the selected Group scope's External Defensive container.",
                    assistantSettingKeys = GroupAuraSettingKeys(scope, ".auras.externals.layer"),
                }
            end
            local widget = BindNestedSlider(ctx, W.Slider(section, label, minValue, maxValue, 1, col4),
                function() return AuraGroup(CurrentScope(), lane) end, key, fallback, "auras",
                AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. AuraCatalogToken(key), nil,
                    assistantContract))
            W.MoveWidget(widget, section, 24 + (col - 1) * (col4 + gap), y, col4)
            controls[#controls + 1] = widget
            return widget
        end
        Slider("X", 1, -92, -300, 300, "x", 0)
        Slider("Y", 2, -92, -300, 300, "y", 0)
        Slider("Max", 3, -92, 0, 20, "max", defaults.max)
        Slider("Size", 4, -92, 8, 80, "size", defaults.size)
        local perRowControl = Slider("Per row", 1, -146, 1, 20, "perRow", defaults.perRow)
        Slider("Gap", 2, -146, 0, 12, "spacing", defaults.spacing)
        Slider("Layer (0-30)", 3, -146, 0, 30, "layer", defaults.layer)
        M.TrackRefresh(ctx, function()
            local shown = LaneBackendEnabled(CurrentScope(), lane)
            SetOptionEnabled(enable, true)
            SetOptionsEnabled(controls, shown)
            local growth = tostring(AuraGroup(CurrentScope(), lane).growth or defaults.growth):upper()
            SetOptionEnabled(perRowControl, shown and growth ~= "UP" and growth ~= "DOWN")
        end)
    elseif type(M.BuildAuras3GroupLaneWorkspace) == "function" then
        M.BuildAuras3GroupLaneWorkspace(ctx, auraBuilder, scope, lane, { tool = tool, compact = true })
    end

    if GP.BuildSpellIndicatorsSection then GP.BuildSpellIndicatorsSection(ctx, b, RefreshPage) end
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 28 })
