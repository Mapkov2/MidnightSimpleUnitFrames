local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local function Tr(text)
    if type(text) ~= "string" then return text end
    local fn = M.Tr or MSUF.TR or MSUF.Translate
    if type(fn) == "function" then
        local translated = fn(text)
        if translated ~= nil then return translated end
    end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" and locale[text] ~= nil then return locale[text] end
    return text
end

local AURA_ANCHORS = GP.AURA_ANCHORS or {}
local STATUS_ICON_ANCHORS = GP.STATUS_ICON_ANCHORS or {}
local SPELL_GROWTH_VALUES = GP.SPELL_GROWTH_VALUES or {}

local GF = GP.GF
local Conf = GP.Conf
local ScopeSection = GP.ScopeSection
local CurrentScope = GP.CurrentScope
local AurasRoot = GP.AurasRoot
local AuraGroup = GP.AuraGroup
local BindNestedToggle = GP.BindNestedToggle
local BindNestedSlider = GP.BindNestedSlider
local BindNestedDropdown = GP.BindNestedDropdown
local SetOptionEnabled = GP.SetOptionEnabled
local SetOptionsEnabled = GP.SetOptionsEnabled
local ApplyScopeEnabledGate = GP.ApplyScopeEnabledGate
local SetSectionHeaderStatus = GP.SetSectionHeaderStatus
local SetSectionBadges = GP.SetSectionBadges or function() end
local OnOffBadge = GP.OnOffBadge or function(enabled, onText, offText) return { text = enabled and (onText or "Shown") or (offText or "Hidden"), kind = enabled and "ok" or "muted" } end
local BadgeNumber = GP.BadgeNumber or function(value) return tostring(value or 0) end

local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local AURA_POSITION_ANCHORS = (#STATUS_ICON_ANCHORS > 0 and STATUS_ICON_ANCHORS) or AURA_ANCHORS
    local AURA_GROWTH_VALUES = (#SPELL_GROWTH_VALUES > 0 and SPELL_GROWTH_VALUES) or {
        { value = "RIGHTDOWN", text = "Right then Down" },
        { value = "LEFTDOWN", text = "Left then Down" },
        { value = "RIGHTUP", text = "Right then Up" },
        { value = "LEFTUP", text = "Left then Up" },
    }

    local AURA_GROUP_DEFAULTS = {
        buff = {
            enabledLabel = "Buffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "BOTTOMRIGHT", growth = "LEFTUP", size = 22, perRow = 4, max = 6, spacing = 1, layer = 5,
            height = 360,
        },
        debuff = {
            enabledLabel = "Debuffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6,
            height = 360,
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
            W.ControlCard(section, "Icon Grid", nil, rightX - 14, -84, rightW + 28, 282)
        end

        local enable = BindNestedToggle(ctx, W.SwitchAt(section, def.enabledLabel, leftX, -44, 190), function() return AuraGroup(CurrentScope(), groupKey) end, "enabled", true, "visual")
        enable._msuf2GroupFrameGateAlwaysEnabled = true

        local anchor = BindNestedDropdown(ctx, W.Dropdown(section, "Anchor", AURA_POSITION_ANCHORS, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "anchor", def.anchor, "geometry")
        local growth = BindNestedDropdown(ctx, W.Dropdown(section, "Growth", AURA_GROWTH_VALUES, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "growth", def.growth, "geometry")
        local offsetX = BindNestedSlider(ctx, W.Slider(section, "Offset X", -160, 160, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "x", 0, "geometry")
        local offsetY = BindNestedSlider(ctx, W.Slider(section, "Offset Y", -160, 160, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "y", 0, "geometry")
        W.MoveWidget(anchor, section, leftX, -118, leftW, "LEFT")
        W.MoveWidget(growth, section, leftX, -172, leftW, "LEFT")
        W.MoveWidget(offsetX, section, leftX, -226, leftW, "CENTER")
        W.MoveWidget(offsetY, section, leftX, -280, leftW, "CENTER")
        controls[#controls + 1] = anchor
        controls[#controls + 1] = growth
        controls[#controls + 1] = offsetX
        controls[#controls + 1] = offsetY

        local maxIcons = BindNestedSlider(ctx, W.Slider(section, def.maxLabel, 0, def.maxMax, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "max", def.max, "visual")
        local iconSize = BindNestedSlider(ctx, W.Slider(section, "Icon size", 8, 64, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "size", def.size, "geometry")
        local perRow = BindNestedSlider(ctx, W.Slider(section, "Per row", 1, 20, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "perRow", def.perRow, "geometry")
        local spacing = BindNestedSlider(ctx, W.Slider(section, "Spacing", 0, 12, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "spacing", def.spacing, "geometry")
        local layer = BindNestedSlider(ctx, W.Slider(section, "Layer (Z-Order)", 1, 15, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "layer", def.layer, "geometry")
        W.MoveWidget(maxIcons, section, rightX, -118, rightW, "CENTER")
        W.MoveWidget(iconSize, section, rightX, -172, rightW, "CENTER")
        W.MoveWidget(perRow, section, rightX, -226, rightW, "CENTER")
        W.MoveWidget(spacing, section, rightX, -280, rightW, "CENTER")
        W.MoveWidget(layer, section, rightX, -334, rightW, "CENTER")
        controls[#controls + 1] = maxIcons
        controls[#controls + 1] = iconSize
        controls[#controls + 1] = perRow
        controls[#controls + 1] = spacing
        controls[#controls + 1] = layer

        local function RefreshAuraGroupState()
            local cfg = AuraGroup(CurrentScope(), groupKey)
            local groupEnabled = cfg.enabled ~= false
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
        do
            local entry = section and section._msuf2CollapsibleEntry
            if entry then entry._msuf2RefreshState = RefreshAuraGroupState end
        end
    end

    BuildAuraGroupSection("buff", "Buffs")
    BuildAuraGroupSection("debuff", "Debuffs")

    if type(ApplyScopeEnabledGate) == "function" then
        M.AddRefresher(ctx, function() ApplyScopeEnabledGate(ctx) end)
        ApplyScopeEnabledGate(ctx)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_auras", { title = "MSUF Group Auras", build = BuildGFAuras, version = 16 })
