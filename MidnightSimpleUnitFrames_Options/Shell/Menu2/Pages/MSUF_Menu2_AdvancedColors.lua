local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"
local PixelLayoutRegion = MSUF.Require("MSUF_PixelLayoutRegion", FILE)
-- Core functions this page calls by their global names: required here at
-- load, resolved at use time so a hook installed on one later still applies.
M.RequireGlobals(FILE, {
    "MSUF_GetBarTexture",
    "MSUF_GetBarBackgroundTexture",
})
local EnsureDB = M.EnsureDB

-- Advanced Colors page.
-- Binds global color palettes, class/power overrides, aura colors, and border colors. Color
-- apply is coalesced because one edit may need to refresh several frame families.
local W = M.Widgets
local T = M.Theme
local Schema = M.ControlSchema
local AP = M.AdvancedPage or {}
local GP = M.GlobalPage or {}
local C_Timer = M.MenuTimer or C_Timer
local floor = math.floor
local max = math.max
local min = math.min
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DB, G, Gameplay = AP.DB, AP.G, AP.Gameplay
local ApplyAuras, MoveWidget, LabelAt, SwitchAt = AP.ApplyAuras, AP.MoveWidget, AP.LabelAt, AP.SwitchAt
local ValueToggleAt, ValueSwitchAt, SliderAt, ValueSliderAt, ValueDropdownAt =
    AP.ValueToggleAt, AP.ValueSwitchAt, AP.SliderAt, AP.ValueSliderAt, AP.ValueDropdownAt
local SetControlEnabled, RegisterControl = AP.SetControlEnabled, AP.RegisterControl
local CurrentBarsScope, NormalizeScopeKey, ScopeHasOverride, GradientScopeGet, GradientScopeSet =
    GP.CurrentBarsScope, GP.NormalizeScopeKey, GP.ScopeHasOverride, GP.GradientScopeGet, GP.GradientScopeSet
local function ReadNameColor()
    local g = G()
    return tonumber(g.nameColorR) or 1, tonumber(g.nameColorG) or 1, tonumber(g.nameColorB) or 1
end
local function TrText(text)
    local translate = M.TranslateText or M.Tr
    if type(translate) == "function" then return translate(text) end
    return text
end

local CP = M.ColorsPage or {}
M.ColorsPage = CP
-- Search metadata (Meta) comes from the MSUF_Menu2_AdvancedColors_Meta.lua
-- sibling that loads right before this page; the Group, Resources and Context
-- siblings that load right after it pick the helpers published at the bottom.
local Meta = CP.Meta
local Req, Opt = CP.Req, CP.Opt
local ColorRows, KeyLabelMap, ValueTextPairs, SetControlsEnabled = M.ColorRows, M.KeyLabelMap, M.ValueTextPairs, W.SetControlsEnabled
local ColorValueAt

local function CurrentApplyService()
    return M.ApplyService or Opt.MSUF_Menu2_ApplyService
end

local function RequestGeneral(reason, opts)
    if type(M.RequestGeneralDomains) == "function" then
        return M.RequestGeneralDomains(reason, opts)
    end
    local apply = CurrentApplyService()
    if apply and type(apply.RequestGeneral) == "function" then
        return apply.RequestGeneralDomains(reason, opts)
    end
    return false
end

local function ApplyColors()
    -- The painter's Resources strip paints straight from these DB values and
    -- has no writer of its own, so both apply paths poke it. Kept inline: this
    -- file's main chunk holds 160 of Lua 5.1's 200 locals.
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
-- The threat colors live in the threat module's own curve, which only its element
-- apply re-reads, so a curve edit also re-applies that one element on every frame.
function M._ApplyThreatCurveColors()
    ApplyColors()
    local refresh = Opt.MSUF_RequestThreatIndicatorRefresh
    if type(refresh) == "function" then refresh(nil, "MSUF2_THREAT_CURVE_COLORS") end
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
    M.RequestGeneralDomains("MSUF2_CASTBAR_COLORS", { castbar = true, castbarTextures = true, preview = true, applyAll = false })
end
local function ApplyBossTargetHighlightColor()
    local reason = "MSUF2_BOSS_TARGET_HIGHLIGHT_COLOR"
    local apply = CurrentApplyService()
    if apply and type(apply.RequestBossTargetBorder) == "function" then
        return apply.RequestBossTargetBorder(reason, "boss")
    end
    Req.MSUF_UFCore_RefreshSettingsCache(reason)
    if apply and type(apply.RequestUnit) == "function" then
        return apply.RequestUnitDomains("boss", reason, { preview = true })
    end
    return true, Req.MSUF_UFCore_NotifyConfigChanged("boss", true, true, reason)
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
    Req.MSUF_GF_ForceAuraTextColorRefresh()
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
    if useOverride ~= false and M._DispelTypeColorSpec(dispelType) then
        local general = DB().general
        local overrides = general and general.dispelTypeColorOverrides
        local r, g, b = CP.TableRGB(type(overrides) == "table" and overrides or nil, dispelType)
        if r then return max(0, min(1, r)), max(0, min(1, g)), max(0, min(1, b)) end
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
        return apply.RequestGeneralDomains(reason, { preview = true, applyAll = true, colors = true })
    end
    Req.MSUF_UFCore_NotifyConfigChanged(nil, true, true, reason)
    Req.MSUF_UFPreview_RequestRefresh(reason)
end
-- Resource editors list only what this client can show; Mists adds three resources of its own.
local function ClientResourceTokens(tokens)
    local client = MSUF.Client
    if not (client and client.SupportsClassResource) then return tokens end
    if client.IsMists then
        for _, item in ipairs(ValueTextPairs "SHADOW_ORBS=Shadow Orbs|BURNING_EMBERS=Burning Embers|DEMONIC_FURY=Demonic Fury") do
            tokens[#tokens + 1] = item
        end
    end
    local supported = {}
    for _, item in ipairs(tokens) do
        if client.SupportsClassResource(item.value) then supported[#supported + 1] = item end
    end
    return supported
end
local COLOR_DATA = {
    CLASS_TOKENS = M.WordList [[WARRIOR PALADIN HUNTER ROGUE PRIEST DEATHKNIGHT SHAMAN MAGE WARLOCK MONK DRUID DEMONHUNTER EVOKER]],
    CLASS_LABELS = KeyLabelMap("WARRIOR=Warrior|PALADIN=Paladin|HUNTER=Hunter|ROGUE=Rogue|PRIEST=Priest|DEATHKNIGHT=Death Knight|SHAMAN=Shaman|MAGE=Mage|"
        .. "WARLOCK=Warlock|MONK=Monk|DRUID=Druid|DEMONHUNTER=Demon Hunter|EVOKER=Evoker"),
    NPC_ROWS = ColorRows("friendly|Friendly NPC Color|0|1|0;neutral|Neutral NPC Color|1|1|0;enemy|Enemy NPC Color|0.85|0.10|0.10;"
        .. "dead|Dead NPC Color|0.40|0.40|0.40"),
    NPC_TYPE_ROWS = ColorRows("npcBoss|Boss|0.74|0.11|0;npcMiniboss|Miniboss / Lieutenant|0.56|0|0.74;npcCaster|Caster|0|0.45|0.74;"
        .. "npcMelee|Melee|0.99|0.99|0.99;npcRegular|Regular|0.70|0.56|0.33"),
    POWER_TOKENS = ValueTextPairs("MANA=Mana|RAGE=Rage|ENERGY=Energy|FOCUS=Focus|RUNIC_POWER=Runic Power|INSANITY=Insanity|FURY=Fury|PAIN=Pain|"
        .. "ESSENCE=Essence|LUNAR_POWER=Astral Power|MAELSTROM=Maelstrom"),
    CP_TOKENS = ClientResourceTokens(ValueTextPairs("COMBO_POINTS=Combo Points|HOLY_POWER=Holy Power|SOUL_SHARDS=Soul Shards|CHI=Chi|"
        .. "ARCANE_CHARGES=Arcane Charges|RUNES=Runes|ESSENCE=Essence|MANA=Alternative Mana|CHARGED=Empowered / Charged|SOUL_FRAGMENTS=Soul Fragments|"
        .. "SOUL_FRAGMENTS_META=Soul Fragments (Void Meta)|MAELSTROM=Maelstrom Weapon|MAELSTROM_ABOVE_5=Maelstrom Weapon 5+|ASTRAL_POWER=Astral Power|"
        .. "AP_PREDICTION=Astral Prediction|ECLIPSE_SOLAR=Eclipse Solar|ECLIPSE_LUNAR=Eclipse Lunar|ECLIPSE_CA=Celestial Alignment|"
        .. "STAGGER_GREEN=Stagger Light|STAGGER_YELLOW=Stagger Moderate|STAGGER_RED=Stagger Heavy|SOUL_FRAGMENTS_VENG=Soul Fragments (Vengeance)|"
        .. "INSANITY=Insanity|MAELSTROM_POWER=Maelstrom Power|WHIRLWIND=Whirlwind|TIP_OF_THE_SPEAR=Tip of the Spear|ICICLES=Icicles|EBON_MIGHT=Ebon Might|"
        .. "RESOURCE_TEXT=Resource Text")),
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
    if not preview or not preview.surface then return false end
    local _, class = UnitClass("player")
    local frame = preview.surface:Refresh({ hp = preview.healthFraction or .62, class = class })
    if not frame then return false end
    preview.bar, preview.backgroundBar, preview.background = frame.hpBar, frame.healthBackgroundBar, frame.hpBarBG
    local fill, color = M.ColorsBackgroundMode.GetFill(), M.ColorsBackgroundMode.GetColor()
    preview.resolvedFillMode, preview.resolvedColorMode = fill, color
    local fillLabel = fill == "missing" and "Missing health only" or "Full bar"
    local colorLabel = color == "match_health" and "Match health bar" or color == "class" and "Class color"
        or color == "health_gradient" and "Health gradient" or "Custom tint"
    T.SetTranslatedText(preview.mode, M.Tr(fillLabel) .. "  |  " .. M.Tr(colorLabel))
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
    local getter = Opt.MSUF_GetConfiguredFontColor or MSUF.MSUF_GetConfiguredFontColor
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
    local t = type(tbl) == "table" and tbl[key]
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
local function ClearRGBAs(tbl, ...) for i = 1, select("#", ...) do
    local prefix = select(i, ...)
    ClearRGB(tbl, prefix)
    tbl[prefix .. "A"] = nil end
end
local function HighlightRGB()
    local g = G()
    if type(g.highlightColor) == "table" then return TableRGB(g, "highlightColor", 1, 1, 1) end
    -- A named entry of the font color palette (white by default).
    local key, colors = g.highlightColor or "white", Opt.MSUF_FONT_COLORS
    local c = type(colors) == "table" and type(key) == "string" and colors[key:lower()]
    if c then return c[1] or 1, c[2] or 1, c[3] or 1 end
    return 1, 1, 1
end
local function SetHighlightRGB(r, g, b)
    G().highlightColor = { r, g, b }
    ApplyColors()
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
    W.SetCollapsibleBadges(entry.body, count > 0 and {{
        text = tostring(count) .. " " .. TrText("modified"),
        kind = "accent",
        showWhenClosed = true,
    }} or {})
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
        M.AddTooltip(control, control._msuf2ColorLabel,
            "Right-click resets this color to its default.", { hook = true })
    end
    RefreshDot()
end
-- Shared completion keeps default resets, swatch geometry and badges with the
-- existing color owner, after either the legacy or schema typed binding.
function CP.FinishColorRow(ctx, color, section, x, y, labelWidthOverride, swatchWidth, defaultRGB)
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
function ColorValueAt(ctx, section, label, x, y, getRGB, setRGB, labelWidthOverride, swatchWidth, metadata,
    defaultRGB, declaration)
    local color = W.Color(section, label)
    -- Callers that re-declare the swatch through Owned() afterwards pass no declaration.
    declaration = declaration or { scope = "colors", applyDomain = "unitColors", labelKey = label }
    declaration.kind, declaration.id, declaration.meta = "color", metadata.controlId, metadata
    declaration.settingPath = metadata.settingKey
    declaration.customSetReason = declaration.customSetReason or "Writes the RGB/opacity channels and dependent color-mode state together."
    declaration.get, declaration.set = getRGB, setRGB
    Schema.Bind(ctx, color, declaration)
    CP.AttachNativeCastColorState(color, metadata)
    return CP.FinishColorRow(ctx, color, section, x, y, labelWidthOverride, swatchWidth, defaultRGB)
end
function CP.BuildDispelColorControls(ctx, dispel)
    for i = 1, #M.DISPEL_COLOR_SPECS do
        local spec = M.DISPEL_COLOR_SPECS[i]
        local dispelType, y = spec.key, -104 - ((i - 1) * 38)
        local color, custom
        local metadata = Meta("auras.dispel." .. spec.path .. ".enabled")
        custom = Schema.Render(ctx, dispel, {
            kind = "toggle", view = "switch", labelKey = dispelType .. " custom",
            id = metadata.controlId, scope = "general", applyDomain = "auras", meta = metadata,
            get = function() return M._HasDispelTypeColorOverride(dispelType) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(value)
                M._SetDispelTypeColorEnabled(dispelType, value)
                if color then color:SetRGB(M._GetDispelTypeRGB(dispelType, true)) end
            end,
        }, { x = 16, y = y, width = 250 })
        color = ColorValueAt(ctx, dispel, dispelType .. " color", 330, y,
            function() return M._GetDispelTypeRGB(dispelType, true) end,
            function(r, g, blue)
                M._SetDispelTypeRGB(dispelType, r, g, blue)
                if custom then custom:SetChecked(true) end
            end,
            120, 44, Meta("auras.dispel." .. spec.path .. ".color"), nil,
            { scope = "general", applyDomain = "auras" })
    end
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
        ["*"] = function(s, i) return ApiColorAt(ctx, section, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9] or apply, s[10],
            s[11]), s[12] or s[5] or i end,
    })
