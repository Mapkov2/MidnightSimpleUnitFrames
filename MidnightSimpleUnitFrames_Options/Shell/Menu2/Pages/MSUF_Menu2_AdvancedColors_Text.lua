-- AdvancedColors: Text responsibility.
local addonName, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.AdvancedColorsParts
local ApiCall = Parts.ApiCall
local ApiColorAt = Parts.ApiColorAt
local ApiRGB = Parts.ApiRGB
local ApplyAuraColors = Parts.ApplyAuraColors
local ApplyColors = Parts.ApplyColors
local ApplyPortraitColors = Parts.ApplyPortraitColors
local ApplyUnitframeColorWithReload = Parts.ApplyUnitframeColorWithReload
local Build = Parts.Build
local ButtonAt = Parts.ButtonAt
local COLOR_DATA = Parts.COLOR_DATA
local CP = Parts.CP
local Card = Parts.Card
local ClassColorRGB = Parts.ClassColorRGB
local ClassDefaultRGB = Parts.ClassDefaultRGB
local ClearRGB = Parts.ClearRGB
local ColorAPI = Parts.ColorAPI
local ColorValueAt = Parts.ColorValueAt
local ColorsSection = Parts.ColorsSection
local CurrentApplyService = Parts.CurrentApplyService
local DB = Parts.DB
local FONT = Parts.FONT
local G = Parts.G
local GeneralRGB = Parts.GeneralRGB
local LabelAt = Parts.LabelAt
local Meta = Parts.Meta
local Owned = Parts.Owned
local ReadNameColor = Parts.ReadNameColor
local RegisterControl = Parts.RegisterControl
local RequestGeneral = Parts.RequestGeneral
local ResetAuraColorSettings = Parts.ResetAuraColorSettings
local Schema = Parts.Schema
local SchemaRows = Parts.SchemaRows
local SetAllPortraitRGB = Parts.SetAllPortraitRGB
local SetControlEnabled = Parts.SetControlEnabled
local T = Parts.T
local TableColorAt = Parts.TableColorAt
local TableRGB = Parts.TableRGB
local TrText = Parts.TrText
local ValueDropdownAt = Parts.ValueDropdownAt
local ValueSliderAt = Parts.ValueSliderAt
local ValueSwitchAt = Parts.ValueSwitchAt
local ValueTextPairs = Parts.ValueTextPairs
local W = Parts.W
local floor = Parts.floor
local max = Parts.max
local min = Parts.min

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
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "general.nameColorMode", "general.nameClassColor" },
            set = function(r, g2, b2)
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


-- Explicit load-time exports for the following responsibility modules.
