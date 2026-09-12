local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local EnsureDB = M.EnsureDB

-- Advanced Colors page.
-- Binds global color palettes, class/power overrides, aura colors, and border colors. Color
-- apply is coalesced because one edit may need to refresh several frame families.
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}
local GP = M.GlobalPage or {}
local C_Timer = M.MenuTimer or _G.C_Timer
local floor = math.floor
local max = math.max
local min = math.min
local FONT = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DB, G, Gameplay = AP.DB, AP.G, AP.Gameplay
local BindTableToggle, ApplyAuras, MoveWidget, LabelAt, SwitchAt = AP.BindTableToggle, AP.ApplyAuras, AP.MoveWidget, AP.LabelAt, AP.SwitchAt
local ValueToggleAt, ValueSwitchAt, SliderAt, ValueSliderAt, ValueDropdownAt = AP.ValueToggleAt, AP.ValueSwitchAt, AP.SliderAt, AP.ValueSliderAt, AP.ValueDropdownAt
local SetControlEnabled, RegisterControl = AP.SetControlEnabled, AP.RegisterControl
local CurrentBarsScope, NormalizeScopeKey, ScopeHasOverride, GradientScopeGet, GradientScopeSet = GP.CurrentBarsScope, GP.NormalizeScopeKey, GP.ScopeHasOverride, GP.GradientScopeGet, GP.GradientScopeSet
local ReadNameColor = function()
local g = G()
            return tonumber(g.nameColorR) or 1, tonumber(g.nameColorG) or 1, tonumber(g.nameColorB) or 1
end

local CP = M.ColorsPage or {}
M.ColorsPage = CP
-- Assistant metadata (Meta) comes from the MSUF_Menu2_AdvancedColors_Meta.lua
-- sibling that loads right before this page; the Group, Resources and Context
-- siblings that load right after it pick the helpers published at the bottom.
local Meta = CP.Meta
local KLR, WL, ColorRows, KeyLabelMap, ValueTextPairs, SetControlsEnabled = M.KeyLabelRows, M.WordList, M.ColorRows, M.KeyLabelMap, M.ValueTextPairs, W.SetControlsEnabled
local ColorValueAt

local function CurrentApplyService()
    return M.ApplyService or _G.MSUF_Menu2_ApplyService
end

local function RequestGeneral(reason, opts)
    if type(M.RequestGeneralApply) == "function" then
        return M.RequestGeneralApply(reason, opts)
    end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGeneral) == "function" then
        return apply.RequestGeneral(reason, opts)
    end
    return false
end

local function ApplyColors()
    -- The painter's Resources strip paints straight from these DB values and
    -- has no writer of its own, so both apply paths poke it. Kept inline: this
    -- file rides the 200 active-local ceiling.
    local painter = M.ColorPainter
    if painter and type(painter.RefreshResourcesStrip) == "function" then painter.RefreshResourcesStrip() end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestColors) == "function" then
        return apply.RequestColors("MSUF2_COLORS")
    end
    local api = MSUF and MSUF._colorsAPI
    if api and type(api.PushVisualUpdates) == "function" then
        api.PushVisualUpdates()
        return true
    end
    return RequestGeneral("MSUF2_COLORS", { preview = true, applyAll = false, colors = true })
end

function M.RefreshActiveHealthBackgroundInlinePreview()
    if M.activeKey ~= "opt_colors" then return false end
    local entry = M.cache and M.cache.opt_colors
    if not entry or entry._msuf2Invalidated == true then return false end
    if entry.wrapper and entry.wrapper.IsShown and not entry.wrapper:IsShown() then return false end
    local refresh = entry and entry._msuf2HealthBackgroundInlinePreviewRefresh
    if type(refresh) ~= "function" then return false end
    refresh()
    return true
end
local function ApplyUnitframeColorWithReload()
    ApplyColors()
    M.RefreshActiveHealthBackgroundInlinePreview()
end
local function ApplyCastbarColors()
    M.RequestGeneralApply("MSUF2_CASTBAR_COLORS", { castbar = true, castbarTextures = true, preview = true, applyAll = false })
end
local function ApplyBossTargetHighlightColor()
    local reason = "MSUF2_BOSS_TARGET_HIGHLIGHT_COLOR"
    local apply = CurrentApplyService()
    if apply and type(apply.RequestBossTargetBorder) == "function" then
        return apply.RequestBossTargetBorder(reason, "boss")
    end
    _G.MSUF_UFCore_RefreshSettingsCache(reason)
    if apply and type(apply.RequestUnit) == "function" then
        return apply.RequestUnit("boss", reason, { preview = true })
    end
    return true, _G.MSUF_UFCore_NotifyConfigChanged("boss", true, true, reason)
end
local function ApplyGameplayColors()
    ApplyColors()
end
local function ApplyAuraColors()
    ApplyColors()
    local apply = CurrentApplyService()
    if apply and type(apply.RequestAuraFonts) == "function" then
        apply.RequestAuraFonts("shared", "MSUF2_AURA_COLORS")
    else
        ApplyAuras()
    end
    _G.MSUF_GF_ForceAuraTextColorRefresh()
end

function M._DispelTypeColorSpec(dispelType)
    for i = 1, #M.DISPEL_COLOR_SPECS do
        local spec = M.DISPEL_COLOR_SPECS[i]
        if spec.key == dispelType then return spec end
    end
end

function M._SetDispelColorPreviewType(dispelType)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.SetDispelColorPreviewType) == "function" then
        a3.SetDispelColorPreviewType(dispelType)
    end
end

function M._GetDispelTypeRGB(dispelType, useOverride)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.GetDispelTypeColor) == "function" then
        return a3.GetDispelTypeColor(dispelType, useOverride)
    end
    if dispelType == "Curse" then return 0.60, 0.00, 1.00 end
    if dispelType == "Disease" then return 0.60, 0.40, 0.00 end
    if dispelType == "Poison" then return 0.00, 0.60, 0.00 end
    if dispelType == "Bleed" then return 0.80, 0.10, 0.10 end
    return 0.20, 0.60, 1.00
end

function M._HasDispelTypeColorOverride(dispelType)
    local overrides = G().dispelTypeColorOverrides
    return type(overrides) == "table" and type(overrides[dispelType]) == "table"
end

function M._SetDispelTypeRGB(dispelType, r, g, b)
    if not M._DispelTypeColorSpec(dispelType) then return false end
    local general = G()
    general.dispelTypeColorOverrides = type(general.dispelTypeColorOverrides) == "table"
        and general.dispelTypeColorOverrides or {}
    general.dispelTypeColorOverrides[dispelType] = {
        max(0, min(1, tonumber(r) or 0)),
        max(0, min(1, tonumber(g) or 0)),
        max(0, min(1, tonumber(b) or 0)),
    }
    M._SetDispelColorPreviewType(dispelType)
    ApplyAuraColors()
    return true
end

function M._SetDispelTypeColorEnabled(dispelType, enabled)
    if not M._DispelTypeColorSpec(dispelType) then return false end
    local general = G()
    if enabled == true then
        if not M._HasDispelTypeColorOverride(dispelType) then
            local r, g, b = M._GetDispelTypeRGB(dispelType, false)
            general.dispelTypeColorOverrides = type(general.dispelTypeColorOverrides) == "table"
                and general.dispelTypeColorOverrides or {}
            general.dispelTypeColorOverrides[dispelType] = { r, g, b }
        end
    elseif type(general.dispelTypeColorOverrides) == "table" then
        general.dispelTypeColorOverrides[dispelType] = nil
        if next(general.dispelTypeColorOverrides) == nil then general.dispelTypeColorOverrides = nil end
    end
    M._SetDispelColorPreviewType(dispelType)
    ApplyAuraColors()
    return true
end
local function ApplyPortraitColors(reason)
    reason = reason or "PORTRAIT_COLORS"
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGeneral) == "function" then
        return apply.RequestGeneral(reason, { preview = true, applyAll = true, colors = true })
    end
    _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)
    _G.MSUF_UFPreview_RequestRefresh(reason)