end
local function BuildTableColorSpecs(ctx, section, getTable, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return TableColorAt(ctx, section, s[1], s[2], s[3], getTable, s[4], s[5], s[6], s[7], s[8] or apply,
            s[9]), s[10] or s[4] or i end,
    })
end
local function BuildApiOrGeneralColorSpecs(ctx, section, specs, apply)
    return M.BuildControlSpecs(specs, {
        ["*"] = function(s, i) return ApiOrGeneralColorAt(ctx, section, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10] or apply,
            s[11]), s[12] or s[6] or i end,
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
    -- stable Search action contract. Keep them menu-executable but exclude
    -- them from automatic Search mutation.
    local classification = (semanticPath == "castbar.text_color.reset" or semanticPath == "status_text.color.reset")
        and "ephemeral" or "action"
    RegisterControl(btn, Meta(semanticPath, classification), label, "button")
    return btn
end
local Card = W.ThemedControlCard
-- Declares a bound control as owned by the Colors page under one apply domain.
local function Owned(control, domain) return Schema.Owned(control, "colors", domain) end
local function ColorsSection(b, id, title, height, open)
    return Schema.Section(b:CollapsibleSection(id, title, height, open), "colors")
end
local Build = {}
-- Only the reaction/type sections use this row policy. Existing API fallbacks,
-- central input/history binding and canonical swatch completion keep their owners.
local UnitColorRows = { bind = function(ctx, control, row, kind)
    local key, defaults = row[2], row[3]
    local function Get()
        if row.get then return row.get() end
        if kind == "color" then
            if row.arg then return ApiRGB(row.apiGet, defaults[1], defaults[2], defaults[3], row.arg) end
            return ApiRGB(row.apiGet, defaults[1], defaults[2], defaults[3])
        end
        return ApiValue(row.apiGet, function() return G()[key] ~= false end, row.arg)
    end
    local function Set(value, green, blue, alpha)
        if row.set then return row.set(value, green, blue, alpha) end
        local ok
        if kind == "color" then
            if row.arg then ok = ApiCall(row.apiSet, row.arg, value, green, blue)
            else ok = ApiCall(row.apiSet, value, green, blue, alpha) end
        elseif row.arg then ok = ApiCall(row.apiSet, row.arg, value)
        else ok = ApiCall(row.apiSet, value) end
        if not ok then
            if kind == "toggle" then G()[key] = value and true or false end
            ApplyUnitframeColorWithReload()
        end
    end
    local meta = Meta(row.path)
    Schema.Bind(ctx, control, { id = meta.controlId, kind = kind, key = key, labelKey = row[4][1],
        scope = "colors", applyDomain = "unitColors", meta = meta, settingPath = meta.settingKey,
        get = Get, set = not row.write and Set or nil, write = row.write,
        customSetReason = row.customSetReason or "Uses the color API or coordinates dependent color fields and runtime refresh." })
    if kind == "color" then
        local p = row.position
        CP.FinishColorRow(ctx, control, control:GetParent(), p[1], p[2], nil, nil, defaults)
    end
end }
local function ResetNPCColors(apiName)
    if ApiCall(apiName) then return end
    DB().npcColors = nil
    ApplyUnitframeColorWithReload()
end
local function ResetUnitframeColors()
    local db = DB()
    local g = G()
    db.npcColors = nil
    g.tapDeniedGray = nil
    ClearRGB(g, "petFrameColor")
    g.petFrameUsePlayerClassColor = nil
    g.npcClassColorBar = nil
    ApplyUnitframeColorWithReload()
end
-- Replacing rows for the remaining shared color styles; exceptional callbacks stay local.
local function SchemaRows(ctx, parent, rows)
    return Schema.Build(ctx, parent, rows, { bind = function(context, control, row, kind)
        local key, default = row[2], row[3]
        local meta = Meta(row.path or "general." .. key)
        local spec = { id = meta.controlId, kind = kind, key = key, labelKey = row[4][1], meta = meta,
            settingPath = meta.settingKey, scope = "colors", applyDomain = row.domain or "unitColors",
            get = row.get, set = row.set, write = row.write,
                customSetReason = row.customSetReason or "Writes color channels and coordinates dependent color modes and runtime state.",
                    source = row.source, apply = row.apply, defaultSource = function() return default end }
        if kind == "color" then
            if not spec.get then spec.get = function()
                if row.source then return TableRGB(row.source(), key, default[1], default[2], default[3]) end
                return GeneralRGB(key, default[1], default[2], default[3])
            end end
            if not spec.set then spec.customSetReason = "Executes the existing composite command, conversion or selection-dependent policy."
    spec.set = function(r, g, b)
                if row.source then SetTableRGB(row.source(), key, r, g, b) else SetGeneralRGB(key, r, g, b) end
                if row.apply then row.apply() else ApplyColors() end
            end end
        end
        Schema.Bind(context, control, spec)
        if kind == "color" then
            local p = row.position
            CP.FinishColorRow(context, control, parent, p[1], p[2], p[3], p[4], default)
        end
    end })
end
local function ClassDefaultRGB(token)
    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if rc then return rc.r, rc.g, rc.b end
    return 1, 1, 1
end
local function ClassColorRGB(token)
    local r, g, b = ClassDefaultRGB(token)
    return ApiRGB("GetClassColor", r, g, b, token)
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
-- Writes one color prefix to the general baseline and to every unit frame copy.
local function SetGeneralAndUnitRGB(prefix, r, g, b)
    local db = DB()
    db.general = db.general or {}
    db.general[prefix .. "R"], db.general[prefix .. "G"], db.general[prefix .. "B"] = r, g, b
    for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget", "boss" }) do
        db[key] = db[key] or {}
        db[key][prefix .. "R"], db[key][prefix .. "G"], db[key][prefix .. "B"] = r, g, b
    end
end
local function SetAllPortraitRGB(prefix, r, g, b)
    SetGeneralAndUnitRGB(prefix, r, g, b)
    ApplyPortraitColors(prefix)
end
--- Texture layer colors mirror the portrait pattern: the Colors page writes the
--- general baseline plus every unit's copy, while the unit accordion edits only
--- its own frame. Refreshes are cold path (one re-stamp per frame). Stored on M
--- instead of file locals: this file's main chunk holds 160 of Lua 5.1's 200 locals.
function M._ApplyTextureLayerColors()
    Req.MSUF_RefreshUnitTextureLayers()
    Req.MSUF_UFPreview_RequestRefresh("MSUF2_TEXLAYER")
end
function M._SetAllTextureLayerRGB(prefix, r, g, b)
    SetGeneralAndUnitRGB(prefix, r, g, b)
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

function Build.Aura(ctx, b)
    local auras = ColorsSection(b, "colors_auras", "Auras", 900, false)
    local w = auras._msuf2Width or b.width or 720
    local colW = max(310, floor((w - 58) / 2))
    local rightX = 24 + colW + 18
    local cooldown = Card(auras, "Cooldown Timer Colors", nil, 24, -42, colW, 380)
    local markers = Card(auras, "Timer Thresholds", nil, rightX, -42, colW, 380)
    cooldown._msuf2ResizeColumn = { left = 24, right = 16, gap = 18, count = 2, index = 1, y = -42, min = 310 }
    markers._msuf2ResizeColumn = { left = 24, right = 16, gap = 18, count = 2, index = 2, y = -42, min = 310 }

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
    local function RefreshTextColors()
        RefreshColorSamples()
        ApplyAuraColors()
    end
    local function AuraColorAt(label, y, key, r, g, bcol)
        return Owned(TableColorAt(ctx, cooldown, label, 16, y, G, key, r, g, bcol, RefreshTextColors, nil, nil,
            Meta("auras.color." .. key)), "auras")
    end
    Owned(ColorValueAt(ctx, cooldown, "Safe", 16, -210, M._ContextGetAuraSafeRGB,
        function(r, g, b)
            M._ContextSetAuraSafeRGB(r, g, b)
            RefreshColorSamples()
        end, nil, nil, Meta("auras.color.aurasCooldownTextSafeColor"), { 1, 1, 1 }), "auras")
    AuraColorAt("Warning", -248, "aurasCooldownTextWarningColor", 1, 0.85, 0.20)
    AuraColorAt("Urgent", -286, "aurasCooldownTextUrgentColor", 1, 0.55, 0.10)
    local function SecondsSlider(label, y, maxValue, key, default, path)
        ValueSliderAt(ctx, markers, label, 16, y, 0, maxValue, 1, colW - 32,
            function() return min(maxValue, max(0, tonumber(G()[key]) or default)) end,
            function(v)
                v = min(maxValue, max(0, tonumber(v) or 0))
                if floor(v) == v then v = floor(v + 0.5) end
                G()[key] = v
                ApplyAuraColors()
            end, Meta(path))
    end
    SecondsSlider("Safe seconds", -72, 600, "aurasCooldownTextSafeSeconds", 60, "auras.cooldown.safe_seconds")
    SecondsSlider("Warning <= sec", -142, 60, "aurasCooldownTextWarningSeconds", 15, "auras.cooldown.warning_seconds")
    SecondsSlider("Urgent <= sec", -212, 30, "aurasCooldownTextUrgentSeconds", 5, "auras.cooldown.urgent_seconds")
    W.Text(markers, "Thresholds choose when Warning and Urgent replace the Safe timer color.", 16, -276, colW - 32, T.colors.muted)
    local dispel = Card(auras, "Dispel Type Colors", nil, 24, -448, w - 48, 310)
    W.Text(dispel, "Optional global overrides for harmful Magic, Curse, Disease, Poison and Bleed indicators. Off uses Blizzard's current default. The last "
        .. "edited type is shown first in every aura preview.", 16, -52, w - 80, T.colors.muted)
    CP.BuildDispelColorControls(ctx, dispel)
    local sharedNote = "Timer and Dispel colors are shared by live unit/group auras and every preview. "
        .. "Icon border and shadow colors live in %s, scoped by Aura type."
    W.Text(auras, M.Format(sharedNote, M.NavPath("auras3_styling")), 24, -786, w - 48, T.colors.muted)
    Owned(ButtonAt(auras, "Reset aura colors", 24, -838, 150, ResetAuraColorSettings, "auras.reset"), "auras")
    M.TrackRefresh(ctx, RefreshColorSamples)
end
function Build.Portrait(ctx, b)
    local portrait = ColorsSection(b, "colors_portrait", "Portrait Colors", 180, false)
    -- Both colors write general and every unit frame (SetAllPortraitRGB): whole-profile undo.
    ColorValueAt(ctx, portrait, "Border custom color", 12, -10,
        function() return GeneralRGB("portraitBorderColor", 1, 1, 1) end,
        function(r, g, c) SetAllPortraitRGB("portraitBorderColor", r, g, c) end,
        nil, nil, Meta("portrait.border_color", nil, { historyScope = false }), { 1, 1, 1 },
        { scope = "colors", applyDomain = "unitColors", labelKey = "Border custom color" })
    ColorValueAt(ctx, portrait, "Background color", 12, -46,
        function() return GeneralRGB("portraitBgColor", 0.05, 0.05, 0.05) end,
        function(r, g, c) SetAllPortraitRGB("portraitBgColor", r, g, c) end,
        nil, nil, Meta("portrait.background_color", nil, { historyScope = false }), { 0.05, 0.05, 0.05 },
        { scope = "colors", applyDomain = "unitColors", labelKey = "Background color" })
    Owned(ButtonAt(portrait, "Reset portrait colors", 12, -118, 170, function()
        SetAllPortraitRGB("portraitBorderColor", 1, 1, 1)
        SetAllPortraitRGB("portraitBgColor", 0.05, 0.05, 0.05)
        G().portraitBorderColorA = 1
        G().portraitBgColorA = 0.85
        ApplyPortraitColors("PORTRAIT_COLOR_RESET")
    end, "portrait.reset"), "unitColors")
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
    MSUF.ExportPublic("MSUF_EM2_MenuFocusRequest", request)
    if type(M.SelectPage) ~= "function" or M.SelectPage("opt_fonts") == false then
        if MSUF.PublicGlobals.MSUF_EM2_MenuFocusRequest == request then MSUF.ExportPublic("MSUF_EM2_MenuFocusRequest", nil) end
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
    if type(UnitClass) == "function" then
        local _, token = UnitClass("player")
        classToken = token
    end
    local r, g, b = ClassColorRGB(classToken or "WARRIOR")
    return { r, g, b }
end
-- Frame and indicator choices for the canonical status text color surface. The
-- indicator value IS the DB key prefix, which keeps this list and the engine's
-- PrefixedStatusDef naming in one piece. Parked on M rather than a file local:
-- the main chunk holds 160 of Lua 5.1's 200 locals.
M._levelDifficultyColor = {
    -- key prefix, label, default RGB, semantic path. Order and defaults mirror
    -- Shared.LEVEL_DIFFICULTY_TIERS in MSUF_UF_Shared.lua.
    { "levelColorImpossible", "Far above / ??", 1.00, 0.10, 0.10, "level_difficulty.impossible" },
    { "levelColorVeryDifficult", "Above your level", 1.00, 0.50, 0.25, "level_difficulty.very_difficult" },
    { "levelColorStandard", "Your level", 1.00, 1.00, 1.00, "level_difficulty.standard" },
    { "levelColorEasy", "Below your level", 0.25, 0.75, 0.25, "level_difficulty.easy" },
    { "levelColorTrivial", "Trivial", 0.50, 0.50, 0.50, "level_difficulty.trivial" },
}
-- Threat % color curve, low to high threat, in the same row shape. Keys and
-- defaults mirror CURVE_STOPS in Game/Shared/UnitFrames/MSUF_UF_ThreatText.lua
-- (threat_text_smoke.lua pins both). Only the clients offering the text list it.
if MSUF.Client.SupportsThreatText == true then
    M._threatCurveColor = {
        { "threatColorLow", "Low threat", 0.30, 0.85, 0.30, "threat.curve.low" },
        { "threatColorMid", "Medium threat", 1.00, 0.82, 0.10, "threat.curve.mid" },
        { "threatColorHigh", "High threat", 1.00, 0.60, 0.60, "threat.curve.high" },
    }
end
M._statusTextColor = {
    units = M.FilterSupportedUnitValues(ValueTextPairs("player=Player|target=Target|focus=Focus|"
        .. "targettarget=Target of Target|focustarget=Focus Target|pet=Pet|pettarget=Pet Target|boss=Boss Frames|arena=Arena Frames")),
    indicators = ValueTextPairs("levelIndicator=Level Text|raceIndicator=Race Text|classTextIndicator=Class Text|raidGroupName=Raid Group|"
        .. "statusText=Dead / Offline Text|statusGhostText=Ghost Text|statusAFKText=AFK Text|statusDNDText=DND Text"),
    unitKeys = {},
    prefixKeys = {},
}
-- The threat text's own color, used while it does not follow the threat colors.
if M._threatCurveColor then
    local indicators = M._statusTextColor.indicators
    indicators[#indicators + 1] = { value = "threatIndicator", text = "Threat %" }
end
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
        { value = "NPC", text = "NPC / Reaction Color", swatchColor = function()
            local r, g, b = ApiRGB("GetNPCColor", 0.85, 0.10, 0.10, "enemy")
            return { r, g, b }
        end },
        { value = "CLASS", text = "Class Color (Reaction fallback)", swatchColor = PlayerClassSwatch },
    },
    health = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "CLASS", text = "Class Color", swatchColor = PlayerClassSwatch },
        { value = "HEALTH", text = "Health Gradient", swatchColor = function() return { 1, 0.7, 0 } end },
    },
    power = {
        { value = "DEFAULT", text = "Default (Font Color)", swatchColor = FontColorSwatch },
        { value = "RESOURCE", text = "By Power Type", swatchColor = function()
            local token
            if type(UnitPowerType) == "function" then
                local _, powerToken = UnitPowerType("player")
                token = powerToken
            end
            local r, g, b = CP.GetPowerOverrideRGB(token and token ~= "" and token or "MANA")
            return { r, g, b }
        end },
    },
}
local function ApplySharedFontTextColors(reason)
    local apply = CurrentApplyService()
    if apply and type(apply.RequestFonts) == "function" then
        return apply.RequestFonts(reason or "MSUF2_COLORS_TEXT_MODES", "shared")
    end
    return RequestGeneral(reason or "MSUF2_COLORS_TEXT_MODES", { preview = true, applyAll = true })
