local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
-- Core functions this page calls by their global names: required here at
-- load, resolved through MSUF.Require on first use (see Core below).
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua"
M.RequireGlobals("Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua", {
    "MSUF_Tooltip_ShowEditPreview",
    "MSUF_SetGameMenuButtonEnabled",
    "MSUF_Grid2EditMode_SetEnabled",
    "MSUF_DetailsEditMode_SetEnabled",
    "MSUF_DominosEditMode_SetEnabled",
    "MSUF_DandersEditMode_SetEnabled",
    "MSUF_SetMinimapIconEnabled",
})
-- Core functions resolve through MSUF.Require on their first use and are read from
-- this table afterwards, so a value path (switch callback, dropdown write) never calls Require.
local Core = setmetatable({}, { __index = function(core, name)
    local fn = MSUF.Require(name, FILE)
    core[name] = fn
    return fn
end })
-- The Blizzard Edit Mode adapter exists only where the client has the Edit
-- Mode system (MSUF.Client.SupportsBlizzardEditMode, Game/Shared/Initialize.lua);
-- elsewhere Shell/EditMode/MSUF_EditMode_Blizzard.lua exports nothing, so the
-- adapter is required only with the capability on and its switch stays
-- disabled without it, as the profile and reset paths gate it.
local SUPPORTS_BLIZZARD_EDIT_MODE = MSUF.Client.SupportsBlizzardEditMode == true
if SUPPORTS_BLIZZARD_EDIT_MODE then
    MSUF.Require("MSUF_BlizzardEditMode_SetEnabled", FILE)
end

-- Menu2 global Misc page.
-- Binds tooltip provider/anchor/modifier behavior and small global UI options. Tooltip
-- rendering itself is handled by runtime tooltip modules.
local W = M.Widgets
local Schema = M.ControlSchema
local ROW_OPTIONS = Schema.UnitOptions()
local T = M.Theme
local GP = M.GlobalPage or {}
local max = math.max
local min = math.min
local C_Timer = M.MenuTimer or C_Timer
local G, ReadG, SetG, ReadGBool, SetGBool, MenuFontValues = GP.G, GP.ReadG, GP.SetG, GP.ReadGBool, GP.SetGBool, GP.MenuFontValues
local MenuFontKeyGet, MenuFontKeySet, ControlMeta = GP.MenuFontKeyGet, GP.MenuFontKeySet, GP.ControlMeta
local SETTING_KEY_BY_PATH = {
    ["language.selection"] = "general.menuLocale",
    ["menu.font"] = "general.menuFontKey",
    ["tooltips.provider"] = "general.unitTooltipProvider",
    ["tooltips.anchor"] = "general.unitTooltipAnchor",
    ["tooltips.visibility_mode"] = "general.unitTooltipMode",
    ["tooltips.modifier"] = "general.unitTooltipModifier",
    ["mouseover.style"] = "general.highlightStyle",
    ["mouseover.size"] = "general.highlightThickness",
}
local function Meta(path, classification, exact)
    exact = type(exact) == "table" and exact or {}
    if exact.settingKey == nil then
        exact.settingKey = SETTING_KEY_BY_PATH[path]
        if exact.settingKey == nil then
            local dbKey = tostring(path or ""):match("^setting%.(.+)$")
            if dbKey then exact.settingKey = "general." .. dbKey end
        end
    end
    return ControlMeta("opt_misc", "global", path, classification, exact)
end
local VT = M.ValueTextList
local TOOLTIP_MODES = VT("ALWAYS", "Always", "OOC", "Out of Combat", "MODIFIER", "Modifier Key", "NEVER", "Never")
local TOOLTIP_MODIFIERS = VT("ALT", "Alt", "CTRL", "Ctrl", "SHIFT", "Shift")
local MOUSEOVER_STYLES = VT("GRADIENT", "Soft gradient", "BORDER", "Solid border")
local ABBREV_STYLES = VT("GAME", "Game default", "COMPACT", "Compact")
--- Sample ladder for the live example line: one value per breakpoint tier so
--- the difference between the client's locale output and MSUF's compact form is
--- visible without any explanatory text.
local ABBREV_SAMPLES = { 123, 12345, 123456, 1234567, 12345678, 1234567890 }
local MENU_WRITE_OPTS = { preview = false, applyAll = false, notify = false }
local MOUSEOVER_WRITE_OPTS = { preview = false, applyAll = false, mouseoverHighlight = true }
local PREVIEW_FALSE = { preview = false }
-- Code family from the client model (WoW Forever is Mainline whatever project ID
-- it reports), so the raw project is never asked here.
local IS_MAINLINE = MSUF.Client.Family == "Mainline"
local function NormalizeTooltipMode(mode)
    if mode == "OOC" or mode == "MODIFIER" or mode == "NEVER" then return mode end
    if mode == "OFF" then return "NEVER" end
    return "ALWAYS"
end
local function NormalizeTooltipModifier(modifier)
    if modifier == "CTRL" or modifier == "SHIFT" then return modifier end
    return "ALT"
end
local function ReadTooltipProvider()
    local provider = ReadG("unitTooltipProvider", nil)
    if provider == "MSUF" then return "MSUF" end
    if provider == "GAME" then return "GAME" end
    return ReadGBool("disableUnitInfoTooltips", true) and "GAME" or "MSUF"
end
local function ReadTooltipAnchor()
    local anchor = ReadG("unitTooltipAnchor", nil)
    if anchor == "EXTERNAL" or anchor == "FIXED" or anchor == "CURSOR" then return anchor end
    if ReadTooltipProvider() == "MSUF" then return (ReadG("unitInfoTooltipStyle", "classic") == "modern") and "CURSOR" or "FIXED" end
    if type(ReadG("tooltipPosX", nil)) == "number" and type(ReadG("tooltipPosY", nil)) == "number" then return "FIXED" end
    if ReadG("unitInfoTooltipStyle", "classic") == "modern" then return "CURSOR" end
    return "EXTERNAL"
end
local function ReadTooltipMode()
    return NormalizeTooltipMode(ReadG("unitTooltipMode", "ALWAYS"))
