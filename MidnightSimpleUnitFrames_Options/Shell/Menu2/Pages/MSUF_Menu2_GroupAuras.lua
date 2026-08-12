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
local VT = M.ValueTextList
local C_Timer = M.MenuTimer or _G.C_Timer
local GF, RefreshGFPreview, AURA_ANCHORS, STATUS_ICON_ANCHORS, SPELL_GROWTH_VALUES, ScopeSection, CurrentScope, AuraGroup, AurasRoot, QueueGF, RefreshContext, BindNestedSlider, BindNestedDropdown, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, OnOffBadge, BadgeNumber, OptionText = M.Pick(GP, [[GF RefreshGFPreview AURA_ANCHORS STATUS_ICON_ANCHORS SPELL_GROWTH_VALUES ScopeSection CurrentScope AuraGroup AurasRoot QueueGF RefreshContext BindNestedSlider BindNestedDropdown SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus OnOffBadge BadgeNumber OptionText]])
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
local GF_AURA_WORKSPACE_TOOL_OK = { layout = true, filters = true, blacklist = GF_AURA_BLACKLIST_AVAILABLE, style = true }
local function CurrentAuraWorkspaceTool(scope, lane)
    M.gfAuraToolSelection = M.gfAuraToolSelection or {}
    local scopeState = M.gfAuraToolSelection[scope]
    if type(scopeState) ~= "table" then scopeState = {}; M.gfAuraToolSelection[scope] = scopeState end
    local tool = scopeState[lane]
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
local function RebuildGroupAuraPage(ctx)
    M.CallIf(M.RebuildPageKeepingScroll, (ctx and ctx.key) or M.activeKey or "gf_auras")
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
        values = lane == "externals"
            and { GF_AURA_WORKSPACE_TOOLS[1], GF_AURA_WORKSPACE_TOOLS[4] }
            or GF_AURA_WORKSPACE_TOOLS,
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
    local sharedLane = lane == "debuff" and "debuff" or "buff"
    local openStyle = T.Button(section, "Shared Aura Style", 150, 22)
    openStyle:SetPoint("TOPRIGHT", section, "TOPRIGHT", -16, -76)
    if T.CenterButtonLabel then T.CenterButtonLabel(openStyle) end
    openStyle:SetScript("OnClick", function()
        M.SetMenuStateValue("auraAppearanceContainer", sharedLane)
        M.SetMenuStateValue("auraStyleGFLane", sharedLane)
        if M.SelectPage then M.SelectPage("auras3_styling") end
    end)
    RegisterAuraControl(ctx, openStyle, "Shared Aura Style", "button", "group-workspace.open-aura-style", "navigation", "auras3_styling")
    if type(M.AddTooltip) == "function" then
        M.AddTooltip(openStyle, "Shared Aura Style",
            "Opens the global Aura icon theme: border, shadow, colors, lane padding and native Player weapon enchants. This GroupFrame's individual Style stays here.",
            { hook = true, titleAsLine = true })
    end
    W.Text(section, "Individual Style is edited here. Shared icon theme: Appearance > Aura Style.", 16, -84, sectionW - 198, MUTED)
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
    local function CombatLocked()
        if type(M.IsConfigCombatLocked) == "function" then return M.IsConfigCombatLocked() == true end
        return _G.InCombatLockdown and _G.InCombatLockdown() or false
    end
    local function RefreshAuraPreviews(scope)
        if CombatLocked() then return false end
        M.CallIf(RefreshGFPreview, scope, { auraOnly = true })
        return true
    end
    local function BindLiveAuraSlider(widget, scope, lane, key, fallback, meta)
        local pendingApply, pendingScope, releaseScheduled
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
            pendingApply = nil
            pendingScope = nil
            releaseScheduled = nil
            QueueGF(applyScope, "auras")
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
        meta = meta or AuraControlMeta(ctx,
            "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. AuraCatalogToken(key))
        meta.step, meta.roundStep = 1, true
        M.BindNumberWidget(ctx, widget,
            function() return tonumber(AuraGroup(CurrentScope(), lane)[key]) or fallback end,
            function(value)
                local activeScope = CurrentScope()
                value = floor((tonumber(value) or fallback or 0) + 0.5)
                local group = AuraGroup(activeScope, lane)
                if group[key] == value then return end
                group[key] = value
                pendingApply = true
                pendingScope = activeScope
                -- Every drag tick repaints both preview surfaces from the same
                -- freshly compiled Aura lane, while live GroupFrames stay on
                -- the bounded release-time apply below.
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
    local function BindLiveAuraDropdown(widget, scope, lane, key, fallback, meta)
        M.BindDropdownWidget(ctx, widget,
            function() return AuraGroup(CurrentScope(), lane)[key] or fallback end,
            function(value)
                if CombatLocked() then return end
                local activeScope = CurrentScope()
                local group = AuraGroup(activeScope, lane)
                value = value or fallback
                if group[key] == value then return end
                group[key] = value
                RefreshAuraPreviews(activeScope)
                QueueGF(activeScope, "auras")
                if key == "growth" then M.CallIf(RefreshContext, ctx) end
            end,
            meta or AuraControlMeta(ctx,
                "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. AuraCatalogToken(key)))
        return widget
    end
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
    if type(M.AttachAuraFontsAndColors) == "function" then
        M.AttachAuraFontsAndColors(top, M.Format("Auras"), scope)
    end

    local rootSection = auraBuilder:Section("Group Aura Visibility", 88)
    local rootWidth = rootSection._msuf2Width or auraBuilder.width or 720
    local rootEnabled = BindAuraRootEnabled(ctx,
        W.SwitchAt(rootSection, "Enable group auras", 24, -50, rootWidth - 48))
    rootEnabled._msuf2GroupFrameGateAlwaysEnabled = true

    if tool == "layout" and lane == "externals" then
        local filterSection = auraBuilder:Section("External Defensive Filtering", 88)
        local filterWidth = filterSection._msuf2Width or auraBuilder.width or 720
        local autoBlacklist = W.SwitchAt(filterSection, "Auto-blacklist from Buffs", 24, -50, filterWidth - 48)
        M.BindBoolWidget(ctx, autoBlacklist,
            function()
                return AuraGroup(CurrentScope(), "externals").autoBlacklistBuffs ~= false
            end,
            function(value)
                local activeScope = CurrentScope()
                AuraGroup(activeScope, "externals").autoBlacklistBuffs = value == true
                if QueueGF then QueueGF(activeScope, "auras") end
                M.CallIf(RefreshContext, ctx)
            end,
            AuraControlMeta(ctx, "group-workspace.lane.externals.auto-blacklist-buffs", nil, {
                assistantDisposition = "dynamic",
                assistantDispositionReason = "This toggle targets duplicate handling between the selected Group scope's External Defensive and Buff containers.",
                -- This workspace control is rebuilt for Party and Raid states
                -- under one stable catalog identity. Keep its finite route set
                -- complete regardless of which state was captured last.
                assistantSettingKeys = AllGroupAuraSettingKeys(".auras.externals.autoBlacklistBuffs"),
            }))
        if type(M.AddTooltip) == "function" then
            M.AddTooltip(autoBlacklist, "Auto-blacklist from Buffs",
                "While External Defensives is visible and Max is above 0, hides every aura Blizzard classifies as EXTERNAL_DEFENSIVE from the normal Buffs container. If External Defensives is disabled, those auras remain visible in Buffs.",
                { hook = true, titleAsLine = true })
        end
    end

    if tool == "layout" then
        local title = lane == "debuff" and "Debuff Layout"
            or (lane == "externals" and "External Defensive Layout" or "Buff Layout")
        local section = auraBuilder:Section(title, 202)
        local w = section._msuf2Width or auraBuilder.width or 720
        local inner, gap = w - 48, 10
        local controls = {}
        local enable = BindAuraLaneEnabled(ctx, W.SwitchAt(section, "Visible", 24, -62, 104), lane)
        enable._msuf2GroupFrameGateAlwaysEnabled = true
        local dropdownW = max(180, floor((inner - 126 - gap * 2) / 2))
        local anchorX = 24 + 126 + gap
        local growthX = anchorX + dropdownW + gap
        local function Dropdown(label, x, values, key, fallback, y, width)
            width = width or dropdownW
            local assistantContract
            if lane == "externals" and key == "growth" then
                assistantContract = {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "Growth targets the selected Group scope's External Defensive container.",
                    assistantSettingKeys = GroupAuraSettingKeys(scope, ".auras.externals.growth"),
                }
            end
            local widget = BindLiveAuraDropdown(W.Dropdown(section, label, values, width),
                scope, lane, key, fallback,
                AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. AuraCatalogToken(key), nil,
                    assistantContract))
            W.MoveWidget(widget, section, x, y or -34, width, "LEFT")
            controls[#controls + 1] = widget
            return widget
        end
        Dropdown("Anchor", anchorX, anchors, "anchor", defaults.anchor)
        Dropdown("Growth", growthX, growthValues, "growth", defaults.growth)
        local col4 = floor((inner - gap * 3) / 4)
        local function Slider(label, col, y, minValue, maxValue, key, fallback)
            local assistantContract
            if lane == "externals" and (key == "layer" or key == "max") then
                assistantContract = {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = (key == "layer" and "Layer" or "Max") .. " targets the selected Group scope's External Defensive container.",
                    assistantSettingKeys = GroupAuraSettingKeys(scope, ".auras.externals." .. key),
                }
            end
            local widget = BindLiveAuraSlider(W.Slider(section, label, minValue, maxValue, 1, col4),
                scope, lane, key, fallback,
                AuraControlMeta(ctx, "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout." .. AuraCatalogToken(key), nil,
                    assistantContract))
            W.MoveWidget(widget, section, 24 + (col - 1) * (col4 + gap), y, col4)
            controls[#controls + 1] = widget
            return widget
        end
        Slider("Max", 1, -92, 0, 20, "max", defaults.max)
        Slider("Size", 2, -92, 8, 80, "size", defaults.size)
        Slider("Layer (0-30)", 3, -92, 0, 30, "layer", defaults.layer)
        local perRowControl = Slider("Per row", 1, -146, 1, 20, "perRow", defaults.perRow)
        Slider("Gap", 2, -146, 0, 12, "spacing", defaults.spacing)
        local iconScale = BindLiveAuraSlider(W.Slider(section, "Icon Scale (%)", 20, 300, 1, col4),
            scope, lane, "iconScale", 100,
            AuraControlMeta(ctx,
                "group-workspace.lane." .. AuraCatalogToken(lane) .. ".layout.icon-scale", nil, {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "Icon Scale targets the selected Group scope's Aura container.",
                    assistantSettingKeys = GroupAuraSettingKeys(scope, ".auras." .. tostring(lane) .. ".iconScale"),
                }))
        W.MoveWidget(iconScale, section, 24 + 2 * (col4 + gap), -146, col4)
        controls[#controls + 1] = iconScale
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
M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 33 })