end
function Build.Font(ctx, b)
    local font = ColorsSection(b, "colors_font", "Text Colors", 296, false)
    local fontW = font._msuf2Width or ctx.width or 720
    Owned(ApiColorAt(ctx, font, "Global font color", 12, -10, "GetGlobalFontColor", "SetGlobalFontColor", 1, 1, 1), "fontColors")
    Owned(ButtonAt(font, "Use font palette", 360, -10, 170, function()
        if not ApiCall("ResetGlobalFontToPalette") then
            G().useCustomFontColor = false
            ClearRGB(G(), "fontColorCustom")
            ApplyColors()
        end
    end, "font.use_palette"), "fontColors")
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
        for _, row in ipairs({
            { nameModeDropdown, "Player Name Color",
                "Name color for player characters on ALL frames - target, focus, party and raid included. NPC names use the setting next to this one." },
            { npcModeDropdown, "NPC / Boss Name Color", "Name color for NPCs and bosses on all frames that follow the shared text settings." },
            { hpModeDropdown, "HP Text Color", "HP text color mode for all frames that follow the shared text settings." },
            { powerModeDropdown, "Power Text Color", "Power text color mode for all frames that follow the shared text settings." },
        }) do M.AddTooltip(row[1], TrText(row[2]), TrText(row[3]), { hook = true }) end
    end
    local nameCustomColor = SchemaRows(ctx, font, { { "color", "nameCustom", { 1, 1, 1 }, { "Custom name color" },
        path = "font.name_custom.color", domain = "fontColors", position = { 12, -166 }, get = ReadNameColor,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(r, g2, b2)
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
    } }).nameCustom
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
    Owned(openFonts, "fontColors")
