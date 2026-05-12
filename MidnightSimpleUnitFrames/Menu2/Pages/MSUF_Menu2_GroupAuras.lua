local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local GP = M.GroupPage or {}

local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min

local SCOPE_VALUES = GP.SCOPE_VALUES or {}
local GROWTH_VALUES = GP.GROWTH_VALUES or {}
local HEALTH_MODES = GP.HEALTH_MODES or {}
local TEXT_MODES = GP.TEXT_MODES or {}
local ANCHORS = GP.ANCHORS or {}
local AURA_ANCHORS = GP.AURA_ANCHORS or {}
local GF_RENDERERS = GP.GF_RENDERERS or {}
local GF_AURA_FILTERS = GP.GF_AURA_FILTERS or {}
local GF_AURA_ORG = GP.GF_AURA_ORG or {}
local SORT_MODES = GP.SORT_MODES or {}
local GF_BAR_MODES = GP.GF_BAR_MODES or {}
local SIMPLE_TEXTURES = GP.SIMPLE_TEXTURES or {}
local GF_ANCHOR_TO = GP.GF_ANCHOR_TO or {}
local GF_ANCHOR_POINTS = GP.GF_ANCHOR_POINTS or {}
local TOOLTIP_MODES = GP.TOOLTIP_MODES or {}
local TOOLTIP_MODIFIERS = GP.TOOLTIP_MODIFIERS or {}
local STATUS_ICON_ANCHORS = GP.STATUS_ICON_ANCHORS or {}
local GF_STATUS_ICON_SPECS = GP.GF_STATUS_ICON_SPECS or {}
local GF_STATUS_ICON_VALUES = GP.GF_STATUS_ICON_VALUES or {}
local PLACED_INDICATOR_TYPES = GP.PLACED_INDICATOR_TYPES or {}
local FRAME_EFFECT_TYPES = GP.FRAME_EFFECT_TYPES or {}
local SPELL_GROWTH_VALUES = GP.SPELL_GROWTH_VALUES or {}
local CI_SLOT_VALUES = GP.CI_SLOT_VALUES or {}
local CI_SLOT_DEFAULTS = GP.CI_SLOT_DEFAULTS or {}
local DISPEL_OVERLAY_STYLES = GP.DISPEL_OVERLAY_STYLES or {}
local DEBUFF_STRIPE_EDGES = GP.DEBUFF_STRIPE_EDGES or {}

