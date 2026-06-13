local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

-- Advanced Colors page.
-- Binds global color palettes, class/power overrides, aura colors, and border colors. Color
-- apply is coalesced because one edit may need to refresh several frame families.
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local CallGlobal, DB, G, Bars, Gameplay, BindTableToggle, ApplyAuras, MoveWidget, LabelAt, SwitchAt, ValueToggleAt, ValueSwitchAt, SliderAt, ValueSliderAt, ValueDropdownAt, SetControlEnabled = M.Pick(AP, [[CallGlobal DB G Bars Gameplay BindTableToggle ApplyAuras MoveWidget LabelAt SwitchAt ValueToggleAt ValueSwitchAt SliderAt ValueSliderAt ValueDropdownAt SetControlEnabled]])
local KLR = M.KeyLabelRows
local WL = M.WordList

local function ColorRows(...)
    local out = {}
    local n = select("#", ...)
    if n == 1 and type((...)) == "string" then
        for line in tostring((...) or ""):gmatch("[^;\r\n]+") do
            local key, label, r, g, b = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
            if key then out[#out + 1] = { key = key, label = label, dr = tonumber(r), dg = tonumber(g), db = tonumber(b) } end
        end
        return out
    end
    for i = 1, n, 5 do
        out[#out + 1] = {
            key = select(i, ...),
            label = select(i + 1, ...),
            dr = select(i + 2, ...),
            dg = select(i + 3, ...),
            db = select(i + 4, ...),
        }
    end
    return out
end

local function KeyLabelMap(rows)
    local out = {}
    for item in tostring(rows or ""):gmatch("[^|\r\n]+") do
        local key, label = item:match("^(.-)=(.*)$")
        if key then out[key] = label ~= "" and label or key end
    end
    return out
end

local function ValueTextPairs(rows)
    local out = {}
    for item in tostring(rows or ""):gmatch("[^|\r\n]+") do
        local value, text = item:match("^(.-)=(.*)$")
        if value then out[#out + 1] = { value = value, text = text ~= "" and text or value } end
    end
    return out
end

local colorApplyQueued = false
-- Multiple color sliders can fire in one frame while dragging. Queue a single apply so live
-- frames repaint once per frame instead of per slider event.
local ColorValueAt
local function FlushColorApply()
    colorApplyQueued = false
    local api = MSUF and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then
        pcall(api.PushVisualUpdates)
    end
    M.RequestGeneralApply("MSUF2_COLORS", { preview = true, applyAll = false })
    CallGlobal("MSUF_RefreshAllFrames")
    CallGlobal("MSUF_RefreshAllIdentityColors")
    CallGlobal("MSUF_RefreshAllPowerTextColors")
    CallGlobal("MSUF_UpdateAllBarTextures_Immediate")
    if M.ApplyGameplay then M.ApplyGameplay() end
    local gf = MSUF and MSUF.GF
    if gf and type(gf.RefreshVisuals) == "function" then pcall(gf.RefreshVisuals) end
end

local function ApplyColors()
    if colorApplyQueued then return end
    colorApplyQueued = true
    if type(_G.MSUF_ScheduleOnce) == "function" then
        _G.MSUF_ScheduleOnce("MSUF2_COLORS_APPLY", FlushColorApply)
    elseif _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, FlushColorApply)
    else
        FlushColorApply()
    end
end

local function ApplyCastbarColors()
    ApplyColors()
    if MSUF and type(MSUF.MSUF_UpdateCastbarVisuals) == "function" then pcall(MSUF.MSUF_UpdateCastbarVisuals) end
    if MSUF and type(MSUF.MSUF_UpdateCastbarTextures_Immediate) == "function" then pcall(MSUF.MSUF_UpdateCastbarTextures_Immediate) end
end

local function ApplyGameplayColors()
    ApplyColors()
    if M.ApplyGameplay then M.ApplyGameplay() end
end

local function ApplyAuraColors()
    ApplyAuras()
    ApplyColors()
    CallGlobal("MSUF_GF_InvalidateCooldownTextCurve")
    CallGlobal("MSUF_GF_ForceCooldownTextRecolor")
    CallGlobal("MSUF_Auras3_RefreshAll")
    CallGlobal("MSUF_GF_ForceAuraTextColorRefresh")
end

local function ApplyClassPowerColors()
    ApplyColors()
    CallGlobal("MSUF_ClassPower_InvalidateColors")
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
end

local function ApplyPortraitColors(reason)
    ApplyColors()
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, true, true, reason or "PORTRAIT_COLORS")
    CallGlobal("MSUF_UFPreview_RequestRefresh", reason or "PORTRAIT_COLORS")
