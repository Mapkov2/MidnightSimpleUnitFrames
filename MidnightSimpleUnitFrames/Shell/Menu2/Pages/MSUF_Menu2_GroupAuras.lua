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
local floor = math.floor
local max = math.max
local min = math.min
local C_Timer = _G.C_Timer
local VT = M.ValueTextList
local AURA_ANCHORS, STATUS_ICON_ANCHORS, SPELL_GROWTH_VALUES, ScopeSection, CurrentScope, AuraGroup, AurasRoot, QueueGF, RefreshContext, BindNestedSlider, BindNestedStrataSlider, BindNestedDropdown, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, OnOffBadge, BadgeNumber, OptionText, FrameStrataCount = M.Pick(GP, [[AURA_ANCHORS STATUS_ICON_ANCHORS SPELL_GROWTH_VALUES ScopeSection CurrentScope AuraGroup AurasRoot QueueGF RefreshContext BindNestedSlider BindNestedStrataSlider BindNestedDropdown SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus OnOffBadge BadgeNumber OptionText FrameStrataCount]])
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
local function AuraControlMeta(ctx, path, classification)
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
    if meta.classification == "action" then meta.actionKey = identity end
    return meta
end
local function RegisterAuraControl(ctx, widget, label, kind, path, classification)
    if not widget or type(M.RegisterSearchWidget) ~= "function" then return widget end
    local meta = AuraControlMeta(ctx, path, classification)
    meta.label = label
    meta.kind = kind
    M.RegisterSearchWidget(widget, meta)
    return widget
end
local MUTED = ThemeColor("muted", { 0.55, 0.66, 0.82, 0.92 })
local GF_AURA_WORKSPACE_TOOLS = {
    { value = "layout", text = "Layout" },
    { value = "filters", text = "Filters" },
    { value = "blacklist", text = "Blacklist" },
}
local GF_AURA_WORKSPACE_TOOL_OK = { layout = true, filters = true, blacklist = true }
local GF_AURA_WORKSPACE_TAB_STYLE = {
    bg = { 0.012, 0.025, 0.052, 0.90 },
    border = { 0.070, 0.130, 0.235, 0.52 },
    textColor = { 0.78, 0.86, 0.97, 0.96 },
    hoverBg = { 0.024, 0.052, 0.100, 0.96 },
    hoverBorder = { 0.120, 0.245, 0.455, 0.78 },
    activeBg = { 0.032, 0.090, 0.205, 0.97 },
    activeBorder = { 0.150, 0.385, 0.760, 0.92 },
    activeTextColor = { 0.94, 0.98, 1.00, 1.00 },
}
local function CurrentAuraWorkspaceTool(scope, lane)
    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
    local scopeState = M.gfAuraToolSelection[scope]
    if type(scopeState) ~= "table" then scopeState = {}; M.gfAuraToolSelection[scope] = scopeState end
    local tool = scopeState[lane]
    if not GF_AURA_WORKSPACE_TOOL_OK[tool] then tool = "layout"; scopeState[lane] = tool end
    return tool
end
local function SetAuraWorkspaceTool(scope, lane, tool)
    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
    local scopeState = M.gfAuraToolSelection[scope]
    if type(scopeState) ~= "table" then scopeState = {}; M.gfAuraToolSelection[scope] = scopeState end
    scopeState[lane] = GF_AURA_WORKSPACE_TOOL_OK[tool] and tool or "layout"
end
local groupAuraRebuildSerial = 0
local function RestoreGroupAuraScroll(offset, key, serial)
    if M.activeKey ~= key or serial ~= groupAuraRebuildSerial then return end
    local scroll = M.scrollFrame
    if not (scroll and scroll.SetVerticalScroll) then return end
    local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or offset
    scroll:SetVerticalScroll(min(max(tonumber(offset) or 0, 0), max(tonumber(range) or 0, 0)))
    if M.RefreshPinnedPreviews then M.RefreshPinnedPreviews(scroll) end