end
local COLOR_CLASS_TOKENS = WL [[WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER]]
local COLOR_CLASS_LABELS = KeyLabelMap [[WARRIOR=Warrior|PALADIN=Paladin|HUNTER=Hunter|ROGUE=Rogue|PRIEST=Priest|DEATHKNIGHT=Death Knight|SHAMAN=Shaman|MAGE=Mage|WARLOCK=Warlock|MONK=Monk|DRUID=Druid|DEMONHUNTER=Demon Hunter|EVOKER=Evoker]]
local COLOR_NPC_ROWS = ColorRows "friendly|Friendly NPC Color|0|1|0;neutral|Neutral NPC Color|1|1|0;enemy|Enemy NPC Color|0.85|0.10|0.10;dead|Dead NPC Color|0.40|0.40|0.40"
local COLOR_NPC_TYPE_ROWS = ColorRows "npcBoss|Boss|0.74|0.11|0;npcMiniboss|Miniboss / Lieutenant|0.56|0|0.74;npcCaster|Caster|0|0.45|0.74;npcMelee|Melee|0.99|0.99|0.99;npcRegular|Regular|0.70|0.56|0.33"
local COLOR_POWER_TOKENS = ValueTextPairs [[MANA=Mana|RAGE=Rage|ENERGY=Energy|FOCUS=Focus|RUNIC_POWER=Runic Power|INSANITY=Insanity|FURY=Fury|PAIN=Pain|ESSENCE=Essence|LUNAR_POWER=Astral Power|MAELSTROM=Maelstrom]]
local COLOR_CP_TOKENS = ValueTextPairs [[COMBO_POINTS=Combo Points|HOLY_POWER=Holy Power|SOUL_SHARDS=Soul Shards|CHI=Chi|ARCANE_CHARGES=Arcane Charges|RUNES=Runes|ESSENCE=Essence|MANA=Alternative Mana|CHARGED=Empowered / Charged|SOUL_FRAGMENTS=Soul Fragments|SOUL_FRAGMENTS_META=Soul Fragments (Void Meta)|MAELSTROM=Maelstrom Weapon|MAELSTROM_ABOVE_5=Maelstrom Weapon 5+|ASTRAL_POWER=Astral Power|AP_PREDICTION=Astral Prediction|ECLIPSE_SOLAR=Eclipse Solar|ECLIPSE_LUNAR=Eclipse Lunar|ECLIPSE_CA=Celestial Alignment|STAGGER_GREEN=Stagger Light|STAGGER_YELLOW=Stagger Moderate|STAGGER_RED=Stagger Heavy|SOUL_FRAGMENTS_VENG=Soul Fragments (Vengeance)|INSANITY=Insanity|MAELSTROM_POWER=Maelstrom Power|WHIRLWIND=Whirlwind|TIP_OF_THE_SPEAR=Tip of the Spear|ICICLES=Icicles|EBON_MIGHT=Ebon Might|RESOURCE_TEXT=Resource Text]]
local COLOR_DATA = {
    CLASS_LABELS = COLOR_CLASS_LABELS,
    NPC_ROWS = COLOR_NPC_ROWS,
    NPC_TYPE_ROWS = COLOR_NPC_TYPE_ROWS,
    POWER_TOKENS = COLOR_POWER_TOKENS,
    CP_TOKENS = COLOR_CP_TOKENS,
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
M.ColorsBackgroundMode = M.ColorsBackgroundMode or {}
function M.ColorsBackgroundMode.GetFill()
    local value = ApiValue("GetBarBgFillMode", function() return G().barBgFillMode end)
    value = type(value) == "string" and value:lower() or nil
    return value == "missing" and "missing" or "full"
end
function M.ColorsBackgroundMode.SetFill(value)
    value = type(value) == "string" and value:lower() or nil
    value = value == "missing" and "missing" or "full"
    if not ApiCall("SetBarBgFillMode", value) then
        G().barBgFillMode = value
        ApplyUnitframeColorWithReload()
    end
end
function M.ColorsBackgroundMode.GetColor()
    local general = G()
    local value = ApiValue("GetBarBgColorMode", function() return general.barBgColorMode end)
    value = type(value) == "string" and value:lower() or nil
    if value == "custom" or value == "match_health" or value == "class" or value == "health_gradient" then
        return value
    end
    if general.barBgClassColor == true then return "class" end
    if general.barBgMatchHPColor == true then return "match_health" end
    return "custom"
end
function M.ColorsBackgroundMode.SetColor(value)
    value = type(value) == "string" and value:lower() or nil
    if value ~= "match_health" and value ~= "class" and value ~= "health_gradient" then value = "custom" end
    if not ApiCall("SetBarBgColorMode", value) then
        local general = G()
        general.barBgColorMode = value
        general.barBgMatchHPColor = value == "match_health"
        general.barBgClassColor = value == "class"
        ApplyUnitframeColorWithReload()
    end
end
function M.RefreshHealthBackgroundInlinePreview(preview)
    if type(preview) ~= "table" then return false end
    local bar, backgroundBar, background = preview.bar, preview.backgroundBar, preview.background
    if not (bar and backgroundBar and background) then return false end

    local pct = tonumber(preview.healthFraction) or 0.62
    pct = max(0, min(1, pct))
    local db = EnsureDB()
    local general = type(db.general) == "table" and db.general or {}
    local bars = type(db.bars) == "table" and db.bars or {}
    local player = type(db.player) == "table" and db.player or {}
    local model = MSUF.UFPreview and MSUF.UFPreview.Model or {}
    local classToken
    if type(_G.UnitClass) == "function" then
        local _, token = _G.UnitClass("player")
        classToken = token
    end
    local classTokenSecret = type(_G.issecretvalue) == "function" and _G.issecretvalue(classToken) == true
    if classTokenSecret or type(classToken) ~= "string" or classToken == "" then classToken = nil end
    local data = preview.data or {}
    data.hp, data.isPlayer, data.class = pct, true, classToken
    preview.data = data

    -- Resolve the fixed Player sample from the just-edited DB/API values. The
    -- compiled settings cache intentionally trails picker writes by one
    -- coalesced apply and would make this inline preview appear stuck.
    local classR, classG, classB
    local colorsAPI = ColorAPI()
    if classToken and type(colorsAPI.GetClassColor) == "function" then
        classR, classG, classB = colorsAPI.GetClassColor(classToken)
    end
    if type(classR) ~= "number" or type(classG) ~= "number" or type(classB) ~= "number" then
        local override = classToken and type(db.classColors) == "table" and db.classColors[classToken] or nil
        classR, classG, classB = tonumber(override and (override.r or override[1])),
            tonumber(override and (override.g or override[2])), tonumber(override and (override.b or override[3]))
    end
    if type(classR) ~= "number" or type(classG) ~= "number" or type(classB) ~= "number" then
        local classColor = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
        classR, classG, classB = classColor and classColor.r or 0.12, classColor and classColor.g or 0.62,
            classColor and classColor.b or 0.95
    end

    local colorMode = M.ColorsBackgroundMode.GetColor()
    local healthMode = type(player.healthColorMode) == "string" and player.healthColorMode:lower() or nil
    if healthMode ~= "class" and healthMode ~= "gradient" and healthMode ~= "dark" and healthMode ~= "unified" then
        healthMode = type(general.barMode) == "string" and general.barMode:lower() or nil
        if healthMode ~= "class" and healthMode ~= "gradient" and healthMode ~= "dark" and healthMode ~= "unified" then
            healthMode = general.useClassColors == true and "class" or "dark"
        end
        if healthMode == "gradient" and general.enableHealthGradient == false then healthMode = "class" end
    end

    local gradientR, gradientG, gradientB
    if healthMode == "gradient" or colorMode == "health_gradient" then
        local gradientHealth = preview.gradientHealth or {}
        gradientHealth.gradientLowR = tonumber(general.healthGradientLowR) or 1
        gradientHealth.gradientLowG = tonumber(general.healthGradientLowG) or 0
        gradientHealth.gradientLowB = tonumber(general.healthGradientLowB) or 0
        gradientHealth.gradientMidR = tonumber(general.healthGradientMidR) or 1
        gradientHealth.gradientMidG = tonumber(general.healthGradientMidG) or 1
        gradientHealth.gradientMidB = tonumber(general.healthGradientMidB) or 0
        gradientHealth.gradientHighR = tonumber(general.healthGradientHighR) or 0
        gradientHealth.gradientHighG = tonumber(general.healthGradientHighG) or 1
        gradientHealth.gradientHighB = tonumber(general.healthGradientHighB) or 0
        preview.gradientHealth = gradientHealth
        local common = MSUF.UFBarTextCommon
        if common and type(common.PreviewHealthGradientColor) == "function" then
            gradientR, gradientG, gradientB = common.PreviewHealthGradientColor(gradientHealth, pct)
        elseif type(model.GradientPreviewColor) == "function" then
            gradientR, gradientG, gradientB = model.GradientPreviewColor(pct, gradientHealth)
        end
    end

    local hr, hg, hb
    if healthMode == "class" then
        hr, hg, hb = classR, classG, classB
    elseif healthMode == "gradient" and type(gradientR) == "number"
        and type(gradientG) == "number" and type(gradientB) == "number" then
        hr, hg, hb = gradientR, gradientG, gradientB
    elseif healthMode == "unified" then
        hr, hg, hb = tonumber(general.unifiedBarR) or 0.10, tonumber(general.unifiedBarG) or 0.60,
            tonumber(general.unifiedBarB) or 0.90
    else
        local gray = tonumber(general.darkBarGray or general.darkBgBrightness) or 0.07
        if gray > 1 then gray = gray / 100 end
        gray = max(0, min(1, gray))
        hr, hg, hb = tonumber(general.darkBarR) or gray, tonumber(general.darkBarG) or gray,
            tonumber(general.darkBarB) or gray
    end

    local br, bg, bb, tintAlpha
    local getTint = _G.MSUF_GetBarBackgroundTintRGBA
    if type(getTint) == "function" then
        br, bg, bb, tintAlpha = getTint()
    else
        br, bg, bb, tintAlpha = tonumber(general.classBarBgR) or 0, tonumber(general.classBarBgG) or 0,
            tonumber(general.classBarBgB) or 0, tonumber(general.classBarBgA) or 1
        local darkTint = MSUF.Bars and MSUF.Bars._DarkTint
        if type(darkTint) == "function" then br, bg, bb = darkTint(general, br, bg, bb) end
    end

    if colorMode == "match_health" then
        local darkTint = MSUF.Bars and MSUF.Bars._DarkTint
        if type(darkTint) == "function" then br, bg, bb = darkTint(general, hr, hg, hb)
        else br, bg, bb = hr, hg, hb end
    elseif colorMode == "class" then
        if classToken then br, bg, bb = classR, classG, classB end
    elseif colorMode == "health_gradient" then
        br, bg, bb = gradientR or br, gradientG or bg, gradientB or bb
    end

    local backgroundAlpha = tonumber(player.hpBgAlpha)
    if backgroundAlpha == nil then
        local percent = tonumber(bars.barBackgroundAlpha)
        backgroundAlpha = percent and (percent / 100) or tonumber(general.barBackgroundAlpha) or 0.9
    end
    backgroundAlpha = max(0, min(1, backgroundAlpha)) * max(0, min(1, tonumber(tintAlpha) or 1))
    local foregroundAlpha = max(0, min(1, tonumber(player.hpBarAlpha) or 1))
    local foregroundTexture = type(_G.MSUF_GetBarTexture) == "function" and _G.MSUF_GetBarTexture()
        or "Interface\\Buttons\\WHITE8X8"
    local backgroundTexture = type(_G.MSUF_GetBarBackgroundTexture) == "function" and _G.MSUF_GetBarBackgroundTexture()
        or foregroundTexture

    if bar.SetMinMaxValues then bar:SetMinMaxValues(0, 1) end
    if bar.SetValue then bar:SetValue(pct) end
    if bar.SetStatusBarTexture then bar:SetStatusBarTexture(foregroundTexture) end
    if bar.SetStatusBarColor then bar:SetStatusBarColor(hr, hg, hb, 1) end
    local fillTexture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fillTexture and fillTexture.SetAlpha then fillTexture:SetAlpha(foregroundAlpha) end
    if background.SetTexture then background:SetTexture(backgroundTexture) end
    if background.SetVertexColor then background:SetVertexColor(br, bg, bb, backgroundAlpha) end

    local fillMode = M.ColorsBackgroundMode.GetFill()
    if backgroundBar.SetMinMaxValues then backgroundBar:SetMinMaxValues(0, 1) end
    if backgroundBar.SetReverseFill then backgroundBar:SetReverseFill(fillMode == "missing") end
    local missingValue = fillMode == "missing" and (1 - pct) or 1
    if backgroundBar.SetValue then backgroundBar:SetValue(missingValue) end

    if preview.percent and preview.percent.SetText then preview.percent:SetText(floor((pct * 100) + 0.5) .. "%") end
    if preview.mode and preview.mode.SetText then
        local fillLabel = fillMode == "missing" and "Missing health only" or "Full bar"
        local colorLabel = colorMode == "match_health" and "Match health bar"
            or colorMode == "class" and "Class color"
            or colorMode == "health_gradient" and "Health gradient" or "Custom tint"
        local translate = M.TranslateText or M.Tr
        if type(translate) == "function" then fillLabel, colorLabel = translate(fillLabel), translate(colorLabel) end
        preview.mode:SetText(fillLabel .. "  |  " .. colorLabel)
    end
    preview.resolvedFillMode, preview.resolvedColorMode = fillMode, colorMode
    local resolved = preview.resolvedBackground or {}
    resolved[1], resolved[2], resolved[3], resolved[4] = br, bg, bb, backgroundAlpha
    preview.resolvedBackground = resolved
    return true
end
local function ApiRGB(name, dr, dg, db, ...)
    local fn = ColorAPI()[name]
    if type(fn) == "function" then
        local r, g, b, a = fn(...)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b, a end
    end
    return dr, dg, db
end
function M._ContextConfiguredGlobalFontRGB()
    local getter = _G.MSUF_GetConfiguredFontColor or (MSUF and MSUF.MSUF_GetConfiguredFontColor)
    if type(getter) == "function" then
        local r, g, b = getter()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return ApiRGB("GetGlobalFontColor", 1, 1, 1)
end
local function ApiSetRGB(name, r, g, b, a)
    return ApiCall(name, r, g, b, a)
end
local function GeneralRGB(prefix, dr, dg, db)
    local g = G()
    return tonumber(g[prefix .. "R"]) or dr, tonumber(g[prefix .. "G"]) or dg,
        tonumber(g[prefix .. "B"]) or db, tonumber(g[prefix .. "A"])
end
local function SetGeneralRGB(prefix, r, gCol, b, a)
    local g = G()
    g[prefix .. "R"], g[prefix .. "G"], g[prefix .. "B"] = r, gCol, b
    if type(a) == "number" then g[prefix .. "A"] = a end
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
end
local function TrText(text)
    local translate = M.TranslateText or M.Tr
    if type(translate) == "function" then return translate(text) end
    return text
end
-- Default-aware color controls: an amber dot marks values that differ from the
-- shipped default, right-click restores the default through the normal bound
-- apply path, and section headers show a live "N modified" badge.
local COLOR_DEFAULT_EPS = 0.003
local function FindCollapsibleEntryFor(frame)
    local parent = frame
    for _ = 1, 12 do
        if not parent then return nil end
        local entry = parent._msuf2CollapsibleEntry
        if entry then return entry end
        parent = parent.GetParent and parent:GetParent()
    end
end
local function ColorMatchesDefault(control)
    local defaults = control and control._msuf2DefaultRGB
    if not defaults or not control.GetRGB then return true end
    local r, g, b = control:GetRGB()
    return math.abs((tonumber(r) or 1) - defaults[1]) < COLOR_DEFAULT_EPS
        and math.abs((tonumber(g) or 1) - defaults[2]) < COLOR_DEFAULT_EPS
        and math.abs((tonumber(b) or 1) - defaults[3]) < COLOR_DEFAULT_EPS
end
local function RefreshSectionModifiedBadge(entry)
    if not (entry and entry.body) or type(W.SetCollapsibleBadges) ~= "function" then return end
    local list = entry._msuf2DefaultColorControls
    if not list or #list == 0 then return end
    local count = 0
    for i = 1, #list do
        if not ColorMatchesDefault(list[i]) then count = count + 1 end
    end
    if entry._msuf2ModifiedBadgeCount == count then return end
    entry._msuf2ModifiedBadgeCount = count
    if count > 0 then
        W.SetCollapsibleBadges(entry.body, {{
            text = tostring(count) .. " " .. TrText("modified"),
            kind = "accent",
            showWhenClosed = true,
        }})
    else
        W.SetCollapsibleBadges(entry.body, {})
    end
end
local function AttachDefaultColorBehavior(ctx, control, defaultRGB)
    if not (control and control.GetRGB and control.SetRGB and type(defaultRGB) == "table") then return end
    local dr = tonumber(defaultRGB[1])
    local dg = tonumber(defaultRGB[2])
    local db = tonumber(defaultRGB[3])
    if not (dr and dg and db) then return end
    control._msuf2DefaultRGB = { dr, dg, db }
    local entry = FindCollapsibleEntryFor(control)
    if entry then
        entry._msuf2DefaultColorControls = entry._msuf2DefaultColorControls or {}
        entry._msuf2DefaultColorControls[#entry._msuf2DefaultColorControls + 1] = control
    end
    -- Modified marker: tint the swatch's existing rounded edge amber instead
    -- of drawing an extra corner marker. This reuses the exact pill texture
    -- path every swatch already renders, so it cannot add stray artifacts.
    local edge = control._msuf2Edge
    local function RefreshDot()
        local modified = not ColorMatchesDefault(control)
        if edge and edge.SetVertexColor then
            if modified then
                edge:SetVertexColor(0.98, 0.74, 0.26, 1)
            else
                local base = (T.colors and T.colors.borderSoft) or { 0.30, 0.40, 0.50, 1 }
                edge:SetVertexColor(base[1], base[2], base[3], 0.75)
            end
        end
        if entry then RefreshSectionModifiedBadge(entry) end
    end
    control._msuf2RefreshDefaultDot = RefreshDot
    local baseSetRGB = control.SetRGB
    control.SetRGB = function(self, r, g, b)
        baseSetRGB(self, r, g, b)
        RefreshDot()
    end
    if control.RegisterForClicks then control:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    local baseClick = control.GetScript and control:GetScript("OnClick")
    control:SetScript("OnClick", function(self, mouseButton, ...)
        if mouseButton == "RightButton" then
            if self.IsEnabled and not self:IsEnabled() then return end
            local defaults = self._msuf2DefaultRGB
            self:SetRGB(defaults[1], defaults[2], defaults[3])
            if type(self._msuf2OnColorChanged) == "function" then
                self._msuf2OnColorChanged(defaults[1], defaults[2], defaults[3])
            end
            return
        end
        if type(baseClick) == "function" then baseClick(self, mouseButton, ...) end
    end)
    if M.AddTooltip and control._msuf2ColorLabel then
        M.AddTooltip(control, TrText(control._msuf2ColorLabel),
            TrText("Right-click resets this color to its default."), { hook = true })
    end
    RefreshDot()
end
function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB, labelWidthOverride, swatchWidth, metadata, defaultRGB)
    local color = W.Color(section, label)
    M.BindColor(ctx, color, getRGB, setRGB, metadata)
    AttachDefaultColorBehavior(ctx, color, defaultRGB)
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
local function ApiColorAt(ctx, section, label, x, y, getName, setName, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c, a)
            if not ApiSetRGB(setName, r, g, c, a) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        labelWidth, swatchWidth, metadata or Meta("api." .. tostring(setName or getName)), { dr, dg, db })