end
local function ReadTooltipModifier()
    return NormalizeTooltipModifier(ReadG("unitTooltipModifier", "ALT"))
end
local function RefreshTooltipPreview()
    local tooltips = MSUF and MSUF.Tooltips
    if tooltips and type(tooltips.Refresh) == "function" then tooltips.Refresh() end
    if MSUF_UnitEditModeActive == true then Core.MSUF_Tooltip_ShowEditPreview() end
end
local function RefreshAuraTooltipSettings(reason)
    local a3 = MSUF and MSUF.MSUF_Auras3
    if a3 and type(a3.RequestApply) == "function" then
        a3.RequestApply("shared", reason or "MSUF2_AURA_TOOLTIP_SETTINGS")
    end
end
local function WriteTooltipSettings(provider, anchor)
    provider = (provider == "MSUF") and "MSUF" or "GAME"
    if anchor ~= "FIXED" and anchor ~= "CURSOR" and anchor ~= "EXTERNAL" then anchor = "EXTERNAL" end
    if provider == "MSUF" and anchor == "EXTERNAL" then anchor = "FIXED" end
    SetG("unitTooltipProvider", provider, "MSUF2_TOOLTIP_PROVIDER", { preview = false })
    SetG("unitTooltipAnchor", anchor, "MSUF2_TOOLTIP_ANCHOR", { preview = false })
    SetGBool("disableUnitInfoTooltips", provider ~= "MSUF", "MSUF2_TOOLTIPS", { preview = false })
    SetG("unitInfoTooltipStyle", (anchor == "CURSOR") and "modern" or "classic", "MSUF2_TOOLTIP_STYLE", { preview = false })
    RefreshTooltipPreview()
    RefreshAuraTooltipSettings("MSUF2_AURA_TOOLTIP_APPEARANCE")
end
local function WriteTooltipBehavior(mode, modifier)
    mode = NormalizeTooltipMode(mode)
    modifier = NormalizeTooltipModifier(modifier)
    SetG("unitTooltipMode", mode, "MSUF2_TOOLTIP_MODE", { preview = false, applyAll = false, notify = false })
    SetG("unitTooltipModifier", modifier, "MSUF2_TOOLTIP_MODIFIER", { preview = false, applyAll = false, notify = false })
    RefreshTooltipPreview()
end
-- A muted, word-wrapped help line under a control.
local function HelpText(ctx, parent, id, text, x, y, width)
    local help = Schema.Build(ctx, parent, {
        { "text", id, nil, { text, x, y, width, T.colors.muted } },
    })[id]
    if help.SetWordWrap then help:SetWordWrap(true) end
end
local function ShowReloadPrompt(key, text)
    M.ShowPrompt(key, {
        text = text,
        accept = RELOADUI or M.Tr("Reload"),
        cancel = CANCEL or M.Tr("Not now"),
        onAccept = function() ReloadUI() end,
    })
end
-- An integration switch (on by default, no preview refresh) that hands its value to the
-- core function setter and carries its hover text. A nil setter leaves the switch disabled.
local function BindIntegrationToggle(s, parent, label, key, reason, y, setter, tipTitle, tipText)
    local toggle = s.BindMiscToggle(parent, label, key, true, reason, 14, y, 430, PREVIEW_FALSE,
        function(value) if setter then Core[setter](value) end end)
    if not setter then W.SetControlEnabled(toggle, false) end
    M.AddTooltip(toggle, tipTitle, tipText, { hook = true })
end
-- The Miscellaneous page builds its sections in page order through these
-- functions; s carries the page context, the builder, the binders and the
-- few values a later section reads.
local MiscSection = {}
function MiscSection.Binders(s)
    local ctx = s.ctx
    local function BindMiscToggle(parent, label, key, default, reason, x, y, width, opts, afterSet)
        local control = Schema.Build(ctx, parent, {
            { "flowToggle", key, default, { label },
            companionWrites = key == "showMinimapIcon"
                and { "general.minimapIconDB.hide", "general.minimapIconDB.minimapPos" } or nil,
            get = function() return ReadGBool(key, default) end,
            write = { call = SetGBool, keyOnly = true, args = { reason, opts or PREVIEW_FALSE }, after = afterSet }, --[[schema setter: GlobalMisc.1]]
            meta = Meta("setting." .. key), domain = "global" },
        }, ROW_OPTIONS)[key]
        if x then W.MoveWidget(control, parent, x, y, width, "LEFT") end
        return control
    end
    local function BindMiscDropdown(parent, label, values, width, x, y, getValue, setValue, path, writePolicy)
        local companions
        if path == "setting.menuAppearancePreset" then
            companions = { "general.menuAccent", "general.menuAccentTintSurfaces" }
        elseif path == "tooltips.provider" or path == "tooltips.anchor" then
            companions = { "general.unitTooltipProvider", "general.unitTooltipAnchor",
                "general.disableUnitInfoTooltips", "general.unitInfoTooltipStyle" }
        elseif path == "tooltips.visibility_mode" or path == "tooltips.modifier" then
            companions = { "general.unitTooltipMode", "general.unitTooltipModifier" }
        end
        local control = Schema.Build(ctx, parent, {
            { "dropdown", path, nil, { label, values, width }, companionWrites = companions,
                get = getValue, customSetReason = "Normalizes menu options or coordinates tooltip companion fields and runtime state.",
                    set = setValue, write = writePolicy, meta = Meta(path), domain = "global" },
        }, ROW_OPTIONS)[path]
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end
    local function BindGroupTargetSwitch(parent, label, kind, x, y, width)
        local control = Schema.Build(ctx, parent, {
            { "switch", kind, true, { label, x, y, width },
            get = function()
                local groupPage = M.GroupPage
                if groupPage and type(groupPage.Bool) == "function" then
                    return groupPage.Bool(kind, "targetIndicator", true)
                end
                return true
            end,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.",
            write = { call = M.GroupPage.Set, group = true, boolean = true, args = { "visual" } } --[[schema setter: H4.GlobalMisc.1]],
            meta = Meta("group_target." .. kind, "setting", {
                settingKey = "gf_" .. kind .. ".targetIndicator",
            }), domain = "global" },
        }, ROW_OPTIONS)[kind]
        return control
    end
    s.BindMiscToggle, s.BindMiscDropdown = BindMiscToggle, BindMiscDropdown
    s.BindGroupTargetSwitch = BindGroupTargetSwitch
