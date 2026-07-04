local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Advanced Colors page.
-- Binds global color palettes, class/power overrides, aura colors, and border colors. Color
-- apply is coalesced because one edit may need to refresh several frame families.
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}
local floor = math.floor
local max = math.max
local min = math.min
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CallGlobal, DB, G, Bars, Gameplay, BindTableToggle, ApplyAuras, MoveWidget, LabelAt, SwitchAt, ValueToggleAt, ValueSwitchAt, SliderAt, ValueSliderAt, ValueDropdownAt, SetControlEnabled = M.Pick(AP, [[CallGlobal DB G Bars Gameplay BindTableToggle ApplyAuras MoveWidget LabelAt SwitchAt ValueToggleAt ValueSwitchAt SliderAt ValueSliderAt ValueDropdownAt SetControlEnabled]])
local KLR, WL, ColorRows, KeyLabelMap, ValueTextPairs, SetControlsEnabled = M.KeyLabelRows, M.WordList, M.ColorRows, M.KeyLabelMap, M.ValueTextPairs, W.SetControlsEnabled
local colorApplyQueued = false
local auraColorFanoutQueued = false
local classPowerColorFanoutQueued = false
local portraitColorFanoutQueued = false
local unitframeColorReloadPromptQueued = false
local COLOR_APPLY_DELAY = 0.04
-- Multiple color sliders can fire in one frame while dragging. Queue a single apply so live
-- frames repaint once per frame instead of per slider event.
local ColorValueAt
local function FlushColorApply()
    colorApplyQueued = false
    local api = MSUF and MSUF._colorsAPI
    local pushed = api and type(api.PushVisualUpdates) == "function"
    if pushed then api.PushVisualUpdates() end
    M.RequestGeneralApply("MSUF2_COLORS", { preview = true, applyAll = false, colors = true, colorsPushed = pushed })
end
local function ApplyColors()
    if colorApplyQueued then return end
    colorApplyQueued = true
    if type(_G.MSUF_ScheduleOnce) == "function" then
        if type(_G.MSUF_ScheduleDelayOnce) == "function" then
            _G.MSUF_ScheduleDelayOnce("MSUF2_COLORS_APPLY", COLOR_APPLY_DELAY, FlushColorApply)
        else
            _G.MSUF_ScheduleOnce("MSUF2_COLORS_APPLY", FlushColorApply)
        end
    else
        _G.C_Timer.After(COLOR_APPLY_DELAY, FlushColorApply)
    end
end
local function ScheduleColorFanout(key, flagName, fn)
    if flagName == "auras" then
        if auraColorFanoutQueued then return end
        auraColorFanoutQueued = true
    elseif flagName == "classpower" then
        if classPowerColorFanoutQueued then return end
        classPowerColorFanoutQueued = true
    elseif flagName == "portrait" then
        if portraitColorFanoutQueued then return end
        portraitColorFanoutQueued = true
    end
    local function Run()
        if flagName == "auras" then auraColorFanoutQueued = false
        elseif flagName == "classpower" then classPowerColorFanoutQueued = false
        elseif flagName == "portrait" then portraitColorFanoutQueued = false end
        fn()
    end
    if type(_G.MSUF_ScheduleDelayOnce) == "function" then
        _G.MSUF_ScheduleDelayOnce(key, COLOR_APPLY_DELAY, Run)
    else
        _G.C_Timer.After(COLOR_APPLY_DELAY, Run)
    end
end
local function ShowUnitframeColorReloadPrompt()
    if unitframeColorReloadPromptQueued then return end
    unitframeColorReloadPromptQueued = true
    local function Show()
        unitframeColorReloadPromptQueued = false
        if type(_G.StaticPopup_FindVisible) == "function" and _G.StaticPopup_FindVisible("MSUF_RELOAD_RECOMMENDED") then return end
        CallGlobal("MSUF_ShowReloadRecommendedPopup", "Unitframe color changes")
    end
    if type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce("MSUF2_UNITFRAME_COLOR_RELOAD_PROMPT", Show)
    else
        _G.C_Timer.After(0, Show)
    end
end
local function ApplyUnitframeColorWithReload()
    ApplyColors()
    ShowUnitframeColorReloadPrompt()
end
local function ApplyCastbarColors()
    ApplyColors()
    M.RequestGeneralApply("MSUF2_CASTBAR_COLORS", { castbar = true, castbarTextures = true, preview = true, applyAll = false })
    CallGlobal("MSUF_KickReady_RefreshAll")
end
local function ApplyGameplayColors()
    ApplyColors()
end
local function ApplyAuraColors()
    ApplyAuras()
    ApplyColors()
    -- Aura timer bucket coloring is baked into a C-side formatter at button-create
    -- time, so a plain RefreshAll (which reuses lanes) would not pick up new
    -- colors/thresholds. Bump the native visual generation to force lane recreate.
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.ApplyFontsFromGlobal) == "function" then a3.ApplyFontsFromGlobal() end
    ScheduleColorFanout("MSUF2_AURA_COLOR_FANOUT", "auras", function()
        CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
    end)
end
local function ApplyClassPowerColors()
    ApplyColors()
    ScheduleColorFanout("MSUF2_CLASSPOWER_COLOR_FANOUT", "classpower", function()
        CallGlobal("MSUF_ClassPower_InvalidateColors")
        CallGlobal("MSUF_ClassPower_Refresh")
        CallGlobal("MSUF_ClassPower_RefreshTextures")
    end)
end
local function ApplyPortraitColors(reason)
    ApplyColors()
    ScheduleColorFanout("MSUF2_PORTRAIT_COLOR_FANOUT", "portrait", function()
        CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "PORTRAIT_COLORS")
        CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "PORTRAIT_COLORS")
    end)
