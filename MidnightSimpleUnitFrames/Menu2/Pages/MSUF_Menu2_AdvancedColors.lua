local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local CallGlobal = AP.CallGlobal
local DB = AP.DB
local G = AP.G
local Bars = AP.Bars
local Gameplay = AP.Gameplay
local BoolValue = AP.BoolValue
local NumValue = AP.NumValue
local SetValue = AP.SetValue
local DeepCopyTable = AP.DeepCopyTable
local BindTableToggle = AP.BindTableToggle
local BindTableSlider = AP.BindTableSlider
local BindTableDropdown = AP.BindTableDropdown
local BindValueDropdown = AP.BindValueDropdown
local ReadRGB = AP.ReadRGB
local WriteRGB = AP.WriteRGB
local BindTableColor = AP.BindTableColor
local BindSeparateRGB = AP.BindSeparateRGB
local ApplyAuras = AP.ApplyAuras
local MoveWidget = AP.MoveWidget
local LabelAt = AP.LabelAt
local DividerAt = AP.DividerAt
local BindValueToggle = AP.BindValueToggle
local BindValueSlider = AP.BindValueSlider
local ToggleAt = AP.ToggleAt
local SwitchAt = AP.SwitchAt
local ValueToggleAt = AP.ValueToggleAt
local ValueSwitchAt = AP.ValueSwitchAt
local SliderAt = AP.SliderAt
local ValueSliderAt = AP.ValueSliderAt
local DropdownAt = AP.DropdownAt
local ValueDropdownAt = AP.ValueDropdownAt
local ColorAt = AP.ColorAt
local ScopedToggleAt = AP.ScopedToggleAt
local ScopedSliderAt = AP.ScopedSliderAt
local ScopedDropdownAt = AP.ScopedDropdownAt
local TogglePillAt = AP.TogglePillAt
local SetControlEnabled = AP.SetControlEnabled

local PRESERVE_HP_UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "boss" }

local function AllUnitframesPreserveHPColor()
    local db = DB()
    for i = 1, #PRESERVE_HP_UNIT_KEYS do
        local key = PRESERVE_HP_UNIT_KEYS[i]
        local conf = db[key]
        if not (conf and conf.alphaPreserveHPColor == true) then
            return false
        end
    end
    return true
end

local function SetAllUnitframesPreserveHPColor(enabled)
    enabled = enabled and true or false
    for i = 1, #PRESERVE_HP_UNIT_KEYS do
        M.SetUnitValue(PRESERVE_HP_UNIT_KEYS[i], "alphaPreserveHPColor", enabled, "MSUF2_PRESERVE_HP_COLOR_ALL", { alpha = true, preview = true })
    end
    if M.WarnPreserveHPColorIfNeeded then M.WarnPreserveHPColorIfNeeded(enabled) end
end

local function ApplyColors()
    local api = ns and ns._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then
        pcall(api.PushVisualUpdates)
    end
    M.RequestGeneralApply("MSUF2_COLORS", { preview = true, applyAll = false })
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    if ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then pcall(ns.MSUF_ApplyGameplayVisuals) end
    local gf = ns and ns.GF
    if gf and type(gf.RefreshVisuals) == "function" then pcall(gf.RefreshVisuals) end
end

local function ApplyCastbarColors()
    ApplyColors()
    if ns and type(ns.MSUF_UpdateCastbarVisuals) == "function" then pcall(ns.MSUF_UpdateCastbarVisuals) end
    if ns and type(ns.MSUF_UpdateCastbarTextures_Immediate) == "function" then pcall(ns.MSUF_UpdateCastbarTextures_Immediate) end
end

local function ApplyGameplayColors()
    ApplyColors()
    if ns and type(ns.MSUF_RequestGameplayApply) == "function" then
        pcall(ns.MSUF_RequestGameplayApply)
    elseif ns and type(ns.MSUF_ApplyGameplayVisuals) == "function" then
        pcall(ns.MSUF_ApplyGameplayVisuals)
    end
end

local function ApplyAuraColors()
    ApplyAuras()
    ApplyColors()
    CallGlobal("MSUF_A2_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_A2_ForceCooldownTextRecolor")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    CallGlobal("MSUF_Auras2_RefreshAll")
    CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
end

local function ApplyClassPowerColors()
    ApplyColors()
    CallGlobal("MSUF_ClassPower_InvalidateColors")
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
end

local function ApplyPortraitColors(reason)
    CallGlobal("MSUF_PortraitDecoration_RefreshAll")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "PORTRAIT_COLORS")
    ApplyColors()
end

local COLOR_CLASS_TOKENS = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local COLOR_CLASS_LABELS = {
    WARRIOR = "Warrior",
    PALADIN = "Paladin",
    HUNTER = "Hunter",
    ROGUE = "Rogue",
    PRIEST = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN = "Shaman",
    MAGE = "Mage",
    WARLOCK = "Warlock",
    MONK = "Monk",
    DRUID = "Druid",
    DEMONHUNTER = "Demon Hunter",
    EVOKER = "Evoker",
}

local COLOR_NPC_ROWS = {
    { key = "friendly", label = "Friendly NPC Color", dr = 0, dg = 1, db = 0 },
    { key = "neutral", label = "Neutral NPC Color", dr = 1, dg = 1, db = 0 },
    { key = "enemy", label = "Enemy NPC Color", dr = 0.85, dg = 0.10, db = 0.10 },
    { key = "dead", label = "Dead NPC Color", dr = 0.40, dg = 0.40, db = 0.40 },
}

local COLOR_NPC_TYPE_ROWS = {
    { key = "npcBoss", label = "Boss", dr = 0.74, dg = 0.11, db = 0 },
    { key = "npcMiniboss", label = "Miniboss / Lieutenant", dr = 0.56, dg = 0, db = 0.74 },
    { key = "npcCaster", label = "Caster", dr = 0, dg = 0.45, db = 0.74 },
    { key = "npcMelee", label = "Melee", dr = 0.99, dg = 0.99, db = 0.99 },
    { key = "npcRegular", label = "Regular", dr = 0.70, dg = 0.56, db = 0.33 },
}

local COLOR_DISPEL_TYPES = {
    { key = "Magic", label = "Magic", dr = 0.20, dg = 0.60, db = 1.00 },
    { key = "Curse", label = "Curse", dr = 0.60, dg = 0.00, db = 1.00 },
    { key = "Disease", label = "Disease", dr = 0.60, dg = 0.40, db = 0.00 },
    { key = "Poison", label = "Poison", dr = 0.00, dg = 0.60, db = 0.00 },
    { key = "Bleed", label = "Bleed", dr = 0.80, dg = 0.10, db = 0.10 },
}