end

local COLOR_CLASS_TOKENS = WL [[WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER]]

local COLOR_CLASS_LABELS = KeyLabelMap [[WARRIOR=Warrior|PALADIN=Paladin|HUNTER=Hunter|ROGUE=Rogue|PRIEST=Priest|DEATHKNIGHT=Death Knight|SHAMAN=Shaman|MAGE=Mage|WARLOCK=Warlock|MONK=Monk|DRUID=Druid|DEMONHUNTER=Demon Hunter|EVOKER=Evoker]]

local COLOR_NPC_ROWS = ColorRows [[
friendly|Friendly NPC Color|0|1|0
neutral|Neutral NPC Color|1|1|0
enemy|Enemy NPC Color|0.85|0.10|0.10
dead|Dead NPC Color|0.40|0.40|0.40
]]

local COLOR_NPC_TYPE_ROWS = ColorRows [[
npcBoss|Boss|0.74|0.11|0
npcMiniboss|Miniboss / Lieutenant|0.56|0|0.74
npcCaster|Caster|0|0.45|0.74
npcMelee|Melee|0.99|0.99|0.99
npcRegular|Regular|0.70|0.56|0.33
]]

local COLOR_DISPEL_TYPES = ColorRows [[
Magic|Magic|0.20|0.60|1.00
Curse|Curse|0.60|0.00|1.00
Disease|Disease|0.60|0.40|0.00
Poison|Poison|0.00|0.60|0.00
Bleed|Bleed|0.80|0.10|0.10
]]

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
    DISPEL_TYPES = COLOR_DISPEL_TYPES,
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
        local ok = pcall(fn, ...)
        if ok then return true end
    end
    return false
end