end
local COLOR_CLASS_TOKENS = WL [[WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER]]
local COLOR_CLASS_LABELS = KeyLabelMap [[WARRIOR=Warrior|PALADIN=Paladin|HUNTER=Hunter|ROGUE=Rogue|PRIEST=Priest|DEATHKNIGHT=Death Knight|SHAMAN=Shaman|MAGE=Mage|WARLOCK=Warlock|MONK=Monk|DRUID=Druid|DEMONHUNTER=Demon Hunter|EVOKER=Evoker]]
local COLOR_NPC_ROWS = ColorRows "friendly|Friendly NPC Color|0|1|0;neutral|Neutral NPC Color|1|1|0;enemy|Enemy NPC Color|0.85|0.10|0.10;dead|Dead NPC Color|0.40|0.40|0.40"
local COLOR_NPC_TYPE_ROWS = ColorRows "npcBoss|Boss|0.74|0.11|0;npcMiniboss|Miniboss / Lieutenant|0.56|0|0.74;npcCaster|Caster|0|0.45|0.74;npcMelee|Melee|0.99|0.99|0.99;npcRegular|Regular|0.70|0.56|0.33"
local COLOR_POWER_TOKENS = ValueTextPairs [[MANA=Mana|RAGE=Rage|ENERGY=Energy|FOCUS=Focus|RUNIC_POWER=Runic Power|INSANITY=Insanity|FURY=Fury|PAIN=Pain|ESSENCE=Essence|LUNAR_POWER=Astral Power|MAELSTROM=Maelstrom]]
local COLOR_CP_TOKENS = ValueTextPairs [[COMBO_POINTS=Combo Points|HOLY_POWER=Holy Power|SOUL_SHARDS=Soul Shards|CHI=Chi|ARCANE_CHARGES=Arcane Charges|RUNES=Runes|ESSENCE=Essence|CHARGED=Empowered / Charged|SOUL_FRAGMENTS=Soul Fragments|SOUL_FRAGMENTS_META=Soul Fragments (Void Meta)|MAELSTROM=Maelstrom Weapon|MAELSTROM_ABOVE_5=Maelstrom Weapon 5+|ASTRAL_POWER=Astral Power|AP_PREDICTION=Astral Prediction|ECLIPSE_SOLAR=Eclipse Solar|ECLIPSE_LUNAR=Eclipse Lunar|ECLIPSE_CA=Celestial Alignment|STAGGER_GREEN=Stagger Light|STAGGER_YELLOW=Stagger Moderate|STAGGER_RED=Stagger Heavy|SOUL_FRAGMENTS_VENG=Soul Fragments (Vengeance)|INSANITY=Insanity|MAELSTROM_POWER=Maelstrom Power|WHIRLWIND=Whirlwind|TIP_OF_THE_SPEAR=Tip of the Spear|ICICLES=Icicles|EBON_MIGHT=Ebon Might|RESOURCE_TEXT=Resource Text]]
local COLOR_CP_SLOT_TOKENS = WL [[COMBO_POINTS_1 COMBO_POINTS_2 COMBO_POINTS_3 COMBO_POINTS_4 COMBO_POINTS_5 COMBO_POINTS_6 COMBO_POINTS_7]]
local COLOR_CP_SLOT_DEFAULTS = {}
for _, row in ipairs(ColorRows [[COMBO_POINTS_1|1|0.00|0.95|1.00;COMBO_POINTS_2|2|0.00|0.95|1.00;COMBO_POINTS_3|3|1.00|1.00|0.00;COMBO_POINTS_4|4|1.00|1.00|0.00;COMBO_POINTS_5|5|1.00|1.00|0.00;COMBO_POINTS_6|6|1.00|0.05|0.05;COMBO_POINTS_7|7|1.00|0.05|0.05]]) do
    COLOR_CP_SLOT_DEFAULTS[row.key] = { row.dr, row.dg, row.db }
end
local COLOR_CP_SLOT_MODES = ValueTextPairs "default=Resource color|ramp=Combo ramp|custom=Custom slots"
local COLOR_DATA = {
    CLASS_LABELS = COLOR_CLASS_LABELS,
    NPC_ROWS = COLOR_NPC_ROWS,
    NPC_TYPE_ROWS = COLOR_NPC_TYPE_ROWS,
    POWER_TOKENS = COLOR_POWER_TOKENS,
    CP_TOKENS = COLOR_CP_TOKENS,
    CP_SLOT_TOKENS = COLOR_CP_SLOT_TOKENS,
    CP_SLOT_MODES = COLOR_CP_SLOT_MODES,
}
local function ColorAPI()
    return (MSUF and MSUF._colorsAPI) or {}