end
function MiscSection.Language(s)
    local ctx, b, BindMiscDropdown = s.ctx, s.b, s.BindMiscDropdown
    local language = Schema.Section(b:CollapsibleSection("misc_language", "Language", 268, true), ctx.key)
    local languageW = language._msuf2Width or ctx.width or 720
    local languageDropW = max(260, min(360, languageW - 70))
    local write = { call = SetG, keyOnly = true, fallback = "auto",
        args = { "MSUF2_LOCALE", { preview = false, applyAll = false, noRuntime = true } } }
        --[[schema setter: GlobalMisc.Language]]
    BindMiscDropdown(language, "Menu language", function()
        return (M.GetLocaleDropdownValues and M.GetLocaleDropdownValues()) or {
            { value = "auto", text = "Follow Blizzard" },
        }
    end, languageDropW, 30, -44,
        function()
            return (M.GetLocaleSelection and M.GetLocaleSelection()) or "auto"
        end,
        nil,
        "language.selection", write)
    HelpText(ctx, language, "menu2.opt_misc.language.languageHelp",
        "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus.", 30, -96, languageW - 70)
    -- Number abbreviation belongs here, not on the Fonts page: it is a locale
    -- formatting rule and it is global. The Fonts page is scope-aware, so a
    -- global control there would sit greyed out in 19 of 20 scopes and read as
    -- "per unit, but locked".
    local abbrevSegW = max(220, min(320, languageW - 70))
    local abbrevSample
    local function AbbrevStyle()
        local NumberFormat = MSUF.NumberFormat
        local style = ReadG("numberAbbrevStyle", "GAME")
        if NumberFormat and NumberFormat.NormalizeStyle then return NumberFormat.NormalizeStyle(style) end
        return style == "COMPACT" and "COMPACT" or "GAME"
    end
    -- The example line is rendered through the real C abbreviator, so it shows
    -- the running client's actual locale output instead of a guess.
    local function RefreshAbbrevSample()
        if not (abbrevSample and abbrevSample.SetText) then return end
        local NumberFormat = MSUF.NumberFormat
        if not (NumberFormat and NumberFormat.FormatWith) then abbrevSample:SetText("") return end
        local style, parts = AbbrevStyle(), {}
        for i = 1, #ABBREV_SAMPLES do
            parts[i] = NumberFormat.FormatWith(ABBREV_SAMPLES[i], style)
        end
        abbrevSample:SetText(table.concat(parts, "   "))
    end
    local abbrevSegment = Schema.Build(ctx, language, {
        { "segment", "setting.numberAbbrevStyle", nil, { "Number abbreviation", ABBREV_STYLES, abbrevSegW },
        get = AbbrevStyle,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", write = {
                call = SetG, keyOnly = true,
                convert = function(value) return value == "COMPACT" and "COMPACT" or "GAME" end,
                args = { "MSUF2_NUMBER_ABBREV", MENU_WRITE_OPTS }, after = function()
                    local NumberFormat = MSUF.NumberFormat
                    if NumberFormat and NumberFormat.Refresh then NumberFormat.Refresh() end
                    M.RequestGeneralDomains("MSUF2_NUMBER_ABBREV_TEXT", { text = true })
                    MSUF.GF.RefreshVisuals()
                    RefreshAbbrevSample()
                end
            } --[[schema setter: H4.GlobalMisc.2]],
        meta = Meta("setting.numberAbbrevStyle"), domain = "global",
        beforeBind = function(abbrevSegment)
            W.MoveWidget(abbrevSegment, language, 30, -134, abbrevSegW, "LEFT")
        end },
    }, ROW_OPTIONS)["setting.numberAbbrevStyle"]
    HelpText(ctx, language, "menu2.opt_misc.language.abbrevHelp",
        "Compact keeps 12.3K / 1.23M on every client language. Game default follows the client, which adds spaces or different letters on some locales.",
        30, -186, languageW - 70)
    abbrevSample = Schema.Custom(W.Text(language, "", 30, -232, languageW - 70, T.colors.text),
        { id = "menu2.opt_misc.language.abbrevSample", kind = "preview", scope = ctx.key, applyDomain = "preview" })
    RefreshAbbrevSample()
    if M.TrackRefresh then
        M.TrackRefresh(ctx, function()
            local NumberFormat = MSUF.NumberFormat
            if type(W.SetControlEnabled) == "function" and NumberFormat and NumberFormat.IsCompactSupported then
                W.SetControlEnabled(abbrevSegment, NumberFormat.IsCompactSupported() and true or false)
            end
            RefreshAbbrevSample()
        end)
    end