local GF = GP.GF
local RefreshGFPreview = GP.RefreshGFPreview
local Conf = GP.Conf
local Val = GP.Val
local QueueGF = GP.QueueGF
local Set = GP.Set
local Bool = GP.Bool
local Num = GP.Num
local ScopeSection = GP.ScopeSection
local CurrentScope = GP.CurrentScope
local BindScopeToggle = GP.BindScopeToggle
local BindScopeSlider = GP.BindScopeSlider
local BindScopeDropdown = GP.BindScopeDropdown
local BuildGrowthDirectionTiles = GP.BuildGrowthDirectionTiles
local BuildRoleOrderRows = GP.BuildRoleOrderRows
local AurasRoot = GP.AurasRoot
local AuraGroup = GP.AuraGroup
local PrivateAuras = GP.PrivateAuras
local SpellIndicators = GP.SpellIndicators
local IconStyleValues = GP.IconStyleValues
local CurrentGFStatusSpec = GP.CurrentGFStatusSpec
local QueueSpellIndicators = GP.QueueSpellIndicators
local SpellSpecValues = GP.SpellSpecValues
local SpellTrackedSpecValues = GP.SpellTrackedSpecValues
local CurrentSpellMultiSpec = GP.CurrentSpellMultiSpec
local EffectiveSpellSpec = GP.EffectiveSpellSpec
local SpellAuraValues = GP.SpellAuraValues
local CurrentSpellAura = GP.CurrentSpellAura
local CurrentSpellConfig = GP.CurrentSpellConfig
local PlacedConfig = GP.PlacedConfig
local FrameEffectConfig = GP.FrameEffectConfig
local CICategoryValues = GP.CICategoryValues
local CIFilterValues = GP.CIFilterValues
local CIModeValues = GP.CIModeValues
local CurrentCISlot = GP.CurrentCISlot
local CICustomConfig = GP.CICustomConfig
local BindNestedToggle = GP.BindNestedToggle
local BindNestedSlider = GP.BindNestedSlider
local BindNestedDropdown = GP.BindNestedDropdown
local SetOptionEnabled = GP.SetOptionEnabled
local SetOptionsEnabled = GP.SetOptionsEnabled
local function BuildGFAuras(ctx)
    local b = W.PageBuilder(ctx)
    ScopeSection(ctx, b)
    M.GroupPreview.Add(ctx, b)

    local renderer = b:CollapsibleSection("blizzrenderer", "Blizzard Renderer", 456, false)
    W.Text(renderer, "Renderer path: Blizzard is the default native aura block. Checked types below are rendered by Blizzard; unchecked types use MSUF Custom groups. Custom mode disables the native block completely. Blizzard controls final native aura placement; MSUF only shows an approximate locked preview.", 14, -38, 620, T.colors.muted)

    local function PlaceDropdown(dropdown, x, y, width, hideTitle)
        if dropdown._msuf2Title then
            dropdown._msuf2Title:ClearAllPoints()
            dropdown._msuf2Title:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y + 20)
            dropdown._msuf2Title:SetShown(not hideTitle)
        end
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", renderer, "TOPLEFT", x, y)
        dropdown:SetSize(width, 22)
    end

    local function PlaceSlider(slider, x, y, width)
        W.MoveWidget(slider, renderer, x, y, width, "CENTER")
    end

    local function BindRendererSlider(widget, getTable, key, default, mode, labelFn)
        BindNestedSlider(ctx, widget, getTable, key, default, mode)
        local function RefreshLabel()
            local tbl = getTable()
            local value = tonumber(tbl and tbl[key]) or default or 0
            if widget._msuf2Title then widget._msuf2Title:SetText(labelFn(value)) end
        end
        widget:HookScript("OnValueChanged", function(self, value)
            if self._msuf2Refreshing then return end
            if self._msuf2Title then self._msuf2Title:SetText(labelFn(value)) end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local rendererMode = BindNestedDropdown(ctx, W.Dropdown(renderer, "", GF_RENDERERS, 180), function() return AurasRoot(CurrentScope()) end, "renderer", "BLIZZARD", "rebuild")
    PlaceDropdown(rendererMode, 14, -96, 180, true)

    local iconSize = BindRendererSlider(W.Slider(renderer, "", 8, 80, 1, 260), function() return AurasRoot(CurrentScope()) end, "blizzardIconSize", 20, "geometry",
        function(v) return string.format("Icon size: %d", v) end)
    PlaceSlider(iconSize, 14, -156, 260)

    local buffMax = BindRendererSlider(W.Slider(renderer, "", 0, 20, 1, 260), function() return AuraGroup(CurrentScope(), "buff") end, "max", 6, "visual",
        function(v) return string.format("Buff max: %d", v) end)
    PlaceSlider(buffMax, 14, -208, 260)

    local debuffMax = BindRendererSlider(W.Slider(renderer, "", 0, 20, 1, 260), function() return AuraGroup(CurrentScope(), "debuff") end, "max", 3, "visual",
        function(v) return string.format("Debuff max: %d", v) end)
    PlaceSlider(debuffMax, 14, -260, 260)

    local routingLabel = W.Text(renderer, "Rendered by Blizzard", 350, -82, 330, T.colors.text)
    local buffChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Buffs", 350, -112, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "buffs", true, "rebuild")
    local debuffChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Debuffs", 350, -172, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "debuffs", true, "rebuild")
    local dispelChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Dispels", 350, -232, 140), function() return AurasRoot(CurrentScope()).blizzardTypes end, "dispels", true, "rebuild")
    local extChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Defensives", 520, -112, 150), function() return AurasRoot(CurrentScope()).blizzardTypes end, "externals", true, "rebuild")
    local cdTextChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Blizzard Cooldown Text", 520, -172, 150), function() return AurasRoot(CurrentScope()) end, "blizzardShowCooldownText", true, "visual")
    local privateChk = BindNestedToggle(ctx, W.ToggleAt(renderer, "Use Blizzard: Private", 520, -232, 150), function() return AurasRoot(CurrentScope()).blizzardTypes end, "privateAuras", true, "rebuild")

    local orgLabel = W.Text(renderer, "Organization", 350, -292, 240, T.colors.text)
    local orgMode = BindNestedDropdown(ctx, W.Dropdown(renderer, "", GF_AURA_ORG, 260), function() return AurasRoot(CurrentScope()) end, "blizzardOrganizationType", "default", "geometry")
    PlaceDropdown(orgMode, 350, -314, 260, true)

    local posLabel = W.Text(renderer, "Blizzard Position", 350, -362, 240, T.colors.text)
    local posHint = W.Text(renderer, "Locked by Blizzard. MSUF can pass the native renderer settings above, but cannot drag or set the native block position. The preview marks the Blizzard-owned area and enabled aura types; exact placement is decided by Blizzard at runtime.", 350, -382, 330, T.colors.muted)

    M.AddRefresher(ctx, function()
        local native = (AurasRoot(CurrentScope()).renderer or "BLIZZARD") ~= "CUSTOM"
        SetOptionsEnabled({ buffChk, debuffChk, dispelChk, extChk, cdTextChk, privateChk, iconSize, buffMax, debuffMax, orgMode }, native)
        SetOptionEnabled(rendererMode, true)
        local c = native and T.colors.text or T.colors.dim
        routingLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        orgLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        posLabel:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        posHint:SetTextColor((native and T.colors.muted or T.colors.dim)[1], (native and T.colors.muted or T.colors.dim)[2], (native and T.colors.muted or T.colors.dim)[3], native and 1 or 0.75)
    end)

    local AURA_POSITION_ANCHORS = (#STATUS_ICON_ANCHORS > 0 and STATUS_ICON_ANCHORS) or AURA_ANCHORS
    local AURA_GROWTH_VALUES = (#SPELL_GROWTH_VALUES > 0 and SPELL_GROWTH_VALUES) or {
        { value = "RIGHTDOWN", text = "Right then Down" },
        { value = "LEFTDOWN", text = "Left then Down" },
        { value = "RIGHTUP", text = "Right then Up" },
        { value = "LEFTUP", text = "Left then Up" },
    }

    local AURA_GROUP_DEFAULTS = {
        buff = {
            enabledLabel = "Enable buffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "BOTTOMRIGHT", growth = "LEFTUP", size = 22, perRow = 4, max = 6, spacing = 1, layer = 5,
            filter = "RAID", height = 1030,
        },
        debuff = {
            enabledLabel = "Enable debuffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6,
            filter = "ALL", height = 1070, dispelBorder = true,
        },
        externals = {
            enabledLabel = "Enable defensives", maxLabel = "Max defensives", maxMax = 12,
            anchor = "CENTER", growth = "RIGHTDOWN", size = 28, perRow = 3, max = 2, spacing = 1, layer = 7,
            height = 780,
        },
    }

    local function AuraFilter()
        local gf = GF and GF()
        return (gf and gf.AuraFilter) or _G.MSUF_GF_AuraFilter
    end

    local function AuraFilterValues(groupKey)
        local af = AuraFilter()
        if af then
            local values = groupKey == "debuff" and af.DEBUFF_FILTER_ITEMS or af.BUFF_FILTER_ITEMS
            if type(values) == "table" and #values > 0 then return values end
        end
        return GF_AURA_FILTERS
    end

    local function BindBlacklistToggle(widget, groupKey, catKey)
        M.BindToggle(ctx, widget,
            function()
                local g = AuraGroup(CurrentScope(), groupKey)
                return type(g.blacklistCats) == "table" and g.blacklistCats[catKey] == true
            end,
            function(v)
                local g = AuraGroup(CurrentScope(), groupKey)
                if type(g.blacklistCats) ~= "table" then g.blacklistCats = {} end
                g.blacklistCats[catKey] = v and true or nil
                local af = AuraFilter()
                if af and type(af.InvalidateBlacklistHash) == "function" then
                    af.InvalidateBlacklistHash(g)
                end
                QueueGF(CurrentScope(), "visual")
            end)
        return widget
    end

    local function BuildAuraBlacklist(section, groupKey, x1, x2, y, width, controls)
        local af = AuraFilter()
        local meta = af and af.DECLASSIFIED_META
        if not (type(meta) == "table" and #meta > 0) then return y end

        W.DividerAt(section, y + 20, x1, section._msuf2Width - x2 - width)
        W.LabelAt(section, "Hide Categories", x1, y, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
        W.Text(section, "Checked categories are hidden. Only applies to declassified spells.", x1, y - 20, (x2 + width) - x1, T.colors.muted)

        local startY = y - 52
        for i = 1, #meta do
            local cat = meta[i]
            local col = (i <= ceil(#meta / 2)) and 0 or 1
            local row = (col == 0) and (i - 1) or (i - ceil(#meta / 2) - 1)
            local tx = col == 0 and x1 or x2
            local toggle = BindBlacklistToggle(W.ToggleAt(section, cat.label or cat.key, tx, startY - row * 30, width - 36), groupKey, cat.key)
            controls[#controls + 1] = toggle
            if cat.tooltip then
                toggle:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(cat.label or cat.key, 1, 1, 1)
                    GameTooltip:AddLine(cat.tooltip, 0.7, 0.7, 0.7, true)
                    GameTooltip:Show()
                end)
                toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end

        return startY - ceil(#meta / 2) * 30 - 18
    end

    local function BuildAuraGroupSection(groupKey, title)
        local def = AURA_GROUP_DEFAULTS[groupKey]
        local section = b:CollapsibleSection(groupKey == "externals" and "ext" or (groupKey == "buff" and "buffs" or "debuffs"), title, def.height, false)
        local sectionW = section._msuf2Width or b.width or 720
        local leftX = 30
        local rightX = max(430, min(520, floor(sectionW * 0.50)))
        local leftW = max(270, min(340, rightX - leftX - 70))
        local rightW = max(280, min(360, sectionW - rightX - 42))
        local controls, cooldownChildren, stackChildren = {}, {}, {}

        local enable = BindNestedToggle(ctx, W.ToggleAt(section, def.enabledLabel, leftX, -44, 190), function() return AuraGroup(CurrentScope(), groupKey) end, "enabled", true, "visual")

        W.LabelAt(section, "Placement", leftX, -84, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
        local anchor = BindNestedDropdown(ctx, W.Dropdown(section, "Anchor", AURA_POSITION_ANCHORS, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "anchor", def.anchor, "geometry")
        local growth = BindNestedDropdown(ctx, W.Dropdown(section, "Growth", AURA_GROWTH_VALUES, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "growth", def.growth, "geometry")
        local offsetX = BindNestedSlider(ctx, W.Slider(section, "Offset X", -160, 160, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "x", 0, "geometry")
        local offsetY = BindNestedSlider(ctx, W.Slider(section, "Offset Y", -160, 160, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "y", 0, "geometry")
        W.MoveWidget(anchor, section, leftX, -108, leftW, "LEFT")
        W.MoveWidget(growth, section, leftX, -162, leftW, "LEFT")
        W.MoveWidget(offsetX, section, leftX, -216, leftW, "CENTER")
        W.MoveWidget(offsetY, section, leftX, -270, leftW, "CENTER")
        controls[#controls + 1] = anchor
        controls[#controls + 1] = growth
        controls[#controls + 1] = offsetX
        controls[#controls + 1] = offsetY

        W.DividerAt(section, -314, leftX, sectionW - (leftX + leftW))
        W.LabelAt(section, "Behind Health Bar", leftX, -338, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
        local behind = BindNestedToggle(ctx, W.ToggleAt(section, "Show icons behind HP bar", leftX, -364, 230), function() return AuraGroup(CurrentScope(), groupKey) end, "behindBar", false, "geometry")
        local behindAlpha = BindNestedSlider(ctx, W.Slider(section, "Behind Bar Opacity", 30, 100, 5, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "behindBarAlpha", 85, "visual")
        W.MoveWidget(behindAlpha, section, leftX, -408, leftW, "CENTER")
        controls[#controls + 1] = behind
        controls[#controls + 1] = behindAlpha

        W.LabelAt(section, "Icon Grid", rightX, -84, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
        local maxIcons = BindNestedSlider(ctx, W.Slider(section, def.maxLabel, 0, def.maxMax, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "max", def.max, "visual")
        local iconSize = BindNestedSlider(ctx, W.Slider(section, "Icon size", 8, 64, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "size", def.size, "geometry")
        local perRow = BindNestedSlider(ctx, W.Slider(section, "Per row", 1, 20, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "perRow", def.perRow, "geometry")
        local spacing = BindNestedSlider(ctx, W.Slider(section, "Spacing", 0, 12, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "spacing", def.spacing, "geometry")
        local layer = BindNestedSlider(ctx, W.Slider(section, "Layer (Z-Order)", 1, 15, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "layer", def.layer, "geometry")
        W.MoveWidget(maxIcons, section, rightX, -108, rightW, "CENTER")
        W.MoveWidget(iconSize, section, rightX, -162, rightW, "CENTER")
        W.MoveWidget(perRow, section, rightX, -216, rightW, "CENTER")
        W.MoveWidget(spacing, section, rightX, -270, rightW, "CENTER")
        W.MoveWidget(layer, section, rightX, -324, rightW, "CENTER")
        controls[#controls + 1] = maxIcons
        controls[#controls + 1] = iconSize
        controls[#controls + 1] = perRow
        controls[#controls + 1] = spacing
        controls[#controls + 1] = layer

        local nextY = -456
        if groupKey == "buff" or groupKey == "debuff" then
            W.DividerAt(section, -368, rightX, sectionW - (rightX + rightW))
            W.LabelAt(section, "Filter", rightX, -392, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
            local filter = BindNestedDropdown(ctx, W.Dropdown(section, "Base Filter", AuraFilterValues(groupKey), rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "filterToken", def.filter, "visual")
            W.MoveWidget(filter, section, rightX, -416, rightW, "LEFT")
            controls[#controls + 1] = filter
            if groupKey == "debuff" then
                local dispel = BindNestedToggle(ctx, W.ToggleAt(section, "Show Dispel Type Border", rightX, -470, rightW - 36), function() return AuraGroup(CurrentScope(), groupKey) end, "showDispelBorder", true, "visual")
                controls[#controls + 1] = dispel
                nextY = -526
            else
                nextY = -486
            end
            nextY = BuildAuraBlacklist(section, groupKey, leftX, rightX, nextY, rightW, controls)
        end

        local textY = min(nextY, groupKey == "externals" and -456 or -646)
        W.DividerAt(section, textY + 20, leftX, 12)
        W.LabelAt(section, "Cooldown", leftX, textY, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
        W.LabelAt(section, "Stack Count", rightX, textY, 180, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })

        local showSwipe = BindNestedToggle(ctx, W.ToggleAt(section, "Show Cooldown Swipe", leftX, textY - 30, 220), function() return AuraGroup(CurrentScope(), groupKey) end, "showCooldownSwipe", true, "visual")
        local showCooldown = BindNestedToggle(ctx, W.ToggleAt(section, "Show Cooldown Text", leftX, textY - 62, 220), function() return AuraGroup(CurrentScope(), groupKey) end, "showCooldown", true, "visual")
        local cooldownSize = BindNestedSlider(ctx, W.Slider(section, "Font size", 6, 24, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "cooldownSize", groupKey == "externals" and 10 or 8, "font")
        local cooldownAnchor = BindNestedDropdown(ctx, W.Dropdown(section, "Anchor", AURA_POSITION_ANCHORS, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "cooldownAnchor", "CENTER", "geometry")
        local cooldownX = BindNestedSlider(ctx, W.Slider(section, "Offset X", -30, 30, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "cooldownOffsetX", 0, "geometry")
        local cooldownY = BindNestedSlider(ctx, W.Slider(section, "Offset Y", -30, 30, 1, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "cooldownOffsetY", 0, "geometry")
        W.MoveWidget(cooldownSize, section, leftX, textY - 106, leftW, "CENTER")
        W.MoveWidget(cooldownAnchor, section, leftX, textY - 160, leftW, "LEFT")
        W.MoveWidget(cooldownX, section, leftX, textY - 214, leftW, "CENTER")
        W.MoveWidget(cooldownY, section, leftX, textY - 268, leftW, "CENTER")
        controls[#controls + 1] = showSwipe
        controls[#controls + 1] = showCooldown
        controls[#controls + 1] = cooldownSize
        controls[#controls + 1] = cooldownAnchor
        controls[#controls + 1] = cooldownX
        controls[#controls + 1] = cooldownY
        cooldownChildren[#cooldownChildren + 1] = cooldownSize
        cooldownChildren[#cooldownChildren + 1] = cooldownAnchor
        cooldownChildren[#cooldownChildren + 1] = cooldownX
        cooldownChildren[#cooldownChildren + 1] = cooldownY

        local showStacks = BindNestedToggle(ctx, W.ToggleAt(section, "Show Stack Count", rightX, textY - 30, 220), function() return AuraGroup(CurrentScope(), groupKey) end, "showStacks", groupKey ~= "externals", "visual")
        local stackSize = BindNestedSlider(ctx, W.Slider(section, "Font size", 6, 24, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "stackSize", 10, "font")
        local stackAnchor = BindNestedDropdown(ctx, W.Dropdown(section, "Anchor", AURA_POSITION_ANCHORS, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "stackAnchor", "BOTTOMRIGHT", "geometry")
        local stackX = BindNestedSlider(ctx, W.Slider(section, "Offset X", -30, 30, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "stackOffsetX", 2, "geometry")
        local stackY = BindNestedSlider(ctx, W.Slider(section, "Offset Y", -30, 30, 1, rightW), function() return AuraGroup(CurrentScope(), groupKey) end, "stackOffsetY", -2, "geometry")
        W.MoveWidget(stackSize, section, rightX, textY - 74, rightW, "CENTER")
        W.MoveWidget(stackAnchor, section, rightX, textY - 128, rightW, "LEFT")
        W.MoveWidget(stackX, section, rightX, textY - 182, rightW, "CENTER")
        W.MoveWidget(stackY, section, rightX, textY - 236, rightW, "CENTER")
        controls[#controls + 1] = showStacks
        controls[#controls + 1] = stackSize
        controls[#controls + 1] = stackAnchor
        controls[#controls + 1] = stackX
        controls[#controls + 1] = stackY
        stackChildren[#stackChildren + 1] = stackSize
        stackChildren[#stackChildren + 1] = stackAnchor
        stackChildren[#stackChildren + 1] = stackX
        stackChildren[#stackChildren + 1] = stackY

        M.AddRefresher(ctx, function()
            local cfg = AuraGroup(CurrentScope(), groupKey)
            local groupEnabled = cfg.enabled ~= false
            SetOptionsEnabled(controls, groupEnabled)
            SetOptionsEnabled(cooldownChildren, groupEnabled and cfg.showCooldown ~= false)
            SetOptionsEnabled(stackChildren, groupEnabled and cfg.showStacks ~= false)
            SetOptionEnabled(enable, true)
            SetOptionEnabled(showCooldown, groupEnabled)
            SetOptionEnabled(showStacks, groupEnabled)
        end)
    end

    BuildAuraGroupSection("buff", "Buffs")
    BuildAuraGroupSection("debuff", "Debuffs")
    BuildAuraGroupSection("externals", "Defensives")

    local function GeneralDB()
        _G.MSUF_DB = _G.MSUF_DB or {}
        _G.MSUF_DB.general = _G.MSUF_DB.general or {}
        return _G.MSUF_DB.general
    end

    local function ReadRGB(t, dr, dg, db)
        if type(t) ~= "table" then return dr, dg, db end
        local r = t[1] or t.r
        local g = t[2] or t.g
        local bcol = t[3] or t.b
        if type(r) ~= "number" then r = dr end
        if type(g) ~= "number" then g = dg end
        if type(bcol) ~= "number" then bcol = db end
        return r, g, bcol
    end

    local function GetBaseTimerColor()
        local g = GeneralDB()
        if g.useCustomFontColor == true
            and type(g.fontColorCustomR) == "number"
            and type(g.fontColorCustomG) == "number"
            and type(g.fontColorCustomB) == "number" then
            return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
        end
        return 1, 1, 1
    end

    local function GetTimerSafeColor()
        local r, g, bcol = GetBaseTimerColor()
        return ReadRGB(GeneralDB().aurasCooldownTextSafeColor, r, g, bcol)
    end

    local function GetTimerWarningColor()
        return ReadRGB(GeneralDB().aurasCooldownTextWarningColor, 1, 0.85, 0.20)
    end

    local function GetTimerUrgentColor()
        return ReadRGB(GeneralDB().aurasCooldownTextUrgentColor, 1, 0.55, 0.10)
    end

    local function RequestTimerColorRefresh()
        if _G.MSUF_A2_InvalidateCooldownTextCurve then _G.MSUF_A2_InvalidateCooldownTextCurve() end
        if _G.MSUF_A2_ForceCooldownTextRecolor then _G.MSUF_A2_ForceCooldownTextRecolor() end
        if _G.MSUF_GF_InvalidateCooldownTextCurve then _G.MSUF_GF_InvalidateCooldownTextCurve() end
        if _G.MSUF_GF_ForceCooldownTextRecolor then _G.MSUF_GF_ForceCooldownTextRecolor() end
        QueueGF(CurrentScope(), "visual")
        RefreshGFPreview()
    end

    local function RefreshContext()
        if not (ctx and ctx.refreshers) then return end
        for i = 1, #ctx.refreshers do
            local fn = ctx.refreshers[i]
            if type(fn) == "function" then pcall(fn) end
        end
    end

    local function HasCustomIconAuraGroups()
        local auras = AurasRoot(CurrentScope())
        if (auras.renderer or "BLIZZARD") == "CUSTOM" then return true end
        local types = auras.blizzardTypes
        if type(types) ~= "table" then return false end
        return types.buffs == false or types.debuffs == false or types.externals == false
    end

    local function ClampNumber(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return floor(v + 0.5)
    end

    local function BindGeneralToggle(widget, key, default)
        M.BindToggle(ctx, widget,
            function()
                local v = GeneralDB()[key]
                if v == nil then v = default end
                return v and true or false
            end,
            function(v)
                GeneralDB()[key] = v and true or false
                RequestTimerColorRefresh()
                RefreshContext()
            end)
        return widget
    end

    local function BindGeneralSlider(widget, key, lo, hi, default, clampFn, afterSet)
        M.BindSlider(ctx, widget,
            function()
                local value = GeneralDB()[key]
                if type(value) ~= "number" then value = default end
                if clampFn then value = clampFn(value) end
                return value
            end,
            function(value)
                value = clampFn and clampFn(value) or ClampNumber(value, lo, hi)
                local g = GeneralDB()
                if g[key] == value then return end
                g[key] = value
                if afterSet then afterSet(value) end
                RequestTimerColorRefresh()
                RefreshContext()
            end)
        return widget
    end

    local function BindGeneralColor(widget, getColor, setColor)
        M.BindColor(ctx, widget, getColor, function(r, g, bcol)
            setColor(r, g, bcol)
            RequestTimerColorRefresh()
            RefreshContext()
        end)
        return widget
    end

    local textcolor = b:CollapsibleSection("textcolor", "Text Coloring", 370, false)
    local textW = textcolor._msuf2Width or b.width or 720
    local leftX = 30
    local rightX = max(430, min(520, floor(textW * 0.50)))
    local leftW = max(280, min(340, rightX - leftX - 70))
    local rightW = max(300, min(360, textW - rightX - 42))

    W.LabelAt(textcolor, "Cooldown Timer Text", leftX, -42, 220, "GameFontNormalSmall", { 1.00, 0.82, 0.18, 1 })
    local info = W.Text(textcolor, "MSUF timer coloring only applies to custom aura icons. Blizzard-rendered cooldown text can be shown or hidden per group, but not recolored here.", leftX, -64, textW - 60, T.colors.muted)
    if info.SetWordWrap then info:SetWordWrap(true) end

    local colorByTime = BindGeneralToggle(W.ToggleAt(textcolor, "Color aura timers by remaining time", leftX, -112, leftW), "gfAurasCooldownTextUseBuckets", true)
    W.LabelAt(textcolor, "Colors", leftX, -154, 180, "GameFontNormalSmall", T.colors.text)
    local safeColor = BindGeneralColor(W.Color(textcolor, "Safe"), GetTimerSafeColor, function(r, g, bcol)
        GeneralDB().aurasCooldownTextSafeColor = { r, g, bcol }
    end)
    local warningColor = BindGeneralColor(W.Color(textcolor, "Warning"), GetTimerWarningColor, function(r, g, bcol)
        GeneralDB().aurasCooldownTextWarningColor = { r, g, bcol }
    end)
    local urgentColor = BindGeneralColor(W.Color(textcolor, "Urgent"), GetTimerUrgentColor, function(r, g, bcol)
        GeneralDB().aurasCooldownTextUrgentColor = { r, g, bcol }
    end)
    W.MoveWidget(safeColor, textcolor, leftX, -178)
    W.MoveWidget(warningColor, textcolor, leftX, -218)
    W.MoveWidget(urgentColor, textcolor, leftX, -258)

    local resetColors = W.Button(textcolor, "Reset", 84)
    resetColors:ClearAllPoints()
    resetColors:SetPoint("TOPLEFT", textcolor, "TOPLEFT", leftX, -304)
    resetColors:SetScript("OnClick", function()
        local g = GeneralDB()
        g.aurasCooldownTextSafeColor = nil
        g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
        g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
        RequestTimerColorRefresh()
        RefreshContext()
    end)

    W.LabelAt(textcolor, "Preview", rightX, -112, 180, "GameFontNormalSmall", T.colors.text)
    local previewSamples = {
        { text = "60", label = "Safe", get = GetTimerSafeColor, bucket = false },
        { text = "15", label = "Warning", get = GetTimerWarningColor, bucket = true },
        { text = "5", label = "Urgent", get = GetTimerUrgentColor, bucket = true },
    }
    local sampleW = min(96, floor((rightW - 18) / 3))
    for i = 1, #previewSamples do
        local spec = previewSamples[i]
        local box = CreateFrame("Frame", nil, textcolor, "BackdropTemplate")
        box:SetSize(sampleW, 46)
        box:SetPoint("TOPLEFT", textcolor, "TOPLEFT", rightX + (i - 1) * (sampleW + 9), -138)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0.02, 0.02, 0.03, 0.82)
        box:SetBackdropBorderColor(0.14, 0.16, 0.22, 0.90)
        local value = T.Font(box, "GameFontNormalLarge", spec.text, T.colors.text)
        value:SetPoint("CENTER", box, "CENTER", 0, 5)
        local label = T.Font(box, "GameFontDisableSmall", spec.label, T.colors.dim)
        label:SetPoint("BOTTOM", box, "BOTTOM", 0, 3)
        spec.box = box
        spec.value = value
    end

    local function ClampSafe(value)
        return ClampNumber(value, 0, 600)
    end
    local function ClampWarning(value)
        local safe = tonumber(GeneralDB().gfAurasCooldownTextSafeSeconds) or 60
        return min(ClampNumber(value, 0, 30), safe)
    end
    local function ClampUrgent(value)
        local warning = tonumber(GeneralDB().gfAurasCooldownTextWarningSeconds) or 15
        return min(ClampNumber(value, 0, 15), warning)
    end
    local function AfterSafe(value)
        local g = GeneralDB()
        if type(g.gfAurasCooldownTextWarningSeconds) ~= "number" then g.gfAurasCooldownTextWarningSeconds = 15 end
        if type(g.gfAurasCooldownTextUrgentSeconds) ~= "number" then g.gfAurasCooldownTextUrgentSeconds = 5 end
        if g.gfAurasCooldownTextWarningSeconds > value then g.gfAurasCooldownTextWarningSeconds = value end
        if g.gfAurasCooldownTextUrgentSeconds > g.gfAurasCooldownTextWarningSeconds then
            g.gfAurasCooldownTextUrgentSeconds = g.gfAurasCooldownTextWarningSeconds
        end
    end
    local function AfterWarning(value)
        local g = GeneralDB()
        if type(g.gfAurasCooldownTextSafeSeconds) ~= "number" then g.gfAurasCooldownTextSafeSeconds = 60 end
        if type(g.gfAurasCooldownTextUrgentSeconds) ~= "number" then g.gfAurasCooldownTextUrgentSeconds = 5 end
        if value > g.gfAurasCooldownTextSafeSeconds then g.gfAurasCooldownTextWarningSeconds = g.gfAurasCooldownTextSafeSeconds end
        if g.gfAurasCooldownTextUrgentSeconds > value then g.gfAurasCooldownTextUrgentSeconds = value end
    end
    local function AfterUrgent(value)
        local g = GeneralDB()
        if type(g.gfAurasCooldownTextWarningSeconds) ~= "number" then g.gfAurasCooldownTextWarningSeconds = 15 end
        if value > g.gfAurasCooldownTextWarningSeconds then g.gfAurasCooldownTextUrgentSeconds = g.gfAurasCooldownTextWarningSeconds end
    end

    local safeSeconds = BindGeneralSlider(W.Slider(textcolor, "Safe (seconds)", 0, 600, 1, rightW), "gfAurasCooldownTextSafeSeconds", 0, 600, 60, ClampSafe, AfterSafe)
    local warningSeconds = BindGeneralSlider(W.Slider(textcolor, "Warning (<=)", 0, 30, 1, rightW), "gfAurasCooldownTextWarningSeconds", 0, 30, 15, ClampWarning, AfterWarning)
    local urgentSeconds = BindGeneralSlider(W.Slider(textcolor, "Urgent (<=)", 0, 15, 1, rightW), "gfAurasCooldownTextUrgentSeconds", 0, 15, 5, ClampUrgent, AfterUrgent)
    W.MoveWidget(safeSeconds, textcolor, rightX, -218, rightW, "CENTER")
    W.MoveWidget(warningSeconds, textcolor, rightX, -272, rightW, "CENTER")
    W.MoveWidget(urgentSeconds, textcolor, rightX, -326, rightW, "CENTER")

    local textColorControls = { colorByTime, safeColor, warningColor, urgentColor, resetColors, safeSeconds, warningSeconds, urgentSeconds }
    local bucketControls = { warningColor, urgentColor, warningSeconds, urgentSeconds }
    M.AddRefresher(ctx, function()
        local customIcons = HasCustomIconAuraGroups()
        local bucketsOn = GeneralDB().gfAurasCooldownTextUseBuckets ~= false
        SetOptionsEnabled(textColorControls, customIcons)
        SetOptionsEnabled(bucketControls, customIcons and bucketsOn)
        SetOptionEnabled(colorByTime, customIcons)

        local colors = {
            { GetTimerSafeColor() },
            { GetTimerWarningColor() },
            { GetTimerUrgentColor() },
        }
        local g = GeneralDB()
        local sampleValues = {
            tostring(tonumber(g.gfAurasCooldownTextSafeSeconds) or 60),
            tostring(tonumber(g.gfAurasCooldownTextWarningSeconds) or 15),
            tostring(tonumber(g.gfAurasCooldownTextUrgentSeconds) or 5),
        }
        for i = 1, #previewSamples do
            local sample = previewSamples[i]
            local r, g, bcol = colors[i][1], colors[i][2], colors[i][3]
            local alpha = (customIcons and (not sample.bucket or bucketsOn)) and 1 or 0.35
            if sample.value then sample.value:SetText(sampleValues[i]) end
            if sample.value then sample.value:SetTextColor(r, g, bcol, alpha) end
            if sample.box and sample.box.SetAlpha then sample.box:SetAlpha(customIcons and 1 or 0.45) end
        end
    end)

    local priv = b:CollapsibleSection("priv", "Private Auras", 390, false)
    local privEnable = BindNestedToggle(ctx, W.Toggle(priv, "Enable private auras"), function() return PrivateAuras(CurrentScope()) end, "enabled", true, "visual")
    local privControls = {
        BindNestedSlider(ctx, W.Slider(priv, "Private aura max", 0, 12, 1, 300), function() return PrivateAuras(CurrentScope()) end, "max", 4, "visual"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura size", 8, 64, 1, 300), function() return PrivateAuras(CurrentScope()) end, "size", 20, "geometry"),
        BindNestedDropdown(ctx, W.Dropdown(priv, "Private aura anchor", AURA_ANCHORS, 220), function() return PrivateAuras(CurrentScope()) end, "anchor", "TOPRIGHT", "geometry"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura X", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "x", 0, "geometry"),
        BindNestedSlider(ctx, W.Slider(priv, "Private aura Y", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "y", 0, "geometry"),
        BindNestedToggle(ctx, W.Toggle(priv, "Show countdown"), function() return PrivateAuras(CurrentScope()) end, "showCountdown", true, "visual"),
        BindNestedToggle(ctx, W.Toggle(priv, "Show numbers"), function() return PrivateAuras(CurrentScope()) end, "showNumbers", false, "visual"),
    }
    M.AddRefresher(ctx, function()
        SetOptionsEnabled(privControls, PrivateAuras(CurrentScope()).enabled ~= false)
        SetOptionEnabled(privEnable, true)
    end)

    local style = b:CollapsibleSection("masque", "Cooldown Style", 166, false)
    BindScopeToggle(ctx, W.Toggle(style, "Cooldown darkens on loss"), "cooldownSwipeDarkenOnLoss", false, "visual")
    M.BindToggle(ctx, W.Toggle(style, "Masque skin"),
        function() return Bool(CurrentScope(), "masqueEnabled", false) end,
        function(v)
            Set(CurrentScope(), "masqueEnabled", v and true or false, "visual")
            local gf = GF and GF()
            if gf and gf.Masque and type(gf.Masque.ReskinAllIcons) == "function" then
                gf.Masque.ReskinAllIcons()
            end
            if ctx and ctx.refreshers then
                for i = 1, #ctx.refreshers do
                    local fn = ctx.refreshers[i]
                    if type(fn) == "function" then pcall(fn) end
                end
            end
        end)
    BindNestedToggle(ctx, W.Toggle(style, "Dynamic icon scale"), function() return AurasRoot(CurrentScope()) end, "dynamicScale", false, "geometry")

    local utilities = b:CollapsibleSection("autil", "Aura Utilities", 180, false)
    BindNestedToggle(ctx, W.Toggle(utilities, "Show tooltip on auras"), function() return AurasRoot(CurrentScope()) end, "showTooltip", true, "visual")
    BindNestedToggle(ctx, W.Toggle(utilities, "Sort by duration"), function() return AurasRoot(CurrentScope()) end, "sortByDuration", false, "visual")
    BindNestedToggle(ctx, W.Toggle(utilities, "Prefer player auras"), function() return AurasRoot(CurrentScope()) end, "preferPlayer", true, "visual")

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_auras", { title = "MSUF Group Buffs & Debuffs", build = BuildGFAuras, version = 10 })