local COLOR_POWER_TOKENS = {
    { value = "MANA", text = "Mana" },
    { value = "RAGE", text = "Rage" },
    { value = "ENERGY", text = "Energy" },
    { value = "FOCUS", text = "Focus" },
    { value = "RUNIC_POWER", text = "Runic Power" },
    { value = "INSANITY", text = "Insanity" },
    { value = "FURY", text = "Fury" },
    { value = "PAIN", text = "Pain" },
    { value = "ESSENCE", text = "Essence" },
    { value = "LUNAR_POWER", text = "Astral Power" },
    { value = "MAELSTROM", text = "Maelstrom" },
}

local COLOR_CP_TOKENS = {
    { value = "COMBO_POINTS", text = "Combo Points" },
    { value = "HOLY_POWER", text = "Holy Power" },
    { value = "SOUL_SHARDS", text = "Soul Shards" },
    { value = "CHI", text = "Chi" },
    { value = "ARCANE_CHARGES", text = "Arcane Charges" },
    { value = "RUNES", text = "Runes" },
    { value = "ESSENCE", text = "Essence" },
    { value = "CHARGED", text = "Empowered / Charged" },
    { value = "SOUL_FRAGMENTS", text = "Soul Fragments" },
    { value = "SOUL_FRAGMENTS_META", text = "Soul Fragments (Void Meta)" },
    { value = "MAELSTROM", text = "Maelstrom Weapon" },
    { value = "MAELSTROM_ABOVE_5", text = "Maelstrom Weapon 5+" },
    { value = "ASTRAL_POWER", text = "Astral Power" },
    { value = "AP_PREDICTION", text = "Astral Prediction" },
    { value = "ECLIPSE_SOLAR", text = "Eclipse Solar" },
    { value = "ECLIPSE_LUNAR", text = "Eclipse Lunar" },
    { value = "ECLIPSE_CA", text = "Celestial Alignment" },
    { value = "STAGGER_GREEN", text = "Stagger Light" },
    { value = "STAGGER_YELLOW", text = "Stagger Moderate" },
    { value = "STAGGER_RED", text = "Stagger Heavy" },
    { value = "SOUL_FRAGMENTS_VENG", text = "Soul Fragments (Vengeance)" },
    { value = "INSANITY", text = "Insanity" },
    { value = "MAELSTROM_POWER", text = "Maelstrom Power" },
    { value = "WHIRLWIND", text = "Whirlwind" },
    { value = "TIP_OF_THE_SPEAR", text = "Tip of the Spear" },
    { value = "ICICLES", text = "Icicles" },
    { value = "EBON_MIGHT", text = "Ebon Might" },
    { value = "RESOURCE_TEXT", text = "Resource Text" },
}

local COLOR_CP_SLOT_TOKENS = {
    "COMBO_POINTS_1", "COMBO_POINTS_2", "COMBO_POINTS_3", "COMBO_POINTS_4",
    "COMBO_POINTS_5", "COMBO_POINTS_6", "COMBO_POINTS_7",
}

local COLOR_CP_SLOT_DEFAULTS = {
    COMBO_POINTS_1 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_2 = { 0.00, 0.95, 1.00 },
    COMBO_POINTS_3 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_4 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_5 = { 1.00, 1.00, 0.00 },
    COMBO_POINTS_6 = { 1.00, 0.05, 0.05 },
    COMBO_POINTS_7 = { 1.00, 0.05, 0.05 },
}

local COLOR_CP_SLOT_MODES = {
    { value = "default", text = "Resource color" },
    { value = "ramp", text = "Combo ramp" },
    { value = "custom", text = "Custom slots" },
}

local COLOR_DATA = {
    CLASS_LABELS = COLOR_CLASS_LABELS,
    NPC_ROWS = COLOR_NPC_ROWS,
    NPC_TYPE_ROWS = COLOR_NPC_TYPE_ROWS,
    DISPEL_TYPES = COLOR_DISPEL_TYPES,
    POWER_TOKENS = COLOR_POWER_TOKENS,
    CP_TOKENS = COLOR_CP_TOKENS,
    CP_SLOT_TOKENS = COLOR_CP_SLOT_TOKENS,
    CP_SLOT_MODES = COLOR_CP_SLOT_MODES,
}

local function ColorAPI()
    return (ns and ns._colorsAPI) or {}
end

local function ApiRGB(name, dr, dg, db)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return dr, dg, db
end

local function ApiSetRGB(name, r, g, b)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        pcall(fn, r, g, b)
    else
        ApplyColors()
    end
end

local function GeneralRGB(prefix, dr, dg, db)
    local g = G()
    return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg, tonumber(g[prefix .. "B"]) or db
end

local function SetGeneralRGB(prefix, r, gCol, b)
    local g = G()
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
    ApplyColors()
end

local function GeneralRGBAlias(primaryPrefix, legacyPrefix, dr, dg, db)
    local g = G()
    return tonumber(g[primaryPrefix .. "R"]) or tonumber(g[legacyPrefix .. "R"]) or dr,
           tonumber(g[primaryPrefix .. "G"]) or tonumber(g[legacyPrefix .. "G"]) or dg,
           tonumber(g[primaryPrefix .. "B"]) or tonumber(g[legacyPrefix .. "B"]) or db
end

local function SetGeneralRGBAlias(primaryPrefix, legacyPrefix, r, gCol, b)
    local g = G()
    g[primaryPrefix .. "R"], g[primaryPrefix .. "G"], g[primaryPrefix .. "B"] = r, gCol, b
    g[legacyPrefix .. "R"], g[legacyPrefix .. "G"], g[legacyPrefix .. "B"] = r, gCol, b
    ApplyColors()
end

local function TableRGB(tbl, key, dr, dg, db)
    local t = tbl and tbl[key]
    if type(t) == "table" then
        local r = tonumber(t[1] or t.r or t["1"])
        local g = tonumber(t[2] or t.g or t["2"])
        local b = tonumber(t[3] or t.b or t["3"])
        if r and g and b then return r, g, b end
    end
    return dr, dg, db
end

local function SetTableRGB(tbl, key, r, g, b)
    if not tbl then return end
    tbl[key] = { r, g, b }
end

local function FontPaletteRGB(key, dr, dg, db)
    local colors = _G.MSUF_FONT_COLORS
    if type(colors) == "table" and type(key) == "string" and colors[key:lower()] then
        local c = colors[key:lower()]
        return c[1] or dr, c[2] or dg, c[3] or db
    end
    return dr, dg, db