end
function MiscSection.MenuBehavior(s)
    local ctx, b, BindMiscToggle, BindMiscDropdown = s.ctx, s.b, s.BindMiscToggle, s.BindMiscDropdown
    local hasAppearancePresets = type(T.GetMenuAppearancePreset) == "function"
    local menuBehavior = Schema.Section(b:CollapsibleSection("misc_menu_behavior", "Menu behavior", hasAppearancePresets and 508 or 380, true), ctx.key)
    local menuBehaviorW = menuBehavior._msuf2Width or ctx.width or 720
    BindMiscToggle(menuBehavior, "Enable Windows-style edge snap for this menu", "slashMenuSnapEnabled", true, "MSUF2_MENU_SNAP", nil,
        nil, nil, MENU_WRITE_OPTS)
    HelpText(ctx, menuBehavior, "menu2.opt_misc.menuBehavior.menuSnapHelp",
        "Drag the MSUF menu to a screen side for a half-screen layout, to a corner for a quarter layout, or to the top edge for a maximized layout.",
        30, -72, menuBehaviorW - 70)
    BindMiscToggle(menuBehavior, "Hide Advanced menu section", "hideAdvancedMenu", true, "MSUF2_ADVANCED_MENU_VISIBILITY", 14, -118, 280, MENU_WRITE_OPTS,
        function() M.RefreshAdvancedNavVisibility() end)
    -- Defaults_Shell turns navigation icons on; an unset key reads the same.
    BindMiscToggle(menuBehavior, "Show navigation icons", "showNavigationIcons", true, "MSUF2_NAV_ICONS", 14, -148, 280, MENU_WRITE_OPTS,
        function() M.RefreshNavIconVisibility() end)
    BindMiscToggle(menuBehavior, "Show MSUF button in game menu", "showGameMenuButton", true, "MSUF2_GAME_MENU_BUTTON", 14, -178, 320, MENU_WRITE_OPTS,
        function(v) Core.MSUF_SetGameMenuButtonEnabled(v) end)
    BindMiscToggle(menuBehavior, "Reduce menu motion", "reduceMotion", false, "MSUF2_REDUCE_MOTION", 14, -208, 280, MENU_WRITE_OPTS)
    local menuFontRightX = max(350, floor(menuBehaviorW * 0.52))
    local menuFontW = max(250, min(340, menuBehaviorW - menuFontRightX - 30))
    BindMiscToggle(menuBehavior, "Show preview drag hint animation", "previewDragHintAnimationEnabled", true,
        "MSUF2_PREVIEW_DRAG_HINT", menuFontRightX, -222, menuFontW, MENU_WRITE_OPTS,
        function(enabled)
            local helpers = M.PreviewHelpers
            if enabled == false and helpers and type(helpers.HidePreviewMoveCue) == "function" then
                helpers.HidePreviewMoveCue()
            end
        end)
    local menuFontPreview
    BindMiscDropdown(menuBehavior, "MSUF menu font", function()
        return (type(MenuFontValues) == "function" and MenuFontValues()) or {
            { value = "", text = "Blizzard default" },
        }
    end, menuFontW, menuFontRightX, -118,
        function()
            return (type(MenuFontKeyGet) == "function" and MenuFontKeyGet()) or ReadG("menuFontKey", "")
        end,
        function(value)
            if type(MenuFontKeySet) == "function" then
                MenuFontKeySet(value)
            else
                SetG("menuFontKey", value or "", "MSUF2_MENU_FONT", MENU_WRITE_OPTS)
            end
            T.ClearMenuFontCache()
            T.RefreshMenuFonts()
            if menuFontPreview and menuFontPreview.SetText then
                menuFontPreview:SetText("AaBbCc 12345 - MSUF Menu")
            end
        end,
        "menu.font")
    menuFontPreview = Schema.Custom(W.Text(menuBehavior, "AaBbCc 12345 - MSUF Menu", menuFontRightX, -178,
        menuBehaviorW - menuFontRightX - 30, T.colors.text), { id = "menu2.opt_misc.menuBehavior.menuFontPreview",
        kind = "preview", scope = ctx.key, applyDomain = "preview" })
    if menuFontPreview.SetHeight then menuFontPreview:SetHeight(24) end
    if menuFontPreview.SetJustifyV then menuFontPreview:SetJustifyV("MIDDLE") end
    s.hasAppearancePresets, s.menuBehavior, s.menuBehaviorW = hasAppearancePresets, menuBehavior, menuBehaviorW
    s.menuFontRightX, s.menuFontW = menuFontRightX, menuFontW
