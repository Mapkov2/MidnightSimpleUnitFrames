local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
-- Load-time dependency handoff; runtime callbacks retain their original local bindings.
local Parts = {}
M.AdvancedColorsParts = Parts
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
        writeTargets = row.writeTargets, companionWrites = row.companionWrites,
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
            writeTargets = row.writeTargets, companionWrites = row.companionWrites,
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
    write = { source = G, convert = function(enabled) return enabled and "class" or "power" end,
        after = ApplyColors } --[[schema setter: J5.Colors.PowerMode]]
}
M.PowerBarColorByClass.Set = Schema.Setter({ id = "colors.powerColorMode", kind = "toggle",
    setting = "general.powerColorMode", write = M.PowerBarColorByClass.write })

-- Explicit load-time exports for the following responsibility modules.
Parts.ApiCall = ApiCall
Parts.ApiColorAt = ApiColorAt
Parts.ApiRGB = ApiRGB
Parts.ApiSetRGB = ApiSetRGB
Parts.ApiValue = ApiValue
Parts.ApplyAuraColors = ApplyAuraColors
Parts.ApplyBossTargetHighlightColor = ApplyBossTargetHighlightColor
Parts.ApplyCastbarColors = ApplyCastbarColors
Parts.ApplyColors = ApplyColors
Parts.ApplyGameplayColors = ApplyGameplayColors
Parts.ApplyGlobalOutlineColor = ApplyGlobalOutlineColor
Parts.ApplyPortraitColors = ApplyPortraitColors
Parts.ApplyUnitframeColorWithReload = ApplyUnitframeColorWithReload
Parts.Build = Build
Parts.BuildApiColorSpecs = BuildApiColorSpecs
Parts.BuildApiOrGeneralColorSpecs = BuildApiOrGeneralColorSpecs
Parts.BuildTableColorSpecs = BuildTableColorSpecs
Parts.ButtonAt = ButtonAt
Parts.COLOR_DATA = COLOR_DATA
Parts.CP = CP
Parts.C_Timer = C_Timer
Parts.Card = Card
Parts.ClassColorRGB = ClassColorRGB
Parts.ClassDefaultRGB = ClassDefaultRGB
Parts.ClearRGB = ClearRGB
Parts.ClearRGBAs = ClearRGBAs
Parts.ClearRGBs = ClearRGBs
Parts.ColorAPI = ColorAPI
Parts.ColorValueAt = ColorValueAt
Parts.ColorsSection = ColorsSection
Parts.CurrentApplyService = CurrentApplyService
Parts.CurrentBarsScope = CurrentBarsScope
Parts.DB = DB
Parts.FILE = FILE
Parts.FONT = FONT
Parts.G = G
Parts.GP = GP
Parts.Gameplay = Gameplay
Parts.GeneralColorAt = GeneralColorAt
Parts.GeneralRGB = GeneralRGB
Parts.GeneralRGBAlias = GeneralRGBAlias
Parts.GradientScopeGet = GradientScopeGet
Parts.GradientScopeSet = GradientScopeSet
Parts.HighlightRGB = HighlightRGB
Parts.LabelAt = LabelAt
Parts.Meta = Meta
Parts.MoveWidget = MoveWidget
Parts.NormalizeScopeKey = NormalizeScopeKey
Parts.Opt = Opt
Parts.Owned = Owned
Parts.PixelLayoutRegion = PixelLayoutRegion
Parts.ReadNameColor = ReadNameColor
Parts.RegisterControl = RegisterControl
Parts.RequestGeneral = RequestGeneral
Parts.ResetAuraColorSettings = ResetAuraColorSettings
Parts.ResetNPCColors = ResetNPCColors
Parts.ResetUnitframeColors = ResetUnitframeColors
Parts.Schema = Schema
Parts.SchemaRows = SchemaRows
Parts.ScopeHasOverride = ScopeHasOverride
Parts.SetAllPortraitRGB = SetAllPortraitRGB
Parts.SetControlEnabled = SetControlEnabled
Parts.SetControlsEnabled = SetControlsEnabled
Parts.SetGeneralRGB = SetGeneralRGB
Parts.SetGeneralRGBAlias = SetGeneralRGBAlias
Parts.SetHighlightRGB = SetHighlightRGB
Parts.SetTableRGB = SetTableRGB
Parts.SliderAt = SliderAt
Parts.SwitchAt = SwitchAt
Parts.T = T
Parts.TableColorAt = TableColorAt
Parts.TableRGB = TableRGB
Parts.TrText = TrText
Parts.UnitColorRows = UnitColorRows
Parts.ValueDropdownAt = ValueDropdownAt
Parts.ValueSliderAt = ValueSliderAt
Parts.ValueSwitchAt = ValueSwitchAt
Parts.ValueTextPairs = ValueTextPairs
Parts.ValueToggleAt = ValueToggleAt
Parts.W = W
Parts.floor = floor
Parts.max = max
Parts.min = min