local function ApiValue(name, fallback, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local ok, value = pcall(fn, ...)
        if ok and value ~= nil then return value end
    end
    if type(fallback) == "function" then return fallback() end
    return fallback
end

local function ApiRGB(name, dr, dg, db, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn, ...)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
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
    if _G.MSUF_RefreshMouseoverHighlight then
        _G.MSUF_RefreshMouseoverHighlight()
    end
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

local function TableColorAt(ctx, section, label, x, y, getTable, key, dr, dg, db, apply, labelWidth, swatchWidth)
    return ColorValueAt(ctx, section, label, x, y,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, c)
            SetTableRGB(getTable(), key, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth)
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

local COLOR_HELPERS = {
    ApiColorAt = ApiColorAt,
    ButtonAt = ButtonAt,
    GeneralColorAt = GeneralColorAt,
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
    local auras = b:CollapsibleSection("colors_auras", "Auras", 310, false)
    CH.TableColorAt(ctx, auras, "Own buff highlight color", 12, -10, G, "aurasOwnBuffHighlightColor", 1.0, 0.85, 0.2, ApplyAuraColors)
    CH.TableColorAt(ctx, auras, "Own debuff highlight color", 12, -46, G, "aurasOwnDebuffHighlightColor", 1.0, 0.85, 0.2, ApplyAuraColors)
    CH.TableColorAt(ctx, auras, "Stack count text color", 12, -82, G, "aurasStackCountColor", 1, 1, 1, ApplyAuraColors)
    ColorValueAt(ctx, auras, "Pandemic window color", 12, -118, GetPandemicRGB, SetPandemicRGB)
    local bucketToggle = BindTableToggle(ctx, auras, "Color aura timers by remaining time", G, "aurasCooldownTextUseBuckets", false, ApplyAuraColors)
    MoveWidget(bucketToggle, auras, 12, -154)
    ColorValueAt(ctx, auras, "Cooldown text: Safe", 360, -10,
        function()
            local t = G().aurasCooldownTextSafeColor
            if type(t) == "table" then return TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1) end
            return ApiRGB("GetGlobalFontColor", 1, 1, 1)
        end,
        function(r, g, c) SetTableRGB(G(), "aurasCooldownTextSafeColor", r, g, c); ApplyAuraColors() end)
    CH.TableColorAt(ctx, auras, "Cooldown text: Warning", 360, -46, G, "aurasCooldownTextWarningColor", 1, 0.85, 0.2, ApplyAuraColors)
    CH.TableColorAt(ctx, auras, "Cooldown text: Urgent", 360, -82, G, "aurasCooldownTextUrgentColor", 1, 0.55, 0.1, ApplyAuraColors)
    CH.ButtonAt(auras, "Reset aura colors", 12, -264, 150, function()
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
            G().fontColorCustomR, G().fontColorCustomG, G().fontColorCustomB = nil, nil, nil
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
            end, classLabelW, 44)
    end
    CH.ButtonAt(classColors, "Reset all class colors", 12, classResetY, 190, function()
        if not ApiCall("ResetAllClassColors") then DB().classColors = nil end
        ApplyColors()
    end)

    local background = b:CollapsibleSection("colors_background", "Bar Background Tint", 226, false)
    LabelAt(background, "Tint applied to the bar background in *all* bar modes. Dark Mode uses this tint too.", 12, -8, 660, "GameFontHighlightSmall", T.colors.muted)
    ColorValueAt(ctx, background, "Bar background tint", 12, -46,
        function() return ApiRGB("GetClassBarBgColor", 0, 0, 0) end,
        function(r, g, c)
            if not ApiCall("SetClassBarBgColor", r, g, c) then SetGeneralRGB("classBarBg", r, g, c) end
        end)
    ValueToggleAt(ctx, background, "Background follows HP color", 12, -86,
        function() return ApiValue("GetBarBgMatchHP", function() return G().barBgMatchHPColor == true end) end,
        function(v)
            if not ApiCall("SetBarBgMatchHP", v) then
                G().barBgMatchHPColor = v and true or false
                if v then G().barBgClassColor = false end
            end
            ApplyColors()
        end)
    ValueToggleAt(ctx, background, "Health background follows class color", 12, -114,
        function() return ApiValue("GetBarBgClassColor", function() return G().barBgClassColor == true end) end,
        function(v)
            if not ApiCall("SetBarBgClassColor", v) then
                G().barBgClassColor = v and true or false
                if v then G().barBgMatchHPColor = false end
            end
            ApplyColors()
        end)
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -142,
        function() return G().darkBgCustomColor == true end,
        function(v) G().darkBgCustomColor = v and true or false; ApplyColors() end)
    CH.ButtonAt(background, "Reset to black", 12, -184, 140, function()
        if not ApiCall("ResetClassBarBgColor") then
            G().classBarBgR, G().classBarBgG, G().classBarBgB = nil, nil, nil
        end
        ApplyColors()
    end)

    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 290, true)
    ValueDropdownAt(ctx, appearance, "Bar mode", 12, -10, ValueTextPairs "dark=Dark Mode (dark black bars)|class=Class Color Mode (color HP bars)|unified=Unified Color Mode (one color for all frames)|gradient=Color Gradient", 320,
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
    CH.GeneralColorAt(ctx, appearance, "Unified bar color", 12, -70, "unifiedBar", 0.10, 0.60, 0.90)
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
            function() return ApiRGB("GetNPCColor", row.dr, row.dg, row.db, row.key) end,
            function(r, g, c)
                if not ApiCall("SetNPCColor", row.key, r, g, c) then ApplyColors() end
            end)
    end
    CH.ApiColorAt(ctx, unit, "Pet Frame Color", 360, -10, "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0)
    CH.ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190, function()
        if not ApiCall("ResetAllNPCColors") then DB().npcColors = nil end
        ApplyColors()
    end)

    local npcType = b:CollapsibleSection("colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls = {}
    local npcMaster
    local function RefreshNPCTypeControls(enabled)
        if enabled == nil then enabled = npcMaster and npcMaster:GetChecked() and true or false end
        for i = 1, #npcControls do SetControlEnabled(npcControls[i], enabled) end
    end
    npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, "Color HP bar (Class Color mode only)", 32, -38,
        function() return ApiValue("GetNPCTypeColorBar", function() return G().npcTypeColorBar ~= false end) end,
        function(v)
            if not ApiCall("SetNPCTypeColorBar", v) then G().npcTypeColorBar = v and true or false end
            ApplyColors()
        end)
    npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, "Color name text", 32, -62,
        function() return ApiValue("GetNPCTypeColorText", function() return G().npcTypeColorText ~= false end) end,
        function(v)
            if not ApiCall("SetNPCTypeColorText", v) then G().npcTypeColorText = v and true or false end
            ApplyColors()
        end)
    npcMaster = ValueSwitchAt(ctx, npcType, "NPC Type Colors", 12, -10, 260,
        function()
            return ApiValue("GetNPCColorMode", function() return G().npcColorMode end) == "type"
        end,
        function(v)
            if not ApiCall("SetNPCColorMode", v and "type" or "reaction") then G().npcColorMode = v and "type" or "reaction" end
            ApplyColors()
            RefreshNPCTypeControls(v and true or false)
        end)
    local units = GetNPCTypeUnits()
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    for i = 1, #units do
        local info = units[i]
        local col = (i - 1) % 2
        local row = floor((i - 1) / 2)
        npcControls[#npcControls + 1] = ValueToggleAt(ctx, npcType, info.label or info.key, 32 + col * 180, -114 - row * 24,
            function() return ApiValue("GetNPCTypePerUnit", function() return G()[info.key] ~= false end, info.key) end,
            function(v)
                if not ApiCall("SetNPCTypePerUnit", info.key, v) then G()[info.key] = v and true or false end
                ApplyColors()
            end)
    end
    for i = 1, #COLOR_DATA.NPC_TYPE_ROWS do
        local row = COLOR_DATA.NPC_TYPE_ROWS[i]
        local col = (i - 1) % 2
        local line = floor((i - 1) / 2)
        local sw = ColorValueAt(ctx, npcType, row.label, 12 + col * 330, -174 - line * 38,
            function() return ApiRGB("GetNPCColor", row.dr, row.dg, row.db, row.key) end,
            function(r, g, c)
                if not ApiCall("SetNPCColor", row.key, r, g, c) then ApplyColors() end
            end)
        npcControls[#npcControls + 1] = sw
    end
    CH.ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190, function()
        if not ApiCall("ResetNPCTypeColors") then DB().npcColors = nil end
        ApplyColors()
    end)
    M.AddRefresher(ctx, RefreshNPCTypeControls)

    local barColors = b:CollapsibleSection("colors_bar_colors", "Bar Colors", 240, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    CH.ApiColorAt(ctx, barColors, "Absorb Bar Color", barLeftX, -38, "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1)
    CH.ApiColorAt(ctx, barColors, "Heal-Absorb Bar Color", barLeftX, -74, "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0)
    local powerBg = CH.ApiColorAt(ctx, barColors, "Power Bar Background Color", barLeftX, -110, "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0)
    CH.ApiColorAt(ctx, barColors, "Aggro Border Color", barRightX, -38, "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0)
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
        for _, prefix in ipairs({ "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor" }) do
            g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"], g[prefix .. "A"] = nil, nil, nil, nil
        end
        g.barOutlineColorMode = nil
        g.hlAggroColorR, g.hlAggroColorG, g.hlAggroColorB = nil, nil, nil
        g.hlPurgeColorR, g.hlPurgeColorG, g.hlPurgeColorB = nil, nil, nil
        g.aggroBorderColorR, g.aggroBorderColorG, g.aggroBorderColorB = nil, nil, nil
        g.powerBarBgMatchBarColor = nil
        ApplyGlobalOutlineColor()
    end)
    M.AddRefresher(ctx, function()
        SetControlEnabled(powerBg, not (powerBgMatch:GetChecked() and true or false))
    end)

    local dispel = b:CollapsibleSection("colors_dispel", "Dispel", 310, false)
    LabelAt(dispel, "Dispel color shared by Highlight Border and Unit/Group Frame Dispel Overlay.", 12, -8, 620, "GameFontHighlightSmall", T.colors.muted)
    ValueDropdownAt(ctx, dispel, "Color mode", 12, -42, ValueTextPairs "SINGLE=Single color|TYPE=Per debuff type", 220,
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
    CH.ButtonAt(dispel, "Reset Dispel Colors", 12, -274, 180, function()
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
    CH.ApiColorAt(ctx, castbar, "Interruptible cast color", 12, -10, "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8, ApplyCastbarColors)
    CH.ApiColorAt(ctx, castbar, "Non-interruptible cast color", 12, -46, "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01, ApplyCastbarColors)
    CH.ApiColorAt(ctx, castbar, "Interrupt color (all castbars)", 12, -82, "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1.0, 0.82, 0.0, ApplyCastbarColors)
    CH.ApiColorAt(ctx, castbar, "Castbar text color", 360, -10, "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1, ApplyCastbarColors)
    ColorValueAt(ctx, castbar, "Castbar border color", 360, -46,
        function() return ApiRGB("GetCastbarBorderColor", 0, 0, 0) end,
        function(r, g, c)
            if not ApiCall("SetCastbarBorderColor", r, g, c, 1) then SetGeneralRGB("castbarBorder", r, g, c) end
            ApplyCastbarColors()
        end)
    ColorValueAt(ctx, castbar, "Castbar background color", 360, -82,
        function() return ApiRGB("GetCastbarBackgroundColor", 0.10, 0.10, 0.10) end,
        function(r, g, c)
            if not ApiCall("SetCastbarBackgroundColor", r, g, c, 0.85) then SetGeneralRGB("castbarBg", r, g, c) end
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
    CH.TableColorAt(ctx, castbar, "Ready color (kick available)", 12, -274, G, "kickReadyColor", 0, 1, 0, ApplyCastbarColors)
    CH.TableColorAt(ctx, castbar, "Not ready color (kick on cooldown)", 12, -310, G, "kickNotReadyColor", 1, 0, 0, ApplyCastbarColors)
    CH.ButtonAt(castbar, "Reset castbar colors", 12, -470, 170, function()
        ApiCall("ResetCastbarTextColorToGlobal")
        ApiCall("ResetCastbarBorderColor")
        ApiCall("ResetCastbarBackgroundColor")
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
    M.AddRefresher(ctx, RefreshCastbarOverrideControls)

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
    M.AddRefresher(ctx, function()
        SetControlEnabled(highlightColor, G().highlightEnabled ~= false)
    end)

    local gameplay = b:CollapsibleSection("colors_gameplay", "Gameplay", 310, false)
    CH.TableColorAt(ctx, gameplay, "Combat timer text color", 12, -10, Gameplay, "combatTimerColor", 1, 1, 1, ApplyGameplayColors)
    ColorValueAt(ctx, gameplay, "Combat Enter text color", 12, -46,
        function() return TableRGB(Gameplay(), "combatStateEnterColor", 1, 1, 1) end,
        function(r, g, c)
            local gp = Gameplay()
            SetTableRGB(gp, "combatStateEnterColor", r, g, c)
            if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
            ApplyGameplayColors()
        end)
    local leaveColor = CH.TableColorAt(ctx, gameplay, "Combat Leave text color", 12, -82, Gameplay, "combatStateLeaveColor", 0.7, 0.7, 0.7, ApplyGameplayColors)
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
    CH.TableColorAt(ctx, gameplay, "Crosshair in-range color", 12, -142, Gameplay, "crosshairInRangeColor", 0, 1, 0, ApplyGameplayColors)
    CH.TableColorAt(ctx, gameplay, "Crosshair out-of-range color", 12, -178, Gameplay, "crosshairOutRangeColor", 1, 0, 0, ApplyGameplayColors)
    CH.ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
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

    BuildPowerAndClassPowerColors(ctx, b, CH)
    BuildAuraAndPortraitColors(ctx, b, CH)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 5 })