end
function MiscSection.MenuAccent(s)
    local ctx, BindMiscToggle, BindMiscDropdown = s.ctx, s.BindMiscToggle, s.BindMiscDropdown
    local hasAppearancePresets, menuBehavior, menuBehaviorW = s.hasAppearancePresets, s.menuBehavior, s.menuBehaviorW
    local menuFontRightX, menuFontW = s.menuFontRightX, s.menuFontW
    local accentSwatch
    local function IsAccentMode(mode)
        if mode == "class" or mode == "custom" then return true end
        local presets = T.MENU_ACCENT_PRESETS
        return type(presets) == "table" and presets[mode] ~= nil
    end
    local function ReadAccentMode()
        local mode = ReadG("menuAccent", "midnight")
        if IsAccentMode(mode) then return mode end
        return "midnight"
    end
    local function AccentReloadCheck()
        local applied = T._menuAccentApplied
        local sig = type(T.MenuAccentSignature) == "function" and T.MenuAccentSignature(M.GetGeneralDB and M.GetGeneralDB()) or nil
        if applied and sig and sig ~= applied then
            -- Re-showing an already-visible popup replays its open sound; guard
            -- so live color-picker painting cannot spam it.
            if not M.IsPromptShown("MSUF2_ACCENT_RELOAD_REQUIRED") then
                ShowReloadPrompt("MSUF2_ACCENT_RELOAD_REQUIRED",
                    M.Tr("The menu accent color is baked in while the menu is built, so a UI reload is required to apply it.\n\nReload now?"))
            end
        else
            M.HidePrompt("MSUF2_ACCENT_RELOAD_REQUIRED")
        end
    end
    local accentCheckTimer
    local function QueueAccentReloadCheck()
        if accentCheckTimer and accentCheckTimer.Cancel then accentCheckTimer:Cancel() end
        if not (C_Timer and C_Timer.NewTimer) then return AccentReloadCheck() end
        accentCheckTimer = C_Timer.NewTimer(0.45, function()
            accentCheckTimer = nil
            AccentReloadCheck()
        end)
    end
    local accentTint
    local function RefreshAccentSwatchEnabled()
        local mode = ReadAccentMode()
        if accentSwatch then W.SetControlEnabled(accentSwatch, mode == "custom") end
        -- Tinting only means anything once an accent replaces midnight.
        if accentTint then W.SetControlEnabled(accentTint, mode ~= "midnight") end
    end
    BindMiscDropdown(menuBehavior, "Menu accent color",
        VT("midnight", hasAppearancePresets and "Preset accent (default)" or "Midnight (default)", "class", "Class color",
            "ember", "Ember", "jade", "Jade", "violet", "Violet",
            "custom", "Custom"),
        hasAppearancePresets and menuFontW or 250, hasAppearancePresets and menuFontRightX or 14, -244,
        ReadAccentMode,
        function(value)
            if not IsAccentMode(value) then value = "midnight" end
            SetG("menuAccent", value, "MSUF2_MENU_ACCENT", MENU_WRITE_OPTS)
            RefreshAccentSwatchEnabled()
            AccentReloadCheck()
        end,
        "setting.menuAccent")
    accentSwatch = Schema.Build(ctx, menuBehavior, {
        { "color", "setting.menuAccentColor", nil, { "Custom accent color" },
        get = function()
            local r, g2, b2 = T.MenuAccentHexToRGB(ReadG("menuAccentColor", "3b82f6"))
            if not r then r, g2, b2 = 0.231, 0.510, 0.965 end
            return r, g2, b2
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.", set = function(r, g2, b2)
            SetG("menuAccentColor", T.MenuAccentRGBToHex(r, g2, b2), "MSUF2_MENU_ACCENT_COLOR", MENU_WRITE_OPTS)
            QueueAccentReloadCheck()
        end,
        meta = Meta("setting.menuAccentColor"), domain = "global" },
    }, ROW_OPTIONS)["setting.menuAccentColor"]
    if accentSwatch._msuf2Title then
        accentSwatch._msuf2Title:ClearAllPoints()
        accentSwatch._msuf2Title:SetPoint("TOPLEFT", menuBehavior, "TOPLEFT", menuFontRightX, hasAppearancePresets and -312 or -256)
        accentSwatch._msuf2Title:SetWidth(170)
    end
    accentSwatch:ClearAllPoints()
    accentSwatch:SetPoint("TOPLEFT", menuBehavior, "TOPLEFT", menuFontRightX + 182, hasAppearancePresets and -310 or -254)
    accentTint = BindMiscToggle(menuBehavior, "Tint menu surfaces", "menuAccentTintSurfaces", false,
        "MSUF2_MENU_ACCENT_TINT", 14, hasAppearancePresets and -308 or -292, 320, MENU_WRITE_OPTS, AccentReloadCheck)
    -- One string literal, not a concatenation: the locale coverage gate reads
    -- literals, so a split body would demand a key per fragment.
    M.AddTooltip(accentTint, "Tint menu surfaces",
        T.classicAtlas and "Off (default): panels keep the Classic Glass appearance. On: panels and navigation follow your accent color. Success, " ..
            "warning and danger colors never change."
            or "Off (default): the accent colors buttons, tabs and highlights while panels keep the selected look. On: panels, borders and the " ..
                "navigation rail follow the accent too. Success, warning and danger colors never change.",
        { hook = true })
    M.TrackRefresh(ctx, RefreshAccentSwatchEnabled)
    HelpText(ctx, menuBehavior, "menu2.opt_misc.menuBehavior.accentHelp", hasAppearancePresets
        and "Background opacity changes the MSUF Forever background only; text stays fully opaque."
        or "Midnight keeps the stock blue accent. Class color follows this character; the accent applies after a UI reload.",
        30, hasAppearancePresets and -450 or -330, menuBehaviorW - 70)
    if hasAppearancePresets then
        BindMiscDropdown(menuBehavior, "Menu appearance preset",
            VT("classicGlass", "MSUF Forever", "midnight", "Midnight Blue",
                "midnightDark", "Midnight Dark",
                "class", "Class color", "ember", "Ember", "jade", "Jade", "violet", "Violet", "custom", "Custom"),
            250, 14, -244,
            function()
                local accent = ReadAccentMode()
                return accent ~= "midnight" and accent or T.GetMenuAppearancePreset(M.GetGeneralDB())
            end,
            function(value)
                if value == "classicGlass" or value == "midnight" or value == "midnightDark" then
                    SetG("menuAppearancePreset", value, "MSUF2_MENU_APPEARANCE", MENU_WRITE_OPTS)
                    SetG("menuAccent", "midnight", "MSUF2_MENU_APPEARANCE", MENU_WRITE_OPTS)
                    SetG("menuAccentTintSurfaces", false, "MSUF2_MENU_APPEARANCE", MENU_WRITE_OPTS)
                    local skin = MapkoSkin
                    if skin and skin.addonName == "MSUF_Suite_Skin"
                        and skin.Theme and skin.Theme.ApplyLook then
                        local look = value == "classicGlass" and "foreverGlass" or value
                        skin.Theme.ApplyLook(look)
                    end
                elseif IsAccentMode(value) then
                    -- Legacy color presets keep the chosen materials and saved custom color.
                    SetG("menuAccent", value, "MSUF2_MENU_APPEARANCE", MENU_WRITE_OPTS)
                else
                    return
                end
                RefreshAccentSwatchEnabled()
                ShowReloadPrompt("MSUF2_APPEARANCE_RELOAD_REQUIRED", M.Tr("Reload the UI to apply the menu appearance preset?"))
            end,
            "setting.menuAppearancePreset")
        local opacity = Schema.Build(ctx, menuBehavior, {
            { "slider", "setting.menuBackgroundOpacity", nil, { "Background opacity", 80, 100, 1, 250 },
                get = function() return T.GetMenuBackgroundOpacity(M.GetGeneralDB()) end,
                write = { call = SetG, keyOnly = true, args = { "MSUF2_MENU_BACKGROUND", MENU_WRITE_OPTS },
                    after = function() if T.RefreshMenuBackgroundOpacity then T.RefreshMenuBackgroundOpacity() end end }, --[[schema setter: GlobalMisc.5]]
                meta = Meta("setting.menuBackgroundOpacity"), domain = "global",
                beforeBind = function(opacity)
                    if opacity.SetValueFormatter then opacity:SetValueFormatter(function(v) return M.Format("%d%%", v) end) end
                end },
        }, ROW_OPTIONS)["setting.menuBackgroundOpacity"]
        W.MoveWidget(opacity, menuBehavior, 14, -372, 250, "LEFT")
        W.SetControlEnabled(opacity, T.classicAtlas == true)
    end
