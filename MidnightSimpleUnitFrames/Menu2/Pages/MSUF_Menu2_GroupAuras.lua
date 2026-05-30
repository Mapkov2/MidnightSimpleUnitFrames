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
local PrivateAuras = GP.PrivateAuras
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
            height = 470,
        },
        debuff = {
            enabledLabel = "Debuffs", maxLabel = "Max icons", maxMax = 20,
            anchor = "TOPLEFT", growth = "RIGHTDOWN", size = 20, perRow = 3, max = 6, spacing = 1, layer = 6,
            height = 470,
        },
        externals = {
            enabledLabel = "Defensives", maxLabel = "Max defensives", maxMax = 12,
            anchor = "CENTER", growth = "RIGHTDOWN", size = 28, perRow = 3, max = 2, spacing = 1, layer = 7,
            height = 470,
        },
    }

    local function BlizzardTypeKeyForGroup(groupKey)
        if groupKey == "buff" then return "buffs" end
        if groupKey == "debuff" then return "debuffs" end
        if groupKey == "externals" then return "externals" end
        return nil
    end

    local function IsGroupRenderedByBlizzard(groupKey)
        local nativeKey = BlizzardTypeKeyForGroup(groupKey)
        if not nativeKey then return false end
        local gf = GF and GF()
        if gf and type(gf.IsBlizzardAuraTypeEnabled) == "function" then
            return gf.IsBlizzardAuraTypeEnabled(Conf(CurrentScope()), nativeKey) == true
        end
        local root = AurasRoot(CurrentScope())
        if (root.renderer or "BLIZZARD") == "CUSTOM" then return false end
        local types = root.blizzardTypes
        return type(types) ~= "table" or types[nativeKey] ~= false
    end

    local function IsBlizzardRendererMode()
        local root = AurasRoot(CurrentScope())
        return (root.renderer or "BLIZZARD") ~= "CUSTOM"
    end

    local function BuildAuraGroupSection(groupKey, title)
        local def = AURA_GROUP_DEFAULTS[groupKey]
        local section = b:CollapsibleSection(groupKey == "externals" and "ext" or (groupKey == "buff" and "buffs" or "debuffs"), title, def.height, false)
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
            W.ControlCard(section, "Behind Health Bar", nil, leftX - 14, -320, leftW + 28, 132)
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

        local behind = BindNestedToggle(ctx, W.ToggleAt(section, "Show icons behind HP bar", leftX, -364, 230), function() return AuraGroup(CurrentScope(), groupKey) end, "behindBar", false, "geometry")
        local behindAlpha = BindNestedSlider(ctx, W.Slider(section, "Behind Bar Opacity", 30, 100, 5, leftW), function() return AuraGroup(CurrentScope(), groupKey) end, "behindBarAlpha", 85, "visual")
        W.MoveWidget(behindAlpha, section, leftX, -408, leftW, "CENTER")
        controls[#controls + 1] = behind
        controls[#controls + 1] = behindAlpha

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
            local nativeGroup = IsGroupRenderedByBlizzard(groupKey)
            local mixedGroup = groupEnabled and IsBlizzardRendererMode() and not nativeGroup
            local warningColor = T.colors.danger or { 0.88, 0.28, 0.28, 1 }
            SetOptionsEnabled(controls, groupEnabled and not nativeGroup)
            SetOptionEnabled(enable, true)
            SetSectionBadges(section, {
                OnOffBadge(groupEnabled, "Shown", "Hidden"),
                { text = nativeGroup and Tr("Blizzard") or Tr("Custom"), kind = nativeGroup and "muted" or "accent" },
                { text = "Max " .. BadgeNumber(cfg.max or def.max), kind = (groupEnabled and not nativeGroup) and "info" or "muted" },
                { text = BadgeNumber(cfg.size or def.size) .. "px", kind = (groupEnabled and not nativeGroup) and "info" or "muted" },
            })
            if type(SetSectionHeaderStatus) == "function" then
                if nativeGroup then
                    SetSectionHeaderStatus(section, {
                        hint = Tr("Rendered by Blizzard"),
                        hintColor = warningColor,
                        bg = { 0.120, 0.035, 0.040, 0.55 },
                        arrowColor = warningColor,
                    })
                elseif mixedGroup then
                    SetSectionHeaderStatus(section, {
                        hint = Tr("MSUF Custom + Blizzard active"),
                        hintColor = warningColor,
                        bg = { 0.120, 0.035, 0.040, 0.55 },
                        arrowColor = warningColor,
                    })
                else
                    SetSectionHeaderStatus(section, nil)
                end
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
    BuildAuraGroupSection("externals", "Defensives")

    local function IsPrivateAurasRenderedByBlizzard()
        local gf = GF and GF()
        if gf and type(gf.IsBlizzardAuraTypeEnabled) == "function" then
            return gf.IsBlizzardAuraTypeEnabled(Conf(CurrentScope()), "privateAuras") == true
        end
        local root = AurasRoot(CurrentScope())
        if (root.renderer or "BLIZZARD") == "CUSTOM" then return false end
        local types = root.blizzardTypes
        return type(types) ~= "table" or types.privateAuras ~= false
    end

    local priv = b:CollapsibleSection("priv", "Private Auras", 224, false)
    local privW = priv._msuf2Width or ctx.width or 900
    local privLeftX = 32
    local privRightX = min(max(430, floor(privW * 0.52)), max(360, privW - 360))
    local privLeftW = max(250, privRightX - privLeftX - 42)
    local privRightW = max(250, privW - privRightX - 32)
    local privControlW = max(260, min(320, privLeftW))
    local privRightControlW = max(260, min(320, privRightW))
    W.ControlCardBackdrop(priv, privLeftX - 14, -38, privControlW + 28, 180)
    W.ControlCardBackdrop(priv, privRightX - 14, -38, privRightControlW + 28, 180)
    local privMax = BindNestedSlider(ctx, W.Slider(priv, "Private aura max", 0, 12, 1, 300), function() return PrivateAuras(CurrentScope()) end, "max", 4, "visual")
    local privSize = BindNestedSlider(ctx, W.Slider(priv, "Private aura size", 8, 64, 1, 300), function() return PrivateAuras(CurrentScope()) end, "size", 20, "geometry")
    local privAnchor = BindNestedDropdown(ctx, W.Dropdown(priv, "Private aura anchor", AURA_ANCHORS, 220), function() return PrivateAuras(CurrentScope()) end, "anchor", "TOPRIGHT", "geometry")
    local privX = BindNestedSlider(ctx, W.Slider(priv, "Private aura X", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "x", 0, "geometry")
    local privY = BindNestedSlider(ctx, W.Slider(priv, "Private aura Y", -100, 100, 1, 300), function() return PrivateAuras(CurrentScope()) end, "y", 0, "geometry")
    local privControls = {
        privMax,
        privSize,
        privAnchor,
        privX,
        privY,
    }
    local privEnable = BindNestedToggle(ctx, W.SwitchAt(priv, "Private Auras", privLeftX, -64, privControlW), function() return PrivateAuras(CurrentScope()) end, "enabled", true, "visual")
    privEnable._msuf2GroupFrameGateAlwaysEnabled = true
    W.LabelAt(priv, "Display", privLeftX, -38, privLeftW, "GameFontNormalSmall", T.colors.accent)
    W.LabelAt(priv, "Position", privRightX, -38, privRightW, "GameFontNormalSmall", T.colors.accent)
    W.MoveWidget(privMax, priv, privLeftX, -98, privControlW)
    W.MoveWidget(privSize, priv, privLeftX, -150, privControlW)
    W.MoveWidget(privAnchor, priv, privRightX, -64, privRightControlW)
    W.MoveWidget(privX, priv, privRightX, -116, privRightControlW)
    W.MoveWidget(privY, priv, privRightX, -168, privRightControlW)
    local function RefreshPrivateAuraState()
        local nativePrivate = IsPrivateAurasRenderedByBlizzard()
        local cfg = PrivateAuras(CurrentScope())
        local enabled = cfg.enabled ~= false
        SetOptionsEnabled(privControls, enabled and not nativePrivate)
        SetOptionEnabled(privEnable, true)
        SetSectionBadges(priv, {
            OnOffBadge(enabled, "Shown", "Hidden"),
            { text = nativePrivate and Tr("Blizzard") or Tr("Custom"), kind = nativePrivate and "muted" or "accent" },
            { text = "Max " .. BadgeNumber(cfg.max or 4), kind = (enabled and not nativePrivate) and "info" or "muted" },
            { text = BadgeNumber(cfg.size or 20) .. "px", kind = (enabled and not nativePrivate) and "info" or "muted" },
        })
        if type(SetSectionHeaderStatus) == "function" then
            if nativePrivate then
                SetSectionHeaderStatus(priv, {
                    hint = Tr("Rendered by Blizzard"),
                    hintColor = T.colors.danger or { 0.88, 0.28, 0.28, 1 },
                    bg = { 0.120, 0.035, 0.040, 0.55 },
                    arrowColor = T.colors.danger or { 0.88, 0.28, 0.28, 1 },
                })
            else
                SetSectionHeaderStatus(priv, nil)
            end
        end
    end
    M.AddRefresher(ctx, RefreshPrivateAuraState)
    RefreshPrivateAuraState()
    do
        local entry = priv and priv._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshPrivateAuraState end
    end

    if type(ApplyScopeEnabledGate) == "function" then
        M.AddRefresher(ctx, function() ApplyScopeEnabledGate(ctx) end)
        ApplyScopeEnabledGate(ctx)
    end

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("gf_auras", { title = "MSUF Group Buffs & Debuffs", build = BuildGFAuras, version = 15 })