end

local function HighlightRGB()
    local g = G()
    if type(g.highlightColor) == "table" then return TableRGB(g, "highlightColor", 1, 1, 1) end
    return FontPaletteRGB(g.highlightColor or "white", 1, 1, 1)
end

local function SetHighlightRGB(r, g, b)
    G().highlightColor = { r, g, b }
    ApplyColors()
    CallGlobal("MSUF_UpdateBossTargetHighlight", true)
    if ns and type(ns.MSUF_FixMouseoverHighlightBindings) == "function" then
        pcall(ns.MSUF_FixMouseoverHighlightBindings)
    end
end

local function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB, labelWidthOverride, swatchWidth)
    local color = W.Color(section, label)
    M.BindColor(ctx, color, getRGB, setRGB)
    if color._msuf2Title then
        local sx, sy = x or 0, y or 0
        local sectionW = section._msuf2Width or 720
        local labelWidth = tonumber(labelWidthOverride) or min(230, max(86, sectionW - sx - 76))
        local buttonWidth = tonumber(swatchWidth) or 44
        color._msuf2Title:ClearAllPoints()
        color._msuf2Title:SetPoint("TOPLEFT", section, "TOPLEFT", sx, sy)
        color._msuf2Title:SetWidth(labelWidth)
        color:SetSize(buttonWidth, 18)
        color:ClearAllPoints()
        color:SetPoint("TOPLEFT", section, "TOPLEFT", sx + labelWidth + 12, sy + 2)
        return color
    end
    return MoveWidget(color, section, x, y)
end

local function ButtonAt(parent, label, x, y, width, onClick)
    local btn = T.Button(parent, label, width or 150, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if type(onClick) == "function" then
        btn:SetScript("OnClick", function(self, ...)
            onClick(self, ...)
            if M.Refresh then M.Refresh() end
        end)
    end
    return btn
end

local function GetClassTokens()
    local tokens = ColorAPI().CLASS_TOKENS
    if type(tokens) == "table" and #tokens > 0 then return tokens end
    return COLOR_CLASS_TOKENS
end

local function GetNPCTypeUnits()
    local units = ColorAPI().NPC_TYPE_UNITS
    if type(units) == "table" and #units > 0 then return units end
    return {
        { key = "npcTypeTarget", label = "Target" },
        { key = "npcTypeFocus", label = "Focus" },
        { key = "npcTypeBoss", label = "Boss" },
        { key = "npcTypeToT", label = "Target of Target" },
    }
end

local function PowerDefaultRGB(token)
    local col = _G.PowerBarColor and token and _G.PowerBarColor[token]
    if type(col) == "table" then
        local r = tonumber(col.r or col[1])
        local g = tonumber(col.g or col[2])
        local b = tonumber(col.b or col[3])
        if r and g and b then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end

local function EnsurePowerOverrides()
    local g = G()
    if type(g.powerColorOverrides) ~= "table" then g.powerColorOverrides = {} end
    return g.powerColorOverrides
end

local function GetPowerOverrideRGB(token)
    local overrides = G().powerColorOverrides
    local r, g, b = PowerDefaultRGB(token)
    if type(overrides) == "table" then return TableRGB(overrides, token, r, g, b) end
    return r, g, b
end

local function SetPowerOverrideRGB(token, r, g, b)
    EnsurePowerOverrides()[token] = { r, g, b }
    ApplyColors()
end

local function ResetPowerOverride(token)
    local overrides = EnsurePowerOverrides()
    overrides[token] = nil
    ApplyColors()
end

local function ClassPowerDefaultRGB(token)
    local slot = COLOR_CP_SLOT_DEFAULTS[token]
    if slot then return slot[1], slot[2], slot[3] end
    if token == "CHARGED" then return 0.60, 0.20, 0.80 end
    if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1) end
    if token == "SOUL_FRAGMENTS" then return 0.00, 0.80, 0.00 end
    if token == "SOUL_FRAGMENTS_META" then return 0.60, 0.20, 0.93 end
    if token == "MAELSTROM" or token == "MAELSTROM_POWER" then return PowerDefaultRGB("MAELSTROM") end
    if token == "MAELSTROM_ABOVE_5" then return 1.00, 0.50, 0.00 end
    if token == "ASTRAL_POWER" or token == "AP_PREDICTION" then return PowerDefaultRGB("LUNAR_POWER") end
    if token == "ECLIPSE_SOLAR" then return 0.82, 0.56, 0.25 end
    if token == "ECLIPSE_LUNAR" then return 0.41, 0.49, 0.82 end
    if token == "ECLIPSE_CA" then return 0.30, 1.00, 0.43 end
    if token == "STAGGER_GREEN" then return 0.52, 1.00, 0.52 end
    if token == "STAGGER_YELLOW" then return 1.00, 0.98, 0.72 end
    if token == "STAGGER_RED" then return 1.00, 0.42, 0.42 end
    if token == "SOUL_FRAGMENTS_VENG" then return 0.34, 0.06, 0.46 end
    if token == "INSANITY" then return PowerDefaultRGB("INSANITY") end
    if token == "WHIRLWIND" then return 0.20, 0.80, 0.20 end
    if token == "TIP_OF_THE_SPEAR" then return 0.60, 0.80, 0.20 end
    if token == "ICICLES" then return 0.50, 0.80, 1.00 end
    if token == "EBON_MIGHT" then return 0.40, 0.80, 0.60 end
    return PowerDefaultRGB(token)
end

local function EnsureClassPowerOverrides()
    local g = G()
    if type(g.classPowerColorOverrides) ~= "table" then g.classPowerColorOverrides = {} end
    if type(g.classPowerBgColorOverrides) ~= "table" then g.classPowerBgColorOverrides = {} end
    return g
end

local function GetClassPowerRGB(token)
    local dr, dg, db = ClassPowerDefaultRGB(token)
    local g = G()
    return TableRGB(g.classPowerColorOverrides, token, dr, dg, db)
end

local function SetClassPowerRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end

local function GetClassPowerBgRGB(token)
    return TableRGB(G().classPowerBgColorOverrides, token, 0, 0, 0)
end

local function SetClassPowerBgRGB(token, r, g, b)
    EnsureClassPowerOverrides().classPowerBgColorOverrides[token] = { r, g, b }
    ApplyClassPowerColors()
end