end
-- Canonical surface for the per-indicator status text colors. Unit > Status
-- reaches the same three keys through its ::: text shortcut only; it no longer
-- carries a swatch of its own. Frame and indicator are picked one at a time so
-- the eight indicators across seven frames stay a single swatch. An indicator
-- with no stored color shows the font color it currently inherits.
function Build.StatusText(ctx, b)
    local statusText = Schema.Section(
        b:CollapsibleSection("colors_status_text", "Status Text Colors", M._threatCurveColor and 550 or 410, false), "colors")
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
        if type(conf) ~= "table" then
            conf = {}
            db[key] = conf
        end
        return conf
    end
    local function ApplyStatusTextColors()
        M.RequestGeneralDomains("MSUF2_STATUS_TEXT_COLOR", { preview = true, applyAll = false, colors = true, colorScope = StatusTextUnit() })
    end
    LabelAt(statusText, "Color for a single text indicator on one frame. Unset indicators follow that frame's font color.",
        12, -8, statusTextW - 28, "GameFontHighlightSmall", T.colors.muted)
    -- The picked frame / indicator live on M; each pick refreshes the swatch below.
    local function StatusPicker(label, y, values, get, field, reason, path)
        local dropdown = ValueDropdownAt(ctx, statusText, label, 12, y, values, min(260, statusTextW - 32), get,
            function(value)
                M[field] = value
                if M.RequestRefresh then M.RequestRefresh(ctx, reason) elseif M.Refresh then M.Refresh(ctx) end
            end,
            Meta(path, "ephemeral"))
        RegisterControl(dropdown, Meta(path, "ephemeral"), label, "dropdown", values)
    end
    StatusPicker("Frame", -44, M._statusTextColor.units, StatusTextUnit, "_colorsStatusTextUnit",
        "status-text-color-unit", "status_text.color.unit")
    StatusPicker("Indicator", -100, M._statusTextColor.indicators, StatusTextPrefix, "_colorsStatusTextIndicator",
        "status-text-color-indicator", "status_text.color.indicator")
    SchemaRows(ctx, statusText, { { "color", "statusText", nil, { "Text color" },
        path = "status_text.color.value", domain = "fontColors", position = { 12, -156 },
        get = function()
            local conf, prefix = StatusTextConf(), StatusTextPrefix()
            local r = tonumber(conf[prefix .. "ColorR"])
            local g = tonumber(conf[prefix .. "ColorG"])
            local bcol = tonumber(conf[prefix .. "ColorB"])
            if r and g and bcol then return r, g, bcol end
            return M._ContextConfiguredGlobalFontRGB()
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(r, g, bcol)
            local conf, prefix = StatusTextConf(), StatusTextPrefix()
            conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = r, g, bcol
            ApplyStatusTextColors()
        end,
    } })
    Owned(ButtonAt(statusText, "Follow font color", 12, -196, 190, function()
        local conf, prefix = StatusTextConf(), StatusTextPrefix()
        conf[prefix .. "ColorR"], conf[prefix .. "ColorG"], conf[prefix .. "ColorB"] = nil, nil, nil
        ApplyStatusTextColors()
    end, "status_text.color.reset"), "fontColors")
    -- Level difficulty palette. Global on purpose: the bands mean the same on
    -- every unit and group frame, and each frame only decides whether to use
    -- them (Status icons > Level Text > Color by level difficulty). Rows come
    -- from M._levelDifficultyColor, which is parked on M instead of a file local.
    -- No reset button: right-click on a swatch already restores its default.
    LabelAt(statusText, "Level Difficulty Colors", 12, -240, statusTextW - 28, "GameFontNormal", T.colors.accent)
    LabelAt(statusText, "Shared by every unit and group frame that colors its level by difficulty.",
        12, -260, statusTextW - 28, "GameFontHighlightSmall", T.colors.muted)
    local function Palette(rows, y, apply)
        local specs = {}
        for i, row in ipairs(rows) do
            specs[i] = { "color", row[1], { row[3], row[4], row[5] }, { row[2] },
                path = row[6], domain = "fontColors", position = { 12 + ((i - 1) % 2) * 330, y - floor((i - 1) / 2) * 36 },
                apply = apply,
            }
        end
        SchemaRows(ctx, statusText, specs)
    end
    Palette(M._levelDifficultyColor, -290, ApplyColors)
    -- Threat % colors. Global like the level bands: every Threat % text that
    -- colors itself by threat (Status icons > Threat % > Color by threat) blends
    -- between these three. Only the clients offering the threat text build them.
    if M._threatCurveColor then
        LabelAt(statusText, "Threat % Colors", 12, -410, statusTextW - 28, "GameFontNormal", T.colors.accent)
        LabelAt(statusText, "Blended from low to high threat on every frame that colors its threat text by threat.",
            12, -430, statusTextW - 28, "GameFontHighlightSmall", T.colors.muted)
        Palette(M._threatCurveColor, -460, function() M._ApplyThreatCurveColors() end)
    end