end
local function GeneralColorAt(ctx, section, label, x, y, prefix, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return GeneralRGB(prefix, dr, dg, db) end,
        function(r, g, c, a)
            SetGeneralRGB(prefix, r, g, c, a)
            if type(apply) == "function" then apply() else ApplyColors() end
        end,
        labelWidth, swatchWidth, metadata or Meta("general." .. tostring(prefix)), { dr, dg, db })
end
local function ApiOrGeneralColorAt(ctx, section, label, x, y, getName, setName, prefix, dr, dg, db, apply, alpha, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return ApiRGB(getName, dr, dg, db) end,
        function(r, g, c, a)
            local nextAlpha = type(a) == "number" and a or alpha
            local ok = nextAlpha ~= nil and ApiCall(setName, r, g, c, nextAlpha) or ApiCall(setName, r, g, c)
            if not ok then
                SetGeneralRGB(prefix, r, g, c, nextAlpha)
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        nil, nil, metadata or Meta("general." .. tostring(prefix)), { dr, dg, db })
end
local function TableColorAt(ctx, section, label, x, y, getTable, key, dr, dg, db, apply, labelWidth, swatchWidth, metadata)
    return ColorValueAt(ctx, section, label, x, y,
        function() return TableRGB(getTable(), key, dr, dg, db) end,
        function(r, g, c)
            SetTableRGB(getTable(), key, r, g, c)
            if type(apply) == "function" then apply() end
        end,
        labelWidth, swatchWidth, metadata or Meta("table." .. tostring(key)), { dr, dg, db })
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
local function ButtonAt(parent, label, x, y, width, onClick, semanticPath)
    local btn = T.Button(parent, label, width or 150, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if type(onClick) == "function" then
        btn:SetScript("OnClick", function(self, ...)
            onClick(self, ...)
            if M.RequestRefresh then M.RequestRefresh(nil, "advanced-colors-button") elseif M.Refresh then M.Refresh() end
        end)
    end
    -- These two resets depend on the adjacent ephemeral selectors and have no
    -- stable Assistant action contract. Keep them menu-executable but exclude
    -- them from automatic Assistant mutation.
    local classification = (semanticPath == "castbar.text_color.reset" or semanticPath == "status_text.color.reset")
        and "ephemeral" or "action"
    RegisterControl(btn, Meta(semanticPath, classification), label, "button")
    return btn
end
local Card = W.ThemedControlCard
local function NPCColorAt(ctx, section, row, x, y, apply)
    return ColorValueAt(ctx, section, row.label, x, y,
        function() return ApiRGB("GetNPCColor", row.dr, row.dg, row.db, row.key) end,
        function(r, g, c)
            if not ApiCall("SetNPCColor", row.key, r, g, c) then
                if type(apply) == "function" then apply() else ApplyColors() end
            end
        end,
        nil, nil, Meta("npc.color." .. tostring(row.key)), { row.dr, row.dg, row.db })
end
local function ResetNPCColors(apiName)
    if ApiCall(apiName) then return end
    DB().npcColors = nil
    ApplyUnitframeColorWithReload()
end
local function ResetUnitframeColors()
    local db = DB()
    local g = G()
    db.npcColors = nil
    ClearRGB(g, "petFrameColor")
    g.petFrameUsePlayerClassColor = nil
    g.npcClassColorBar = nil
    ApplyUnitframeColorWithReload()
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
function M._ContextGetAuraSafeRGB()
    local color = G().aurasCooldownTextSafeColor
    if type(color) == "table" then
        return TableRGB(G(), "aurasCooldownTextSafeColor", 1, 1, 1)
    end
    return M._ContextConfiguredGlobalFontRGB()
end
function M._ContextSetAuraSafeRGB(r, g, b)
    G().aurasCooldownTextSafeColor = { r, g, b }
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
    g.aurasCooldownTextUseBuckets = false
    g.aurasCooldownTextSafeColor = nil
    g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
    g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
    g.aurasCooldownTextSafeSeconds = 60
    g.aurasCooldownTextWarningSeconds = 15
    g.aurasCooldownTextUrgentSeconds = 5
    g.dispelTypeColorOverrides = nil
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
--- Texture layer colors mirror the portrait pattern: the Colors page writes the
--- general baseline plus every unit's copy, while the unit accordion edits only
--- its own frame. Refreshes are cold path (one re-stamp per frame). Stored on M
--- instead of file locals: this file rides the 200 active-local ceiling.
function M._ApplyTextureLayerColors()
    _G.MSUF_RefreshUnitTextureLayers()
    _G.MSUF_UFPreview_RequestRefresh("MSUF2_TEXLAYER")
end
function M._SetAllTextureLayerRGB(prefix, r, g, b)
    local db = DB()
    db.general = db.general or {}
    db.general[prefix .. "R"], db.general[prefix .. "G"], db.general[prefix .. "B"] = r, g, b
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
        db[key] = db[key] or {}
        db[key][prefix .. "R"], db[key][prefix .. "G"], db[key][prefix .. "B"] = r, g, b
    end
    M._ApplyTextureLayerColors()
end
M.PowerBarColorByClass = {
    Get = function()
        local g = G()
        return tostring(g.powerColorMode or g.powerBarColorMode or "power"):lower() == "class"
    end,
    Set = function(enabled)
        G().powerColorMode = enabled and "class" or "power"
        ApplyColors()
    end,
}

local function BuildAuraAndPortraitColors(ctx, b, CH, part)
    if part ~= "portrait" then
    local auras = b:CollapsibleSection("colors_auras", "Auras", 900, false)
    local w = auras._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(auras, "Cooldown Timer Colors", nil, 24, -42, colW, 380)
    local markers = Card(auras, "Timer Thresholds", nil, rightX, -42, colW, 380)

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
        fs:SetFont(FONT, T.FontSize("heading"), "OUTLINE")
        fs:SetPoint("CENTER", box, "CENTER", 0, 6)
        local label = T.Font(box, "GameFontDisableSmall", i == 1 and "Safe" or (i == 2 and "Warn" or "Urgent"), T.colors.muted)
        label:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
        samples[i] = fs
    end
    local function RefreshColorSamples()
        local sr, sg, sb = M._ContextGetAuraSafeRGB()
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
        end,
        Meta("auras.cooldown.color_by_time"))
    local function AuraColorAt(parent, label, y, key, r, g, bcol, after)
        return CH.TableColorAt(ctx, parent, label, 16, y, G, key, r, g, bcol,
            after or ApplyAuraColors, nil, nil, Meta("auras.color." .. tostring(key)))
    end
    local function RefreshTextColors()
        RefreshColorSamples()
        ApplyAuraColors()
    end
    ColorValueAt(ctx, cooldown, "Safe", 16, -210, M._ContextGetAuraSafeRGB,
        function(r, g, b)
            M._ContextSetAuraSafeRGB(r, g, b)
            RefreshColorSamples()
        end, nil, nil, Meta("auras.color.aurasCooldownTextSafeColor"), { 1, 1, 1 })
    AuraColorAt(cooldown, "Warning", -248, "aurasCooldownTextWarningColor", 1, 0.85, 0.20, RefreshTextColors)
    AuraColorAt(cooldown, "Urgent", -286, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10, RefreshTextColors)
    ValueSliderAt(ctx, markers, "Safe seconds", 16, -72, 0, 600, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextSafeSeconds", 60, 0, 600) end,
        function(v) WriteAuraNumber("aurasCooldownTextSafeSeconds", v, 0, 600) end,
        Meta("auras.cooldown.safe_seconds"))
    ValueSliderAt(ctx, markers, "Warning <= sec", 16, -142, 0, 60, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextWarningSeconds", 15, 0, 60) end,
        function(v) WriteAuraNumber("aurasCooldownTextWarningSeconds", v, 0, 60) end,
        Meta("auras.cooldown.warning_seconds"))
    ValueSliderAt(ctx, markers, "Urgent <= sec", 16, -212, 0, 30, 1, colW - 32,
        function() return ReadAuraNumber("aurasCooldownTextUrgentSeconds", 5, 0, 30) end,
        function(v) WriteAuraNumber("aurasCooldownTextUrgentSeconds", v, 0, 30) end,
        Meta("auras.cooldown.urgent_seconds"))
    W.Text(markers, "Thresholds choose when Warning and Urgent replace the Safe timer color.", 16, -276, colW - 32, T.colors.muted)
    local dispel = Card(auras, "Dispel Type Colors", nil, 24, -448, w - 48, 310)
    W.Text(dispel, "Optional global overrides for harmful Magic, Curse, Disease, Poison and Bleed indicators. Off uses Blizzard's current default. The last edited type is shown first in every aura preview.", 16, -52, w - 80, T.colors.muted)
    for i = 1, #M.DISPEL_COLOR_SPECS do
        local spec = M.DISPEL_COLOR_SPECS[i]
        local dispelType, y = spec.key, -104 - ((i - 1) * 38)
        local color, custom
        custom = ValueSwitchAt(ctx, dispel, dispelType .. " custom", 16, y, 250,
            function() return M._HasDispelTypeColorOverride(dispelType) end,
            function(value)
                M._SetDispelTypeColorEnabled(dispelType, value)
                if color then color:SetRGB(M._GetDispelTypeRGB(dispelType, true)) end
            end,
            Meta("auras.dispel." .. spec.path .. ".enabled"))
        color = ColorValueAt(ctx, dispel, dispelType .. " color", 330, y,
            function() return M._GetDispelTypeRGB(dispelType, true) end,
            function(r, g, blue)
                M._SetDispelTypeRGB(dispelType, r, g, blue)
                if custom then custom:SetChecked(true) end
            end,
            120, 44, Meta("auras.dispel." .. spec.path .. ".color"))
    end
    W.Text(auras, "Timer and Dispel colors are shared by live unit/group auras and every preview. Icon border and shadow colors live in Appearance > Auras, scoped by Aura type.", 24, -786, w - 48, T.colors.muted)
    CH.ButtonAt(auras, "Reset aura colors", 24, -838, 150, ResetAuraColorSettings, "auras.reset")
    M.TrackRefresh(ctx, RefreshColorSamples)
    end
    if part == "auras" then return end

    local portrait = b:CollapsibleSection("colors_portrait", "Portrait Colors", 180, false)
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end,
        nil, nil, Meta("portrait.border_color"), { 1, 1, 1 })
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end,
        nil, nil, Meta("portrait.background_color"), { 0.05, 0.05, 0.05 })
    CH.ButtonAt(portrait, "Reset portrait colors", 12, -118, 170, function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        G().portraitBorderColorA = 1
        G().portraitBgColorA = 0.85
        ApplyPortraitColors("PORTRAIT_COLOR_RESET")
    end, "portrait.reset")