local function ResetClassPowerRGB(token, bg)
    local g = EnsureClassPowerOverrides()
    if bg then g.classPowerBgColorOverrides[token] = nil else g.classPowerColorOverrides[token] = nil end
    ApplyClassPowerColors()
end

local function GetPandemicRGB()
    local db = DB()
    db.auras2 = db.auras2 or {}
    db.auras2.shared = db.auras2.shared or {}
    local sh = db.auras2.shared
    return tonumber(sh.pandemicR) or 0.0, tonumber(sh.pandemicG) or 0.4, tonumber(sh.pandemicB) or 1.0
end

local function SetPandemicRGB(r, g, b)
    local db = DB()
    db.auras2 = db.auras2 or {}
    db.auras2.shared = db.auras2.shared or {}
    db.auras2.shared.pandemicR, db.auras2.shared.pandemicG, db.auras2.shared.pandemicB = r, g, b
    ApplyAuraColors()
end

local function SetAllPortraitRGB(prefix, r, g, b)
    local db = DB()
    db.general = db.general or {}
    db.general[prefix .. "R"], db.general[prefix .. "G"], db.general[prefix .. "B"] = r, g, b
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
        db[key] = db[key] or {}
        db[key][prefix .. "R"], db[key][prefix .. "G"], db[key][prefix .. "B"] = r, g, b
    end
    ApplyPortraitColors(prefix)
end