end
function Build.Classes(ctx, b)
    local tokens = ColorAPI().CLASS_TOKENS
    if not (type(tokens) == "table" and #tokens > 0) then tokens = COLOR_DATA.CLASS_TOKENS end
    local classRows = max(1, floor((#tokens + 3) / 4))
    local classResetY = -36 - (classRows * 36)
    local classHeight = max(190, math.abs(classResetY) + 48)
    local classColors = ColorsSection(b, "colors_classes", "Class Bar Colors", classHeight, false)
    LabelAt(classColors, "Choose an override bar color per class.", 12, -8, 540, "GameFontHighlightSmall", T.colors.muted)
    local classW = classColors._msuf2Width or ctx.width or 720
    local classColW = max(142, floor((classW - 24) / 4))
    local classLabelW = max(76, min(112, classColW - 62))
    local rows = {}
    for i, token in ipairs(tokens) do
        local r, g, bcol = ClassDefaultRGB(token)
        rows[i] = { "color", token, { r, g, bcol }, { COLOR_DATA.CLASS_LABELS[token] or token },
            position = { 12 + ((i - 1) % 4) * classColW, -34 - floor((i - 1) / 4) * 36, classLabelW, 44 },
            path = "class_bar.token." .. tostring(token), get = function() return ClassColorRGB(token) end,
            customSetReason = "Changes preview or editor selection state through its existing owner.", set = function(red, green, blue)
                if ApiCall("SetClassColor", token, red, green, blue) then M.RefreshActiveHealthBackgroundInlinePreview()
                else ApplyUnitframeColorWithReload() end
            end }
    end
    SchemaRows(ctx, classColors, rows)
    Owned(ButtonAt(classColors, "Reset all class colors", 12, classResetY, 190, function()
        if ApiCall("ResetAllClassColors") then M.RefreshActiveHealthBackgroundInlinePreview()
        else
            DB().classColors = nil
            ApplyUnitframeColorWithReload()
        end
    end, "class_bar.reset_all"), "unitColors")
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


function Build.BarGradients(ctx, b)
    local values, sectionW = GP.SCOPE_VALUES or {}, ctx.width or 720
    local scopeMetrics = W.MeasureScopeOverrideBar and W.MeasureScopeOverrideBar(values, { width = sectionW })
    local scopeBottom = (scopeMetrics and scopeMetrics.bottomY) or -40
    local colorY = math.min(-104, scopeBottom - 54)
    local compact = sectionW < 560
    local resetY = compact and (colorY - 86) or (colorY - 44)
    local section = ColorsSection(b, "colors_bar_gradients", "Bar Gradient Colors", math.abs(resetY) + 54, true)
    local scopeBar = W.ScopeOverrideBar(ctx, section, {
        values = values, width = sectionW, getValue = CurrentBarsScope,
        setValue = function(value)
            G().hpPowerTextSelectedKey = NormalizeScopeKey(value)
            if M.RequestRefresh then M.RequestRefresh(ctx, "bar-gradient-color-scope")
            elseif M.Refresh then M.Refresh(ctx) end
        end,
        hasOverride = function(value) return value ~= "shared" and ScopeHasOverride(value, "hlOverride") end,
    })
    RegisterControl(scopeBar, Meta("bar_gradient.scope.selector", "ephemeral"), "Editing:", "segment", values)
    Schema.ScopeOwner(scopeBar, "colors")
    local hint = W.Text(section, "Health and Power use separate gradient colors. Choosing a color creates a custom Bars override for the selected scope.",
        14, colorY + 28, sectionW - 28, T.colors.muted)
    hint:SetJustifyH("LEFT")
    local function GradientRGB(prefix)
        return tonumber(GradientScopeGet(prefix .. "R", 0)) or 0,
            tonumber(GradientScopeGet(prefix .. "G", 0)) or 0, tonumber(GradientScopeGet(prefix .. "B", 0)) or 0
    end
    local function SetGradientRGB(prefix, r, g, bcol, reason)
        GradientScopeSet(prefix .. "R", r)
        GradientScopeSet(prefix .. "G", g)
        GradientScopeSet(prefix .. "B", bcol)
        ApplyScopedBarGradientColors(reason)
    end
    local function GradientRow(key, label, prefix, reason, path, position)
        return { "color", key, { 0, 0, 0 }, { label }, domain = "barGradients", position = position, path = path,
            get = function() return GradientRGB(prefix) end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g,
                bcol) SetGradientRGB(prefix, r, g, bcol, reason) end }
    end
    SchemaRows(ctx, section, {
        GradientRow("health", "Health gradient color", "healthBarGradientColor", "MSUF2_HP_GRADIENT_COLOR",
            "bar_gradient.health.color", { 14, colorY, compact and 180 or 190, 52 }),
        GradientRow("power", "Power gradient color", "powerBarGradientColor", "MSUF2_POWER_GRADIENT_COLOR",
            "bar_gradient.power.color", { compact and 14 or math.max(360, floor(sectionW * 0.50)),
                compact and (colorY - 38) or colorY, compact and 180 or 190, 52 }),
    })
    Owned(ButtonAt(section, "Reset gradient colors", 14, resetY, 180, function()
        for _, prefix in ipairs({ "healthBarGradientColor", "powerBarGradientColor" }) do
            GradientScopeSet(prefix .. "R", 0)
            GradientScopeSet(prefix .. "G", 0)
            GradientScopeSet(prefix .. "B", 0)
        end
        ApplyScopedBarGradientColors("MSUF2_RESET_GRADIENT_COLORS")
    end, "bar_gradient.reset"), "barGradients")
end

function Build.Background(ctx, b)
    local background = ColorsSection(b, "colors_background", "Bar Background Tint", 332, false)
    LabelAt(background, "Fill and color mode affect only the health background; foreground health coloring stays independent.", 12, -8, 660,
        "GameFontHighlightSmall", T.colors.muted)
    LabelAt(background, "Texture comes from Bars; preview uses Player background opacity multiplied by tint opacity.", 12, -24, 660, "GameFontHighlightSmall",
        T.colors.muted)
    local refreshBackgroundPreview
    -- A mode setter of ColorsBackgroundMode (looked up when it runs) that repaints the preview afterwards.
    local function ThenRefresh(name)
        return function(value)
            M.ColorsBackgroundMode[name](value)
            if refreshBackgroundPreview then refreshBackgroundPreview() end
        end
    end
    ValueDropdownAt(ctx, background, "Background Fill", 12, -46,
        ValueTextPairs "full=Full bar|missing=Missing health only", 300,
        M.ColorsBackgroundMode.GetFill, ThenRefresh("SetFill"), Meta("background.fill_mode"))
    ValueDropdownAt(ctx, background, "Background Color", 340, -46,
        ValueTextPairs "custom=Custom tint|match_health=Match health bar|class=Class color|health_gradient=Health gradient", 320,
        M.ColorsBackgroundMode.GetColor, ThenRefresh("SetColor"), Meta("background.color_mode"))
    local previewWidth = max(300, min(648, (background._msuf2Width or ctx.width or 720) - 24))
    local previewPanel = T.Panel(background, nil, T.colors.panel2 or { 0.014, 0.038, 0.072, 0.92 }, T.colors.borderSoft)
    previewPanel:SetPoint("TOPLEFT", background, "TOPLEFT", 12, -104)
    previewPanel:SetSize(previewWidth, 66)
    local previewLabel = T.Font(previewPanel, "GameFontNormalSmall", "Preview", T.colors.muted)
    previewLabel:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 12, -8)
    local previewMode = T.Font(previewPanel, "GameFontHighlightSmall", "", T.colors.muted)
    previewMode:SetPoint("TOPRIGHT", previewPanel, "TOPRIGHT", -12, -8)
    previewMode:SetJustifyH("RIGHT")
    local previewTrack = T.Panel(previewPanel, nil, { 0.006, 0.012, 0.024, 1 }, T.colors.borderSoft)
    previewTrack:SetPoint("TOPLEFT", previewPanel, "TOPLEFT", 12, -28)
    previewTrack:SetPoint("TOPRIGHT", previewPanel, "TOPRIGHT", -12, -28)
    previewTrack:SetHeight(22)
    local previewState = { mode = previewMode, healthFraction = .62 }
    previewState.surface = M.PreviewHelpers.NewRuntimeUnitSurface(previewTrack, "player", { hp = .62 })

    refreshBackgroundPreview = function()
        if previewPanel.IsVisible and not previewPanel:IsVisible() then return false end
        return M.RefreshHealthBackgroundInlinePreview(previewState)
    end
    local function ApplyBackgroundColorPreview()
        ApplyColors()
        refreshBackgroundPreview()
    end
    Owned(ColorValueAt(ctx, background, "Bar background tint", 12, -188,
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
        nil, nil, Meta("general.classBarBg"), { 0, 0, 0 }), "unitColors")
    ValueToggleAt(ctx, background, "Custom color in Dark Mode", 12, -228,
        function() return G().darkBgCustomColor == true end,
        function(v)
            G().darkBgCustomColor = v and true or false
            ApplyBackgroundColorPreview()
        end,
        Meta("background.dark_mode_custom_color"))
    Owned(ButtonAt(background, "Reset to black", 12, -274, 140, function()
        if not ApiCall("ResetClassBarBgColor") then
            ClearRGB(G(), "classBarBg")
            ApplyUnitframeColorWithReload()
        end
        refreshBackgroundPreview()
    end, "background.reset_to_black"), "unitColors")
    if M.TrackCollapsibleRefresh then M.TrackCollapsibleRefresh(ctx, background, refreshBackgroundPreview)
    elseif M.TrackRefresh then M.TrackRefresh(ctx, refreshBackgroundPreview) end
    if ctx.entry then ctx.entry._msuf2HealthBackgroundInlinePreviewRefresh = refreshBackgroundPreview end
end
function Build.Appearance(ctx, b)
    local appearance = ColorsSection(b, "colors_appearance", "Unitframe Global Coloring", 290, true)
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
    -- The leading mode row retains the canonical Search/input owner.
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
    local modeMeta = Meta("appearance.bar_mode")
    Schema.Bind(ctx, modeRow, { id = modeMeta.controlId, kind = "segment", labelKey = "Bar mode", scope = "colors",
        applyDomain = "unitColors", settingPath = modeMeta.settingKey, meta = modeMeta,
        get = CurrentBarMode,
            customSetReason = "Writes color channels and coordinates dependent color modes and runtime state.", set = SetBarMode })
    for i = 1, #BAR_MODE_CARDS do
        local btn = modeRow.buttons[i]
        if btn and M.AddTooltip then M.AddTooltip(btn, TrText(BAR_MODE_CARDS[i].title), TrText(BAR_MODE_CARDS[i].desc), { hook = true }) end
    end
    local modeDescLabel = LabelAt(appearance, "", 12, -64, appearanceW - 24, "GameFontHighlightSmall", T.colors.muted)
    local unifiedColor = GeneralColorAt(ctx, appearance, "Unified bar color", 12, -94, "unifiedBar", 0.10, 0.60, 0.90, ApplyUnitframeColorWithReload)
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
    local gradientStrength = SliderAt(ctx, appearance, "Health strength", 360, -94, 0, 1, 0.05, 250, G, "gradientStrength", 0.45,
        ApplyUnitframeColorWithReload, Meta("appearance.gradient.strength"))
    local healthGradient = SwitchAt(ctx, appearance, "Health Gradient", 360, -142, 230, G, "enableHealthGradient", true, function()
        ApplyUnitframeColorWithReload()
        if refreshBarModeControls then refreshBarModeControls() end
    end, Meta("appearance.gradient.enabled"))
    local gradientStopsLabel = LabelAt(appearance, "Health gradient stops", 12, -190, 220, "GameFontNormalSmall", T.colors.muted)
    local gradientLow = GeneralColorAt(ctx, appearance, "Low", 12, -220, "healthGradientLow", 1, 0, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientMid = GeneralColorAt(ctx, appearance, "Mid", 170, -220, "healthGradientMid", 1, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientHigh = GeneralColorAt(ctx, appearance, "High", 328, -220, "healthGradientHigh", 0, 1, 0, ApplyUnitframeColorWithReload, 58, 34)
    local gradientReset = ButtonAt(appearance, "Reset gradient", 486, -220, 150, function()
        local g = G()
        g.healthGradientLowR, g.healthGradientLowG, g.healthGradientLowB = 1, 0, 0
        g.healthGradientMidR, g.healthGradientMidG, g.healthGradientMidB = 1, 1, 0
        g.healthGradientHighR, g.healthGradientHighG, g.healthGradientHighB = 0, 1, 0
        ApplyUnitframeColorWithReload()
    end, "appearance.gradient.reset")
    for _, control in ipairs({ modeRow, unifiedColor, gradientLow, gradientMid, gradientHigh, gradientReset }) do
        Owned(control, "unitColors")
    end
    local gradientEditControls = { gradientStrength, gradientStopsLabel, gradientLow, gradientMid, gradientHigh, gradientReset }
    if M.AddTooltip then
        M.AddTooltip(gradientStrength, "Health strength",
            "How dark the health bar shade gets at its strongest edge. 0 shows no shade, 1 uses the full shade color.", { hook = true, labelHit = true })
    end
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
                modeDescLabel:SetText(BAR_MODE_CARDS[i].desc)
            end
        end
    end
    M.TrackRefresh(ctx, refreshBarModeControls)
    refreshBarModeControls()
end

function Build.Unit(ctx, b)
    local unit = ColorsSection(b, "colors_unit", "Unitframe Colors", 230, false)
    -- One UnitColorRows row built on its own; the result is the widget.
    local function UnitRow(parent, row) return Schema.Build(ctx, parent, { row }, UnitColorRows)[row[2]] end
    local function NPCColors(section, values, columns, xStep, y, yStep)
        local rows = {}
        for i, value in ipairs(values) do
            rows[i] = { "color", value.key, { value.dr, value.dg, value.db }, { value.label },
                position = { 12 + ((i - 1) % columns) * xStep, y - floor((i - 1) / columns) * yStep },
                apiGet = "GetNPCColor", apiSet = "SetNPCColor", arg = value.key, path = "npc.color." .. tostring(value.key) }
        end
        return Schema.Build(ctx, section, rows, UnitColorRows)
    end
    NPCColors(unit, COLOR_DATA.NPC_ROWS, 1, 0, -10, 36)
    local petColor = UnitRow(unit, { "color", "pet", { 0, 0.8, 0 }, { "Pet Frame Color" }, position = { 360, -10 },
        apiGet = "GetPetFrameColor", apiSet = "SetPetFrameColor", path = "api.SetPetFrameColor" })
    local function RefreshPetColorControl() SetControlEnabled(petColor, G().petFrameUsePlayerClassColor ~= true) end
    local petPlayerClass = UnitRow(unit, { "flowToggle", "petPlayerClass", false, { "Use player's class color for Pet Frame" }, { 360, -54 },
        path = "unit.pet.use_player_class_color", get = function() return G().petFrameUsePlayerClassColor == true end,
        write = { source = G, boolean = true, after = function()
                M.RequestUnitDomains("pet", "MSUF2_PET_PLAYER_CLASS_COLOR", { preview = true })
                RefreshPetColorControl()
            end } --[[schema setter: AdvancedColors.7]] })
    M.TrackRefresh(ctx, RefreshPetColorControl)
    RefreshPetColorControl()
    if M.AddTooltip then M.AddTooltip(petPlayerClass, "Use player's class color for Pet Frame",
        "Colors the Pet health bar with your class color while its Health Color Scheme is Class / Reaction.", { hook = true }) end
    UnitRow(unit, { "flowToggle", "npcClassColorBar", false,
        { "Friendly NPC class colors on HP bars (Class Color mode only)" }, { 360, -82 }, path = "npc.class_color_bar",
        get = function() return ApiValue("GetNPCClassColorBar", function() return G().npcClassColorBar == true end) end,
        apiSet = "SetNPCClassColorBar" })
    -- Tagged colors read their own stored kind: the general getter falls back to enemy red.
    if MSUF.Client.SupportsTapDenied == true then
        local tappedColor = UnitRow(unit, { "color", "tapped", { 0.5, 0.5, 0.5 }, { "Tagged by others" }, position = { 12, -154 },
            path = "npc.color.tapped",
            get = function()
                local colors = DB().npcColors
                local stored = type(colors) == "table" and colors.tapped or nil
                if type(stored) == "table" then return stored.r or 0.5, stored.g or 0.5, stored.b or 0.5 end
                return 0.5, 0.5, 0.5
            end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g, c)
                if not ApiCall("SetNPCColor", "tapped", r, g, c) then
                    local db = DB()
                    db.npcColors = db.npcColors or {}
                    db.npcColors.tapped = { r = r, g = g, b = c }
                    ApplyUnitframeColorWithReload()
                end
            end })
        UnitRow(unit, { "flowToggle", "tappedGray", true, { "Gray out mobs tagged by others" }, { 360, -110 }, path = "npc.tap_denied_gray",
            get = function() return G().tapDeniedGray ~= false end,
            write = { source = G, boolean = true, after = function(value)
                    ApplyUnitframeColorWithReload() SetControlEnabled(tappedColor, value)
                end } --[[schema setter: AdvancedColors.9]], tip = { "Gray out mobs tagged by others",
                "A mob another player hit first gives you no loot or experience. Its health bar and name turn gray, like on the default target frame.",
                { hook = true } } })
        M.TrackRefresh(ctx, function() SetControlEnabled(tappedColor, G().tapDeniedGray ~= false) end)
        SetControlEnabled(tappedColor, G().tapDeniedGray ~= false)
    end
    Owned(ButtonAt(unit, "Reset Unitframe Colors", 12, -190, 190, ResetUnitframeColors, "unitframe.reset"), "unitColors")
    local npcType = ColorsSection(b, "colors_npc_type", "NPC Type Colors", 330, false)
    local npcControls, npcMaster = {}, nil
    local function RefreshNPCTypeControls(enabled)
        if enabled == nil then enabled = npcMaster and npcMaster:GetChecked() and true or false end
        SetControlsEnabled(npcControls, enabled)
    end
    local function NPCTypeToggle(label, x, y, apiGet, apiSet, key, apiArg)
        npcControls[#npcControls + 1] = UnitRow(npcType, { "flowToggle", key, true, { label }, { x, y },
            apiGet = apiGet, apiSet = apiSet, arg = apiArg, path = "npc_type.option." .. tostring(key) })
    end
    NPCTypeToggle("Color HP bar (Class Color mode only)", 32, -38, "GetNPCTypeColorBar", "SetNPCTypeColorBar", "npcTypeColorBar")
    NPCTypeToggle("Color name text", 32, -62, "GetNPCTypeColorText", "SetNPCTypeColorText", "npcTypeColorText")
    npcMaster = UnitRow(npcType, { "switch", "master", false, { "NPC Type Colors", 12, -10, 260 }, path = "npc_type.enabled",
        get = function() return ApiValue("GetNPCColorMode", function() return G().npcColorMode end) == "type" end,
        customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(v)
            if not ApiCall("SetNPCColorMode", v and "type" or "reaction") then
                G().npcColorMode = v and "type" or "reaction"
                ApplyUnitframeColorWithReload()
            end
            RefreshNPCTypeControls(v and true or false)
        end })
    LabelAt(npcType, "Apply to:", 12, -94, 120, "GameFontNormalSmall", T.colors.muted)
    local units = ColorAPI().NPC_TYPE_UNITS
    if not (type(units) == "table" and #units > 0) then
        units = M.KeyLabelRows [[npcTypeTarget=Target
npcTypeFocus=Focus
npcTypeBoss=Boss
npcTypeToT=Target of Target]]
    end
    for i, info in ipairs(units) do
        NPCTypeToggle(info.label or info.key, 32 + ((i - 1) % 2) * 180, -114 - floor((i - 1) / 2) * 24,
            "GetNPCTypePerUnit", "SetNPCTypePerUnit", info.key, info.key)
    end
    local typeColors = NPCColors(npcType, COLOR_DATA.NPC_TYPE_ROWS, 2, 330, -174, 38)
    for _, row in ipairs(COLOR_DATA.NPC_TYPE_ROWS) do npcControls[#npcControls + 1] = typeColors[row.key] end
    Owned(ButtonAt(npcType, "Reset NPC Type Colors", 12, -292, 190,
        function() ResetNPCColors("ResetNPCTypeColors") end, "npc_type.reset"), "unitColors")
    M.TrackRefresh(ctx, RefreshNPCTypeControls)
end

-- Colors that write one shared setting used by unit AND group frames get a
-- small inline tag so the duplication reads as intentional, not as two
-- separate settings.
local function MarkSharedColor(control)
    if not control then return end
    local tag = T.Font(control, "GameFontDisableSmall", "Shared with group frames", T.colors.muted)
    tag:SetPoint("LEFT", control, "RIGHT", 8, 0)
    control._msuf2SharedColorTag = tag
end
function Build.BarColors(ctx, b)
    local barColors = ColorsSection(b, "colors_bar_colors", "Bar & Prediction Colors", 280, false)
    local barLeftX = 30
    local barRightX = max(430, floor((barColors._msuf2Width or ctx.width or 720) * 0.50))
    LabelAt(barColors, "Bar overlays", barLeftX, -8, 180, "GameFontNormalSmall", T.colors.text)
    LabelAt(barColors, "Borders & matching", barRightX, -8, 220, "GameFontNormalSmall", T.colors.text)
    local barColorControls = BuildApiColorSpecs(ctx, barColors, {
        { "Absorb Bar Color", barLeftX, -38, "GetAbsorbOverlayColor", "SetAbsorbOverlayColor", 1, 1, 1 },
        { "Heal-Absorb / Negative Heal", barLeftX, -74, "GetHealAbsorbOverlayColor", "SetHealAbsorbOverlayColor", 0.7, 0, 0 },
        { "Power Bar Background Color", barLeftX, -110, "GetPowerBarBackgroundColor", "SetPowerBarBackgroundColor", 0, 0, 0, nil, nil, nil, "powerBg" },
        { "Aggro Border Color", barRightX, -38, "GetAggroBorderColor", "SetAggroBorderColor", 1, 0.5, 0 },
    })
    for _, control in pairs(barColorControls) do Owned(control, "unitColors") end
    local powerBg = barColorControls.powerBg
    MarkSharedColor(barColorControls.SetAbsorbOverlayColor)
    MarkSharedColor(barColorControls.SetHealAbsorbOverlayColor)
    -- Plain general-key swatches: the stored prefix carries R / G / B, the page applies on every edit.
    local function GeneralBarColor(label, x, y, prefix, default, path)
        return Owned(ColorValueAt(ctx, barColors, label, x, y,
            function() return GeneralRGB(prefix, default[1], default[2], default[3]) end,
            function(r, g, c)
                local general = G()
                general[prefix .. "R"], general[prefix .. "G"], general[prefix .. "B"] = r, g, c
                ApplyColors()
            end, nil, nil, Meta(path), default), "unitColors")
    end
    MarkSharedColor(GeneralBarColor("Positive Heal Prediction", barLeftX, -146, "healPredictionColor", { 0, 1, 0 }, "prediction.heal_color"))
    GeneralBarColor("Health loss glow", barLeftX, -182, "healthLossColor", { 1, 0.55, 0.08 }, "bar.health_loss_color")
    Owned(ColorValueAt(ctx, barColors, "Purge Border Color", barRightX, -74,
        function() return GeneralRGBAlias("hlPurgeColor", "purgeBorderColor", 1.00, 0.85, 0.00) end,
        function(r, g, c) SetGeneralRGBAlias("hlPurgeColor", "purgeBorderColor", r, g, c) end,
        nil, nil, Meta("bar.purge_border_color"), { 1.00, 0.85, 0.00 }), "unitColors")
    Owned(ColorValueAt(ctx, barColors, "Bar Outline Color", barRightX, -110,
        function() return GeneralRGB("barOutlineColor", 0, 0, 0) end,
        function(r, g, c)
            local general = G()
            general.barOutlineColorR, general.barOutlineColorG, general.barOutlineColorB = r, g, c
            general.barOutlineColorA = 1
            general.barOutlineColorMode = nil
            ApplyGlobalOutlineColor()
        end,
        nil, nil, Meta("bar.outline_color"), { 0, 0, 0 }), "unitColors")
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
    GeneralBarColor("Power loss glow", barRightX, -182, "powerLossColor", { 0.70, 0.90, 1 }, "bar.power_loss_color")
    Owned(ButtonAt(barColors, "Reset Bar Colors", barLeftX, -234, 160, function()
        local g = G()
        ClearRGBAs(g, "absorbBarColor", "healAbsorbBarColor", "powerBarBgColor", "aggroBorder", "purgeBorderColor", "barOutlineColor")
        ClearRGB(g, "healPredictionColor")
        ClearRGB(g, "healthLossColor")
        ClearRGB(g, "powerLossColor")
        g.barOutlineColorMode = nil
        ClearRGBs(g, "hlAggroColor", "hlPurgeColor", "aggroBorderColor")
        g.powerBarBgMatchBarColor = nil
        ApplyGlobalOutlineColor()
    end, "bar.reset"), "unitColors")
    M.BindGateGroup(ctx, nil, {
        { controls = powerBg, on = function() return not (powerBgMatch:GetChecked() and true or false) end },
    })
end

function Build.Castbar(ctx, b)
    local castbar = ColorsSection(b, "colors_castbar", "Castbar Colors", 580, false)
    local castW = castbar._msuf2Width or ctx.width or 720
    for _, control in pairs(BuildApiColorSpecs(ctx, castbar, {
        { "Interruptible cast color", 12, -10, "GetInterruptibleCastColor", "SetInterruptibleCastColor", 0, 0.9, 0.8 },
        { "Non-interruptible cast color", 12, -46, "GetNonInterruptibleCastColor", "SetNonInterruptibleCastColor", 0.4, 0.01, 0.01 },
        { "Interrupt color (all castbars)", 12, -82, "GetInterruptFeedbackCastColor", "SetInterruptFeedbackCastColor", 1.0, 0.82, 0.0 },
        { "Castbar text color", 360, -10, "GetCastbarTextColor", "SetCastbarTextColor", 1, 1, 1 },
        { "Cast Target Name Color", 360, -118, "GetCastbarTargetNameColor", "SetCastbarTargetNameColor", 1, 1, 1 },
    }, ApplyCastbarColors)) do Owned(control, "castbar") end
    for _, control in pairs(BuildApiOrGeneralColorSpecs(ctx, castbar, {
        { "Castbar border color", 360, -46, "GetCastbarBorderColor", "SetCastbarBorderColor", "castbarBorder", 0, 0, 0, nil, 1 },
        { "Castbar background color", 360, -82, "GetCastbarBackgroundColor", "SetCastbarBackgroundColor", "castbarBg", 0.10, 0.10, 0.10, nil, 0.85 },
    }, ApplyCastbarColors)) do Owned(control, "castbar") end
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
    local overrideColor = Owned(ColorValueAt(ctx, castbar, "Custom color", overrideColorX, overrideColorY,
        function() return ApiRGB("GetPlayerCastbarOverrideColor", 0, 0.6, 1) end,
        function(r, g, c)
            if not ApiSetRGB("SetPlayerCastbarOverrideColor", r, g, c) then ApplyCastbarColors() end
        end,
        overrideColorLabelW, nil, Meta("castbar.player_override.custom_color"), { 0, 0.6, 1 }), "castbar")
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
    for _, control in pairs(BuildTableColorSpecs(ctx, castbar, G, {
        { "Ready color (kick available)", 12, -310, "kickReadyColor", 0, 1, 0 },
        { "Not ready color (kick on cooldown)", 12, -346, "kickNotReadyColor", 1, 0, 0 },
    }, ApplyCastbarColors)) do Owned(control, "castbar") end
    Owned(ApiColorAt(ctx, castbar, "Unavailable fill color", 12, -382,
        "GetInterruptUnavailableCastColor", "SetInterruptUnavailableCastColor", 1.0, 0.494117647, 0.137254902, ApplyCastbarColors), "castbar")
    Owned(ButtonAt(castbar, "Reset castbar colors", 12, -506, 170, function()
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
    end, "castbar.reset"), "castbar")
    M.TrackRefresh(ctx, RefreshCastbarOverrideControls)

    -- Canonical surface for the per-castbar text colors that the Unit > Castbar
    -- cards also expose. One castbar is edited at a time so four units stay
    -- three swatches instead of twelve. An unset detail shows the shared castbar
    -- text color it is currently inheriting; the reset button restores that.
    local detail = ColorsSection(b, "colors_castbar_text", "Castbar Text Colors", 280, false)
    local detailW = detail._msuf2Width or ctx.width or 720
    local function DetailUnit()
        local value = tostring(M._colorsCastbarDetailUnit or "player")
        if value == "target" or value == "focus" or value == "boss" or value == "arena" then return value end
        return "player"
    end
    local function DetailRGB(suffix)
        local read = Opt.MSUF_GetCastbarDetailTextColor
        if type(read) == "function" then
            local r, g, bcol, custom = read(DetailUnit(), suffix)
            if custom == true then return r, g, bcol end
        end
        return ApiRGB("GetCastbarTextColor", 1, 1, 1)
    end
    local function SetDetailRGB(suffix, r, g, bcol)
        local write = Opt.MSUF_SetCastbarDetailTextColor
        if type(write) == "function" then write(DetailUnit(), suffix, r, g, bcol) end
        ApplyCastbarColors()
    end
    LabelAt(detail, "Each castbar text can override the shared castbar text color. Target text exists on Target, Focus, Boss, and Arena.",
        12, -8, detailW - 28, "GameFontHighlightSmall", T.colors.muted)
    local detailMeta = Meta("castbar.text_color.unit", "ephemeral")
    local detailUnitDropdown = Schema.Render(ctx, detail, {
        id = detailMeta.controlId, kind = "dropdown", labelKey = "Editing:", scope = "colors", applyDomain = "menuState", meta = detailMeta,
        values = M.FilterSupportedUnitValues(
            ValueTextPairs "player=Player|target=Target|focus=Focus|boss=Boss|arena=Arena"),
        get = DetailUnit, customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set = function(value)
            M._colorsCastbarDetailUnit = value
            if M.RequestRefresh then M.RequestRefresh(ctx, "castbar-text-color-unit") elseif M.Refresh then M.Refresh(ctx) end
        end }, { x = 12, y = -44, width = min(260, detailW - 32) })
    RegisterControl(detailUnitDropdown, Meta("castbar.text_color.unit", "ephemeral"), "Editing:", "dropdown")
    local function DetailColor(label, y, suffix, path)
        return ColorValueAt(ctx, detail, label, 12, y,
            function() return DetailRGB(suffix) end,
            function(r, g, bcol) SetDetailRGB(suffix, r, g, bcol) end,
            nil, nil, Meta(path), nil, { scope = "colors", applyDomain = "castbar" })
    end
    DetailColor("Spell text color", -100, "SpellName", "castbar.text_color.spell_name")
    DetailColor("Cast time color", -136, "Time", "castbar.text_color.time")
    local detailTargetColor = DetailColor("Target text color", -172, "TargetName", "castbar.text_color.target_name")
    Owned(ButtonAt(detail, "Follow shared color", 12, -218, 190, function()
        local reset = MSUF.Require("MSUF_ResetCastbarDetailTextColor", FILE)
        local castUnit = DetailUnit()
        reset(castUnit, "SpellName")
        reset(castUnit, "Time")
        reset(castUnit, "TargetName")
        ApplyCastbarColors()
    end, "castbar.text_color.reset"), "castbar")
    M.TrackRefresh(ctx, function()
        SetControlEnabled(detailTargetColor, DetailUnit() ~= "player")
    end)
end

function Build.Highlight(ctx, b)
    local highlight = ColorsSection(b, "colors_highlight", "Highlight Colors", 154, false)
    SchemaRows(ctx, highlight, {
        { "color", "highlight", { 1, 1, 1 }, { "Mouseover highlight color" }, position = { 12, -10 },
            path = "highlight.mouseover.color", get = HighlightRGB,
                customSetReason = "Writes color channels and coordinates dependent color modes and runtime state.", set = SetHighlightRGB },
        { "color", "bossTargetHighlightColor", { 1, 0.82, 0 }, { "Boss target highlight color" }, position = { 12, -66 },
            path = "table.bossTargetHighlightColor", source = G, apply = ApplyBossTargetHighlightColor },
    })
    local texLayer = ColorsSection(b, "colors_texture_layer", "Texture Layer Colors", 340, false)
    for texIndex, texSlot in ipairs({
        { id = "texture_layer", prefix = "texLayer", suffix = "" },
        { id = "texture_layer2", prefix = "texLayer2", suffix = " 2" },
        { id = "texture_layer3", prefix = "texLayer3", suffix = " 3" },
    }) do
        local rowY, prefix = -10 - (texIndex - 1) * 108, texSlot.prefix
        -- The first slot keeps raw locale keys; later slots add the translated slot number.
        local colorLabel, gradientLabel = "Texture layer color", "Texture layer gradient end"
        if texSlot.suffix ~= "" then
            colorLabel, gradientLabel = M.Tr(colorLabel) .. texSlot.suffix, M.Tr(gradientLabel) .. texSlot.suffix
        end
        SchemaRows(ctx, texLayer, {
            { "color", prefix .. "Color", { 1, 1, 1 }, { colorLabel }, position = { 12, rowY }, path = texSlot.id .. ".color",
                customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g,
                    c) M._SetAllTextureLayerRGB(prefix .. "Color", r, g, c) end },
            { "color", prefix .. "Gradient2", { 0, 0, 0 }, { gradientLabel }, position = { 12, rowY - 36 },
                path = texSlot.id .. ".gradient_color",
                    customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
                    set = function(r, g, c) M._SetAllTextureLayerRGB(prefix .. "Gradient2", r, g, c) end },
        })
    end
end
function Build.Gameplay(ctx, b)
    local gameplay = ColorsSection(b, "colors_gameplay", "Combat Feedback", 310, false)
    local colors = SchemaRows(ctx, gameplay, {
        { "color", "combatTimerColor", { 1, 1, 1 }, { "Combat timer text color" }, position = { 12, -10 },
            path = "table.combatTimerColor", source = Gameplay, apply = ApplyGameplayColors },
        { "color", "combatStateEnterColor", { 1, 1, 1 }, { "Combat Enter text color" }, position = { 12, -46 },
            path = "gameplay.combat_enter_color", source = Gameplay,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(r, g, c)
                local gp = Gameplay()
                SetTableRGB(gp, "combatStateEnterColor", r, g, c)
                if gp.combatStateColorSync then SetTableRGB(gp, "combatStateLeaveColor", r, g, c) end
                ApplyGameplayColors()
            end },
        { "color", "combatStateLeaveColor", { 0.7, 0.7, 0.7 }, { "Combat Leave text color" }, position = { 12, -82 },
            path = "table.combatStateLeaveColor", source = Gameplay, apply = ApplyGameplayColors },
        { "color", "crosshairInRangeColor", { 0, 1, 0 }, { "Crosshair in-range color" }, position = { 12, -142 },
            path = "table.crosshairInRangeColor", source = Gameplay, apply = ApplyGameplayColors },
        { "color", "crosshairOutRangeColor", { 1, 0, 0 }, { "Crosshair out-of-range color" }, position = { 12, -178 },
            path = "table.crosshairOutRangeColor", source = Gameplay, apply = ApplyGameplayColors },
    })
    SchemaRows(ctx, gameplay, {
        { "flowToggle", "combatStateColorSync", false, { "Sync" }, { 360, -82 },
            path = "gameplay.combat_state_color_sync", source = Gameplay, apply = function()
                local gp = Gameplay()
                if gp.combatStateColorSync then
                    local r, g, c = TableRGB(gp, "combatStateEnterColor", 1, 1, 1)
                    SetTableRGB(gp, "combatStateLeaveColor", r, g, c)
                end
                ApplyGameplayColors()
                SetControlEnabled(colors.combatStateLeaveColor, not (gp.combatStateColorSync == true))
            end },
    })
    Owned(ButtonAt(gameplay, "Reset gameplay colors", 12, -254, 170, function()
        local gp = Gameplay()
        gp.combatTimerColor, gp.combatStateEnterColor = { 1, 1, 1 }, { 1, 1, 1 }
        gp.combatStateLeaveColor = gp.combatStateColorSync and { 1, 1, 1 } or { 0.7, 0.7, 0.7 }
        gp.crosshairInRangeColor, gp.crosshairOutRangeColor = { 0, 1, 0 }, { 1, 0, 0 }
        ApplyGameplayColors()
    end, "gameplay.reset"), "unitColors")
    M.BindGateGroup(ctx, nil, {
        { controls = colors.combatStateLeaveColor, on = function() return not (Gameplay().combatStateColorSync == true) end },
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
-- its category, so search keywords, Search metadata and cross-page focus
-- requests keep working. Categories build lazily on first activation; hidden
-- (coverage/audit) builds materialize everything, matching the old groups.
local COLOR_CATEGORY_ORDER = { "unit", "group", "cast", "auras", "resources" }
local COLOR_CATEGORY_SECTIONS = {
    unit = { "colors_appearance", "colors_bar_colors", "colors_bar_gradients", "colors_background",
        "colors_font", "colors_classes", "colors_unit", "colors_npc_type", "colors_highlight",
        "colors_texture_layer", "colors_gameplay", "colors_portrait", "colors_status_text" },
    group = { "colors_group_frames", "colors_group_frames_background", "colors_group_frames_state",
        "colors_group_frames_highlights", "colors_group_frames_healer_mana" },
    cast = { "colors_castbar", "colors_castbar_text" },
    auras = { "colors_auras" },
    resources = { "colors_power", "colors_class_power", "colors_resource_extras", "colors_resource_marks" },
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
    unit = function(ctx, inner)
        Build.Appearance(ctx, inner)
        Build.BarColors(ctx, inner)
        Build.BarGradients(ctx, inner)
        return function()
            Build.Background(ctx, inner)
            Build.Font(ctx, inner)
            Build.StatusText(ctx, inner)
            Build.Classes(ctx, inner)
            return function()
                Build.Unit(ctx, inner)
                Build.Highlight(ctx, inner)
                Build.Gameplay(ctx, inner)
                Build.Portrait(ctx, inner)
            end
        end
    end,
    group = function(ctx, inner)
        CP.BuildGroupFrameColors(ctx, inner)
    end,
    cast = Build.Castbar,
    auras = Build.Aura,
    resources = function(ctx, inner)
        CP.BuildPowerAndClassPowerColors(ctx, inner, { ButtonAt = ButtonAt })
    end,
}

local function PendingColorFocusCategory(ctx)
    local request = MSUF.PublicGlobals.MSUF_EM2_MenuFocusRequest
    if type(request) ~= "table" or request.explicit ~= true or request.consumed == true then return nil end
    if request.pageKey and tostring(request.pageKey) ~= tostring(ctx and ctx.key or "") then return nil end
    return COLOR_SECTION_CATEGORY[tostring(request.sectionId or "")]
end

-- The category host is one frame under the painter tabs that holds a lazily built
-- container per category; H carries the page build state the steps share.
local Host = {}
-- The Suite category exists only while the Suite addon offers Colors sections.
function Host.RegisterSuite()
    local suiteLink = MSUF.SuiteLink
    if not suiteLink.HasColorsCategory() or COLOR_CATEGORY_BUILDERS.suite then return end
    COLOR_PAINTER_CATEGORIES[#COLOR_PAINTER_CATEGORIES + 1] = {
        key = "suite", title = "UI Suite", shortTitle = "Suite",
        subtitle = "Minimap, action bars, damage meter and skin colors.",
        pickerNote = "Suite modules and their shared skin palette.",
    }
    COLOR_CATEGORY_ORDER[#COLOR_CATEGORY_ORDER + 1] = "suite"
    COLOR_CATEGORY_SECTIONS.suite = {
        "colors_suite_minimap", "colors_suite_actionbars", "colors_suite_damageMeter", "colors_suite_skin",
    }
    for _, sectionId in ipairs(COLOR_CATEGORY_SECTIONS.suite) do COLOR_SECTION_CATEGORY[sectionId] = "suite" end
    COLOR_CATEGORY_BUILDERS.suite = function(colorCtx, inner)
        suiteLink.BuildColorsCategory(colorCtx, inner)
    end
end
function Host.New(ctx, b)
    if not b._collapsibleStartY then b._collapsibleStartY = b.y end
    local frame = PixelLayoutRegion(CreateFrame("Frame", nil, b.parent))
    frame:SetSize(b.width, 1)
    frame:SetPoint("TOPLEFT", b.parent, "TOPLEFT", b.x, b.y)
    local entry = { kind = "section", frame = frame, height = 1, gap = 12 }
    b.layoutEntries[#b.layoutEntries + 1] = entry
    b.y = b.y - 1 - 12
    local categories = {}
    for i = 1, #COLOR_CATEGORY_ORDER do
        local categoryKey = COLOR_CATEGORY_ORDER[i]
        local container = PixelLayoutRegion(CreateFrame("Frame", nil, frame))
        container:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        container:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        container:SetHeight(1)
        container:Hide()
        categories[categoryKey] = { key = categoryKey, container = container, height = 1 }
    end
    return { ctx = ctx, b = b, frame = frame, entry = entry, categories = categories }
end
function Host.UpdateHeight(H, layoutOpts)
    local active = H.categories[H.activeKey]
    local height = max(1, tonumber(active and active.height) or 1)
    H.entry.height = height
    if H.frame:GetHeight() ~= height then H.frame:SetHeight(height) end
    H.b:RequestRelayoutCollapsibles(layoutOpts)
end
-- A live stage timer finishes the build on its own tick, so an activation
-- (the page show in the entry frame, painter refreshes) leaves the later
-- stages to it. A cancelled or refused timer (menu hidden, combat) resumes
-- one stage, as before; callers that need the sections now (paint, focus,
-- hidden builds) pass now and run every remaining stage.
function Host.Resume(category, now)
    local task = category.resumeTask
    if not now and type(task) == "table" and task.active == true then return end
    repeat
        local resume = category.resumeStage
        if not resume then return end
        category.resumeStage = nil
        resume()
    until not now
end
-- The painter's category switch, or a direct activation while it is not wired.
function Host.Select(H, categoryKey)
    if type(M.ColorsSetPainterCategory) == "function" then
        M.ColorsSetPainterCategory(categoryKey)
    else
        Host.Activate(H, categoryKey)
    end
end
function Host.Finish(H, build)
    build.category.built = true
    build.category.building = nil
    for i = 1, #build.inner.collapsibles do
        build.inner.collapsibles[i]._msuf2EnsureVisible = function() Host.Select(H, build.key) end
    end
end
-- A builder may return a continuation (which may return another one):
-- later stages run on short ticks so the entry frame only pays for the
-- first slice. Without a timer every stage runs inline, so tests and
-- degraded clients keep the old fully synchronous behavior.
function Host.RunStage(H, build, stage)
    local ctx, category, refreshers = H.ctx, build.category, build.refreshers
    local refreshStart = type(refreshers) == "table" and #refreshers or 0
    local wasBuilding = ctx and ctx._msuf2Building
    if ctx then ctx._msuf2Building = true end
    local entry = ctx.entry
    local wasIncomplete = entry._msuf2BuildIncomplete
    entry._msuf2BuildIncomplete = true
    local nextStage = stage(ctx, build.inner)
    entry._msuf2BuildIncomplete = wasIncomplete
    if ctx then ctx._msuf2Building = wasBuilding end

    build.inner:RelayoutCollapsibles()
    if not wasBuilding and type(refreshers) == "table" then
        for i = refreshStart + 1, #refreshers do
            local refresh = refreshers[i]
            if type(refresh) == "function" then refresh() end
        end
        -- The current outer relayout reads the updated host height after
        -- this callback, so its pending marker has already been satisfied.
        H.b._msuf2RelayoutPending = nil
    end
    if type(nextStage) == "function" then
        if C_Timer and type(C_Timer.After) == "function" then
            -- Combat quiescence may cancel the tracked timer; the
            -- resume hook lets the next Host.Ensure call pick
            -- the build back up instead of leaving it half-finished.
            category.resumeStage = function() Host.RunStage(H, build, nextStage) end
            category.resumeTask = C_Timer.After(0.02, function()
                if H.categories[build.key] ~= category or category.resumeStage == nil then return end
                category.resumeStage = nil
                Host.RunStage(H, build, nextStage)
            end)
            return
        end
        return Host.RunStage(H, build, nextStage)
    end
    Host.Finish(H, build)
end
function Host.Ensure(H, categoryKey, now)
    local category = H.categories[categoryKey]
    if not category or category.built then return category end
    if category.building then
        Host.Resume(category, now)
        return category
    end
    category.building = true
    category.container._msuf2ExactTabView = {
        kind = "colorsPainterCategory", value = categoryKey,
        select = function()
            M.ColorsSetPainterCategory(categoryKey)
        end,
    }
    local ctx = H.ctx
    local refreshers = ctx and ctx.refreshers
    local inner = W.PageBuilder(ctx, {
        parent = category.container,
        width = H.b.width,
        contentX = 0,
        topInset = 0,
        onContentHeight = function(height, layoutOpts)
            height = max(1, tonumber(height) or 1)
            if category.height == height then return end
            category.height = height
            if H.activeKey == categoryKey then Host.UpdateHeight(H, layoutOpts) end
        end,
    })
    Host.RunStage(H, { category = category, key = categoryKey, inner = inner, refreshers = refreshers },
        COLOR_CATEGORY_BUILDERS[categoryKey])
    if now then Host.Resume(category, true) end
    return category
end
function Host.Activate(H, categoryKey)
    if not H.categories[categoryKey] then categoryKey = COLOR_CATEGORY_ORDER[1] end
    Host.Ensure(H, categoryKey)
    H.activeKey = categoryKey
    -- Cached page/search/pin lifecycles can leave a locally hidden active
    -- container behind.  Reconcile every time, including same-category
    -- activation, instead of relying on the key having changed.
    if H.frame.Show then H.frame:Show() end
    for key, category in pairs(H.categories) do
        category.container:SetShown(key == categoryKey)
    end
    Host.UpdateHeight(H)
end

local function BuildColors(ctx)
    Host.RegisterSuite()
    if ctx and ctx.wrapper then ctx.wrapper._msuf2SuppressContextColorShortcuts = true end
    local b = W.PageBuilder(ctx)
    -- Painter callbacks from a previous build of this page must never fire
    -- into stale closures while this build is in progress.
    M.ColorsOnPainterCategory = nil
    M.ColorsSetPainterCategory = nil
    M.ColorsEnsureCategoryBuilt = nil
    if ctx and ctx.entry then ctx.entry._msuf2HealthBackgroundInlinePreviewRefresh = nil end
    b:GlobalStyleHeader("Colors", "Frame, group-frame, bar, aura, castbar and resource colors.", 72)
    BuildColorPainter(ctx, b)

    local H = Host.New(ctx, b)
    M.ColorsOnPainterCategory = function(categoryKey) Host.Activate(H, categoryKey) end
    M.ColorsEnsureCategoryBuilt = function(sectionId)
        local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
        if categoryKey then Host.Ensure(H, categoryKey, true) end
    end
    if ctx.entry then
        ctx.entry._msuf2ResolveMissingSection = function(sectionId)
            local categoryKey = COLOR_SECTION_CATEGORY[tostring(sectionId or "")]
            if not categoryKey then return nil end
            Host.Select(H, categoryKey)
            Host.Ensure(H, categoryKey, true)
            local sections = ctx.entry.sections
            return sections and sections[tostring(sectionId)]
        end
    end
    if ctx.hiddenBuild then
        for i = 1, #COLOR_CATEGORY_ORDER do Host.Ensure(H, COLOR_CATEGORY_ORDER[i], true) end
    end
    local initialKey = PendingColorFocusCategory(ctx)
    if not initialKey then
        local persisted = M.colorsPainterCategory
        initialKey = H.categories[persisted] and persisted or COLOR_CATEGORY_ORDER[1]
    end
    -- The painter's ShowCategory ends in ActivateCategory itself.
    Host.Select(H, initialKey)
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
CP.COLOR_POWER_TOKENS = COLOR_DATA.POWER_TOKENS
CP.COLOR_CP_TOKENS = COLOR_DATA.CP_TOKENS
CP.COLOR_PAINTER_CATEGORIES = COLOR_PAINTER_CATEGORIES