end
local function RebuildGroupAuraPage(ctx)
    local key = (ctx and ctx.key) or M.activeKey or "gf_auras"
    if not (M.InvalidatePage and M.SelectPage and M.frame and M.frame.IsShown and M.frame:IsShown()) then return end
    local offset = M.scrollFrame and M.scrollFrame.GetVerticalScroll and M.scrollFrame:GetVerticalScroll() or 0
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
    W.LabelAt(section, "Edit", 16, -36, 58, "GameFontNormalSmall", ThemeColor("accent", { 0.20, 0.60, 1.00, 1.00 }))
    local x, gap = 88, 8
    local available = max(360, (tonumber(width) or 720) - x - 24)
    local buttonW = floor((available - gap * 2) / 3)
    local buttons = {}
    for i = 1, #GF_AURA_WORKSPACE_TOOLS do
        local item = GF_AURA_WORKSPACE_TOOLS[i]
        local btn = W.TopButton(section, item.text, buttonW, 24, GF_AURA_WORKSPACE_TAB_STYLE, item.value == CurrentAuraWorkspaceTool(scope, lane))
        btn:SetPoint("TOPLEFT", section, "TOPLEFT", x + (i - 1) * (buttonW + gap), -30)
        btn:SetScript("OnClick", function()
            if CurrentAuraWorkspaceTool(scope, lane) == item.value then return end
            SetAuraWorkspaceTool(scope, lane, item.value)
            RebuildGroupAuraPage(ctx)
        end)
        RegisterAuraControl(ctx, btn, item.text, "button",
            "group-workspace.lane." .. AuraCatalogToken(lane, "lane") .. ".tool." .. AuraCatalogToken(item.value), "ephemeral")
        buttons[item.value] = btn
    end
    M.TrackRefresh(ctx, function()
        local current = CurrentAuraWorkspaceTool(scope, lane)
        for i = 1, #GF_AURA_WORKSPACE_TOOLS do
            local item = GF_AURA_WORKSPACE_TOOLS[i]
            if buttons[item.value].SetActive then buttons[item.value]:SetActive(item.value == current) end
        end
    end)
end
local function NativeAuraKey(groupKey)
    return groupKey == "buff" and "buffs" or "debuffs"
end
local function LaneBackendEnabled(scope, groupKey)
    local root = AurasRoot and AurasRoot(scope)
    local group = AuraGroup(scope, groupKey)
    if not root then return group.enabled ~= false end
    return root.enabled ~= false and group.enabled ~= false
end
local function BindAuraLaneEnabled(ctx, widget, groupKey)
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
        AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(groupKey, "lane") .. ".enabled"))
    return widget