local function BuildColors(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Colors", "Frame, bar, aura, castbar and resource colors.", 72)

    local font = b:CollapsibleSection("colors_font", "Global Font Color", 100, false)
    ColorValueAt(ctx, font, "Global font color", 12, -10,
        function() return ApiRGB("GetGlobalFontColor", 1, 1, 1) end,
        function(r, g, c) ApiSetRGB("SetGlobalFontColor", r, g, c) end)
    ButtonAt(font, "Use font palette", 12, -50, 150, function()
        local fn = ColorAPI().ResetGlobalFontToPalette
        if type(fn) == "function" then pcall(fn) else G().useCustomFontColor = false; G().fontColorCustomR, G().fontColorCustomG, G().fontColorCustomB = nil, nil, nil end
        ApplyColors()
    end)

    local tokens = GetClassTokens()
    local classRows = max(1, floor((#tokens + 3) / 4))
    local classResetY = -36 - (classRows * 36)
    local classHeight = max(190, math.abs(classResetY) + 48)
    local classColors = b:CollapsibleSection("colors_classes", "Class Bar Colors", classHeight, false)
    LabelAt(classColors, "Choose an override bar color per class.", 12, -8, 540, "GameFontHighlightSmall", T.colors.muted)
    local classW = classColors._msuf2Width or ctx.width or 720
    local classColW = max(142, floor((classW - 24) / 4))
    local classLabelW = max(76, min(112, classColW - 62))
    for i = 1, #tokens do
        local token = tokens[i]
        local col = (i - 1) % 4
        local row = floor((i - 1) / 4)
        ColorValueAt(ctx, classColors, COLOR_DATA.CLASS_LABELS[token] or token, 12 + col * classColW, -34 - row * 36,
            function()
                local api = ColorAPI()
                if type(api.GetClassColor) == "function" then
                    local ok, r, g, c = pcall(api.GetClassColor, token)
                    if ok then return r, g, c end
                end
                local rc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
                if rc then return rc.r, rc.g, rc.b end
                return 1, 1, 1
            end,
            function(r, g, c)
                local api = ColorAPI()
                if type(api.SetClassColor) == "function" then pcall(api.SetClassColor, token, r, g, c) else ApplyColors() end
            end, classLabelW, 44)
    end
    ButtonAt(classColors, "Reset all class colors", 12, classResetY, 190, function()
        local fn = ColorAPI().ResetAllClassColors
        if type(fn) == "function" then pcall(fn) else DB().classColors = nil end
        ApplyColors()
    end)

    local background = b:CollapsibleSection("colors_background", "Bar Background Tint", 292, false)
    LabelAt(background, "Tint applied to the bar background in *all* bar modes. Dark Mode uses this tint too.", 12, -8, 660, "GameFontHighlightSmall", T.colors.muted)
    ColorValueAt(ctx, background, "Bar background tint", 12, -46,
        function() return ApiRGB("GetClassBarBgColor", 0, 0, 0) end,
        function(r, g, c)
            local api = ColorAPI()
            if type(api.SetClassBarBgColor) == "function" then pcall(api.SetClassBarBgColor, r, g, c) else SetGeneralRGB("classBarBg", r, g, c) end
        end)
    ValueToggleAt(ctx, background, "Background follows HP color", 12, -86,
        function()
            local fn = ColorAPI().GetBarBgMatchHP
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().barBgMatchHPColor == true
        end,
        function(v)
            local fn = ColorAPI().SetBarBgMatchHP
            if type(fn) == "function" then
                pcall(fn, v)
            else
                G().barBgMatchHPColor = v and true or false
                if v then G().barBgClassColor = false end
            end
            ApplyColors()
        end)
    ValueToggleAt(ctx, background, "Health background follows class color", 12, -114,
        function()
            local fn = ColorAPI().GetBarBgClassColor
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().barBgClassColor == true
        end,
        function(v)
            local fn = ColorAPI().SetBarBgClassColor
            if type(fn) == "function" then
                pcall(fn, v)
            else
                G().barBgClassColor = v and true or false
                if v then G().barBgMatchHPColor = false end
            end
            ApplyColors()
        end)
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -142,
        function() return G().darkBgCustomColor == true end,
        function(v) G().darkBgCustomColor = v and true or false; ApplyColors() end)
    ValueToggleAt(ctx, background, "Preserve HP color on all unit frames", 12, -170,
        AllUnitframesPreserveHPColor,
        SetAllUnitframesPreserveHPColor)
    local preserveAllHint = LabelAt(background, "Same setting as each unit page > Transparency. It uses this same HP track color; off here means at least one unit frame is off.", 40, -196, 650, "GameFontHighlightSmall", T.colors.dim)
    if preserveAllHint and preserveAllHint.SetWordWrap then preserveAllHint:SetWordWrap(true) end
    ButtonAt(background, "Reset to black", 12, -250, 140, function()
        local fn = ColorAPI().ResetClassBarBgColor
        if type(fn) == "function" then pcall(fn) else G().classBarBgR, G().classBarBgG, G().classBarBgB = nil, nil, nil end
        ApplyColors()
    end)

    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 290, true)
    ValueDropdownAt(ctx, appearance, "Bar mode", 12, -10, {
        { value = "dark", text = "Dark Mode (dark black bars)" },
        { value = "class", text = "Class Color Mode (color HP bars)" },
        { value = "unified", text = "Unified Color Mode (one color for all frames)" },
        { value = "gradient", text = "Color Gradient" },
    }, 320,
        function()
            local g = G()
            local mode = g.barMode
            if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then
                mode = (g.useClassColors and "class") or "dark"
            end
            return mode
        end,
        function(mode)
            local g = G()
            g.barMode = mode
            g.darkMode = (mode == "dark")
            g.useClassColors = (mode == "class")
            ApplyColors()
        end)
    ColorValueAt(ctx, appearance, "Unified bar color", 12, -70,
        function() return GeneralRGB("unifiedBar", 0.10, 0.60, 0.90) end,
        function(r, g, c) SetGeneralRGB("unifiedBar", r, g, c) end)
    ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -112, 0, 100, 1, 300,
        function()
            local v = tonumber(G().darkBarGray)
            if not v then return 7 end
            if v <= 1 then return floor(v * 100 + 0.5) end
            return floor(v + 0.5)
        end,
        function(v)
            G().darkBarGray = (tonumber(v) or 0) / 100
            G().darkBarTone = nil
            ApplyColors()
        end)
    SliderAt(ctx, appearance, "Gradient strength", 360, -70, 0, 1, 0.05, 250, G, "gradientStrength", 0.45, ApplyColors)
    SwitchAt(ctx, appearance, "Health Gradient", 360, -158, 230, G, "enableHealthGradient", true, ApplyColors)

    local unit = b:CollapsibleSection("colors_unit", "Unitframe Colors", 230, false)
    for i = 1, #COLOR_DATA.NPC_ROWS do
        local row = COLOR_DATA.NPC_ROWS[i]
        ColorValueAt(ctx, unit, row.label, 12, -10 - (i - 1) * 36,
            function()
                local api = ColorAPI()
                if type(api.GetNPCColor) == "function" then
                    local ok, r, g, c = pcall(api.GetNPCColor, row.key)
                    if ok then return r, g, c end
                end
                return row.dr, row.dg, row.db
            end,
            function(r, g, c)
                local api = ColorAPI()
                if type(api.SetNPCColor) == "function" then pcall(api.SetNPCColor, row.key, r, g, c) else ApplyColors() end
            end)
    end
    ColorValueAt(ctx, unit, "Pet Frame Color", 360, -10,
        function() return ApiRGB("GetPetFrameColor", 0, 0.8, 0) end,
        function(r, g, c) ApiSetRGB("SetPetFrameColor", r, g, c) end)
    ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190, function()
        local fn = ColorAPI().ResetAllNPCColors
        if type(fn) == "function" then pcall(fn) else DB().npcColors = nil end
        ApplyColors()
    end)

    local npcType = b:CollapsibleSection("colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls = {}
    npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, "Color HP bar (Class Color mode only)", 32, -38,
        function()
            local fn = ColorAPI().GetNPCTypeColorBar
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().npcTypeColorBar ~= false
        end,
        function(v)
            local fn = ColorAPI().SetNPCTypeColorBar
            if type(fn) == "function" then pcall(fn, v) else G().npcTypeColorBar = v and true or false end
            ApplyColors()
        end)
    npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, "Color name text", 32, -62,
        function()
            local fn = ColorAPI().GetNPCTypeColorText
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().npcTypeColorText ~= false
        end,
        function(v)
            local fn = ColorAPI().SetNPCTypeColorText
            if type(fn) == "function" then pcall(fn, v) else G().npcTypeColorText = v and true or false end
            ApplyColors()
        end)
    local npcMaster = ValueSwitchAt(ctx, npcType, "NPC Type Colors", 12, -10, 260,
        function()
            local fn = ColorAPI().GetNPCColorMode
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v == "type" end end
            return G().npcColorMode == "type"
        end,
        function(v)
            local fn = ColorAPI().SetNPCColorMode
            if type(fn) == "function" then pcall(fn, v and "type" or "reaction") else G().npcColorMode = v and "type" or "reaction" end
            ApplyColors()
        end)
    local units = GetNPCTypeUnits()
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    for i = 1, #units do
        local info = units[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, info.label or info.key, 32 + col * 180, -114 - row * 24,
            function()
                local fn = ColorAPI().GetNPCTypePerUnit
                if type(fn) == "function" then local ok, v = pcall(fn, info.key); if ok then return v end end
                return G()[info.key] ~= false
            end,
            function(v)
                local fn = ColorAPI().SetNPCTypePerUnit
                if type(fn) == "function" then pcall(fn, info.key, v) else G()[info.key] = v and true or false end
                ApplyColors()
            end)
    end
    for i = 1, #COLOR_DATA.NPC_TYPE_ROWS do
        local row = COLOR_DATA.NPC_TYPE_ROWS[i]
        local col = (i - 1) % 2
        local line = floor((i - 1) / 2)
        local sw = ColorValueAt(ctx, npcType, row.label, 12 + col * 330, -174 - line * 38,
            function()
                local api = ColorAPI()
                if type(api.GetNPCColor) == "function" then
                    local ok, r, g, c = pcall(api.GetNPCColor, row.key)
                    if ok then return r, g, c end
                end
                return row.dr, row.dg, row.db
            end,
            function(r, g, c)
                local api = ColorAPI()
                if type(api.SetNPCColor) == "function" then pcall(api.SetNPCColor, row.key, r, g, c) else ApplyColors() end
            end)
        npcControls[#npcControls + 1] = sw
    end
    ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190, function()
        local fn = ColorAPI().ResetNPCTypeColors
        if type(fn) == "function" then pcall(fn) else DB().npcColors = nil end
        ApplyColors()
    end)
    M.AddRefresher(ctx, function()
        local enabled = npcMaster:GetChecked() and true or false
        for i = 1, #npcControls do SetControlEnabled(npcControls[i], enabled) end
    end)

    local barColors = b:CollapsibleSection("colors_bar_colors", "Bar Colors", 240, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    ColorValueAt(ctx, barColors, "Absorb Bar Color", barLeftX, -38,
        function() return ApiRGB("GetAbsorbOverlayColor", 1, 1, 1) end,
        function(r, g, c) ApiSetRGB("SetAbsorbOverlayColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Heal-Absorb Bar Color", barLeftX, -74,
        function() return ApiRGB("GetHealAbsorbOverlayColor", 0.7, 0, 0) end,
        function(r, g, c) ApiSetRGB("SetHealAbsorbOverlayColor", r, g, c) end)
    local powerBg = ColorValueAt(ctx, barColors, "Power Bar Background Color", barLeftX, -110,
        function() return ApiRGB("GetPowerBarBackgroundColor", 0, 0, 0) end,
        function(r, g, c) ApiSetRGB("SetPowerBarBackgroundColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Aggro Border Color", barRightX, -38,
        function() return ApiRGB("GetAggroBorderColor", 1, 0.5, 0) end,
        function(r, g, c) ApiSetRGB("SetAggroBorderColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return ApiRGB("GetBarOutlineColor", 0, 0, 0) end,
        function(r, g, c) ApiSetRGB("SetBarOutlineColor", r, g, c) end)
    local powerBgMatch = ValueToggleAt(ctx, barColors, "Power background matches HP", barRightX, -148,
        function()
            local fn = ColorAPI().GetPowerBarBackgroundMatchHP
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().powerBarBgMatchBarColor == true
        end,
        function(v)
            local fn = ColorAPI().SetPowerBarBackgroundMatchHP
            if type(fn) == "function" then pcall(fn, v) else G().powerBarBgMatchBarColor = v and true or false end
            ApplyColors()
        end)
    ButtonAt(barColors, "Reset Bar Colors", barLeftX, -194, 160, function()
        local g = G()
        for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor" }) do
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = nil, nil, nil, nil
        end
        g.hlAggroColorR, g.hlAggroColorG, g.hlAggroColorB = nil, nil, nil
        g.hlPurgeColorR, g.hlPurgeColorG, g.hlPurgeColorB = nil, nil, nil
        g.aggroBorderColorR, g.aggroBorderColorG, g.aggroBorderColorB = nil, nil, nil
        g.powerBarBgMatchBarColor = nil
        ApplyColors()
    end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(powerBg, not (powerBgMatch:GetChecked() and true or false))
    end)

    local dispel = b:CollapsibleSection("colors_dispel", "Dispel", 310, false)
    LabelAt(dispel, "Dispel color shared by Highlight Border and Unit/Group Frame Dispel Overlay.", 12, -8, 620, "GameFontHighlightSmall", T.colors.muted)
    ValueDropdownAt(ctx, dispel, "Color mode", 12, -42, {
        { value = "SINGLE", text = "Single color" },
        { value = "TYPE", text = "Per debuff type" },
    }, 220,
        function() return G().hlDispelColorMode or "SINGLE" end,
        function(v)
            G().hlDispelColorMode = v or "SINGLE"
            ApplyColors()
            CallGlobal("MSUF_PrioRows_Reinit")
        end)
    local singleDispel = ColorValueAt(ctx, dispel, "Dispel Color (all types)", 12, -102,
        function() return GeneralRGBAlias("hlDispelColor", "dispelBorderColor", 0.25, 0.75, 1.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlDispelColor", "dispelBorderColor", r, g, c) end)
    local typeControls = {}
    for i = 1, #COLOR_DATA.DISPEL_TYPES do
        local def = COLOR_DATA.DISPEL_TYPES[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        typeControls[#typeControls + 1] = ColorValueAt(ctx, dispel, def.label, 12 + col * 330, -146 - row * 36,
            function() return GeneralRGB("dispelType" .. def.key, def.dr, def.dg, def.db) end,
            function(r, g, c) SetGeneralRGB("dispelType" .. def.key, r, g, c) end)
    end
    ButtonAt(dispel, "Reset Dispel Colors", 12, -274, 180, function()
        local g = G()
        g.dispelBorderColorR, g.dispelBorderColorG, g.dispelBorderColorB = nil, nil, nil
        g.hlDispelColorR, g.hlDispelColorG, g.hlDispelColorB = nil, nil, nil
        g.hlDispelColorMode = nil
        for i = 1, #COLOR_DATA.DISPEL_TYPES do
            local prefix = "dispelType" .. COLOR_DATA.DISPEL_TYPES[i].key
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = nil, nil, nil
        end
        ApplyColors()
        CallGlobal("MSUF_PrioRows_Reinit")
    end)
    M.AddRefresher(ctx, function()
        local single = (G().hlDispelColorMode or "SINGLE") ~= "TYPE"
        SetControlEnabled(singleDispel, single)
        for i = 1, #typeControls do SetControlEnabled(typeControls[i], not single) end
    end)

    local castbar = b:CollapsibleSection("colors_castbar", "Castbar Colors", 544, false)
    local castW = castbar._msuf2Width or ctx.width or 720
    ColorValueAt(ctx, castbar, "Interruptible cast color", 12, -10,
        function() return ApiRGB("GetInterruptibleCastColor", 0, 0.9, 0.8) end,
        function(r, g, c) ApiSetRGB("SetInterruptibleCastColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Non-interruptible cast color", 12, -46,
        function() return ApiRGB("GetNonInterruptibleCastColor", 0.4, 0.01, 0.01) end,
        function(r, g, c) ApiSetRGB("SetNonInterruptibleCastColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Interrupt color (all castbars)", 12, -82,
        function() return ApiRGB("GetInterruptFeedbackCastColor", 1.0, 0.82, 0.0) end,
        function(r, g, c) ApiSetRGB("SetInterruptFeedbackCastColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Castbar text color", 360, -10,
        function() return ApiRGB("GetCastbarTextColor", 1, 1, 1) end,
        function(r, g, c) ApiSetRGB("SetCastbarTextColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Castbar border color", 360, -46,
        function() return ApiRGB("GetCastbarBorderColor", 0, 0, 0) end,
        function(r, g, c)
            local fn = ColorAPI().SetCastbarBorderColor
            if type(fn) == "function" then pcall(fn, r, g, c, 1) else SetGeneralRGB("castbarBorder", r, g, c) end
            ApplyCastbarColors()
        end)
    ColorValueAt(ctx, castbar, "Castbar background color", 360, -82,
        function() return ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10) end,
        function(r, g, c)
            local fn = ColorAPI().SetCastbarBackgroundColor
            if type(fn) == "function" then pcall(fn, r, g, c, 0.85) else SetGeneralRGB("castbarBg", r, g, c) end
            ApplyCastbarColors()
        end)
    LabelAt(castbar, "Player castbar override", 12, -134, 260, "GameFontNormal", T.colors.text)
    local overrideModeX, overrideModeW = 300, 190
    local overrideColorX = min(max(overrideModeX + overrideModeW + 36, floor(castW * 0.56)), castW - 236)
    local overrideColorLabelW = max(120, min(168, castW - overrideColorX - 76))
    local overrideColorY = -154
    if overrideColorX < overrideModeX + overrideModeW + 24 then
        overrideColorX = overrideModeX
        overrideColorY = -210
        overrideColorLabelW = max(120, min(230, castW - overrideColorX - 76))
    end
    local overrideColor = ColorValueAt(ctx, castbar, "Custom color", overrideColorX, overrideColorY,
        function() return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1) end,
        function(r, g, c) ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, c); ApplyCastbarColors() end,
        overrideColorLabelW)
    local overrideMode = ValueDropdownAt(ctx, castbar, "Mode", overrideModeX, -154, {
        { value = "CLASS", text = "Class color" },
        { value = "CUSTOM", text = "Custom color" },
    }, overrideModeW,
        function()
            local fn = ColorAPI().GetPlayerCastbarOverrideMode
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().playerCastbarOverrideMode or "CLASS"
        end,
        function(v)
            local fn = ColorAPI().SetPlayerCastbarOverrideMode
            if type(fn) == "function" then pcall(fn, v) else G().playerCastbarOverrideMode = v end
            ApplyCastbarColors()
        end)
    local overrideEnable = ValueSwitchAt(ctx, castbar, "Player override", 12, -154, 260,
        function()
            local fn = ColorAPI().GetPlayerCastbarOverrideEnabled
            if type(fn) == "function" then local ok, v = pcall(fn); if ok then return v end end
            return G().playerCastbarOverrideEnabled == true
        end,
        function(v)
            local fn = ColorAPI().SetPlayerCastbarOverrideEnabled
            if type(fn) == "function" then pcall(fn, v) else G().playerCastbarOverrideEnabled = v and true or false end
            ApplyCastbarColors()
        end)
    LabelAt(castbar, "Interrupt Ready Indicator", 12, -244, 260, "GameFontNormal", T.colors.text)
    ColorValueAt(ctx, castbar, "Ready color (kick available)", 12, -274,
        function() return TableRGB(G(), "kickReadyColor", 0, 1, 0) end,
        function(r, g, c) SetTableRGB(G(), "kickReadyColor", r, g, c); ApplyCastbarColors() end)
    ColorValueAt(ctx, castbar, "Not ready color (kick on cooldown)", 12, -310,
        function() return TableRGB(G(), "kickNotReadyColor", 1, 0, 0) end,
        function(r, g, c) SetTableRGB(G(), "kickNotReadyColor", r, g, c); ApplyCastbarColors() end)
    ButtonAt(castbar, "Reset castbar colors", 12, -470, 170, function()
        local api = ColorAPI()
        if type(api.ResetCastbarTextColorToGlobal) == "function" then pcall(api.ResetCastbarTextColorToGlobal) end
        if type(api.ResetCastbarBorderColor) == "function" then pcall(api.ResetCastbarBorderColor) end
        if type(api.ResetCastbarBackgroundColor) == "function" then pcall(api.ResetCastbarBackgroundColor) end
        local g = G()
        g.castbarInterruptibleR, g.castbarInterruptibleG, g.castbarInterruptibleB = nil, nil, nil
        g.castbarNonInterruptibleR, g.castbarNonInterruptibleG, g.castbarNonInterruptibleB = nil, nil, nil
        g.castbarInterruptFeedbackR, g.castbarInterruptFeedbackG, g.castbarInterruptFeedbackB = nil, nil, nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        g.playerCastbarOverrideR, g.playerCastbarOverrideG, g.playerCastbarOverrideB = nil, nil, nil
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        ApplyCastbarColors()
    end)
    M.AddRefresher(ctx, function()
        local enabled = overrideEnable:GetChecked() and true or false
        SetControlEnabled(overrideMode, enabled)
        SetControlEnabled(overrideColor, enabled and ((overrideMode.GetValue and overrideMode:GetValue()) == "CUSTOM"))
    end)

    local highlight = b:CollapsibleSection("colors_highlight", "Mouseover Highlight", 210, false)
    local highlightColor = ColorValueAt(ctx, highlight, "Mouseover highlight color", 12, -48, HighlightRGB, SetHighlightRGB)
    local highlightEnabled = SwitchAt(ctx, highlight, "Mouseover Highlight", 12, -10, 260, G, "highlightEnabled", true, function()
        SetHighlightRGB(HighlightRGB())
    end)
    ColorValueAt(ctx, highlight, "Boss target highlight color", 12, -104,
        function() return TableRGB(G(), "bossTargetHighlightColor", 1, 0.82, 0) end,
        function(r, g, c)
            SetTableRGB(G(), "bossTargetHighlightColor", r, g, c)
            ApplyColors()
            CallGlobal("MSUF_UpdateBossTargetHighlight", true)
        end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(highlightColor, G().highlightEnabled ~= false)
    end)

    local gameplay = b:CollapsibleSection("colors_gameplay", "Gameplay", 310, false)
    ColorValueAt(ctx, gameplay, "Combat timer text color", 12, -10,
        function() return TableRGB(Gameplay(), "combatTimerColor", 1, 1, 1) end,
        function(r, g, c) SetTableRGB(Gameplay(), "combatTimerColor", r, g, c); ApplyGameplayColors() end)
    ColorValueAt(ctx, gameplay, "Combat Enter text color", 12, -46,
        function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
        function(r, g, c)
            local gp = Gameplay()
            SetTableRGB(gp, "combatStateEnterColor", r, g, c)
            if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
            ApplyGameplayColors()
        end)
    local leaveColor = ColorValueAt(ctx, gameplay, "Combat Leave text color", 12, -82,
        function() return TableRGB(Gameplay(), "combatStateLeaveColor", 0.7, 0.7, 0.7) end,
        function(r, g, c) SetTableRGB(Gameplay(), "combatStateLeaveColor", r, g, c); ApplyGameplayColors() end)
    local sync = BindTableToggle(ctx, gameplay, "Sync", Gameplay, "combatStateColorSync", false, function()
        local gp = Gameplay()
        if gp.combatStateColorSync then
            local r, g, c = TableRGB(gp, "combatStateEnterColor", 1, 1, 1)
            SetTableRGB(gp, "combatStateLeaveColor", r, g, c)
        end
        ApplyGameplayColors()
    end)
    MoveWidget(sync, gameplay, 360, -82)
    ColorValueAt(ctx, gameplay, "Crosshair in-range color", 12, -142,
        function() return TableRGB(Gameplay(), "crosshairInRangeColor", 0, 1, 0) end,
        function(r, g, c) SetTableRGB(Gameplay(), "crosshairInRangeColor", r, g, c); ApplyGameplayColors() end)
    ColorValueAt(ctx, gameplay, "Crosshair out-of-range color", 12, -178,
        function() return TableRGB(Gameplay(), "crosshairOutRangeColor", 1, 0, 0) end,
        function(r, g, c) SetTableRGB(Gameplay(), "crosshairOutRangeColor", r, g, c); ApplyGameplayColors() end)
    ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors()
    end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(leaveColor, not (Gameplay().combatStateColorSync == true))
    end)

    local power = b:CollapsibleSection("colors_power", "Power Bar Colors", 150, false)
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    local powerColor
    ValueDropdownAt(ctx, power, "Power type", 12, -10, COLOR_DATA.POWER_TOKENS, 260,
        function() return M.colorsPowerToken or "MANA" end,
        function(v)
            if type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue("colorsPowerToken", v or "MANA")
            else
                M.colorsPowerToken = v or "MANA"
            end
            if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken)) end
        end)
    powerColor = ColorValueAt(ctx, power, "Color", 360, -10,
        function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
        function(r, g, c) SetPowerOverrideRGB(M.colorsPowerToken or "MANA", r, g, c) end)
    ButtonAt(power, "Reset", 360, -54, 90, function()
        ResetPowerOverride(M.colorsPowerToken or "MANA")
        if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken or "MANA")) end
    end)

    local classPower = b:CollapsibleSection("colors_class_power", "Class Power Colors", 430, false)
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local cpColor, cpBg
    ValueDropdownAt(ctx, classPower, "Resource type", 12, -10, COLOR_DATA.CP_TOKENS, 310,
        function() return M.colorsCPToken or "COMBO_POINTS" end,
        function(v)
            if type(M.PersistMenuStateValue) == "function" then
                M.PersistMenuStateValue("colorsCPToken", v or "COMBO_POINTS")
            else
                M.colorsCPToken = v or "COMBO_POINTS"
            end
            if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken)) end
            if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken)) end
        end)
    cpColor = ColorValueAt(ctx, classPower, "Color", 360, -10,
        function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end)
    cpBg = ColorValueAt(ctx, classPower, "Background", 360, -46,
        function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end)
    ButtonAt(classPower, "Reset color", 360, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", false)
        if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end)
    ButtonAt(classPower, "Reset bg", 480, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", true)
        if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end)
    ValueDropdownAt(ctx, classPower, "Combo point slot mode", 12, -92, COLOR_DATA.CP_SLOT_MODES, 230,
        function()
            local mode = Bars().classPowerComboPointColorMode or "default"
            if mode ~= "ramp" and mode ~= "custom" then mode = "default" end
            return mode
        end,
        function(v)
            Bars().classPowerComboPointColorMode = v or "default"
            ApplyClassPowerColors()
        end)
    for i = 1, #COLOR_DATA.CP_SLOT_TOKENS do
        local token = COLOR_DATA.CP_SLOT_TOKENS[i]
        ColorValueAt(ctx, classPower, tostring(i), 12 + ((i - 1) % 4) * 160, -154 - floor((i - 1) / 4) * 38,
            function() return GetClassPowerRGB(token) end,
            function(r, g, c)
                Bars().classPowerComboPointColorMode = "custom"
                SetClassPowerRGB(token, r, g, c)
            end, 24, 44)
    end
    ButtonAt(classPower, "Reset slots", 12, -246, 120, function()
        local g = EnsureClassPowerOverrides()
        for i = 1, #COLOR_DATA.CP_SLOT_TOKENS do g.classPowerColorOverrides[COLOR_DATA.CP_SLOT_TOKENS[i]] = nil end
        ApplyClassPowerColors()
    end)

    local auras = b:CollapsibleSection("colors_auras", "Auras", 310, false)
    ColorValueAt(ctx, auras, "Own buff highlight color", 12, -10,
        function() return TableRGB(G(), "aurasOwnBuffHighlightColor", 1.0, 0.85, 0.2) end,
        function(r, g, c) SetTableRGB(G(), "aurasOwnBuffHighlightColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Own debuff highlight color", 12, -46,
        function() return TableRGB(G(), "aurasOwnDebuffHighlightColor", 1.0, 0.85, 0.2) end,
        function(r, g, c) SetTableRGB(G(), "aurasOwnDebuffHighlightColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Stack count text color", 12, -82,
        function() return TableRGB(G(), "aurasStackCountColor", 1, 1, 1) end,
        function(r, g, c) SetTableRGB(G(), "aurasStackCountColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Pandemic window color", 12, -118, GetPandemicRGB, SetPandemicRGB)
    local bucketToggle = BindTableToggle(ctx, auras, "Color aura timers by remaining time", G, "aurasCooldownTextUseBuckets", true, ApplyAuraColors)
    MoveWidget(bucketToggle, auras, 12, -154)
    ColorValueAt(ctx, auras, "Cooldown text: Safe", 360, -10,
        function()
            local t = G().aurasCooldownTextSafeColor
            if type(t) == "table" then return TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1) end
            return ApiRGB("GetGlobalFontColor", 1, 1, 1)
        end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextSafeColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Cooldown text: Warning", 360, -46,
        function() return TableRGB(G(), "aurasCooldownTextWarningColor", 1, 0.85, 0.2) end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextWarningColor", r, g, c); ApplyAuraColors() end)
    ColorValueAt(ctx, auras, "Cooldown text: Urgent", 360, -82,
        function() return TableRGB(G(), "aurasCooldownTextUrgentColor", 1, 0.55, 0.1) end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextUrgentColor", r, g, c); ApplyAuraColors() end)
    ButtonAt(auras, "Reset aura colors", 12, -264, 150, function()
        local g = G()
        g.aurasOwnBuffHighlightColor = { 1.0, 0.85, 0.2 }
        g.aurasOwnDebuffHighlightColor = { 1.0, 0.85, 0.2 }
        g.aurasStackCountColor = { 1, 1, 1 }
        g.aurasCooldownTextSafeColor = nil
        g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
        g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
        SetPandemicRGB(0.0, 0.4, 1.0)
        ApplyAuraColors()
    end)

    local portrait = b:CollapsibleSection("colors_portrait", "Portrait Colors", 180, false)
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end)
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end)
    ButtonAt(portrait, "Reset portrait colors", 12, -118, 170, function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        G().portraitBorderColorA = 1
        G().portraitBgColorA = 0.85
        ApplyPortraitColors("PORTRAIT_COLOR_RESET")
    end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 3 })
