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
local VT = M.ValueTextList
local AURA_ANCHORS, STATUS_ICON_ANCHORS, SPELL_GROWTH_VALUES, ScopeSection, CurrentScope, AuraGroup, AurasRoot, QueueGF, RefreshContext, BindNestedSlider, BindNestedStrataSlider, BindNestedDropdown, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionBadgesAndStatus, OnOffBadge, BadgeNumber, SpellIndicators, QueueSpellIndicators, SpellSpecValues, EffectiveSpellSpec, SpellAuraValues, SetCurrentSpellAura, ClearCurrentSpellAura, CurrentSpellAura, CurrentSpellConfig, OptionText, FrameStrataCount = M.Pick(GP, [[AURA_ANCHORS STATUS_ICON_ANCHORS SPELL_GROWTH_VALUES ScopeSection CurrentScope AuraGroup AurasRoot QueueGF RefreshContext BindNestedSlider BindNestedStrataSlider BindNestedDropdown SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionBadgesAndStatus OnOffBadge BadgeNumber SpellIndicators QueueSpellIndicators SpellSpecValues EffectiveSpellSpec SpellAuraValues SetCurrentSpellAura ClearCurrentSpellAura CurrentSpellAura CurrentSpellConfig OptionText FrameStrataCount]])
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
SetCurrentSpellAura = SetCurrentSpellAura or function(scope, auraName)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    M.gfSpellIndicatorSelection[scope] = auraName or ""
end
ClearCurrentSpellAura = ClearCurrentSpellAura or function(scope)
    M.gfSpellIndicatorSelection = M.gfSpellIndicatorSelection or {}
    M.gfSpellIndicatorSelection[scope] = nil
end
local function ThemeColor(key, fallback)
    local colors = T and T.colors
    return colors and colors[key] or fallback
end
local MUTED = ThemeColor("muted", { 0.55, 0.66, 0.82, 0.92 })
local DIM = ThemeColor("dim", { 0.36, 0.44, 0.58, 0.88 })
local function NativeAuraKey(groupKey)
    return groupKey == "buff" and "buffs" or "debuffs"