end
local function ApiCall(name, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        fn(...)
        return true
    end
    return false
end
local function ApiValue(name, fallback, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local value = fn(...)
        if value ~= nil then return value end
    end
    if type(fallback) == "function" then return fallback() end
    return fallback
end
local function ApiRGB(name, dr, dg, db, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local r, g, b = fn(...)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
    end
    return dr, dg, db
end
local function ApiSetRGB(name, r, g, b)
    if not ApiCall(name, r, g, b) then ApplyColors() end
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
local function ApplyGlobalOutlineColor()
    ApplyColors()
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    CallGlobal("MSUF_ApplyRoundedUnitframes")
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
local function ClearRGB(tbl, prefix)
    if tbl then tbl[prefix .. "R"], tbl[prefix .. "G"], tbl[prefix .. "B"] = nil, nil, nil end
end
local function ClearRGBs(tbl, ...) for i = 1, select("#", ...) do ClearRGB(tbl, select(i, ...)) end end
local function ClearRGBAs(tbl, ...) for i = 1, select("#", ...) do local prefix = select(i, ...); ClearRGB(tbl, prefix); tbl[prefix .. "A"] = nil end end
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
    if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate(nil) end
    --- Repaint the mouseover highlight cache so the new colour applies live.
    if _G.MSUF_RefreshMouseoverHighlight then _G.MSUF_RefreshMouseoverHighlight() end
end
function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB, labelWidthOverride, swatchWidth)
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
local function ApiColorAt(ctx, section, label, x, y, getName, setName, dr, dg, db, apply, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c)
            ApiSetRGB(setName, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth)
end
local function GeneralColorAt(ctx, section, label, x, y, prefix, dr, dg, db, apply, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, c)
            SetGeneralRGB(prefix, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth)
end
local function ApiOrGeneralColorAt(ctx, section, label, x, y, getName, setName, prefix, dr, dg, db, apply, alpha)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c)
            local ok = alpha ~= nil and ApiCall(setName, r, g, c, alpha) or ApiCall(setName, r, g, c)
            if not ok then SetGeneralRGB(prefix, r, g, c) end
            if type(apply) == "function" then apply() end
        end)
end
local function TableColorAt(ctx, section, label, x, y, getTable, key, dr, dg, db, apply, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, c)
            SetTableRGB(getTable(), key, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth)
end
local function BuildApiColorSpecs(ctx, section, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return ApiColorAt(ctx, section, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9] or apply, s[10], s[11]), s[12] or s[5] or i end,
    })
end
local function BuildTableColorSpecs(ctx, section, getTable, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return TableColorAt(ctx, section, s[1], s[2], s[3], getTable, s[4], s[5], s[6], s[7], s[8] or apply, s[9]), s[10] or s[4] or i end,
    })
end
local function BuildApiOrGeneralColorSpecs(ctx, section, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return ApiOrGeneralColorAt(ctx, section, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10] or apply, s[11]), s[12] or s[6] or i end,
    })