end
function MiscSection.Integrations(s)
    local ctx, b, BindMiscToggle, menuBehaviorW = s.ctx, s.b, s.BindMiscToggle, s.menuBehaviorW
    local mapkoSkin = Schema.Section(b:CollapsibleSection("misc_mapkoskin", "MapkoSkin", 108, true), ctx.key)
    BindMiscToggle(mapkoSkin, "Use MapkoSkin for MSUF menus", "mapkoSkinMenus", true,
        "MSUF2_MAPKOSKIN_MENUS", 14, -42, 360, MENU_WRITE_OPTS,
        function() if MSUF.MenuSkin then MSUF.MenuSkin.Refresh() end end)
    Schema.Build(ctx, mapkoSkin, {
        { "text", "menu2.opt_misc.mapkoSkin.mapkoSkinHelp", nil,
            { "Requires MapkoSkin API 2.1. Disabling restores the MSUF look; unit frames and profile colors are unchanged.",
            30, -76, menuBehaviorW - 70, T.colors.muted } },
    })
    local startup = Schema.Section(b:CollapsibleSection("misc_startup", "Startup", 124, true), ctx.key)
    BindMiscToggle(startup, "Show welcome message", "showWelcomeMessage", true, "MSUF2_WELCOME", 14, -42, 320)
    BindMiscToggle(startup, "Enable version check (peer-to-peer)", "versionCheckEnabled", true, "MSUF2_VERSION_CHECK", 14, -76, 360, nil,
        function() Core.MSUF_ApplyModules() end)
    local nicknameIntegration = Schema.Section(b:CollapsibleSection("misc_nickname_integration", "Nickname Integration", 124, true), ctx.key)
    BindIntegrationToggle(s, nicknameIntegration, "Use NSRT nicknames on MSUF frames", "nsrtNicknameIntegration",
        "MSUF2_NSRT_NICKNAMES", -42, "MSUF_NSRTNicknames_ApplySetting", "NSRT nickname integration",
        "On (default): names supplied by Northern Sky Raid Tools replace character names on MSUF unit and group frames. Turn this off to always show " ..
            "character names in MSUF. NSRT and its settings are not modified.")
    -- The EllesmereUI bridge loads on the Mainline TOC only (Midnight and WoW
    -- Forever); the section exists only where it does and EllesmereUI is loaded.
    local ellesmereAvailable = MSUF.Optional("MSUF_EllesmereEditMode_IsAvailable")
    if ellesmereAvailable and ellesmereAvailable() then
        local ellesmere = Schema.Section(b:CollapsibleSection("misc_ellesmere_ui", "EllesmereUI", 138, true), ctx.key)
        BindIntegrationToggle(s, ellesmere, "Use EllesmereUI Unlock Mode for MSUF", "ellesmereEditModeIntegration",
            "MSUF2_ELLESMERE_EDIT_MODE", -42, "MSUF_EllesmereEditMode_SetEnabled", "EllesmereUI Unlock Mode",
            "On (default): MSUF frames appear in EllesmereUI Unlock Mode. Turn this off to keep using the native MSUF Edit Mode. MSUF profile " ..
                "positions remain the source of truth.")
        HelpText(ctx, ellesmere, "menu2.opt_misc.ellesmere.ellesmereHelp",
            "This switch is shown only while EllesmereUI is loaded. Disabling it immediately returns MSUF to its own Edit Mode.",
            30, -88, (ellesmere._msuf2Width or ctx.width or 720) - 70)
    end
end
function MiscSection.ExternalEditMode(s)
    local ctx, b = s.ctx, s.b
    local external = Schema.Section(b:CollapsibleSection("misc_external_edit_mode", "External Edit Mode", 298, true), ctx.key)
    BindIntegrationToggle(s, external, "Show Grid2 in MSUF Edit Mode", "grid2EditModeIntegration",
        "MSUF2_GRID2_EDIT_MODE", -42, "MSUF_Grid2EditMode_SetEnabled", "Grid2 Edit Mode integration",
        "On (default): MSUF Edit Mode can move the Grid2 layout and its active detached groups. Grid2 remains the owner of its layout and saved positions.")
    BindIntegrationToggle(s, external, "Show Details! in MSUF Edit Mode", "detailsEditModeIntegration",
        "MSUF2_DETAILS_EDIT_MODE", -78, "MSUF_DetailsEditMode_SetEnabled", "Details! Edit Mode integration",
        "On (default): MSUF Edit Mode can move every active Details! window. Windows snapped together by Details! move as one native group.")
    BindIntegrationToggle(s, external, "Show Dominos in MSUF Edit Mode", "dominosEditModeIntegration",
        "MSUF2_DOMINOS_EDIT_MODE", -114, "MSUF_DominosEditMode_SetEnabled", "Dominos Edit Mode integration",
        "On (default): MSUF Edit Mode can move every Dominos bar that is not docked to another bar. Docked bars follow their host bar, and Dominos " ..
            "remains the owner of all bar positions.")
    BindIntegrationToggle(s, external, "Show DandersFrames in MSUF Edit Mode", "dandersEditModeIntegration",
        "MSUF2_DANDERS_EDIT_MODE", -150, "MSUF_DandersEditMode_SetEnabled", "DandersFrames Edit Mode integration",
        "On (default): MSUF Edit Mode can move the DandersFrames party and raid containers and free pinned sets. Sets glued to the frames follow them, " ..
            "and DandersFrames remains the owner of all saved positions.")
    BindIntegrationToggle(s, external, "Show Blizzard frames in MSUF Edit Mode", "blizzardEditModeIntegration",
        "MSUF2_BLIZZARD_EDIT_MODE", -186, SUPPORTS_BLIZZARD_EDIT_MODE and "MSUF_BlizzardEditMode_SetEnabled" or nil,
        "Blizzard Edit Mode integration",
        "On (default): MSUF Edit Mode can move the Blizzard Minimap, Chat, Micro Menu and Tooltip through the game's own Edit Mode layout. If a " ..
            "Blizzard preset is active, selecting an element creates and activates a saved 'MSUF' layout automatically.")
    HelpText(ctx, external, "menu2.opt_misc.external.externalHelp",
        "Turn any of these switches off to remove only those external movers. The third-party addons and their settings are not modified.",
        30, -232, (external._msuf2Width or ctx.width or 720) - 70)