end
local function QueueAuraRefresh(scope, reason)
    scope = scope or CurrentScope()
    if QueueSpellIndicators then QueueSpellIndicators(scope) end
    if QueueGF then QueueGF(scope, reason or "auras") end
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RequestScope) == "function" then
        a3.RequestScope(scope, "GROUP_TRACKED_BUFFS_MENU")
    end
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
        end)
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
            height = 770,
        },
        debuff = {
            enabledLabel = "Debuffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6,
            height = 486,
        },
    }
    local function EnsureTrackedSpellSpec(scope)
        local gf = MSUF and MSUF.GF
        local si = gf and gf.SpellIndicators
        local specKey = EffectiveSpellSpec and EffectiveSpellSpec(scope)
        local cfg = SpellIndicators and SpellIndicators(scope)
        if si and type(si.EnsureSpecConfig) == "function" and cfg and specKey then
            si.EnsureSpecConfig(cfg, specKey)
        end
        return specKey
    end
    local function CurrentTrackedBuffCount(scope)
        local cfg = SpellIndicators and SpellIndicators(scope)
        local specKey = EnsureTrackedSpellSpec(scope)
        local specCfg = cfg and cfg.specs and specKey and cfg.specs[specKey]
        local count = 0
        if type(specCfg) == "table" then
            for _, entry in pairs(specCfg) do
                if type(entry) == "table" and entry.enabled ~= false then count = count + 1 end
            end
        end
        return count
    end
    local function BindTrackedBool(ctx, widget, read, write)
        M.BindBoolWidget(ctx, widget,
            function() return read(CurrentScope()) end,
            function(v)
                write(CurrentScope(), v and true or false)
                QueueAuraRefresh(CurrentScope(), "auras")
                M.CallIf(RefreshContext, ctx)
            end)
        return widget
    end
    local function BuildTrackedBuffControls(section, sectionW, leftX, rightX, leftW, rightW, def)
        local trackedY = -412
        W.ControlCard(section, "Tracked Buff Icons", nil, leftX - 14, trackedY, leftW + 28, 286)
        W.ControlCard(section, "Tracked Buff Layout", nil, rightX - 14, trackedY, rightW + 28, 340)
        local enable = BindTrackedBool(ctx, W.SwitchAt(section, "Tracked Buff Icons", leftX, trackedY - 34, 210),
            function(scope)
                local si = SpellIndicators and SpellIndicators(scope)
                local buff = AuraGroup(scope, "buff")
                if buff.trackedEnabled ~= nil then return buff.trackedEnabled == true end
                return si and si.enabled == true or false
            end,
            function(scope, value)
                local si = SpellIndicators and SpellIndicators(scope)
                if si then si.enabled = value end
                AuraGroup(scope, "buff").trackedEnabled = value
            end)
        local spec = W.Dropdown(section, "Spec", function() return SpellSpecValues and SpellSpecValues() or VT("auto", "Auto-Detect") end, leftW)
        W.MoveWidget(spec, section, leftX, trackedY - 88, leftW, "LEFT")
        M.BindDropdownWidget(ctx, spec,
            function()
                local si = SpellIndicators and SpellIndicators(CurrentScope())
                return si and si.spec or "auto"
            end,
            function(value)
                local scope = CurrentScope()
                local si = SpellIndicators and SpellIndicators(scope)
                if si then si.spec = value or "auto" end
                EnsureTrackedSpellSpec(scope)
                QueueAuraRefresh(scope, "auras")
                M.CallIf(RefreshContext, ctx)
            end)
        local spell = W.Dropdown(section, "Spell", function() return SpellAuraValues and SpellAuraValues(CurrentScope()) or VT("", "No spells for current spec") end, leftW)
        W.MoveWidget(spell, section, leftX, trackedY - 142, leftW, "LEFT")
        M.BindDropdownWidget(ctx, spell,
            function() return CurrentSpellAura and CurrentSpellAura(CurrentScope()) or "" end,
            function(value)
                SetCurrentSpellAura(CurrentScope(), value or "")
                M.CallIf(RefreshContext, ctx)
            end)
        local trackSpell = BindTrackedBool(ctx, W.SwitchAt(section, "Track selected spell", leftX, trackedY - 186, 230),
            function(scope)
                EnsureTrackedSpellSpec(scope)
                local cfg = CurrentSpellConfig and CurrentSpellConfig(scope, false)
                return cfg and cfg.enabled ~= false or false
            end,
            function(scope, value)
                EnsureTrackedSpellSpec(scope)
                local cfg = CurrentSpellConfig and CurrentSpellConfig(scope, value == true)
                if cfg then cfg.enabled = value end
            end)
        local onlyOwn = BindTrackedBool(ctx, W.SwitchAt(section, "Only my casts", leftX, trackedY - 220, 210),
            function(scope) return AuraGroup(scope, "buff").trackedOnlyOwn ~= false end,
            function(scope, value) AuraGroup(scope, "buff").trackedOnlyOwn = value end)
        local layoutControls = M.BuildControlSpecs({
            { "dropdown", "Anchor", AURA_POSITION_ANCHORS, "trackedAnchor", "TOPLEFT", "auras", rightX, trackedY - 54, rightW, "LEFT" },
            { "dropdown", "Growth", AURA_GROWTH_VALUES, "trackedGrowth", "RIGHTDOWN", "auras", rightX, trackedY - 108, rightW, "LEFT" },
            { "slider", "Max tracked", 0, 20, 1, "trackedMax", 8, "auras", rightX, trackedY - 162, rightW },
            { "slider", "Icon size", 8, 64, 1, "trackedSize", def.size, "auras", rightX, trackedY - 216, rightW },
            { "slider", "Layer (Z-Order)", 0, 30, 1, "trackedLayer", 9, "auras", rightX, trackedY - 270, rightW },
            { "strata", "Frame Strata", 0, (FrameStrataCount or 9) - 1, 1, "trackedStrata", "AUTO", "auras", rightX, trackedY - 324, rightW },
        }, {
            dropdown = function(s) local widget = BindNestedDropdown(ctx, W.Dropdown(section, s[2], s[3], s[9]), function() return AuraGroup(CurrentScope(), "buff") end, s[4], s[5], s[6]); W.MoveWidget(widget, section, s[7], s[8], s[9], s[10] or "CENTER"); return widget end,
            slider = function(s) local widget = BindNestedSlider(ctx, W.Slider(section, s[2], s[3], s[4], s[5], s[11]), function() return AuraGroup(CurrentScope(), "buff") end, s[6], s[7], s[8]); W.MoveWidget(widget, section, s[9], s[10], s[11], s[12] or "CENTER"); return widget end,
            strata = function(s) local widget = BindNestedStrataSlider(ctx, W.Slider(section, s[2], s[3], s[4], s[5], s[11]), function() return AuraGroup(CurrentScope(), "buff") end, s[6], s[7], s[8]); W.MoveWidget(widget, section, s[9], s[10], s[11], s[12] or "CENTER"); return widget end,
        })
        W.Text(section, "Native 12.1 SpellID include filters are used here for HELPFUL auras on friendly Group Frames.", leftX, trackedY - 254, leftW, MUTED)
        return { enable, spec, spell, trackSpell, onlyOwn, unpack(layoutControls) }
    end
    local function BuildDebuffPTRNotice(section, leftX, y, width)
        W.ControlCard(section, "Tracked Debuff IDs", nil, leftX - 14, y, width + 28, 76)
        W.Text(section, "PTR 12.1 does not apply exact SpellID include/exclude identity filters to HARMFUL auras on friendly units. Use normal Debuffs/dispels here; native tracked debuff icons would over-match.", leftX, y - 36, width, MUTED)
    end
    local function BuildAuraGroupSection(groupKey, title)
        local def = AURA_GROUP_DEFAULTS[groupKey]
        local section = b:CollapsibleSection(groupKey == "buff" and "buffs" or "debuffs", title, def.height, false)
        local sectionW = section._msuf2Width or b.width or 720
        local leftX = 30
        local rightX = max(430, min(520, floor(sectionW * 0.50)))
        local leftW = max(270, min(340, rightX - leftX - 70))
        local rightW = max(280, min(360, sectionW - rightX - 42))
        do
            W.ControlCardBackdrop(section, leftX - 14, -38, leftW + 28, 42)
            W.ControlCard(section, "Placement", nil, leftX - 14, -84, leftW + 28, 286)
            W.ControlCard(section, "Icon Grid", nil, rightX - 14, -84, rightW + 28, 326)
        end
        local enable = BindAuraLaneEnabled(ctx, W.SwitchAt(section, def.enabledLabel, leftX, -44, 190), groupKey)
        enable._msuf2GroupFrameGateAlwaysEnabled = true
        local controls = M.BuildControlSpecs({
            { "dropdown", "Anchor", AURA_POSITION_ANCHORS, "anchor", def.anchor, "auras", leftX, -118, leftW, "LEFT" },
            { "dropdown", "Growth", AURA_GROWTH_VALUES, "growth", def.growth, "auras", leftX, -172, leftW, "LEFT" },
            { "slider", "Offset X", -160, 160, 1, "x", 0, "auras", leftX, -226, leftW },
            { "slider", "Offset Y", -160, 160, 1, "y", 0, "auras", leftX, -280, leftW },
            { "strata", "Frame Strata", 0, (FrameStrataCount or 9) - 1, 1, "strata", "AUTO", "auras", leftX, -334, leftW },
            { "slider", def.maxLabel, 0, def.maxMax, 1, "max", def.max, "auras", rightX, -118, rightW },
            { "slider", "Icon size", 8, 64, 1, "size", def.size, "auras", rightX, -172, rightW },
            { "slider", "Per row", 1, 20, 1, "perRow", def.perRow, "auras", rightX, -226, rightW },
            { "slider", "Spacing", 0, 12, 1, "spacing", def.spacing, "auras", rightX, -280, rightW },
            { "slider", "Layer (Z-Order)", 0, 30, 1, "layer", def.layer, "auras", rightX, -334, rightW },
        }, {
            dropdown = function(s) local widget = BindNestedDropdown(ctx, W.Dropdown(section, s[2], s[3], s[9]), function() return AuraGroup(CurrentScope(), groupKey) end, s[4], s[5], s[6]); W.MoveWidget(widget, section, s[7], s[8], s[9], s[10] or "CENTER"); return widget end,
            slider = function(s) local widget = BindNestedSlider(ctx, W.Slider(section, s[2], s[3], s[4], s[5], s[11]), function() return AuraGroup(CurrentScope(), groupKey) end, s[6], s[7], s[8]); W.MoveWidget(widget, section, s[9], s[10], s[11], s[12] or "CENTER"); return widget end,
            strata = function(s) local widget = BindNestedStrataSlider(ctx, W.Slider(section, s[2], s[3], s[4], s[5], s[11]), function() return AuraGroup(CurrentScope(), groupKey) end, s[6], s[7], s[8]); W.MoveWidget(widget, section, s[9], s[10], s[11], s[12] or "CENTER"); return widget end,
        })
        if groupKey == "debuff" then BuildDebuffPTRNotice(section, leftX, -410, sectionW - 72) end
        local function RefreshAuraGroupState()
            local cfg = AuraGroup(CurrentScope(), groupKey)
            local groupEnabled = LaneBackendEnabled(CurrentScope(), groupKey)
            SetOptionsEnabled(controls, groupEnabled)
            SetOptionEnabled(enable, true)
            SetSectionBadgesAndStatus(section, {
                OnOffBadge(groupEnabled, "Shown", "Hidden"),
                { text = "Max " .. BadgeNumber(cfg.max or def.max), kind = groupEnabled and "info" or "muted" },
                { text = BadgeNumber(cfg.size or def.size) .. "px", kind = groupEnabled and "info" or "muted" },
            })
        end
        M.TrackCollapsibleRefresh(ctx, section, RefreshAuraGroupState)
    end
    BuildAuraGroupSection("buff", "Buffs")
    if type(M.BuildAuras3GroupLaneWorkspace) == "function" then
        M.BuildAuras3GroupLaneWorkspace(ctx, b, CurrentScope(), "buff")
    end
    if GP.BuildSpellIndicatorsSection then
        GP.BuildSpellIndicatorsSection(ctx, b, RefreshPage)
    end
    BuildAuraGroupSection("debuff", "Debuffs")
    if type(M.BuildAuras3GroupLaneWorkspace) == "function" then
        M.BuildAuras3GroupLaneWorkspace(ctx, b, CurrentScope(), "debuff")
    end
    FinalizeScopePage(ctx, b)
end
M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 20 })