end
local function ButtonAt(parent, label, x, y, width, onClick)
    local btn = T.Button(parent, label, width or 150, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if type(onClick) == "function" then
        btn:SetScript("OnClick", function(self, ...)
            onClick(self, ...)
            if M.RequestRefresh then M.RequestRefresh(nil, "advanced-colors-button") elseif M.Refresh then M.Refresh() end
        end)
    end
    return btn
end
local function Card(parent, title, subtitle, x, y, width, height)
    local card = W.ControlCard(parent, title, subtitle, x, y, width, height)
    if card and T.ApplyBackdrop then T.ApplyBackdrop(card, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    return card
end
local function NPCColorAt(ctx, section, row, x, y, apply)
    return ColorValueAt(ctx, section, row.label, x, y,
        function() return ApiRGB("GetNPCColor", row.dr, row.dg, row.db, row.key) end,
        function(r, g, c)
            if not ApiCall("SetNPCColor", row.key, r, g, c) then ApplyColors() end
            if type(apply) == "function" then apply() end
        end)
end
local COLOR_HELPERS = {
    ApiColorAt = ApiColorAt,
    ApiColorSpecs = BuildApiColorSpecs,
    ApiOrGeneralColorSpecs = BuildApiOrGeneralColorSpecs,
    ButtonAt = ButtonAt,
    GeneralColorAt = GeneralColorAt,
    TableColorSpecs = BuildTableColorSpecs,
    TableColorAt = TableColorAt,
}
local function GetClassTokens()
    local tokens = ColorAPI().CLASS_TOKENS
    if type(tokens) == "table" and #tokens > 0 then return tokens end
    return COLOR_CLASS_TOKENS
end
local function ClassDefaultRGB(token)
    local rc = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if rc then return rc.r, rc.g, rc.b end
    return 1, 1, 1
end
local function ClassColorRGB(token)
    local r, g, b = ClassDefaultRGB(token)
    return ApiRGB("GetClassColor", r, g, b, token)
end
local function GetNPCTypeUnits()
    local units = ColorAPI().NPC_TYPE_UNITS
    if type(units) == "table" and #units > 0 then return units end
    return KLR [[npcTypeTarget=Target
npcTypeFocus=Focus
npcTypeBoss=Boss
npcTypeToT=Target of Target]]
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
local CLASS_POWER_STATIC_DEFAULTS = {}
for _, row in ipairs(ColorRows [[CHARGED|Charged|0.60|0.20|0.80;SOUL_FRAGMENTS|Soul Fragments|0.00|0.80|0.00;SOUL_FRAGMENTS_META|Soul Fragments Meta|0.60|0.20|0.93;MAELSTROM_ABOVE_5|Maelstrom Above 5|1.00|0.50|0.00;ECLIPSE_SOLAR|Eclipse Solar|0.82|0.56|0.25;ECLIPSE_LUNAR|Eclipse Lunar|0.41|0.49|0.82;ECLIPSE_CA|Eclipse CA|0.30|1.00|0.43;STAGGER_GREEN|Stagger Green|0.52|1.00|0.52;STAGGER_YELLOW|Stagger Yellow|1.00|0.98|0.72;STAGGER_RED|Stagger Red|1.00|0.42|0.42;SOUL_FRAGMENTS_VENG|Soul Fragments Veng|0.34|0.06|0.46;WHIRLWIND|Whirlwind|0.20|0.80|0.20;TIP_OF_THE_SPEAR|Tip of the Spear|0.60|0.80|0.20;ICICLES|Icicles|0.50|0.80|1.00;EBON_MIGHT|Ebon Might|0.40|0.80|0.60]]) do
    CLASS_POWER_STATIC_DEFAULTS[row.key] = { row.dr, row.dg, row.db }
end
local CLASS_POWER_POWER_DEFAULTS = KeyLabelMap [[MAELSTROM=MAELSTROM|MAELSTROM_POWER=MAELSTROM|ASTRAL_POWER=LUNAR_POWER|AP_PREDICTION=LUNAR_POWER|INSANITY=INSANITY]]
local function ClassPowerDefaultRGB(token)
    local slot = COLOR_CP_SLOT_DEFAULTS[token]
    if slot then return slot[1], slot[2], slot[3] end
    local static = CLASS_POWER_STATIC_DEFAULTS[token]
    if static then return static[1], static[2], static[3] end
    if token == "RESOURCE_TEXT" then return ApiRGB("GetGlobalFontColor", 1, 1, 1) end
    local powerToken = CLASS_POWER_POWER_DEFAULTS[token]
    if powerToken then return PowerDefaultRGB(powerToken) end
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
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    local sh = db.auras3.shared
    return tonumber(sh.pandemicR) or 0.0, tonumber(sh.pandemicG) or 0.4, tonumber(sh.pandemicB) or 1.0
end
local function SetPandemicRGB(r, g, b)
    local db = DB()
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    db.auras3.shared.pandemicR, db.auras3.shared.pandemicG, db.auras3.shared.pandemicB = r, g, b
    ApplyAuraColors()
end
local function ReadAuraNumber(key, defaultValue, minValue, maxValue)
    local value = tonumber(G()[key]) or defaultValue
    if minValue then value = max(minValue, value) end
    if maxValue then value = min(maxValue, value) end
    return value
end
local function WriteAuraNumber(key, value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue then value = max(minValue, value) end
    if maxValue then value = min(maxValue, value) end
    if floor(value) == value then value = floor(value + 0.5) end
    G()[key] = value
    ApplyAuraColors()
end
local function ResetAuraColorSettings()
    local g = G()
    g.aurasOwnBuffHighlightColor = { 1.00, 0.85, 0.20 }
    g.aurasOwnDebuffHighlightColor = { 1.00, 0.30, 0.30 }
    g.aurasStackCountColor = { 1.00, 1.00, 1.00 }
    g.aurasCooldownTextUseBuckets = false
    g.aurasCooldownTextSafeColor = nil
    g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
    g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
    g.aurasCooldownTextSafeSeconds = 60
    g.aurasCooldownTextWarningSeconds = 15
    g.aurasCooldownTextUrgentSeconds = 5
    local db = DB()
    db.auras3 = db.auras3 or {}
    db.auras3.shared = db.auras3.shared or {}
    db.auras3.shared.pandemicR, db.auras3.shared.pandemicG, db.auras3.shared.pandemicB = 0.0, 0.4, 1.0
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
local function BuildPowerAndClassPowerColors(ctx, b, CH)
    local power = b:CollapsibleSection("colors_power", "Power Bar Colors", 150, false)
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    local powerColor
    ValueDropdownAt(ctx, power, "Power type", 12, -10, COLOR_DATA.POWER_TOKENS, 260,
        function() return M.colorsPowerToken or "MANA" end,
        function(v)
            M.SetMenuStateValue("colorsPowerToken", v or "MANA")
            if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken)) end
        end)
    powerColor = ColorValueAt(ctx, power, "Color", 360, -10,
        function() return GetPowerOverrideRGB(M.colorsPowerToken or "MANA") end,
        function(r, g, c) SetPowerOverrideRGB(M.colorsPowerToken or "MANA", r, g, c) end)
    CH.ButtonAt(power, "Reset", 360, -54, 90, function()
        ResetPowerOverride(M.colorsPowerToken or "MANA")
        if powerColor then powerColor:SetRGB(GetPowerOverrideRGB(M.colorsPowerToken or "MANA")) end
    end)
    local classPower = b:CollapsibleSection("colors_class_power", "Class Power Colors", 430, false)
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    local cpColor, cpBg
    ValueDropdownAt(ctx, classPower, "Resource type", 12, -10, COLOR_DATA.CP_TOKENS, 310,
        function() return M.colorsCPToken or "COMBO_POINTS" end,
        function(v)
            M.SetMenuStateValue("colorsCPToken", v or "COMBO_POINTS")
            if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken)) end
            if cpBg then cpBg:SetRGB(GetClassPowerBgRGB(M.colorsCPToken)) end
        end)
    cpColor = ColorValueAt(ctx, classPower, "Color", 360, -10,
        function() return GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end)
    cpBg = ColorValueAt(ctx, classPower, "Background", 360, -46,
        function() return GetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS") end,
        function(r, g, c) SetClassPowerBgRGB(M.colorsCPToken or "COMBO_POINTS", r, g, c) end)
    CH.ButtonAt(classPower, "Reset color", 360, -86, 110, function()
        ResetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS", false)
        if cpColor then cpColor:SetRGB(GetClassPowerRGB(M.colorsCPToken or "COMBO_POINTS")) end
    end)
    CH.ButtonAt(classPower, "Reset bg", 480, -86, 110, function()
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
    CH.ButtonAt(classPower, "Reset slots", 12, -246, 120, function()
        local g = EnsureClassPowerOverrides()
        for i = 1, #COLOR_DATA.CP_SLOT_TOKENS do g.classPowerColorOverrides[COLOR_DATA.CP_SLOT_TOKENS[i]] = nil end
        ApplyClassPowerColors()
    end)
end
local function BuildAuraAndPortraitColors(ctx, b, CH)
    local auras = b:CollapsibleSection("colors_auras", "Auras", 526, false)
    local w = auras._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(auras, "Cooldown Timer Colors", nil, 24, -42, colW, 380)
    local markers = Card(auras, "Stack & Highlights", nil, rightX, -42, colW, 380)

    local preview = T.Panel(cooldown, nil, T.colors.glassPopup or { 0.006, 0.016, 0.032, 0.82 }, T.colors.borderSoft)
    preview:SetPoint("TOPLEFT", cooldown, "TOPLEFT", 16, -60)
    preview:SetSize(colW - 32, 88)
    W.LabelAt(preview, "Preview", 12, -12, 120, "GameFontNormalSmall", T.colors.muted)
    local samples = {}
    local sampleAreaW = max(180, (colW - 32) - 88)
    local sampleBoxW = min(64, max(52, floor((sampleAreaW - 16) / 3)))
    local sampleGap = max(8, floor((sampleAreaW - sampleBoxW * 3) / 2))
    for i = 1, 3 do
        local box = T.Panel(preview, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.92 }, T.colors.borderSoft)
        box:SetPoint("LEFT", preview, "LEFT", 88 + (i - 1) * (sampleBoxW + sampleGap), -6)
        box:SetSize(sampleBoxW, 54)
        local fs = T.Font(box, nil, i == 1 and "60" or (i == 2 and "15" or "5"), T.colors.text)
        fs:SetFont(FONT, 18, "OUTLINE")
        fs:SetPoint("CENTER", box, "CENTER", 0, 6)
        local label = T.Font(box, "GameFontDisableSmall", i == 1 and "Safe" or (i == 2 and "Warn" or "Urgent"), T.colors.muted)
        label:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
        samples[i] = fs
    end
    local function RefreshColorSamples()
        local sr, sg, sb = TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1)
        local wr, wg, wb = TableRGB(G(), "aurasCooldownTextWarningColor", 1, 0.85, 0.20)
        local ur, ug, ub = TableRGB(G(), "aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
        local buckets = G().aurasCooldownTextUseBuckets == true
        samples[1]:SetTextColor(sr, sg, sb, 1)
        samples[2]:SetTextColor(buckets and wr or sr, buckets and wg or sg, buckets and wb or sb, 1)
        samples[3]:SetTextColor(buckets and ur or sr, buckets and ug or sg, buckets and ub or sb, 1)
    end
    ValueSwitchAt(ctx, cooldown, "Color by time", 16, -166, colW - 32,
        function() return G().aurasCooldownTextUseBuckets == true end,
        function(v)
            G().aurasCooldownTextUseBuckets = v and true or false
            RefreshColorSamples()
            ApplyAuraColors()
        end)
    local function AuraColorAt(parent, label, y, key, r, g, bcol, after)
        return ColorValueAt(ctx, parent, label, 16, y,
            function() return TableRGB(G(), key, r, g, bcol) end,
            function(nr, ng, nb)
                SetTableRGB(G(), key, nr, ng, nb)
                if type(after) == "function" then after() else ApplyAuraColors() end
            end)
    end
    local function RefreshTextColors()
        RefreshColorSamples()
        ApplyAuraColors()
    end
    AuraColorAt(cooldown, "Safe", -210, "aurasCooldownTextSafeColor", 1, 1, 1, RefreshTextColors)
    AuraColorAt(cooldown, "Warning", -248, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, RefreshTextColors)
    AuraColorAt(cooldown, "Urgent", -286, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, RefreshTextColors)
    AuraColorAt(markers, "Stack Count", -62, "aurasStackCountColor", 1, 1, 1, ApplyAuraColors)
    AuraColorAt(markers, "Own Buff", -102, "aurasOwnBuffHighlightColor", 1, 0.85, 0.20, ApplyAuraColors)
    AuraColorAt(markers, "Own Debuff", -142, "aurasOwnDebuffHighlightColor", 1, 0.30, 0.30, ApplyAuraColors)
    ColorValueAt(ctx, markers, "Pandemic window color", 16, -180, GetPandemicRGB, SetPandemicRGB)
    ValueSliderAt(ctx, markers, "Safe seconds", 16, -232, 0, 600, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) WriteAuraNumber("aurasCooldownTextSafeSeconds", v, 0, 600) end)
    ValueSliderAt(ctx, markers, "Warning <= sec", 16, -292, 0, 60, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) WriteAuraNumber("aurasCooldownTextWarningSeconds", v, 0, 60) end)
    ValueSliderAt(ctx, markers, "Urgent <= sec", 16, -352, 0, 30, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextUrgentSeconds", 5, 0, 30) end,
        function(v) WriteAuraNumber("aurasCooldownTextUrgentSeconds", v, 0, 30) end)
    W.Text(auras, "Timer and marker colors are shared by unit and group aura previews.", 24, -440, w - 48, T.colors.muted)
    CH.ButtonAt(auras, "Reset aura colors", 24, -476, 150, ResetAuraColorSettings)
    M.TrackRefresh(ctx, RefreshColorSamples)

    local portrait = b:CollapsibleSection("colors_portrait", "Portrait Colors", 180, false)
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end)
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end)
    CH.ButtonAt(portrait, "Reset portrait colors", 12, -118, 170, function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        G().portraitBorderColorA = 1
        G().portraitBgColorA = 0.85
        ApplyPortraitColors("PORTRAIT_COLOR_RESET")
    end)
