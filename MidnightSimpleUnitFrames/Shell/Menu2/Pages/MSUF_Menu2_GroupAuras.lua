local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

-- Menu2 Group Auras page.
-- Builds party/raid aura lane controls and group aura backend toggles. Auras3/group runtime
-- own aura scanning, filtering, and icon updates after these settings change.
local W = M.Widgets
local GP = M.GroupPage or {}

local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList

local AURA_ANCHORS, STATUS_ICON_ANCHORS, SPELL_GROWTH_VALUES, ScopeSection, CurrentScope, AuraGroup, AurasRoot, QueueGF, RefreshContext, BindNestedSlider, BindNestedDropdown, SetOptionEnabled, SetOptionsEnabled, FinalizeScopePage, SetSectionHeaderStatus, SetSectionBadges, OnOffBadge, BadgeNumber = M.Pick(GP, [[AURA_ANCHORS STATUS_ICON_ANCHORS SPELL_GROWTH_VALUES ScopeSection CurrentScope AuraGroup AurasRoot QueueGF RefreshContext BindNestedSlider BindNestedDropdown SetOptionEnabled SetOptionsEnabled FinalizeScopePage SetSectionHeaderStatus SetSectionBadges OnOffBadge BadgeNumber]])
AURA_ANCHORS = AURA_ANCHORS or {}
STATUS_ICON_ANCHORS = STATUS_ICON_ANCHORS or {}
SPELL_GROWTH_VALUES = SPELL_GROWTH_VALUES or {}
SetSectionBadges = SetSectionBadges or M.Noop
OnOffBadge = OnOffBadge or M.OnOffBadge
BadgeNumber = BadgeNumber or M.BadgeNumber

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
    M.BindToggle(ctx, widget,
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
            if QueueGF then QueueGF(scope, "rebuild") end
            if RefreshContext then RefreshContext(ctx) end
        end)
    return widget
end


local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local AURA_POSITION_ANCHORS = (#STATUS_ICON_ANCHORS > 0 and STATUS_ICON_ANCHORS) or AURA_ANCHORS
    local AURA_GROWTH_VALUES = (#SPELL_GROWTH_VALUES > 0 and SPELL_GROWTH_VALUES)
        or VT("RIGHTDOWN", "Right then Down", "LEFTDOWN", "Left then Down", "RIGHTUP", "Right then Up", "LEFTUP", "Left then Up")

    local AURA_GROUP_DEFAULTS = {
        buff = {
            enabledLabel = "Buffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "BOTTOMRIGHT", growth = "LEFTUP", size = 22, perRow = 4, max = 6, spacing = 1, layer = 5,
            height = 404,
        },
        debuff = {
            enabledLabel = "Debuffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6,
            height = 404,
        },
    }

    local function BuildAuraGroupSection(groupKey, title)
        local def = AURA_GROUP_DEFAULTS[groupKey]
        local section = b:CollapsibleSection(groupKey == "buff" and "buffs" or "debuffs", title, def.height, false)
        local sectionW = section._msuf2Width or b.width or 720
        local leftX = 30
        local rightX = max(430, min(520, floor(sectionW * 0.50)))
        local leftW = max(270, min(340, rightX - leftX - 70))
        local rightW = max(280, min(360, sectionW - rightX - 42))
        local controls = {}
        do
            W.ControlCardBackdrop(section, leftX - 14, -38, leftW + 28, 42)
            W.ControlCard(section, "Placement", nil, leftX - 14, -84, leftW + 28, 232)
            W.ControlCard(section, "Icon Grid", nil, rightX - 14, -84, rightW + 28, 326)
        end

        local enable = BindAuraLaneEnabled(ctx, W.SwitchAt(section, def.enabledLabel, leftX, -44, 190), groupKey)
        enable._msuf2GroupFrameGateAlwaysEnabled = true

        local auraControlSpecs = {
            { kind = "dropdown", label = "Anchor", values = AURA_POSITION_ANCHORS, key = "anchor", default = def.anchor, mode = "geometry", x = leftX, y = -118, width = leftW, justify = "LEFT" },
            { kind = "dropdown", label = "Growth", values = AURA_GROWTH_VALUES, key = "growth", default = def.growth, mode = "geometry", x = leftX, y = -172, width = leftW, justify = "LEFT" },
            { label = "Offset X", min = -160, max = 160, key = "x", default = 0, mode = "geometry", x = leftX, y = -226, width = leftW },
            { label = "Offset Y", min = -160, max = 160, key = "y", default = 0, mode = "geometry", x = leftX, y = -280, width = leftW },
            { label = def.maxLabel, min = 0, max = def.maxMax, key = "max", default = def.max, mode = "visual", x = rightX, y = -118, width = rightW },
            { label = "Icon size", min = 8, max = 64, key = "size", default = def.size, mode = "geometry", x = rightX, y = -172, width = rightW },
            { label = "Per row", min = 1, max = 20, key = "perRow", default = def.perRow, mode = "geometry", x = rightX, y = -226, width = rightW },
            { label = "Spacing", min = 0, max = 12, key = "spacing", default = def.spacing, mode = "geometry", x = rightX, y = -280, width = rightW },
            { label = "Layer (Z-Order)", min = 1, max = 15, key = "layer", default = def.layer, mode = "geometry", x = rightX, y = -334, width = rightW },
        }
        for i = 1, #auraControlSpecs do
            local spec = auraControlSpecs[i]
            local widget
            if spec.kind == "dropdown" then
                widget = BindNestedDropdown(ctx, W.Dropdown(section, spec.label, spec.values, spec.width), function() return AuraGroup(CurrentScope(), groupKey) end, spec.key, spec.default, spec.mode)
            else
                widget = BindNestedSlider(ctx, W.Slider(section, spec.label, spec.min, spec.max, spec.step or 1, spec.width), function() return AuraGroup(CurrentScope(), groupKey) end, spec.key, spec.default, spec.mode)
            end
            W.MoveWidget(widget, section, spec.x, spec.y, spec.width, spec.justify or "CENTER")
            controls[#controls + 1] = widget
        end

        local function RefreshAuraGroupState()
            local cfg = AuraGroup(CurrentScope(), groupKey)
            local groupEnabled = LaneBackendEnabled(CurrentScope(), groupKey)
            SetOptionsEnabled(controls, groupEnabled)
            SetOptionEnabled(enable, true)
            SetSectionBadges(section, {
                OnOffBadge(groupEnabled, "Shown", "Hidden"),
                { text = "Max " .. BadgeNumber(cfg.max or def.max), kind = groupEnabled and "info" or "muted" },
                { text = BadgeNumber(cfg.size or def.size) .. "px", kind = groupEnabled and "info" or "muted" },
            })
            if type(SetSectionHeaderStatus) == "function" then
                SetSectionHeaderStatus(section, nil)
            end
        end
        M.AddRefresher(ctx, RefreshAuraGroupState)
        RefreshAuraGroupState()
        M.SetCollapsibleRefreshState(section, RefreshAuraGroupState)
    end

    BuildAuraGroupSection("buff", "Buffs")
    BuildAuraGroupSection("debuff", "Debuffs")

    FinalizeScopePage(ctx, b)
end

M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 16 })