end
local function OpenFontsTextColors()
    if W.CloseDropdown then W.CloseDropdown() end
    local request = {
        pageKey = "opt_fonts",
        sectionId = "fonts_name_power_colors",
        explicit = true,
        consumed = false,
        source = "colors-global-font-to-fonts",
        changedAt = GetTime and GetTime() or 0,
    }
    _G.MSUF_EM2_MenuFocusRequest = request
    if type(M.SelectPage) ~= "function" or M.SelectPage("opt_fonts") == false then
        if _G.MSUF_EM2_MenuFocusRequest == request then _G.MSUF_EM2_MenuFocusRequest = nil end
        return false
    end
    return true
end
-- Text-color MODES mirrored from Fonts > Text Colors, pinned to the SHARED
-- font scope so edits here are deterministic no matter which scope the Fonts
-- page currently targets. Same storage keys, same apply route - one source of
-- truth; per-frame and group overrides stay on the Fonts page.
local function FontColorSwatch()
    local r, g, b = M._ContextConfiguredGlobalFontRGB()
    return { r, g, b }
end
local function PlayerClassSwatch()
    local classToken
    if type(_G.UnitClass) == "function" then
        local _, token = _G.UnitClass("player")
        classToken = token
    end
    local r, g, b = ClassColorRGB(classToken or "WARRIOR")
    return { r, g, b }
end
local function NPCReactionSwatch()
    local r, g, b = ApiRGB("GetNPCColor", 0.85, 0.10, 0.10, "enemy")
    return { r, g, b }
end
local function HealthGradientSwatch()
    return { 1, 0.7, 0 }
end
local function PowerTypeSwatch()
    local token
    if type(_G.UnitPowerType) == "function" then
        local _, powerToken = _G.UnitPowerType("player")
        token = powerToken
    end
    local r, g, b = CP.GetPowerOverrideRGB(token and token ~= "" and token or "MANA")
    return { r, g, b }
end
-- Frame and indicator choices for the canonical status text color surface. The
-- indicator value IS the DB key prefix, which keeps this list and the engine's
-- PrefixedStatusDef naming in one piece. Parked on M rather than a file local:
-- this chunk is at Lua 5.1's 200-local ceiling and one more breaks the page.
M._statusTextColor = {
    units = ValueTextPairs "player=Player|target=Target|focus=Focus|targettarget=Target of Target|focustarget=Focus Target|pet=Pet|boss=Boss Frames",
    indicators = ValueTextPairs "levelIndicator=Level Text|raceIndicator=Race Text|classTextIndicator=Class Text|raidGroupName=Raid Group|statusText=Dead / Offline Text|statusGhostText=Ghost Text|statusAFKText=AFK Text|statusDNDText=DND Text",
    unitKeys = {},
    prefixKeys = {},
}
for i = 1, #M._statusTextColor.units do M._statusTextColor.unitKeys[M._statusTextColor.units[i].value] = true end
for i = 1, #M._statusTextColor.indicators do M._statusTextColor.prefixKeys[M._statusTextColor.indicators[i].value] = true end
local FONT_TEXT_MODE_VALUES = {
    name = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassSwatch },
        { value = "CUSTOM", text = "Custom Color", swatchColor = ReadNameColor },
    },
    npc = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "NPC", text = "NPC / Reaction Color", swatchColor = NPCReactionSwatch },
        { value = "CLASS", text = "Class Color (Reaction fallback)", swatchColor = PlayerClassSwatch },
    },
    health = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassSwatch },
        { value = "HEALTH", text = "Health Gradient", swatchColor = HealthGradientSwatch },
    },
    power = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "RESOURCE", text = "By Power Type", swatchColor = PowerTypeSwatch },
    },
}
local function ApplySharedFontTextColors(reason)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestFonts) == "function" then
        return apply.RequestFonts(reason or "MSUF2_COLORS_TEXT_MODES", "shared")
    end
    return RequestGeneral(reason or "MSUF2_COLORS_TEXT_MODES", { preview = true, applyAll = true })
end
local function BuildFontAndClassColors(ctx, b, CH, part)
    if part ~= "classes" then
    local font = b:CollapsibleSection("colors_font", "Text Colors", 296, false)
    local fontW = font._msuf2Width or ctx.width or 720
    CH.ApiColorAt(ctx, font, "Global font color", 12, -10, "GetGlobalFontColor", "SetGlobalFontColor", 1, 1, 1)
    CH.ButtonAt(font, "Use font palette", 360, -10, 170, function()
        if not ApiCall("ResetGlobalFontToPalette") then
            G().useCustomFontColor = false
            ClearRGB(G(), "fontColorCustom")
            ApplyColors()
        end
    end, "font.use_palette")
    local refreshNameCustomColor
    local nameModeDropdown = ValueDropdownAt(ctx, font, "Player Name Color", 12, -52, FONT_TEXT_MODE_VALUES.name, 300,
        function()
            local g = G()
            if g.nameColorMode == "CUSTOM" then return "CUSTOM" end
            return g.nameClassColor and "CLASS" or "DEFAULT"
        end,
        function(v)
            local g = G()
            if v ~= "CLASS" and v ~= "CUSTOM" then v = "DEFAULT" end
            -- nameColorMode is the new source of truth; nameClassColor stays in
            -- sync so the engine fallback and older profiles keep working.
            g.nameColorMode = v
            g.nameClassColor = v == "CLASS"
            ApplySharedFontTextColors("MSUF2_NAME_CLASS_COLOR")
            if refreshNameCustomColor then refreshNameCustomColor() end
        end,
        Meta("font.text_mode.player_name", "ephemeral"))
    local npcModeDropdown = ValueDropdownAt(ctx, font, "NPC / Boss Name Color", 360, -52, FONT_TEXT_MODE_VALUES.npc, 300,
        function()
            local g = G()
            if g.nameNpcClassColor then return "CLASS" end
            return g.npcNameRed and "NPC" or "DEFAULT"
        end,
        function(v)
            local g = G()
            g.nameNpcClassColor = v == "CLASS"
            g.npcNameRed = v == "NPC"
            ApplySharedFontTextColors("MSUF2_NPC_NAME_COLOR")
        end,
        Meta("font.text_mode.npc_name", "ephemeral"))
    local hpModeDropdown = ValueDropdownAt(ctx, font, "HP Text Color", 12, -112, FONT_TEXT_MODE_VALUES.health, 300,
        function()
            local value = G().colorHealthTextByHealth
            if value == "CLASS" then return "CLASS" end
            return (value == true or value == "HEALTH") and "HEALTH" or "DEFAULT"
        end,
        function(v)
            G().colorHealthTextByHealth = (v == "CLASS") and "CLASS" or (v == "HEALTH")
            ApplySharedFontTextColors("MSUF2_HP_TEXT_COLOR")
        end,
        Meta("font.text_mode.hp_text", "ephemeral"))
    local powerModeDropdown = ValueDropdownAt(ctx, font, "Power Text Color", 360, -112, FONT_TEXT_MODE_VALUES.power, 300,
        function() return G().colorPowerTextByType and "RESOURCE" or "DEFAULT" end,
        function(v)
            G().colorPowerTextByType = v == "RESOURCE"
            ApplySharedFontTextColors("MSUF2_POWER_TEXT_COLOR")
        end,
        Meta("font.text_mode.power_text", "ephemeral"))
    if M.AddTooltip then
        -- "Player" means player CHARACTERS (the unit type), not the player
        -- frame: class colors only exist for players, NPC names are governed
        -- by the dropdown next to it. Spell that out.
        M.AddTooltip(nameModeDropdown, TrText("Player Name Color"),
            TrText("Name color for player characters on ALL frames - target, focus, party and raid included. NPC names use the setting next to this one."), { hook = true })
        M.AddTooltip(npcModeDropdown, TrText("NPC / Boss Name Color"),
            TrText("Name color for NPCs and bosses on all frames that follow the shared text settings."), { hook = true })
        M.AddTooltip(hpModeDropdown, TrText("HP Text Color"),
            TrText("HP text color mode for all frames that follow the shared text settings."), { hook = true })
        M.AddTooltip(powerModeDropdown, TrText("Power Text Color"),
            TrText("Power text color mode for all frames that follow the shared text settings."), { hook = true })
    end
    local nameCustomColor = ColorValueAt(ctx, font, "Custom name color", 12, -166,
        ReadNameColor,
        function(r, g2, b2)
            local g = G()
            g.nameColorR, g.nameColorG, g.nameColorB = r, g2, b2
            -- Choosing a color is the intent to use it, so the mode follows.
            if g.nameColorMode ~= "CUSTOM" then
                g.nameColorMode = "CUSTOM"
                g.nameClassColor = false
                if nameModeDropdown and nameModeDropdown.SetValue then nameModeDropdown:SetValue("CUSTOM") end
            end
            ApplySharedFontTextColors("MSUF2_NAME_CUSTOM_COLOR")
        end,
        nil, nil, Meta("font.name_custom.color"), { 1, 1, 1 })
    refreshNameCustomColor = function()
        SetControlEnabled(nameCustomColor, G().nameColorMode == "CUSTOM")
    end
    refreshNameCustomColor()
    M.TrackRefresh(ctx, refreshNameCustomColor)
    local sharedNote = W.Text(font, "Shared defaults for all frames. Per-frame and group overrides live in Fonts > Text Colors.",
        12, -212, fontW - 28, T.colors.muted)
    sharedNote:SetJustifyH("LEFT")
    local openFonts = T.Button(font, "Fonts > Text Colors", 190, 22)
    openFonts:SetPoint("TOPLEFT", font, "TOPLEFT", 12, -248)
    if T.CenterButtonLabel then T.CenterButtonLabel(openFonts) end
    if M.AddTooltip then
        M.AddTooltip(openFonts, "Fonts > Text Colors", "Open the Fonts page at its Text Colors section.", { hook = true })
    end
    openFonts:SetScript("OnClick", OpenFontsTextColors)
    RegisterControl(openFonts, Meta("font.open_text_colors", "navigation", { navigationKey = "opt_fonts" }), "Fonts > Text Colors", "button")

    -- Canonical surface for the per-indicator status text colors. Unit > Status
    -- reaches the same three keys through its ::: text shortcut only; it no longer
    -- carries a swatch of its own. Frame and indicator are picked one at a time so
    -- the eight indicators across seven frames stay a single swatch. An indicator
    -- with no stored color shows the font color it currently inherits.
    local statusText = b:CollapsibleSection("colors_status_text", "Status Text Colors", 250, false)
    local statusTextW = statusText._msuf2Width or ctx.width or 720
    local function StatusTextUnit()
        local value = tostring(M._colorsStatusTextUnit or "player")
        return M._statusTextColor.unitKeys[value] and value or "player"
    end
    local function StatusTextPrefix()
        local value = tostring(M._colorsStatusTextIndicator or "levelIndicator")
        return M._statusTextColor.prefixKeys[value] and value or "levelIndicator"
    end
    local function StatusTextConf()
        local db = DB()
        local key = StatusTextUnit()
        local conf = db[key]
        if type(conf) ~= "table" then conf = {}; db[key] = conf end
        return conf
    end
    local function ApplyStatusTextColors()
        M.RequestGeneralApply("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false })
    end
    LabelAt(statusText, "Color for a single text indicator on one frame. Unset indicators follow that frame's font color.",
        12, -8, statusTextW - 28, "GameFontHighlightSmall", T.colors.muted)
    local statusUnitDropdown = ValueDropdownAt(ctx, statusText, "Frame", 12, -44, M._statusTextColor.units, min(260, statusTextW - 32),
        StatusTextUnit,
        function(value)
            M._colorsStatusTextUnit = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "status-text-color-unit") elseif M.Refresh then M.Refresh(ctx) end
        end,
        Meta("status_text.color.unit", "ephemeral"))
    RegisterControl(statusUnitDropdown, Meta("status_text.color.unit", "ephemeral"), "Frame", "dropdown", M._statusTextColor.units)
    local statusIndicatorDropdown = ValueDropdownAt(ctx, statusText, "Indicator", 12, -100, M._statusTextColor.indicators, min(260, statusTextW - 32),
        StatusTextPrefix,
        function(value)
            M._colorsStatusTextIndicator = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "status-text-color-indicator") elseif M.Refresh then M.Refresh(ctx) end
        end,
        Meta("status_text.color.indicator", "ephemeral"))
    RegisterControl(statusIndicatorDropdown, Meta("status_text.color.indicator", "ephemeral"), "Indicator", "dropdown", M._statusTextColor.indicators)
    ColorValueAt(ctx, statusText, "Text color", 12, -156,
        function()
            local conf, prefix = StatusTextConf(), StatusTextPrefix()
            local r = tonumber(conf[prefix .. "ColorR"])
            local g = tonumber(conf[prefix .. "ColorG"])
            local bcol = tonumber(conf[prefix .. "ColorB"])
            if r and g and bcol then return r, g, bcol end
            return M._ContextConfiguredGlobalFontRGB()
        end,
        function(r, g, bcol)
            local conf, prefix = StatusTextConf(), StatusTextPrefix()
            conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = r, g, bcol
            ApplyStatusTextColors()
        end,
        nil, nil, Meta("status_text.color.value"))
    CH.ButtonAt(statusText, "Follow font color", 12, -196, 190, function()
        local conf, prefix = StatusTextConf(), StatusTextPrefix()
        conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = nil, nil, nil
        ApplyStatusTextColors()
    end, "status_text.color.reset")
    end
    if part == "font" then return end
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
        local cdr, cdg, cdb = ClassDefaultRGB(token)
        ColorValueAt(ctx, classColors, COLOR_DATA.CLASS_LABELS[token] or token, 12 + col * classColW, -34 - row * 36,
            function() return ClassColorRGB(token) end,
            function(r, g, c)
                if ApiCall("SetClassColor", token, r, g, c) then
                    M.RefreshActiveHealthBackgroundInlinePreview()
                else
                    ApplyUnitframeColorWithReload()
                end
            end, classLabelW, 44, Meta("class_bar.token." .. tostring(token)), { cdr, cdg, cdb })
    end
    CH.ButtonAt(classColors, "Reset all class colors", 12, classResetY, 190, function()
        if ApiCall("ResetAllClassColors") then
            M.RefreshActiveHealthBackgroundInlinePreview()
        else
            DB().classColors = nil
            ApplyUnitframeColorWithReload()
        end
    end, "class_bar.reset_all")