end
function MiscSection.FrameHighlights(s)
    local ctx, b, BindMiscToggle, BindMiscDropdown = s.ctx, s.b, s.BindMiscToggle, s.BindMiscDropdown
    local BindGroupTargetSwitch = s.BindGroupTargetSwitch
    local mouseover = Schema.Section(b:CollapsibleSection("misc_mouseover_highlight", "Frame Highlights", 340, true), ctx.key)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(mouseover, { "highlight.mouseover" }, {
            title = "Mouseover Highlight Color",
            historySource = "menu:mouseover-highlight-color",
            offsetY = -8,
        })
    end
    local mouseoverW = mouseover._msuf2Width or ctx.width or 720
    local mouseoverLeftX = 30
    local mouseoverRightX = max(mouseoverLeftX + 300, floor(mouseoverW * 0.52))
    local mouseoverLeftW = max(240, min(280, mouseoverRightX - mouseoverLeftX - 40))
    local mouseoverRightW = max(220, min(300, mouseoverW - mouseoverRightX - 36))
    local enabled = BindMiscToggle(mouseover, "Enable mouseover highlight", "highlightEnabled", true,
        "MSUF2_MOUSEOVER_HIGHLIGHT", 14, -10, 320, MOUSEOVER_WRITE_OPTS)
    local style = BindMiscDropdown(mouseover, "Style", MOUSEOVER_STYLES, mouseoverLeftW,
        mouseoverLeftX, -64,
        function()
            local value = tostring(ReadG("highlightStyle", "GRADIENT")):upper()
            return value == "BORDER" and "BORDER" or "GRADIENT"
        end,
        function(value)
            SetG("highlightStyle", value == "BORDER" and "BORDER" or "GRADIENT",
                "MSUF2_MOUSEOVER_STYLE", MOUSEOVER_WRITE_OPTS)
        end,
        "mouseover.style")
    local size = Schema.Build(ctx, mouseover, {
        { "slider", "mouseover.size", 6, { "Effect size", 1, 16, 1, mouseoverRightW },
        get = function() return floor((tonumber(ReadG("highlightThickness", 6)) or 6) + 0.5) end,
        write = { call = SetG, keyOnly = true, numberDefault = 6, round = true,
                args = { "MSUF2_MOUSEOVER_SIZE", MOUSEOVER_WRITE_OPTS } } --[[schema setter: GlobalMisc.6]],
        meta = Meta("mouseover.size", "setting", { min = 1, max = 16, step = 1, format = "%d px" }), domain = "global",
        beforeBind = function(size)
            if size.SetValueFormatter then
                size:SetValueFormatter(function(value) return M.Format("%d px", floor((tonumber(value) or 6) + 0.5)) end)
            end
        end },
    }, ROW_OPTIONS)["mouseover.size"]
    W.MoveWidget(size, mouseover, mouseoverRightX, -58, mouseoverRightW, "CENTER")
    local mouseoverHelp = Schema.Build(ctx, mouseover, {
        { "text", "menu2.opt_misc.mouseover.mouseoverHelp", nil,
            { M.Format("Soft gradient gives the whole frame a clear, portrait-safe hover cue. Solid border keeps a crisp edge. Choose its color in %s.",
            M.NavPath("opt_colors", "Player & Target Frames")), mouseoverLeftX, -142, mouseoverW - 68, T.colors.muted } },
    })["menu2.opt_misc.mouseover.mouseoverHelp"]
    if mouseoverHelp.SetWordWrap then mouseoverHelp:SetWordWrap(true) end
    local function RefreshMouseoverControls()
        local on = ReadGBool("highlightEnabled", true)
        W.SetControlEnabled(style, on)
        W.SetControlEnabled(size, on)
    end
    if enabled and enabled.HookScript then enabled:HookScript("OnClick", RefreshMouseoverControls) end
    M.TrackRefresh(ctx, RefreshMouseoverControls)
    local targetCardW = max(320, mouseoverW - 28)
    local targetCard = Schema.Build(ctx, mouseover, {
        { "card", "menu2.opt_misc.mouseover.targetCard", nil, { "Group Target Highlight",
            "Independent of mouseover. Marks your current target in the selected group-frame types.", 14, -198, targetCardW, 116 }, domain = "layout" },
    })["menu2.opt_misc.mouseover.targetCard"]
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(targetCard, { "group.target" }, {
            title = "Target Highlight Color",
            note = "Shared by Party, Raid and Mythic Raid.",
            historySource = "menu:group-target-highlight-color",
            offsetX = -76,
        })
    end
    local mythicSupported = not M.SupportsFrameScope or M.SupportsFrameScope("mythicraid")
    local targetColumnW = math.floor((targetCardW - 36) / (mythicSupported and 3 or 2))
    BindGroupTargetSwitch(targetCard, "Party frames", "party", 18, -78, targetColumnW - 42)
    BindGroupTargetSwitch(targetCard, "Raid frames", "raid", 18 + targetColumnW, -78, targetColumnW - 42)
    if mythicSupported then BindGroupTargetSwitch(targetCard, "Mythic Raid frames", "mythicraid", 18 + (targetColumnW * 2), -78, targetColumnW - 42) end