end
local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)
    local function RefreshPage() M.CallIf(M.SelectPage, ctx.key) end
    local AURA_POSITION_ANCHORS = (#STATUS_ICON_ANCHORS > 0 and STATUS_ICON_ANCHORS) or AURA_ANCHORS
    local AURA_GROWTH_VALUES = (#SPELL_GROWTH_VALUES > 0 and SPELL_GROWTH_VALUES)
        or VT("RIGHTDOWN", "Right then Down", "LEFTDOWN", "Left then Down", "RIGHTUP", "Right then Up", "LEFTUP", "Left then Up")
    local AURA_GROUP_DEFAULTS = {
        buff = {
            enabledLabel = "Buffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "BOTTOMRIGHT", growth = "LEFTUP", size = 22, perRow = 4, max = 6, spacing = 1, layer = 5,
            layoutHeight = 520,
        },
        debuff = {
            enabledLabel = "Debuffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6,
            layoutHeight = 590,
        },
    }
    local function BuildDebuffPTRNotice(section, leftX, y, width)
        W.ControlCard(section, "Tracked Debuff IDs", nil, leftX - 14, y, width + 28, 76)
        W.Text(section, "PTR 12.1 does not apply exact SpellID include/exclude identity filters to HARMFUL auras on friendly units. Use normal Debuffs/dispels here; native tracked debuff icons would over-match.", leftX, y - 36, width, MUTED)
    end
    local function BuildAuraGroupSection(groupKey, title)
        local def = AURA_GROUP_DEFAULTS[groupKey]
        local scope = CurrentScope()
        local tool = CurrentAuraWorkspaceTool(scope, groupKey)
        local sectionHeight = tool == "filters" and 360 or (tool == "blacklist" and 920 or def.layoutHeight)
        local section = b:CollapsibleSection(groupKey == "buff" and "buffs" or "debuffs", title, sectionHeight, false)
        local sectionW = section._msuf2Width or b.width or 720
        BuildAuraWorkspaceTabs(ctx, section, scope, groupKey, sectionW)
        local leftX = 30
        local rightX = max(430, min(520, floor(sectionW * 0.50)))
        local leftW = max(270, min(340, rightX - leftX - 70))
        local rightW = max(280, min(360, sectionW - rightX - 42))
        local controls, enable = {}, nil
        if tool == "layout" then
            local contentY = -72
            W.ControlCardBackdrop(section, leftX - 14, -38 + contentY, leftW + 28, 42)
            W.ControlCard(section, "Placement", nil, leftX - 14, -84 + contentY, leftW + 28, 286)
            W.ControlCard(section, "Icon Grid", nil, rightX - 14, -84 + contentY, rightW + 28, 326)
            enable = BindAuraLaneEnabled(ctx, W.SwitchAt(section, def.enabledLabel, leftX, -44 + contentY, 190), groupKey)
            enable._msuf2GroupFrameGateAlwaysEnabled = true
            controls = M.BuildControlSpecs({
                { "dropdown", "Anchor", AURA_POSITION_ANCHORS, "anchor", def.anchor, "auras", leftX, -118 + contentY, leftW, "LEFT" },
                { "dropdown", "Growth", AURA_GROWTH_VALUES, "growth", def.growth, "auras", leftX, -172 + contentY, leftW, "LEFT" },
                { "slider", "Offset X", -160, 160, 1, "x", 0, "auras", leftX, -226 + contentY, leftW },
                { "slider", "Offset Y", -160, 160, 1, "y", 0, "auras", leftX, -280 + contentY, leftW },
                { "strata", "Frame Strata", 0, (FrameStrataCount or 9) - 1, 1, "strata", "AUTO", "auras", leftX, -334 + contentY, leftW },
                { "slider", def.maxLabel, 0, def.maxMax, 1, "max", def.max, "auras", rightX, -118 + contentY, rightW },
                { "slider", "Icon size", 8, 64, 1, "size", def.size, "auras", rightX, -172 + contentY, rightW },
                { "slider", "Per row", 1, 20, 1, "perRow", def.perRow, "auras", rightX, -226 + contentY, rightW },
                { "slider", "Spacing", 0, 12, 1, "spacing", def.spacing, "auras", rightX, -280 + contentY, rightW },
                { "slider", "Layer (Z-Order)", 0, 30, 1, "layer", def.layer, "auras", rightX, -334 + contentY, rightW },
            }, {
                dropdown = function(s) local widget = BindNestedDropdown(ctx, W.Dropdown(section, s[2], s[3], s[9]), function() return AuraGroup(CurrentScope(), groupKey) end, s[4], s[5], s[6],
                    AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(groupKey) .. ".layout." .. AuraCatalogToken(s[4]))); W.MoveWidget(widget, section, s[7], s[8], s[9], s[10] or "CENTER"); return widget end,
                slider = function(s) local widget = BindNestedSlider(ctx, W.Slider(section, s[2], s[3], s[4], s[5], s[11]), function() return AuraGroup(CurrentScope(), groupKey) end, s[6], s[7], s[8],
                    AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(groupKey) .. ".layout." .. AuraCatalogToken(s[6]))); W.MoveWidget(widget, section, s[9], s[10], s[11], s[12] or "CENTER"); return widget end,
                strata = function(s) local widget = BindNestedStrataSlider(ctx, W.Slider(section, s[2], s[3], s[4], s[5], s[11]), function() return AuraGroup(CurrentScope(), groupKey) end, s[6], s[7], s[8],
                    AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(groupKey) .. ".layout." .. AuraCatalogToken(s[6]))); W.MoveWidget(widget, section, s[9], s[10], s[11], s[12] or "CENTER"); return widget end,
            })
            if groupKey == "debuff" then BuildDebuffPTRNotice(section, leftX, -410 + contentY, sectionW - 72) end
        elseif type(M.BuildAuras3GroupLaneWorkspace) == "function" then
            M.BuildAuras3GroupLaneWorkspace(ctx, b, scope, groupKey, {
                parent = section,
                originY = -54,
                tool = tool,
            })
        end
        local function RefreshAuraGroupState()
            local cfg = AuraGroup(CurrentScope(), groupKey)
            local groupEnabled = LaneBackendEnabled(CurrentScope(), groupKey)
            if tool == "layout" then
                SetOptionsEnabled(controls, groupEnabled)
                SetOptionEnabled(enable, true)
            end
            SetSectionBadgesAndStatus(section, {
                OnOffBadge(groupEnabled, "Shown", "Hidden"),
                { text = "Max " .. BadgeNumber(cfg.max or def.max), kind = groupEnabled and "info" or "muted" },
                { text = BadgeNumber(cfg.size or def.size) .. "px", kind = groupEnabled and "info" or "muted" },
            })
        end
        M.TrackCollapsibleRefresh(ctx, section, RefreshAuraGroupState)
    end
    BuildAuraGroupSection("buff", "Buffs")
    if GP.BuildSpellIndicatorsSection then
        GP.BuildSpellIndicatorsSection(ctx, b, RefreshPage)
    end
    BuildAuraGroupSection("debuff", "Debuffs")
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 22 })