end

local function ApplyScopedBarGradientColors(reason)
    local apply = CurrentApplyService()
    local scope = CurrentBarsScope()
    if apply and type(apply.RequestBarGradients) == "function" then
        return apply.RequestBarGradients(reason or "MSUF2_BAR_GRADIENT_COLORS", scope)
    end
    return RequestGeneral(reason or "MSUF2_BAR_GRADIENT_COLORS", {
        preview = true,
        applyAll = false,
        notify = false,
        barGradients = true,
        barsScope = scope,
    })
end


local function BuildBarGradientColors(ctx, b, CH)
    local values = GP.SCOPE_VALUES or {}
    local sectionW = ctx.width or 720
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, { width = sectionW })
    local scopeBottom = (scopeMetrics and scopeMetrics.bottomY) or -40
    local colorY = math.min(-104, scopeBottom - 54)
    local compact = sectionW < 560
    local resetY = compact and (colorY - 86) or (colorY - 44)
    local section = b:CollapsibleSection("colors_bar_gradients", "Bar Gradient Colors", math.abs(resetY) + 54, true)
    local scopeBar = W.ScopeOverrideBar(ctx, section, {
        values = values,
        width = sectionW,
        getValue = CurrentBarsScope,
        setValue = function(value)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(value)
            if M.RequestRefresh then M.RequestRefresh(ctx, "bar-gradient-color-scope")
            elseif M.Refresh then M.Refresh(ctx) end
        end,
        hasOverride = function(value)
            return value ~= "shared" and ScopeHasOverride(value, "hlOverride")
        end,
    })
    RegisterControl(scopeBar, Meta("bar_gradient.scope.selector", "ephemeral"), "Editing:", "segment", values)
    local hint = W.Text(section, "Health and Power use separate gradient colors. Choosing a color creates a custom Bars override for the selected scope.",
        14, colorY + 28, sectionW - 28, T.colors.muted)
    hint:SetJustifyH("LEFT")
    local function GradientRGB(prefix)
        return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
            tonumber(GradientScopeGet(prefix .. "G", 0)) or 0,
            tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
    end
    local function SetGradientRGB(prefix, r, g, bcol, reason)
        GradientScopeSet(prefix .. "R", r)
        GradientScopeSet(prefix .. "G", g)
        GradientScopeSet(prefix .. "B", bcol)
        ApplyScopedBarGradientColors(reason)
    end
    local powerX = compact and 14 or math.max(360, floor(sectionW * 0.50))
    local powerY = compact and (colorY - 38) or colorY
    ColorValueAt(ctx, section, "Health gradient color", 14, colorY,
        function() return GradientRGB("healthBarGradientColor") end,
        function(r, g, bcol) SetGradientRGB("healthBarGradientColor", r, g, bcol, "MSUF2_HP_GRADIENT_COLOR") end,
        compact and 180 or 190, 52, Meta("bar_gradient.health.color"), { 0, 0, 0 })
    ColorValueAt(ctx, section, "Power gradient color", powerX, powerY,
        function() return GradientRGB("powerBarGradientColor") end,
        function(r, g, bcol) SetGradientRGB("powerBarGradientColor", r, g, bcol, "MSUF2_POWER_GRADIENT_COLOR") end,
        compact and 180 or 190, 52, Meta("bar_gradient.power.color"), { 0, 0, 0 })
    CH.ButtonAt(section, "Reset gradient colors", 14, resetY, 180, function()
        GradientScopeSet("healthBarGradientColorR", 0)
        GradientScopeSet("healthBarGradientColorG", 0)
        GradientScopeSet("healthBarGradientColorB", 0)
        GradientScopeSet("powerBarGradientColorR", 0)
        GradientScopeSet("powerBarGradientColorG", 0)
        GradientScopeSet("powerBarGradientColorB", 0)
        ApplyScopedBarGradientColors("MSUF2_RESET_GRADIENT_COLORS")
    end, "bar_gradient.reset")
end