end
function MiscSection.Tooltips(s)
    local ctx, b, BindMiscToggle, BindMiscDropdown = s.ctx, s.b, s.BindMiscToggle, s.BindMiscDropdown
    -- Classic has no aura tooltip switch rows below the help text (-226 and -252).
    local tooltips = Schema.Section(b:CollapsibleSection("misc_tooltips", "Unitframe tooltips", IS_MAINLINE and 290 or 226, false), ctx.key)
    local tooltipW = tooltips._msuf2Width or ctx.width or 720
    local tooltipLeftX = 30
    local tooltipRightX = max(tooltipLeftX + 300, floor(tooltipW * 0.52))
    local tooltipLeftW = max(240, min(300, tooltipRightX - tooltipLeftX - 48))
    local tooltipRightW = max(220, min(300, tooltipW - tooltipRightX - 36))
    BindMiscDropdown(tooltips, "Tooltip source", VT("GAME", "GameTooltip (addon-compatible)", "MSUF", "MSUF custom panel"), tooltipLeftW, tooltipLeftX, -44,
        function() return ReadTooltipProvider() end,
        function(v) WriteTooltipSettings(v, ReadTooltipAnchor()) end,
        "tooltips.provider")
    BindMiscDropdown(tooltips, "Tooltip anchor", VT("EXTERNAL", "Addon / Blizzard controlled", "FIXED", "MSUF fixed position", "CURSOR", "MSUF cursor"),
        tooltipRightW, tooltipRightX, -44,
        function() return ReadTooltipAnchor() end,
        function(v) WriteTooltipSettings(ReadTooltipProvider(), v) end,
        "tooltips.anchor")
    local tooltipModifier
    local function RefreshTooltipControls()
        W.SetControlEnabled(tooltipModifier, ReadTooltipMode() == "MODIFIER")
    end
    BindMiscDropdown(tooltips, "Show unitframe tooltips", TOOLTIP_MODES, tooltipLeftW, tooltipLeftX, -112,
        function() return ReadTooltipMode() end,
        function(v)
            WriteTooltipBehavior(v, ReadTooltipModifier())
            RefreshTooltipControls()
        end,
        "tooltips.visibility_mode")
    tooltipModifier = BindMiscDropdown(tooltips, "Modifier key", TOOLTIP_MODIFIERS, tooltipRightW, tooltipRightX, -112,
        function() return ReadTooltipModifier() end,
        function(v) WriteTooltipBehavior(ReadTooltipMode(), v) end,
        "tooltips.modifier")
    M.TrackRefresh(ctx, RefreshTooltipControls)
    HelpText(ctx, tooltips, "menu2.opt_misc.tooltips.tooltipHelp",
        "Visibility modes apply only to unit and group frames. Aura tooltips use their own Show Tooltip switches; even Never does not override them. " ..
            "Auras only reuse the selected Blizzard/MSUF look and cursor placement.",
        tooltipLeftX, -174, tooltipW - 68)
    -- Both aura tooltip switches drive client options through
    -- Runtime/MSUF_TooltipSpellIDs.lua, and only the Mainline TOC loads that file.
    -- Classic clients would get switches that write settings and change nothing.
    if IS_MAINLINE then
        local tooltipSpellIDs = BindMiscToggle(tooltips, "Show spell IDs in aura tooltips", "tooltipShowAuraSpellIDs", false,
            "MSUF2_TOOLTIP_SPELL_IDS", 14, -226, 360, PREVIEW_FALSE,
            function(v)
                Core.MSUF_ApplyTooltipSpellIDs(v and true or false)
            end)
        local tooltipCasterNames = BindMiscToggle(tooltips, "Show caster names in aura tooltips", "tooltipShowAuraCasterNames", false,
            "MSUF2_TOOLTIP_CASTER_NAMES", 14, -252, 360, PREVIEW_FALSE,
            function(v)
                Core.MSUF_ApplyTooltipCasterNames(v and true or false)
            end)
        M.AddTooltip(tooltipCasterNames, "Aura tooltip caster names",
            "On: aura tooltips name who applied the aura, coloured by reaction or class, through the game's own 12.1.5 option, and MSUF re-enables it " ..
                "after every login. Off (default): MSUF never touches the game option, so other addons or a manual console setting keep control; " ..
                    "turning this switch off clears the option once.",
            { hook = true })
        M.AddTooltip(tooltipSpellIDs, "Aura tooltip spell IDs",
            "On: aura tooltips show the numeric spell ID through the game's own 12.1 option, and MSUF re-enables that option after every login because " ..
                "the game forgets it between sessions. Off (default): MSUF never touches the game option, so other addons or a manual console setting " ..
                    "keep control; turning this switch off clears the option once.",
            { hook = true })
    end
end
function MiscSection.BlizzardFrames(s)
    local ctx, b, BindMiscToggle = s.ctx, s.b, s.BindMiscToggle
    --- Blizzard frame ownership is per unit ("Force Blizzard frame on" in each
    --- unit's Basics), so this section only carries the remaining
    --- Blizzard-adjacent chrome toggles.
    local blizzard = Schema.Section(b:CollapsibleSection("misc_blizzard_frames", "Blizzard Frames", IS_MAINLINE and 170 or 138, false), ctx.key)
    BindMiscToggle(blizzard, "Show MSUF minimap icon", "showMinimapIcon", true, "MSUF2_MINIMAP_ICON", nil, nil, nil, nil,
        function(v) Core.MSUF_SetMinimapIconEnabled(v) end)
    BindMiscToggle(blizzard, "Play sound on Target/Target Lost", "playTargetSelectLostSounds", false, "MSUF2_TARGET_SOUNDS", nil, nil, nil, nil,
        function(v)
            Core.MSUF_TargetSoundDriver_ResetState()
            if v then Core.MSUF_TargetSoundDriver_Ensure() end
        end)
    -- Resource pings need the ping system (Blizzard_PingUI and the PingableType
    -- mixins), which ships on Midnight and WoW Forever only. Classic Era, TBC and
    -- Mists define PingableUnitFrameTemplate as an empty stub, so there the switch
    -- would write a setting that changes nothing.
    if not IS_MAINLINE then return end
    local resourcePing = BindMiscToggle(blizzard, "Enable native Player resource pings (12.1)",
        "playerResourcePingEnabled", true, "MSUF2_PLAYER_RESOURCE_PING", nil, nil, nil, PREVIEW_FALSE,
        function() Core.MSUF_RefreshPlayerResourcePing() end)
    M.AddTooltip(resourcePing, "Native Player resource pings",
        "Contextual pings over the MSUF Player frame can call out health and, when Blizzard supports it, mana. Blizzard does not expose separate " ..
            "Health/Power selection or Energy, Rage and Focus pings. The portrait keeps the normal Player unit ping and radial wheel.",
        { hook = true })
end
local function BuildMisc(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Miscellaneous", "Language, menu behavior, frame highlights, tooltips and Blizzard frames.", 72)
    local s = { ctx = ctx, b = b }
    MiscSection.Binders(s)
    MiscSection.Language(s)
    MiscSection.MenuBehavior(s)
    MiscSection.MenuAccent(s)
    MiscSection.Integrations(s)
    MiscSection.ExternalEditMode(s)
    MiscSection.FrameHighlights(s)
    MiscSection.Tooltips(s)
    MiscSection.BlizzardFrames(s)
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_misc", { title = "MSUF Miscellaneous", build = BuildMisc, version = 17 })