end
local function BuildColors(ctx)
    local CH = COLOR_HELPERS
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Colors", "Frame, bar, aura, castbar and resource colors.", 72)
    local font = b:CollapsibleSection("colors_font", "Global Font Color", 100, false)
    CH.ApiColorAt(ctx, font, "Global font color", 12, -10, "GetGlobalFontColor", "SetGlobalFontColor", 1, 1, 1)
    CH.ButtonAt(font, "Use font palette", 12, -50, 150, function()
        if not ApiCall("ResetGlobalFontToPalette") then
            G().useCustomFontColor = false
            ClearRGB(G(), "fontColorCustom")
        end
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
            function() return ClassColorRGB(token) end,
            function(r, g, c)
                if not ApiCall("SetClassColor", token, r, g, c) then ApplyColors() end
                ApplyUnitframeColorWithReload()
            end, classLabelW, 44)
    end
    CH.ButtonAt(classColors, "Reset all class colors", 12, classResetY, 190, function()
        if not ApiCall("ResetAllClassColors") then DB().classColors = nil end
        ApplyUnitframeColorWithReload()
    end)
    local background = b:CollapsibleSection("colors_background", "Bar Background Tint", 226, false)
    LabelAt(background, "Tint applied to the bar background in *all* bar modes. Dark Mode uses this tint too.", 12, -8, 660, "GameFontHighlightSmall", T.colors.muted)
    ApiOrGeneralColorAt(ctx, background, "Bar background tint", 12, -46, "GetClassBarBgColor", "SetClassBarBgColor", "classBarBg", 0, 0, 0, ApplyUnitframeColorWithReload)
    ValueToggleAt(ctx, background, "Background follows HP color", 12, -86,
        function() return ApiValue("GetBarBgMatchHP", function() return G().barBgMatchHPColor == true end) end,
        function(v)
            if not ApiCall("SetBarBgMatchHP", v) then
                G().barBgMatchHPColor = v and true or false
                if v then G().barBgClassColor = false end
            end
            ApplyUnitframeColorWithReload()
        end)
    ValueToggleAt(ctx, background, "Health background follows class color", 12, -114,
        function() return ApiValue("GetBarBgClassColor", function() return G().barBgClassColor == true end) end,
        function(v)
            if not ApiCall("SetBarBgClassColor", v) then
                G().barBgClassColor = v and true or false
                if v then G().barBgMatchHPColor = false end
            end
            ApplyUnitframeColorWithReload()
        end)
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -142,
        function() return G().darkBgCustomColor == true end,
        function(v) G().darkBgCustomColor = v and true or false; ApplyUnitframeColorWithReload() end)
    CH.ButtonAt(background, "Reset to black", 12, -184, 140, function()
        if not ApiCall("ResetClassBarBgColor") then ClearRGB(G(), "classBarBg") end
        ApplyUnitframeColorWithReload()
    end)
    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 350, true)
    local refreshBarModeControls
    local function CurrentBarMode()
        local g = G()
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then mode = (g.useClassColors and "class") or "dark" end
        return mode
    end
    ValueDropdownAt(ctx, appearance, "Bar mode", 12, -10, ValueTextPairs "dark=Dark Mode (dark black bars)|class=Class Color Mode (color HP bars)|unified=Unified Color Mode (one color for all frames)|gradient=Color Gradient", 320,
        function()
            return CurrentBarMode()
        end,
        function(mode)
            local g = G()
            g.barMode = mode
            g.darkMode = (mode == "dark")
            g.useClassColors = (mode == "class")
            ApplyUnitframeColorWithReload()
            if refreshBarModeControls then refreshBarModeControls() end
        end)
    local unifiedColor = CH.GeneralColorAt(ctx, appearance, "Unified bar color", 12, -70, "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload)
    local darkColor = ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -112, 0, 100, 1, 300,
        function()
            local v = tonumber(G().darkBarGray)
            if not v then return 7 end
            if v <= 1 then return floor(v * 100 + 0.5) end
            return floor(v + 0.5)
        end,
        function(v)
            G().darkBarGray = (tonumber(v) or 0) / 100
            G().darkBarTone = nil
            ApplyUnitframeColorWithReload()
        end)
    local gradientStrength = SliderAt(ctx, appearance, "Gradient strength", 360, -70, 0, 1, 0.05, 250, G, "gradientStrength", 0.45, ApplyUnitframeColorWithReload)
    local healthGradient = SwitchAt(ctx, appearance, "Health Gradient", 360, -118, 230, G, "enableHealthGradient", true, function()
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
    end)
    local gradientStopsLabel = LabelAt(appearance, "Health gradient stops", 12, -166, 220, "GameFontNormalSmall", T.colors.muted)
    local gradientLow = CH.GeneralColorAt(ctx, appearance, "Low", 12, -196, "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientMid = CH.GeneralColorAt(ctx, appearance, "Mid", 170, -196, "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientHigh = CH.GeneralColorAt(ctx, appearance, "High", 328, -196, "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientReset = CH.ButtonAt(appearance, "Reset gradient", 486, -196, 150, function()
        local g = G()
        g.healthGradientLowR, g.healthGradientLowG, g.healthGradientLowB = 1, 0, 0
        g.healthGradientMidR, g.healthGradientMidG, g.healthGradientMidB = 1, 1, 0
        g.healthGradientHighR, g.healthGradientHighG, g.healthGradientHighB = 0, 1, 0
        ApplyUnitframeColorWithReload()
    end)
    local gradientEditControls = { gradientStrength, gradientStopsLabel, gradientLow, gradientMid, gradientHigh, gradientReset }
    refreshBarModeControls = function()
        local mode = CurrentBarMode()
        local gradientMode = mode == "gradient"
        local gradientEnabled = gradientMode and G().enableHealthGradient ~= false
        SetControlEnabled(unifiedColor, mode == "unified")
        SetControlEnabled(darkColor, mode == "dark")
        SetControlEnabled(healthGradient, gradientMode)
        SetControlsEnabled(gradientEditControls, gradientEnabled)
    end
    M.TrackRefresh(ctx, refreshBarModeControls)
    refreshBarModeControls()
    local unit = b:CollapsibleSection("colors_unit", "Unitframe Colors", 230, false)
    for i = 1, #COLOR_DATA.NPC_ROWS do
        local row = COLOR_DATA.NPC_ROWS[i]
        NPCColorAt(ctx, unit, row, 12, -10 - (i - 1) * 36, ApplyUnitframeColorWithReload)
    end
    CH.ApiColorAt(ctx, unit, "Pet Frame Color", 360, -10, "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload)
    CH.ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190, function()
        if not ApiCall("ResetAllNPCColors") then DB().npcColors = nil end
        ApplyUnitframeColorWithReload()
    end)
    local npcType = b:CollapsibleSection("colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls = {}
    local npcMaster
    local function RefreshNPCTypeControls(enabled)
        if enabled == nil then enabled = npcMaster and npcMaster:GetChecked() and true or false end
        SetControlsEnabled(npcControls, enabled)
    end
    local function AddNPCTypeControl(control) M.AppendValues(npcControls, control); return control end
    local function AddNPCTypeToggle(label, x, y, apiGet, apiSet, key, apiArg)
        return AddNPCTypeControl(ValueToggleAt(ctx, npcType, label, x, y,
            function() return ApiValue(apiGet, function() return G()[key] ~= false end, apiArg) end,
            function(v)
                local ok
                if apiArg then ok = ApiCall(apiSet, apiArg, v) else ok = ApiCall(apiSet, v) end
                if not ok then G()[key] = v and true or false end
                ApplyUnitframeColorWithReload()
            end))
    end
    AddNPCTypeToggle("Color HP bar (Class Color mode only)", 32, -38, "GetNPCTypeColorBar", "SetNPCTypeColorBar", "npcTypeColorBar")
    AddNPCTypeToggle("Color name text", 32, -62, "GetNPCTypeColorText", "SetNPCTypeColorText", "npcTypeColorText")
    npcMaster = ValueSwitchAt(ctx, npcType, "NPC Type Colors", 12, -10, 260,
        function()
            return ApiValue("GetNPCColorMode", function() return G().npcColorMode end) == "type"
        end,
        function(v)
            if not ApiCall("SetNPCColorMode", v and "type" or "reaction") then G().npcColorMode = v and "type" or "reaction" end
            ApplyUnitframeColorWithReload()
            RefreshNPCTypeControls(v and true or false)
        end)
    local units = GetNPCTypeUnits()
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    for i = 1, #units do
        local info = units[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        AddNPCTypeToggle(info.label or info.key, 32 + col * 180, -114 - row * 24, "GetNPCTypePerUnit", "SetNPCTypePerUnit", info.key, info.key)
    end
    for i = 1, #COLOR_DATA.NPC_TYPE_ROWS do
        local row = COLOR_DATA.NPC_TYPE_ROWS[i]
        local col = (i - 1) % 2
        local line = floor((i - 1) / 2)
        AddNPCTypeControl(NPCColorAt(ctx, npcType, row, 12 + col * 330, -174 - line * 38, ApplyUnitframeColorWithReload))
    end
    CH.ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190, function()
        if not ApiCall("ResetNPCTypeColors") then DB().npcColors = nil end
        ApplyUnitframeColorWithReload()
    end)
    M.TrackRefresh(ctx, RefreshNPCTypeControls)
    local barColors = b:CollapsibleSection("colors_bar_colors", "Bar Colors", 240, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    local barColorControls = CH.ApiColorSpecs(ctx, barColors, {
        { "Absorb Bar Color", barLeftX, -38, "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1 },
        { "Heal-Absorb Bar Color", barLeftX, -74, "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0 },
        { "Power Bar Background Color", barLeftX, -110, "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0, nil, nil, nil, "powerBg" },
        { "Aggro Border Color", barRightX, -38, "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0 },
    })
    local powerBg = barColorControls.powerBg
    ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end)
    ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return GeneralRGB("barOutlineColor", 0, 0, 0) end,
        function(r, g, c)
            local general = G()
            general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = r, g, c
            general.barOutlineColorA = 1
            general.barOutlineColorMode = nil
            ApplyGlobalOutlineColor()
        end)
    local powerBgMatch = ValueToggleAt(ctx, barColors, "Power background matches HP", barRightX, -148,
        function() return ApiValue("GetPowerBarBackgroundMatchHP", function() return G().powerBarBgMatchBarColor == true end) end,
        function(v)
            if not ApiCall("SetPowerBarBackgroundMatchHP", v) then G().powerBarBgMatchBarColor = v and true or false end
            ApplyColors()
            SetControlEnabled(powerBg, not (v and true or false))
        end)
    CH.ButtonAt(barColors, "Reset Bar Colors", barLeftX, -194, 160, function()
        local g = G()
        ClearRGBAs(g, "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor")
        g.barOutlineColorMode = nil
        ClearRGBs(g, "hlAggroColor", "hlPurgeColor", "aggroBorderColor")
        g.powerBarBgMatchBarColor = nil
        ApplyGlobalOutlineColor()
    end)
    M.BindGateGroup(ctx, nil, {
        { controls = powerBg, on = function() return not (powerBgMatch:GetChecked() and true or false) end },
    })
    local castbar = b:CollapsibleSection("colors_castbar", "Castbar Colors", 544, false)
    local castW = castbar._msuf2Width or ctx.width or 720
    CH.ApiColorSpecs(ctx, castbar, {
        { "Interruptible cast color", 12, -10, "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8 },
        { "Non-interruptible cast color", 12, -46, "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01 },
        { "Interrupt color (all castbars)", 12, -82, "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1.0, 0.82, 0.0 },
        { "Castbar text color", 360, -10, "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1 },
    }, ApplyCastbarColors)
    CH.ApiOrGeneralColorSpecs(ctx, castbar, {
        { "Castbar border color", 360, -46, "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, nil, 1 },
        { "Castbar background color", 360, -82, "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, nil, 0.85 },
    }, ApplyCastbarColors)
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
    local overrideEnable
    local overrideMode = ValueDropdownAt(ctx, castbar, "Mode", overrideModeX, -154, ValueTextPairs "CLASS=Class color|CUSTOM=Custom color", overrideModeW,
        function() return ApiValue("GetPlayerCastbarOverrideMode", function() return G().playerCastbarOverrideMode or "CLASS" end) end,
        function(v)
            if not ApiCall("SetPlayerCastbarOverrideMode", v) then G().playerCastbarOverrideMode = v end
            ApplyCastbarColors()
            SetControlEnabled(overrideColor, (overrideEnable and overrideEnable:GetChecked() and true or false) and v == "CUSTOM")
        end)
    local function RefreshCastbarOverrideControls(enabled)
        if enabled == nil then enabled = overrideEnable and overrideEnable:GetChecked() and true or false end
        SetControlEnabled(overrideMode, enabled)
        SetControlEnabled(overrideColor, enabled and ((overrideMode.GetValue and overrideMode:GetValue()) == "CUSTOM"))
    end
    overrideEnable = ValueSwitchAt(ctx, castbar, "Player override", 12, -154, 260,
        function() return ApiValue("GetPlayerCastbarOverrideEnabled", function() return G().playerCastbarOverrideEnabled == true end) end,
        function(v)
            if not ApiCall("SetPlayerCastbarOverrideEnabled", v) then G().playerCastbarOverrideEnabled = v and true or false end
            ApplyCastbarColors()
            RefreshCastbarOverrideControls(v and true or false)
        end)
    LabelAt(castbar, "Interrupt Ready Indicator", 12, -244, 260, "GameFontNormal", T.colors.text)
    CH.TableColorSpecs(ctx, castbar, G, {
        { "Ready color (kick available)", 12, -274, "kickReadyColor", 0, 1, 0 },
        { "Not ready color (kick on cooldown)", 12, -310, "kickNotReadyColor", 1, 0, 0 },
    }, ApplyCastbarColors)
    CH.ApiColorAt(ctx, castbar, "Unavailable fill color", 12, -346, "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", 1.0, 0.494117647, 0.137254902, ApplyCastbarColors)
    CH.ButtonAt(castbar, "Reset castbar colors", 12, -470, 170, function()
        ApiCall("ResetCastbarTextColorToGlobal")
        ApiCall("ResetCastbarBorderColor")
        ApiCall("ResetCastbarBackgroundColor")
        local g = G()
        ClearRGBs(g, "castbarInterruptible", "castbarNonInterruptible", "castbarInterruptFeedback", "castbarInterruptUnavailable")
        g.castbarInterruptUnavailableColor = nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        ClearRGB(g, "playerCastbarOverride")
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        ApplyCastbarColors()
    end)
    M.TrackRefresh(ctx, RefreshCastbarOverrideControls)
    local highlight = b:CollapsibleSection("colors_highlight", "Mouseover Highlight", 210, false)
    local highlightColor = ColorValueAt(ctx, highlight, "Mouseover highlight color", 12, -48, HighlightRGB, SetHighlightRGB)
    local highlightEnabled = SwitchAt(ctx, highlight, "Mouseover Highlight", 12, -10, 260, G, "highlightEnabled", true, function()
        SetHighlightRGB(HighlightRGB())
        SetControlEnabled(highlightColor, G().highlightEnabled ~= false)
    end)
    CH.TableColorAt(ctx, highlight, "Boss target highlight color", 12, -104, G, "bossTargetHighlightColor", 1, 0.82, 0, function()
        ApplyColors()
        if MSUF and MSUF.UF and MSUF.UF.ForceUpdate then MSUF.UF.ForceUpdate(nil) end
    end)
    M.BindGateGroup(ctx, nil, {
        { controls = highlightColor, on = function() return G().highlightEnabled ~= false end },
    })
    local gameplay = b:CollapsibleSection("colors_gameplay", "Gameplay", 310, false)
    CH.TableColorSpecs(ctx, gameplay, Gameplay, {
        { "Combat timer text color", 12, -10, "combatTimerColor", 1, 1, 1 },
    }, ApplyGameplayColors)
    ColorValueAt(ctx, gameplay, "Combat Enter text color", 12, -46,
        function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
        function(r, g, c)
            local gp = Gameplay()
            SetTableRGB(gp, "combatStateEnterColor", r, g, c)
            if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
            ApplyGameplayColors()
        end)
    local gameplayColors = CH.TableColorSpecs(ctx, gameplay, Gameplay, {
        { "Combat Leave text color", 12, -82, "combatStateLeaveColor", 0.7, 0.7, 0.7 },
        { "Crosshair in-range color", 12, -142, "crosshairInRangeColor", 0, 1, 0 },
        { "Crosshair out-of-range color", 12, -178, "crosshairOutRangeColor", 1, 0, 0 },
    }, ApplyGameplayColors)
    local leaveColor = gameplayColors.combatStateLeaveColor
    local sync = BindTableToggle(ctx, gameplay, "Sync", Gameplay, "combatStateColorSync", false, function()
        local gp = Gameplay()
        if gp.combatStateColorSync then
            local r, g, c = TableRGB(gp, "combatStateEnterColor", 1, 1, 1)
            SetTableRGB(gp, "combatStateLeaveColor", r, g, c)
        end
        ApplyGameplayColors()
        SetControlEnabled(leaveColor, not (gp.combatStateColorSync == true))
    end)
    MoveWidget(sync, gameplay, 360, -82)
    CH.ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors()
    end)
    M.BindGateGroup(ctx, nil, {
        { controls = leaveColor, on = function() return not (Gameplay().combatStateColorSync == true) end },
    })
    BuildPowerAndClassPowerColors(ctx, b, CH)
    BuildAuraAndPortraitColors(ctx, b, CH)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 6 })