local function BuildBackgroundAndAppearance(ctx, b, CH, part)
    if part ~= "appearance" then
    local background = b:CollapsibleSection("colors_background", "Bar Background Tint", 332, false)
    LabelAt(background, "Fill and color mode affect only the health background; foreground health coloring stays independent.", 12, -8, 660, "GameFontHighlightSmall", T.colors.muted)
    LabelAt(background, "Texture comes from Bars; preview uses Player background opacity multiplied by tint opacity.", 12, -24, 660, "GameFontHighlightSmall", T.colors.muted)
    local refreshBackgroundPreview
    local function SetBackgroundFill(value)
        M.ColorsBackgroundMode.SetFill(value)
        if refreshBackgroundPreview then refreshBackgroundPreview() end
    end
    local function SetBackgroundColorMode(value)
        M.ColorsBackgroundMode.SetColor(value)
        if refreshBackgroundPreview then refreshBackgroundPreview() end
    end
    ValueDropdownAt(ctx, background, "Background Fill", 12, -46,
        ValueTextPairs "full=Full bar|missing=Missing health only", 300,
        M.ColorsBackgroundMode.GetFill, SetBackgroundFill, Meta("background.fill_mode"))
    ValueDropdownAt(ctx, background, "Background Color", 340, -46,
        ValueTextPairs "custom=Custom tint|match_health=Match health bar|class=Class color|health_gradient=Health gradient", 320,
        M.ColorsBackgroundMode.GetColor, SetBackgroundColorMode, Meta("background.color_mode"))

    local previewWidth = max(300, min(648, (background._msuf2Width or ctx.width or 720) - 24))
    local previewPanel = T.Panel(background, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.92 }, T.colors.borderSoft)
    previewPanel:SetPoint("TOPLEFT", background, "TOPLEFT", 12, -104)
    previewPanel:SetSize(previewWidth, 66)
    local previewLabel = T.Font(previewPanel, "GameFontNormalSmall", TrText("Preview"), T.colors.muted)
    previewLabel:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 12, -8)
    local previewMode = T.Font(previewPanel, "GameFontHighlightSmall", "", T.colors.muted)
    previewMode:SetPoint("TOPRIGHT", previewPanel, "TOPRIGHT", -12, -8)
    previewMode:SetJustifyH("RIGHT")
    local previewTrack = T.Panel(previewPanel, nil, { 0.006, 0.012, 0.024, 1 }, T.colors.borderSoft)
    previewTrack:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 12, -28)
    previewTrack:SetPoint("TOPRIGHT", previewPanel, "TOPRIGHT", -12, -28)
    previewTrack:SetHeight(22)
    local previewBackgroundBar = CreateFrame("StatusBar", nil, previewTrack)
    previewBackgroundBar:SetPoint("TOPLEFT", previewTrack, "TOPLEFT", 1, -1)
    previewBackgroundBar:SetPoint("BOTTOMRIGHT", previewTrack, "BOTTOMRIGHT", -1, 1)
    previewBackgroundBar:SetMinMaxValues(0, 1)
    previewBackgroundBar:SetValue(1)
    previewBackgroundBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    previewBackgroundBar:EnableMouse(false)
    if previewBackgroundBar.SetFrameLevel and previewTrack.GetFrameLevel then
        previewBackgroundBar:SetFrameLevel(previewTrack:GetFrameLevel() or 0)
    end
    local previewBackground = previewBackgroundBar:GetStatusBarTexture()
    if previewBackground.SetDrawLayer then previewBackground:SetDrawLayer("BACKGROUND", -7) end
    local previewBar = CreateFrame("StatusBar", nil, previewTrack)
    previewBar:SetPoint("TOPLEFT", previewTrack, "TOPLEFT", 1, -1)
    previewBar:SetPoint("BOTTOMRIGHT", previewTrack, "BOTTOMRIGHT", -1, 1)
    previewBar:SetMinMaxValues(0, 1)
    previewBar:SetValue(0.62)
    previewBar:EnableMouse(false)
    if previewBar.SetFrameLevel and previewBackgroundBar.GetFrameLevel then
        previewBar:SetFrameLevel((previewBackgroundBar:GetFrameLevel() or 0) + 1)
    end
    local previewPercent = T.Font(previewBar, "GameFontHighlightSmall", "62%", { 1, 1, 1, 0.95 })
    previewPercent:SetPoint("CENTER", previewBar, "CENTER", 0, 0)
    local previewState = {
        bar = previewBar, backgroundBar = previewBackgroundBar, background = previewBackground,
        percent = previewPercent, mode = previewMode, healthFraction = 0.62,
    }
    refreshBackgroundPreview = function()
        if previewPanel.IsVisible and not previewPanel:IsVisible() then return false end
        return M.RefreshHealthBackgroundInlinePreview(previewState)
    end
    local function ApplyBackgroundColorPreview()
        ApplyColors()
        refreshBackgroundPreview()
    end
    ColorValueAt(ctx, background, "Bar background tint", 12, -188,
        function() return ApiRGB("GetClassBarBgColor", 0, 0, 0) end,
        function(r, g, c, a)
            local nextAlpha = type(a) == "number" and a or nil
            local ok = nextAlpha ~= nil and ApiCall("SetClassBarBgColor", r, g, c, nextAlpha)
                or ApiCall("SetClassBarBgColor", r, g, c)
            if not ok then
                SetGeneralRGB("classBarBg", r, g, c, nextAlpha)
                ApplyColors()
            end
            refreshBackgroundPreview()
        end,
        nil, nil, Meta("general.classBarBg"), { 0, 0, 0 })
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -228,
        function() return G().darkBgCustomColor == true end,
        function(v) G().darkBgCustomColor = v and true or false; ApplyBackgroundColorPreview() end,
        Meta("background.dark_mode_custom_color"))
    CH.ButtonAt(background, "Reset to black", 12, -274, 140, function()
        if not ApiCall("ResetClassBarBgColor") then
            ClearRGB(G(), "classBarBg")
            ApplyUnitframeColorWithReload()
        end
        refreshBackgroundPreview()
    end, "background.reset_to_black")
    if M.TrackCollapsibleRefresh then M.TrackCollapsibleRefresh(ctx, background, refreshBackgroundPreview)
    elseif M.TrackRefresh then M.TrackRefresh(ctx, refreshBackgroundPreview) end
    if ctx.entry then ctx.entry._msuf2HealthBackgroundInlinePreviewRefresh = refreshBackgroundPreview end
    end
    if part == "background" then return end
    local appearance = b:CollapsibleSection("colors_appearance", "Unitframe Global Coloring", 290, true)
    local refreshBarModeControls
    local function CurrentBarMode()
        local g = G()
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" and mode ~= "gradient" then mode = (g.useClassColors and "class") or "dark" end
        return mode
    end
    local function SetBarMode(mode)
        local g = G()
        g.barMode = mode
        g.darkMode = (mode == "dark")
        g.useClassColors = (mode == "class")
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
        if M.RequestRefresh then M.RequestRefresh(ctx, "colors-bar-mode") end
    end
    -- Mode-first: the four coloring modes are the most consequential choice on
    -- this page, so they lead the section as one segmented card row. That row
    -- is the canonical bound control for search and Assistant automation.
    local BAR_MODE_CARDS = {
        { mode = "dark", title = "Dark Mode", desc = "Dark, neutral bars for every frame." },
        { mode = "class", title = "Class Colors", desc = "Health bars use Blizzard class colors." },
        { mode = "unified", title = "Unified", desc = "One custom color for all health bars." },
        { mode = "gradient", title = "Gradient", desc = "Bar color follows health percent (low / mid / high)." },
    }
    local appearanceW = appearance._msuf2Width or ctx.width or 720
    local modeRowW = min(appearanceW, 740) - 24
    local modeValues = {}
    for i = 1, #BAR_MODE_CARDS do
        modeValues[i] = { value = BAR_MODE_CARDS[i].mode, text = BAR_MODE_CARDS[i].title }
    end
    local modeRow = W.Segment(appearance, "Bar mode", modeValues, modeRowW)
    MoveWidget(modeRow, appearance, 12, -10, modeRowW)
    M.BindSegment(ctx, modeRow, CurrentBarMode, SetBarMode, Meta("appearance.bar_mode"))
    for i = 1, #BAR_MODE_CARDS do
        local btn = modeRow.buttons[i]
        if btn and M.AddTooltip then M.AddTooltip(btn, TrText(BAR_MODE_CARDS[i].title), TrText(BAR_MODE_CARDS[i].desc), { hook = true }) end
    end
    local modeDescLabel = LabelAt(appearance, "", 12, -64, appearanceW - 24, "GameFontHighlightSmall", T.colors.muted)
    local unifiedColor = CH.GeneralColorAt(ctx, appearance, "Unified bar color", 12, -94, "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload)
    local darkColor = ValueSliderAt(ctx, appearance, "Dark mode bar color", 12, -136, 0, 100, 1, 300,
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
        end,
        Meta("appearance.dark_mode_tone"))
    local gradientStrength = SliderAt(ctx, appearance, "Gradient strength", 360, -94, 0, 1, 0.05, 250, G, "gradientStrength", 0.45, ApplyUnitframeColorWithReload, Meta("appearance.gradient.strength"))
    local healthGradient = SwitchAt(ctx, appearance, "Health Gradient", 360, -142, 230, G, "enableHealthGradient", true, function()
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
    end, Meta("appearance.gradient.enabled"))
    local gradientStopsLabel = LabelAt(appearance, "Health gradient stops", 12, -190, 220, "GameFontNormalSmall", T.colors.muted)
    local gradientLow = CH.GeneralColorAt(ctx, appearance, "Low", 12, -220, "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientMid = CH.GeneralColorAt(ctx, appearance, "Mid", 170, -220, "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientHigh = CH.GeneralColorAt(ctx, appearance, "High", 328, -220, "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientReset = CH.ButtonAt(appearance, "Reset gradient", 486, -220, 150, function()
        local g = G()
        g.healthGradientLowR, g.healthGradientLowG, g.healthGradientLowB = 1, 0, 0
        g.healthGradientMidR, g.healthGradientMidG, g.healthGradientMidB = 1, 1, 0
        g.healthGradientHighR, g.healthGradientHighG, g.healthGradientHighB = 0, 1, 0
        ApplyUnitframeColorWithReload()
    end, "appearance.gradient.reset")
    local gradientEditControls = { gradientStrength, gradientStopsLabel, gradientLow, gradientMid, gradientHigh, gradientReset }
    refreshBarModeControls = function()
        local mode = CurrentBarMode()
        local gradientMode = mode == "gradient"
        local gradientEnabled = gradientMode and G().enableHealthGradient ~= false
        SetControlEnabled(unifiedColor, mode == "unified")
        SetControlEnabled(darkColor, mode == "dark")
        SetControlEnabled(healthGradient, gradientMode)
        SetControlsEnabled(gradientEditControls, gradientEnabled)
        if modeRow and modeRow.SetValue then modeRow:SetValue(mode) end
        for i = 1, #BAR_MODE_CARDS do
            if BAR_MODE_CARDS[i].mode == mode and modeDescLabel and modeDescLabel.SetText then
                modeDescLabel:SetText(TrText(BAR_MODE_CARDS[i].desc))
            end
        end
    end
    M.TrackRefresh(ctx, refreshBarModeControls)
    refreshBarModeControls()
end

local function BuildUnitAndNPCColors(ctx, b, CH)
    local unit = b:CollapsibleSection("colors_unit", "Unitframe Colors", 230, false)
    for i = 1, #COLOR_DATA.NPC_ROWS do
        local row = COLOR_DATA.NPC_ROWS[i]
        NPCColorAt(ctx, unit, row, 12, -10 - (i - 1) * 36, ApplyUnitframeColorWithReload)
    end
    local petColor = CH.ApiColorAt(ctx, unit, "Pet Frame Color", 360, -10, "GetPetFrameColor", "SetPetFrameColor", 0, 0.8, 0, ApplyUnitframeColorWithReload)
    local refreshPetColorControl
    local petPlayerClassColor = ValueToggleAt(ctx, unit, "Use player's class color for Pet Frame", 360, -54,
        function() return G().petFrameUsePlayerClassColor == true end,
        function(v)
            G().petFrameUsePlayerClassColor = v and true or false
            M.RequestUnitApply("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
            if refreshPetColorControl then refreshPetColorControl() end
        end,
        Meta("unit.pet.use_player_class_color"))
    refreshPetColorControl = function()
        SetControlEnabled(petColor, G().petFrameUsePlayerClassColor ~= true)
    end
    M.TrackRefresh(ctx, refreshPetColorControl)
    refreshPetColorControl()
    if M.AddTooltip then
        M.AddTooltip(petPlayerClassColor, "Use player's class color for Pet Frame",
            "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", { hook = true })
    end
    ValueToggleAt(ctx, unit, "Friendly NPC class colors on HP bars (Class Color mode only)", 360, -82,
        function() return ApiValue("GetNPCClassColorBar", function() return G().npcClassColorBar == true end) end,
        function(v)
            if not ApiCall("SetNPCClassColorBar", v) then
                G().npcClassColorBar = v and true or false
                ApplyUnitframeColorWithReload()
            end
        end,
        Meta("npc.class_color_bar"))
    CH.ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190,
        ResetUnitframeColors, "unitframe.reset")
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
                if not ok then
                    G()[key] = v and true or false
                    ApplyUnitframeColorWithReload()
                end
            end,
            Meta("npc_type.option." .. tostring(key))))
    end
    AddNPCTypeToggle("Color HP bar (Class Color mode only)", 32, -38, "GetNPCTypeColorBar", "SetNPCTypeColorBar", "npcTypeColorBar")
    AddNPCTypeToggle("Color name text", 32, -62, "GetNPCTypeColorText", "SetNPCTypeColorText", "npcTypeColorText")
    npcMaster = ValueSwitchAt(ctx, npcType, "NPC Type Colors", 12, -10, 260,
        function()
            return ApiValue("GetNPCColorMode", function() return G().npcColorMode end) == "type"
        end,
        function(v)
            if not ApiCall("SetNPCColorMode", v and "type" or "reaction") then
                G().npcColorMode = v and "type" or "reaction"
                ApplyUnitframeColorWithReload()
            end
            RefreshNPCTypeControls(v and true or false)
        end,
        Meta("npc_type.enabled"))
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
    CH.ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190,
        function() ResetNPCColors("ResetNPCTypeColors") end, "npc_type.reset")
    M.TrackRefresh(ctx, RefreshNPCTypeControls)
end

-- Colors that write one shared setting used by unit AND group frames get a
-- small inline tag so the duplication reads as intentional, not as two
-- separate settings.
local function MarkSharedColor(control)
    if not control then return end
    local tag = T.Font(control, "GameFontDisableSmall", TrText("Shared with group frames"), T.colors.muted)
    tag:SetPoint("LEFT", control, "RIGHT", 8, 0)
    control._msuf2SharedColorTag = tag
end
local function BuildBarAndGroupColors(ctx, b, CH, includeGroup)
    local barColors = b:CollapsibleSection("colors_bar_colors", "Bar & Prediction Colors", 280, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    local barColorControls = CH.ApiColorSpecs(ctx, barColors, {
        { "Absorb Bar Color", barLeftX, -38, "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1 },
        { "Heal-Absorb / Negative Heal", barLeftX, -74, "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0 },
        { "Power Bar Background Color", barLeftX, -110, "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0, nil, nil, nil, "powerBg" },
        { "Aggro Border Color", barRightX, -38, "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0 },
    })
    local powerBg = barColorControls.powerBg
    MarkSharedColor(barColorControls.SetAbsorbOverlayColor)
    MarkSharedColor(barColorControls.SetHealAbsorbOverlayColor)
    local healPredictionColor = ColorValueAt(ctx, barColors, "Positive Heal Prediction", barLeftX, -146,
        function() return GeneralRGB("healPredictionColor", 0, 1, 0) end,
        function(r, g, c)
            local general = G()
            general.healPredictionColorR, general.healPredictionColorG, general.healPredictionColorB = r, g, c
            ApplyColors()
        end,
        nil, nil, Meta("prediction.heal_color"), { 0, 1, 0 })
    MarkSharedColor(healPredictionColor)
    ColorValueAt(ctx, barColors, "Health loss glow", barLeftX, -182,
        function() return GeneralRGB("healthLossColor", 1, 0.55, 0.08) end,
        function(r, g, c)
            SetGeneralRGB("healthLossColor", r, g, c)
            ApplyColors()
        end,
        nil, nil, Meta("bar.health_loss_color"), { 1, 0.55, 0.08 })
    ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end,
        nil, nil, Meta("bar.purge_border_color"), { 1.00, 0.85, 0.00 })
    ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return GeneralRGB("barOutlineColor", 0, 0, 0) end,
        function(r, g, c)
            local general = G()
            general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = r, g, c
            general.barOutlineColorA = 1
            general.barOutlineColorMode = nil
            ApplyGlobalOutlineColor()
        end,
        nil, nil, Meta("bar.outline_color"), { 0, 0, 0 })
    local powerBgMatch = ValueToggleAt(ctx, barColors, "Power background matches HP", barRightX, -148,
        function() return ApiValue("GetPowerBarBackgroundMatchHP", function() return G().powerBarBgMatchBarColor == true end) end,
        function(v)
            if not ApiCall("SetPowerBarBackgroundMatchHP", v) then
                G().powerBarBgMatchBarColor = v and true or false
                ApplyColors()
            end
            SetControlEnabled(powerBg, not (v and true or false))
        end,
        Meta("bar.power_background_match_health"))
    ColorValueAt(ctx, barColors, "Power loss glow", barRightX, -182,
        function() return GeneralRGB("powerLossColor", 0.70, 0.90, 1) end,
        function(r, g, c)
            SetGeneralRGB("powerLossColor", r, g, c)
            ApplyColors()
        end,
        nil, nil, Meta("bar.power_loss_color"), { 0.70, 0.90, 1 })
    CH.ButtonAt(barColors, "Reset Bar Colors", barLeftX, -234, 160, function()
        local g = G()
        ClearRGBAs(g, "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor")
        ClearRGB(g, "healPredictionColor")
        ClearRGB(g, "healthLossColor")
        ClearRGB(g, "powerLossColor")
        g.barOutlineColorMode = nil
        ClearRGBs(g, "hlAggroColor", "hlPurgeColor", "aggroBorderColor")
        g.powerBarBgMatchBarColor = nil
        ApplyGlobalOutlineColor()
    end, "bar.reset")
    M.BindGateGroup(ctx, nil, {
        { controls = powerBg, on = function() return not (powerBgMatch:GetChecked() and true or false) end },
    })
    if includeGroup ~= false then CP.BuildGroupFrameColors(ctx, b) end
end

local function BuildCastbarColors(ctx, b, CH)
    local castbar = b:CollapsibleSection("colors_castbar", "Castbar Colors", 580, false)
    local castW = castbar._msuf2Width or ctx.width or 720
    CH.ApiColorSpecs(ctx, castbar, {
        { "Interruptible cast color", 12, -10, "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8 },
        { "Non-interruptible cast color", 12, -46, "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01 },
        { "Interrupt color (all castbars)", 12, -82, "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1.0, 0.82, 0.0 },
        { "Castbar text color", 360, -10, "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1 },
        { "Cast Target Name Color", 360, -118, "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", 1, 1, 1 },
    }, ApplyCastbarColors)
    CH.ApiOrGeneralColorSpecs(ctx, castbar, {
        { "Castbar border color", 360, -46, "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, nil, 1 },
        { "Castbar background color", 360, -82, "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, nil, 0.85 },
    }, ApplyCastbarColors)
    LabelAt(castbar, "Player castbar override", 12, -170, 260, "GameFontNormal", T.colors.text)
    local overrideModeX, overrideModeW = 300, 190
    local overrideColorX = min(max(overrideModeX + overrideModeW + 36, floor(castW * 0.56)), castW - 236)
    local overrideColorLabelW = max(120, min(168, castW - overrideColorX - 76))
    local overrideColorY = -190
    if overrideColorX < overrideModeX + overrideModeW + 24 then
        overrideColorX = overrideModeX
        overrideColorY = -246
        overrideColorLabelW = max(120, min(230, castW - overrideColorX - 76))
    end
    local overrideColor = ColorValueAt(ctx, castbar, "Custom color", overrideColorX, overrideColorY,
        function() return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1) end,
        function(r, g, c)
            if not ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, c) then ApplyCastbarColors() end
        end,
        overrideColorLabelW, nil, Meta("castbar.player_override.custom_color"), { 0, 0.6, 1 })
    local overrideEnable
    local overrideMode = ValueDropdownAt(ctx, castbar, "Mode", overrideModeX, -190, ValueTextPairs "CLASS=Class color|CUSTOM=Custom color", overrideModeW,
        function() return ApiValue("GetPlayerCastbarOverrideMode", function() return G().playerCastbarOverrideMode or "CLASS" end) end,
        function(v)
            if not ApiCall("SetPlayerCastbarOverrideMode", v) then
                G().playerCastbarOverrideMode = v
                ApplyCastbarColors()
            end
            SetControlEnabled(overrideColor, (overrideEnable and overrideEnable:GetChecked() and true or false) and v == "CUSTOM")
        end,
        Meta("castbar.player_override.mode"))
    local function RefreshCastbarOverrideControls(enabled)
        if enabled == nil then enabled = overrideEnable and overrideEnable:GetChecked() and true or false end
        SetControlEnabled(overrideMode, enabled)
        SetControlEnabled(overrideColor, enabled and ((overrideMode.GetValue and overrideMode:GetValue()) == "CUSTOM"))
    end
    overrideEnable = ValueSwitchAt(ctx, castbar, "Player override", 12, -190, 260,
        function() return ApiValue("GetPlayerCastbarOverrideEnabled", function() return G().playerCastbarOverrideEnabled == true end) end,
        function(v)
            if not ApiCall("SetPlayerCastbarOverrideEnabled", v) then
                G().playerCastbarOverrideEnabled = v and true or false
                ApplyCastbarColors()
            end
            RefreshCastbarOverrideControls(v and true or false)
        end,
        Meta("castbar.player_override.enabled"))
    LabelAt(castbar, "Interrupt Ready Indicator", 12, -280, 260, "GameFontNormal", T.colors.text)
    CH.TableColorSpecs(ctx, castbar, G, {
        { "Ready color (kick available)", 12, -310, "kickReadyColor", 0, 1, 0 },
        { "Not ready color (kick on cooldown)", 12, -346, "kickNotReadyColor", 1, 0, 0 },
    }, ApplyCastbarColors)
    CH.ApiColorAt(ctx, castbar, "Unavailable fill color", 12, -382, "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", 1.0, 0.494117647, 0.137254902, ApplyCastbarColors)
    CH.ButtonAt(castbar, "Reset castbar colors", 12, -506, 170, function()
        local apiOwnsRefresh = ApiCall("ResetCastbarTextColorToGlobal")
        apiOwnsRefresh = ApiCall("ResetCastbarTargetNameColor") or apiOwnsRefresh
        apiOwnsRefresh = ApiCall("ResetCastbarBorderColor") or apiOwnsRefresh
        apiOwnsRefresh = ApiCall("ResetCastbarBackgroundColor") or apiOwnsRefresh
        local g = G()
        ClearRGBs(g, "castbarInterruptible", "castbarNonInterruptible", "castbarInterruptFeedback", "castbarInterruptUnavailable")
        ClearRGB(g, "castbarTargetName")
        g.castbarInterruptUnavailableColor = nil
        g.playerCastbarOverrideEnabled = false
        g.playerCastbarOverrideMode = "CLASS"
        ClearRGB(g, "playerCastbarOverride")
        g.kickReadyColor, g.kickNotReadyColor = nil, nil
        if not apiOwnsRefresh then ApplyCastbarColors() end
    end, "castbar.reset")
    M.TrackRefresh(ctx, RefreshCastbarOverrideControls)

    -- Canonical surface for the per-castbar text colors that the Unit > Castbar
    -- cards also expose. One castbar is edited at a time so four units stay
    -- three swatches instead of twelve. An unset detail shows the shared castbar
    -- text color it is currently inheriting; the reset button restores that.
    local detail = b:CollapsibleSection("colors_castbar_text", "Castbar Text Colors", 280, false)
    local detailW = detail._msuf2Width or ctx.width or 720
    local function DetailUnit()
        local value = tostring(M._colorsCastbarDetailUnit or "player")
        if value == "target" or value == "focus" or value == "boss" then return value end
        return "player"
    end
    local function DetailRGB(suffix)
        local read = _G.MSUF_GetCastbarDetailTextColor
        if type(read) == "function" then
            local r, g, bcol, custom = read(DetailUnit(), suffix)
            if custom == true then return r, g, bcol end
        end
        return ApiRGB("GetCastbarTextColor", 1, 1, 1)
    end
    local function SetDetailRGB(suffix, r, g, bcol)
        local write = _G.MSUF_SetCastbarDetailTextColor
        if type(write) == "function" then write(DetailUnit(), suffix, r, g, bcol) end
        ApplyCastbarColors()
    end
    LabelAt(detail, "Each castbar text can override the shared castbar text color. Target text exists on Target and Focus only.",
        12, -8, detailW - 28, "GameFontHighlightSmall", T.colors.muted)
    local detailUnitDropdown = ValueDropdownAt(ctx, detail, "Editing:", 12, -44,
        ValueTextPairs "player=Player|target=Target|focus=Focus|boss=Boss", min(260, detailW - 32),
        DetailUnit,
        function(value)
            M._colorsCastbarDetailUnit = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "castbar-text-color-unit") elseif M.Refresh then M.Refresh(ctx) end
        end,
        Meta("castbar.text_color.unit", "ephemeral"))
    RegisterControl(detailUnitDropdown, Meta("castbar.text_color.unit", "ephemeral"), "Editing:", "dropdown")
    ColorValueAt(ctx, detail, "Spell text color", 12, -100,
        function() return DetailRGB("SpellName") end,
        function(r, g, bcol) SetDetailRGB("SpellName", r, g, bcol) end,
        nil, nil, Meta("castbar.text_color.spell_name"))
    ColorValueAt(ctx, detail, "Cast time color", 12, -136,
        function() return DetailRGB("Time") end,
        function(r, g, bcol) SetDetailRGB("Time", r, g, bcol) end,
        nil, nil, Meta("castbar.text_color.time"))
    local detailTargetColor = ColorValueAt(ctx, detail, "Target text color", 12, -172,
        function() return DetailRGB("TargetName") end,
        function(r, g, bcol) SetDetailRGB("TargetName", r, g, bcol) end,
        nil, nil, Meta("castbar.text_color.target_name"))
    CH.ButtonAt(detail, "Follow shared color", 12, -218, 190, function()
        local reset = _G.MSUF_ResetCastbarDetailTextColor
        if type(reset) ~= "function" then return end
        local castUnit = DetailUnit()
        reset(castUnit, "SpellName")
        reset(castUnit, "Time")
        reset(castUnit, "TargetName")
        ApplyCastbarColors()
    end, "castbar.text_color.reset")
    M.TrackRefresh(ctx, function()
        SetControlEnabled(detailTargetColor, DetailUnit() == "target" or DetailUnit() == "focus")
    end)
end

local function BuildHighlightAndGameplayColors(ctx, b, CH, part)
    if part ~= "gameplay" then
    local highlight = b:CollapsibleSection("colors_highlight", "Highlight Colors", 154, false)
    ColorValueAt(ctx, highlight, "Mouseover highlight color", 12, -10, HighlightRGB, SetHighlightRGB,
        nil, nil, Meta("highlight.mouseover.color"), { 1, 1, 1 })
    CH.TableColorAt(ctx, highlight, "Boss target highlight color", 12, -66, G, "bossTargetHighlightColor", 1, 0.82, 0, ApplyBossTargetHighlightColor)
    -- Texture layers: each slot's swatch pair writes the general baseline plus
    -- every unit's per-frame copy (portrait pattern); the unit accordions link
    -- here via context color references instead of hosting swatches.
    local texLayer = b:CollapsibleSection("colors_texture_layer", "Texture Layer Colors", 340, false)
    for texIndex, texSlot in ipairs({
        { id = "texture_layer", prefix = "texLayer", suffix = "" },
        { id = "texture_layer2", prefix = "texLayer2", suffix = " 2" },
        { id = "texture_layer3", prefix = "texLayer3", suffix = " 3" },
    }) do
        local rowY = -10 - (texIndex - 1) * 108
        local slotPrefix = texSlot.prefix
        ColorValueAt(ctx, texLayer, M.Tr("Texture layer color") .. texSlot.suffix, 12, rowY,
            function() return GeneralRGB(slotPrefix .. "Color", 1, 1, 1) end,
            function(r, g, c) M._SetAllTextureLayerRGB(slotPrefix .. "Color", r, g, c) end,
            nil, nil, Meta(texSlot.id .. ".color"), { 1, 1, 1 })
        ColorValueAt(ctx, texLayer, M.Tr("Texture layer gradient end") .. texSlot.suffix, 12, rowY - 36,
            function() return GeneralRGB(slotPrefix .. "Gradient2", 0, 0, 0) end,
            function(r, g, c) M._SetAllTextureLayerRGB(slotPrefix .. "Gradient2", r, g, c) end,
            nil, nil, Meta(texSlot.id .. ".gradient_color"), { 0, 0, 0 })
    end
    end
    if part == "highlight" then return end
    local gameplay = b:CollapsibleSection("colors_gameplay", "Combat Feedback", 310, false)
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
        end,
        nil, nil, Meta("gameplay.combat_enter_color"), { 1, 1, 1 })
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
    end,
    Meta("gameplay.combat_state_color_sync"))
    MoveWidget(sync, gameplay, 360, -82)
    CH.ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor = { 1, 1, 1 }
        gp.combatStateEnterColor = { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor = { 0, 1, 0 }
        gp.crosshairOutRangeColor = { 1, 0, 0 }
        ApplyGameplayColors()
    end, "gameplay.reset")
    M.BindGateGroup(ctx, nil, {
        { controls = leaveColor, on = function() return not (Gameplay().combatStateColorSync == true) end },
    })
end

-- The painter paints through the real bound controls of the sections below
-- (each section's color-context owner list), so every color has exactly one
-- source of truth. This shared spec drives the painter tabs, the description
-- line under them AND the headline above the filtered section list, so users
-- see that one tab controls both.
local COLOR_PAINTER_CATEGORIES = {
    { key = "unit", title = "Player & Target Frames", shortTitle = "Player & Target",
        subtitle = "Bars, text, portraits, NPC colors and combat feedback for unit frames.",
        pickerNote = "HP, name and power text share Font Coloring and remain editable here." },
    { key = "group", title = "Party & Raid Frames", shortTitle = "Party & Raid",
        subtitle = "Shared by Party, Raid and Mythic Raid.",
        pickerNote = "Shared by Party, Raid and Mythic Raid." },
    { key = "cast", title = "Castbars", shortTitle = "Castbar",
        subtitle = "Interrupt states, text, border and kick feedback.",
        pickerNote = "Cast states, feedback, text, border and background." },
    { key = "auras", title = "Auras & Icons", shortTitle = "Auras",
        subtitle = "Cooldown timer urgency, global Dispel types, icon borders and shadows.",
        pickerNote = "Safe, Warning, Urgent, Magic, Curse, Disease, Poison, Bleed, icon border and icon shadow." },
    { key = "resources", title = "Power & Class Resources", shortTitle = "Resources",
        subtitle = "Power bar colors and Class Resource colors (combo points, holy power, ...).",
        pickerNote = "Power and Class Resource colors." },
}
local function BuildColorPainter(ctx, b)
    local painter = M.ColorPainter
    if not (painter and type(painter.Build) == "function") then return end
    M.colorsPowerToken = M.colorsPowerToken or "MANA"
    M.colorsCPToken = M.colorsCPToken or "COMBO_POINTS"
    painter.Build(ctx, b, COLOR_PAINTER_CATEGORIES)
end

-- One taxonomy: the painter tabs above decide which category of sections is
-- visible below the preview. Every legacy section id survives unchanged inside
-- its category, so search keywords, Assistant metadata and cross-page focus
-- requests keep working. Categories build lazily on first activation; hidden
-- (coverage/audit) builds materialize everything, matching the old groups.
local COLOR_CATEGORY_ORDER = { "unit", "group", "cast", "auras", "resources" }
local COLOR_CATEGORY_SECTIONS = {
    unit = { "colors_appearance", "colors_bar_colors", "colors_bar_gradients", "colors_background",
        "colors_font", "colors_classes", "colors_unit", "colors_npc_type", "colors_highlight",
        "colors_texture_layer", "colors_gameplay", "colors_portrait", "colors_status_text" },
    group = { "colors_group_frames", "colors_group_frames_background", "colors_group_frames_state", "colors_group_frames_highlights" },
    cast = { "colors_castbar", "colors_castbar_text" },
    auras = { "colors_auras" },
    resources = { "colors_power", "colors_class_power" },
}
local COLOR_SECTION_CATEGORY = {}
for categoryKey, sectionIds in pairs(COLOR_CATEGORY_SECTIONS) do
    for i = 1, #sectionIds do COLOR_SECTION_CATEGORY[sectionIds[i]] = categoryKey end
end

-- A category builder may return a continuation function (which may return
-- another one): EnsureCategoryBuilt runs the first slice synchronously and the
-- continuations on following short ticks. The unit category is the default
-- Colors entry view and was the single largest chunk of the entry frame; its
-- later stages hold only default-collapsed sections, so they can fill in
-- below the visible content without moving anything the user already sees.
local COLOR_CATEGORY_BUILDERS = {
    unit = function(ctx, inner, CH)
        BuildBackgroundAndAppearance(ctx, inner, CH, "appearance")
        BuildBarAndGroupColors(ctx, inner, CH, false)
        BuildBarGradientColors(ctx, inner, CH)
        return function()
            BuildBackgroundAndAppearance(ctx, inner, CH, "background")
            BuildFontAndClassColors(ctx, inner, CH)
            return function()
                BuildUnitAndNPCColors(ctx, inner, CH)
                BuildHighlightAndGameplayColors(ctx, inner, CH)
                BuildAuraAndPortraitColors(ctx, inner, CH, "portrait")
            end
        end
    end,
    group = function(ctx, inner)
        CP.BuildGroupFrameColors(ctx, inner)
    end,
    cast = function(ctx, inner, CH)
        BuildCastbarColors(ctx, inner, CH)
    end,
    auras = function(ctx, inner, CH)
        BuildAuraAndPortraitColors(ctx, inner, CH, "auras")
    end,
    resources = function(ctx, inner, CH)
        CP.BuildPowerAndClassPowerColors(ctx, inner, CH)
    end,
}

local function PendingColorFocusCategory(ctx)
    local request = _G.MSUF_EM2_MenuFocusRequest
    if type(request) ~= "table" or request.explicit ~= true or request.consumed == true then return nil end
    if request.pageKey and tostring(request.pageKey) ~= tostring(ctx and ctx.key or "") then return nil end
    return COLOR_SECTION_CATEGORY[tostring(request.sectionId or "")]
end

local function BuildColors(ctx)
    if ctx and ctx.wrapper then ctx.wrapper._msuf2SuppressContextColorShortcuts = true end
    local b, CH = W.PageBuilder(ctx), COLOR_HELPERS
    -- Painter callbacks from a previous build of this page must never fire
    -- into stale closures while this build is in progress.
    M.ColorsOnPainterCategory = nil
    M.ColorsSetPainterCategory = nil
    M.ColorsEnsureCategoryBuilt = nil
    if ctx and ctx.entry then ctx.entry._msuf2HealthBackgroundInlinePreviewRefresh = nil end
    b:GlobalStyleHeader("Colors", "Frame, group-frame, bar, aura, castbar and resource colors.", 72)
    BuildColorPainter(ctx, b)

    if not b._collapsibleStartY then b._collapsibleStartY = b.y end
    local host = CreateFrame("Frame", nil, b.parent)
    host:SetSize(b.width, 1)
    host:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    local hostEntry = { kind = "section", frame = host, height = 1, gap = 12 }
    b.layoutEntries[#b.layoutEntries + 1] = hostEntry
    b.y = b.y - 1 - 12

    local categories = {}
    for i = 1, #COLOR_CATEGORY_ORDER do
        local categoryKey = COLOR_CATEGORY_ORDER[i]
        local container = CreateFrame("Frame", nil, host)
        container:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        container:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        container:SetHeight(1)
        container:Hide()
        categories[categoryKey] = { key = categoryKey, container = container, height = 1 }
    end

    local activeKey
    local function UpdateHostHeight()
        local active = categories[activeKey]
        local height = max(1, tonumber(active and active.height) or 1)
        hostEntry.height = height
        if host:GetHeight() ~= height then host:SetHeight(height) end
        b:RequestRelayoutCollapsibles()
    end
    local ActivateCategory
    local function EnsureCategoryBuilt(categoryKey)
        local category = categories[categoryKey]
        if not category or category.built then return category end
        if category.building then
            local resume = category.resumeStage
            if resume then
                category.resumeStage = nil
                resume()
            end
            return category
        end
        category.building = true
        local refreshers = ctx and ctx.refreshers
        local inner = W.PageBuilder(ctx, {
            parent = category.container,
            width = b.width,
            contentX = 0,
            topInset = 0,
            onContentHeight = function(height)
                height = max(1, tonumber(height) or 1)
                if category.height == height then return end
                category.height = height
                if activeKey == categoryKey then UpdateHostHeight() end
            end,
        })
        local function FinishCategoryBuild()
            category.built = true
            category.building = nil
            for i = 1, #inner.collapsibles do
                local sectionEntry = inner.collapsibles[i]
                sectionEntry._msuf2EnsureVisible = function()
                    if type(M.ColorsSetPainterCategory) == "function" then
                        M.ColorsSetPainterCategory(categoryKey)
                    elseif ActivateCategory then
                        ActivateCategory(categoryKey)
                    end
                end
            end
        end
        -- A builder may return a continuation (which may return another one):
        -- later stages run on short ticks so the entry frame only pays for the
        -- first slice. Without a timer every stage runs inline, so tests and
        -- degraded clients keep the old fully synchronous behavior.
        local function RunCategoryStage(stage)
            local refreshStart = type(refreshers) == "table" and #refreshers or 0
            local wasBuilding = ctx and ctx._msuf2Building
            if ctx then ctx._msuf2Building = true end
            local entry = ctx.entry
            local wasIncomplete = entry._msuf2BuildIncomplete
            entry._msuf2BuildIncomplete = true
            local nextStage = stage(ctx, inner, CH)
            entry._msuf2BuildIncomplete = wasIncomplete
            if ctx then ctx._msuf2Building = wasBuilding end

            inner:RelayoutCollapsibles()
            if not wasBuilding and type(refreshers) == "table" then
                for i = refreshStart + 1, #refreshers do
                    local refresh = refreshers[i]
                    if type(refresh) == "function" then refresh() end
                end
                -- The current outer relayout reads the updated host height after
                -- this callback, so its pending marker has already been satisfied.
                b._msuf2RelayoutPending = nil
            end
            if type(nextStage) == "function" then
                if C_Timer and type(C_Timer.After) == "function" then
                    -- Combat quiescence may cancel the tracked timer; the
                    -- resume hook lets the next EnsureCategoryBuilt call pick
                    -- the build back up instead of leaving it half-finished.
                    category.resumeStage = function() RunCategoryStage(nextStage) end
                    C_Timer.After(0.02, function()
                        if categories[categoryKey] ~= category or category.resumeStage == nil then return end
                        category.resumeStage = nil
                        RunCategoryStage(nextStage)
                    end)
                    return
                end
                return RunCategoryStage(nextStage)
            end
            FinishCategoryBuild()
        end
        RunCategoryStage(COLOR_CATEGORY_BUILDERS[categoryKey])
        return category
    end
    ActivateCategory = function(categoryKey)
        if not categories[categoryKey] then categoryKey = COLOR_CATEGORY_ORDER[1] end
        EnsureCategoryBuilt(categoryKey)
        activeKey = categoryKey
        -- Cached page/search/pin lifecycles can leave a locally hidden active
        -- container behind.  Reconcile every time, including same-category
        -- activation, instead of relying on the key having changed.
        if host.Show then host:Show() end
        for key, category in pairs(categories) do
            category.container:SetShown(key == categoryKey)
        end
        UpdateHostHeight()
    end
    M.ColorsOnPainterCategory = ActivateCategory
    M.ColorsEnsureCategoryBuilt = function(sectionId)
        local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
        if categoryKey then EnsureCategoryBuilt(categoryKey) end
    end
    if ctx.entry then
        ctx.entry._msuf2ResolveMissingSection = function(sectionId)
            local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
            if not categoryKey then return nil end
            if type(M.ColorsSetPainterCategory) == "function" then
                M.ColorsSetPainterCategory(categoryKey)
            else
                ActivateCategory(categoryKey)
            end
            local sections = ctx.entry.sections
            return sections and sections[tostring(sectionId)]
        end
    end
    if ctx.hiddenBuild then
        for i = 1, #COLOR_CATEGORY_ORDER do EnsureCategoryBuilt(COLOR_CATEGORY_ORDER[i]) end
    end
    local initialKey = PendingColorFocusCategory(ctx)
    if not initialKey then
        local persisted = M.colorsPainterCategory
        initialKey = categories[persisted] and persisted or COLOR_CATEGORY_ORDER[1]
    end
    if type(M.ColorsSetPainterCategory) == "function" then
        M.ColorsSetPainterCategory(initialKey)
    end
    ActivateCategory(initialKey)
    b:RelayoutCollapsibles()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_colors", { title = "MSUF Colors", build = BuildColors, version = 23 })
-- Helpers the sibling files (Group, Resources, Context) pick from M.ColorsPage
-- when they load right after this page.
CP.CurrentApplyService = CurrentApplyService
CP.RequestGeneral = RequestGeneral
CP.ApplyColors = ApplyColors
CP.ApplyUnitframeColorWithReload = ApplyUnitframeColorWithReload
CP.ApplyCastbarColors = ApplyCastbarColors
CP.ApplyBossTargetHighlightColor = ApplyBossTargetHighlightColor
CP.ApplyGameplayColors = ApplyGameplayColors
CP.ApplyAuraColors = ApplyAuraColors
CP.ApplyScopedBarGradientColors = ApplyScopedBarGradientColors
CP.ApplyGlobalOutlineColor = ApplyGlobalOutlineColor
CP.ColorAPI = ColorAPI
CP.ApiCall = ApiCall
CP.ApiRGB = ApiRGB
CP.ApiSetRGB = ApiSetRGB
CP.GeneralRGB = GeneralRGB
CP.SetGeneralRGB = SetGeneralRGB
CP.GeneralRGBAlias = GeneralRGBAlias
CP.SetGeneralRGBAlias = SetGeneralRGBAlias
CP.TableRGB = TableRGB
CP.SetTableRGB = SetTableRGB
CP.HighlightRGB = HighlightRGB
CP.SetHighlightRGB = SetHighlightRGB
CP.ColorValueAt = ColorValueAt
CP.ClassDefaultRGB = ClassDefaultRGB
CP.ClassColorRGB = ClassColorRGB
CP.SetAllPortraitRGB = SetAllPortraitRGB
CP.COLOR_DATA = COLOR_DATA
CP.COLOR_POWER_TOKENS = COLOR_POWER_TOKENS
CP.COLOR_CP_TOKENS = COLOR_CP_TOKENS
CP.COLOR_PAINTER_CATEGORIES = COLOR_PAINTER_CATEGORIES
