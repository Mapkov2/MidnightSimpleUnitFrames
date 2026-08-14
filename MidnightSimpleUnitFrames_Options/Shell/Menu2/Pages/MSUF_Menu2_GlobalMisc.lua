local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 global Misc page.
-- Binds tooltip provider/anchor/modifier behavior and small global UI options. Tooltip
-- rendering itself is handled by runtime tooltip modules.
local W = M.Widgets
local T = M.Theme
local GP = M.GlobalPage or {}
local max = math.max
local min = math.min
local C_Timer = M.MenuTimer or _G.C_Timer
local Call, G, ReadG, SetG, ReadGBool, SetGBool, MenuFontValues, MenuFontKeyGet, MenuFontKeySet, ControlMeta = M.Pick(GP, [[Call G ReadG SetG ReadGBool SetGBool MenuFontValues MenuFontKeyGet MenuFontKeySet ControlMeta]])
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
    local editActive = (_G.MSUF_UnitEditModeActive == true)
    if not editActive and type(_G.MSUF_IsMSUFEditModeActive) == "function" then editActive = _G.MSUF_IsMSUFEditModeActive() and true or false end
    if editActive and type(_G.MSUF_Tooltip_ShowEditPreview) == "function" then _G.MSUF_Tooltip_ShowEditPreview() end
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
local function BuildMisc(ctx)
    local b = W.PageBuilder(ctx)
    b:GlobalStyleHeader("Miscellaneous", "Language, menu behavior, frame highlights, tooltips and Blizzard frames.", 72)
    local function BindMiscToggle(parent, label, key, default, reason, x, y, width, opts, afterSet)
        local control = W.Toggle(parent, label)
        M.BindBoolWidget(ctx, control,
            function() return ReadGBool(key, default) end,
            function(v)
                SetGBool(key, v, reason, opts or PREVIEW_FALSE)
                M.CallIf(afterSet, v)
            end,
            Meta("setting." .. key))
        if x then W.MoveWidget(control, parent, x, y, width, "LEFT") end
        return control
    end
    local function BindMiscDropdown(parent, label, values, width, x, y, getValue, setValue, path)
        local control = M.BindDropdownWidget(ctx, W.Dropdown(parent, label, values, width), getValue, setValue, Meta(path))
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end
    local function BindGroupTargetSwitch(parent, label, kind, x, y, width)
        local control = W.SwitchAt(parent, label, x, y, width)
        M.BindBoolWidget(ctx, control,
            function()
                local groupPage = M.GroupPage
                if groupPage and type(groupPage.Bool) == "function" then
                    return groupPage.Bool(kind, "targetIndicator", true)
                end
                return true
            end,
            function(value)
                local groupPage = M.GroupPage
                if groupPage and type(groupPage.Set) == "function" then
                    groupPage.Set(kind, "targetIndicator", value and true or false, "visual")
                end
            end,
            Meta("group_target." .. kind, "setting", {
                settingKey = "gf_" .. kind .. ".targetIndicator",
            }))
        return control
    end
    local language = b:CollapsibleSection("misc_language", "Language", 268, true)
    local languageW = language._msuf2Width or ctx.width or 720
    local languageDropW = max(260, min(360, languageW - 70))
    BindMiscDropdown(language, "Menu language", function()
        return (M.GetLocaleDropdownValues and M.GetLocaleDropdownValues()) or {
            { value = "auto", text = "Follow Blizzard" },
        }
    end, languageDropW, 30, -44,
        function()
            return (M.GetLocaleSelection and M.GetLocaleSelection()) or "auto"
        end,
        function(value)
            value = value or "auto"
            SetG("menuLocale", value, "MSUF2_LOCALE", { preview = false, applyAll = false, noRuntime = true })
        end,
        "language.selection")
    local languageHelp = W.Text(language, "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus.", 30, -96, languageW - 70, T.colors.muted)
    if languageHelp.SetWordWrap then languageHelp:SetWordWrap(true) end
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
    local abbrevSegment = W.Segment(language, "Number abbreviation", ABBREV_STYLES, abbrevSegW)
    W.MoveWidget(abbrevSegment, language, 30, -134, abbrevSegW, "LEFT")
    M.BindSegment(ctx, abbrevSegment, AbbrevStyle, function(value)
        value = (value == "COMPACT") and "COMPACT" or "GAME"
        -- Persist without a runtime apply, push the new style, then repaint
        -- once - so the refresh already formats with the new options instead of
        -- painting stale text and correcting it on the next unit event.
        SetG("numberAbbrevStyle", value, "MSUF2_NUMBER_ABBREV", MENU_WRITE_OPTS)
        local NumberFormat = MSUF.NumberFormat
        if NumberFormat and NumberFormat.Refresh then NumberFormat.Refresh() end
        M.RequestGeneralApply("MSUF2_NUMBER_ABBREV_TEXT", { text = true })
        if type(_G.MSUF_GF_RefreshVisuals) == "function" then _G.MSUF_GF_RefreshVisuals() end
        RefreshAbbrevSample()
    end, Meta("setting.numberAbbrevStyle"))
    local abbrevHelp = W.Text(language, "Compact keeps 12.3K / 1.23M on every client language. Game default follows the client, which adds spaces or different letters on some locales.", 30, -186, languageW - 70, T.colors.muted)
    if abbrevHelp.SetWordWrap then abbrevHelp:SetWordWrap(true) end
    abbrevSample = W.Text(language, "", 30, -232, languageW - 70, T.colors.text)
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
    local menuBehavior = b:CollapsibleSection("misc_menu_behavior", "Menu behavior", 380, true)
    local menuBehaviorW = menuBehavior._msuf2Width or ctx.width or 720
    BindMiscToggle(menuBehavior, "Enable Windows-style edge snap for this menu", "slashMenuSnapEnabled", true, "MSUF2_MENU_SNAP", nil, nil, nil, MENU_WRITE_OPTS)
    local menuSnapHelp = W.Text(menuBehavior, "Drag the MSUF menu to a screen side for a half-screen layout, to a corner for a quarter layout, or to the top edge for a maximized layout.", 30, -72, menuBehaviorW - 70, T.colors.muted)
    if menuSnapHelp.SetWordWrap then menuSnapHelp:SetWordWrap(true) end
    BindMiscToggle(menuBehavior, "Hide Advanced menu section", "hideAdvancedMenu", true, "MSUF2_ADVANCED_MENU_VISIBILITY", 14, -118, 280, MENU_WRITE_OPTS,
        function() M.CallIf(M.RefreshAdvancedNavVisibility) end)
    BindMiscToggle(menuBehavior, "Show navigation icons", "showNavigationIcons", false, "MSUF2_NAV_ICONS", 14, -148, 280, MENU_WRITE_OPTS,
        function() M.CallIf(M.RefreshNavIconVisibility) end)
    BindMiscToggle(menuBehavior, "Show MSUF button in game menu", "showGameMenuButton", true, "MSUF2_GAME_MENU_BUTTON", 14, -178, 320, MENU_WRITE_OPTS,
        function(v)
            if type(_G.MSUF_SetGameMenuButtonEnabled) == "function" then
                _G.MSUF_SetGameMenuButtonEnabled(v)
            end
        end)
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
            M.CallIf(T.ClearMenuFontCache)
            M.CallIf(T.RefreshMenuFonts)
            if menuFontPreview and menuFontPreview.SetText then
                menuFontPreview:SetText(M.Tr("AaBbCc 12345 - MSUF Menu"))
            end
        end,
        "menu.font")
    menuFontPreview = W.Text(menuBehavior, "AaBbCc 12345 - MSUF Menu", menuFontRightX, -178, menuBehaviorW - menuFontRightX - 30, T.colors.text)
    if menuFontPreview.SetHeight then menuFontPreview:SetHeight(24) end
    if menuFontPreview.SetJustifyV then menuFontPreview:SetJustifyV("MIDDLE") end
    M.InstallStaticPopup("MSUF2_ACCENT_RELOAD_REQUIRED", {
        text = M.Tr("The menu accent color is baked in while the menu is built, so a UI reload is required to apply it.\n\nReload now?"),
        button1 = RELOADUI or M.Tr("Reload"),
        button2 = CANCEL or M.Tr("Not now"),
        OnAccept = function() M.CallIf(ReloadUI) end,
    })
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
            if not (type(StaticPopup_Visible) == "function" and StaticPopup_Visible("MSUF2_ACCENT_RELOAD_REQUIRED")) then
                StaticPopup_Show("MSUF2_ACCENT_RELOAD_REQUIRED")
            end
        elseif type(StaticPopup_Hide) == "function" then
            StaticPopup_Hide("MSUF2_ACCENT_RELOAD_REQUIRED")
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
        VT("midnight", "Midnight (default)", "class", "Class color",
            "ember", "Ember", "jade", "Jade", "violet", "Violet",
            "custom", "Custom"),
        250, 14, -244,
        ReadAccentMode,
        function(value)
            if not IsAccentMode(value) then value = "midnight" end
            SetG("menuAccent", value, "MSUF2_MENU_ACCENT", MENU_WRITE_OPTS)
            RefreshAccentSwatchEnabled()
            AccentReloadCheck()
        end,
        "setting.menuAccent")
    accentSwatch = W.Color(menuBehavior, "Custom accent color")
    M.BindColor(ctx, accentSwatch,
        function()
            local r, g2, b2 = T.MenuAccentHexToRGB(ReadG("menuAccentColor", "3b82f6"))
            if not r then r, g2, b2 = 0.231, 0.510, 0.965 end
            return r, g2, b2
        end,
        function(r, g2, b2)
            SetG("menuAccentColor", T.MenuAccentRGBToHex(r, g2, b2), "MSUF2_MENU_ACCENT_COLOR", MENU_WRITE_OPTS)
            QueueAccentReloadCheck()
        end,
        Meta("setting.menuAccentColor"))
    if accentSwatch._msuf2Title then
        accentSwatch._msuf2Title:ClearAllPoints()
        accentSwatch._msuf2Title:SetPoint("TOPLEFT", menuBehavior, "TOPLEFT", menuFontRightX, -256)
        accentSwatch._msuf2Title:SetWidth(170)
    end
    accentSwatch:ClearAllPoints()
    accentSwatch:SetPoint("TOPLEFT", menuBehavior, "TOPLEFT", menuFontRightX + 182, -254)
    accentTint = BindMiscToggle(menuBehavior, "Tint menu surfaces", "menuAccentTintSurfaces", false,
        "MSUF2_MENU_ACCENT_TINT", 14, -292, 320, MENU_WRITE_OPTS, AccentReloadCheck)
    -- One string literal, not a concatenation: the locale coverage gate reads
    -- literals, so a split body would demand a key per fragment.
    M.AddTooltip(accentTint, "Tint menu surfaces",
        "Off (default): the accent colors buttons, tabs and highlights while panels stay midnight. On: panels, borders and the navigation rail are rotated onto the accent hue too. Success, warning and danger colors never change.",
        { hook = true })
    M.TrackRefresh(ctx, RefreshAccentSwatchEnabled)
    local accentHelp = W.Text(menuBehavior, "Midnight keeps the stock blue accent. Class color follows this character; the accent applies after a UI reload.", 30, -330, menuBehaviorW - 70, T.colors.muted)
    if accentHelp.SetWordWrap then accentHelp:SetWordWrap(true) end
    local startup = b:CollapsibleSection("misc_startup", "Startup", 124, true)
    BindMiscToggle(startup, "Show welcome message", "showWelcomeMessage", true, "MSUF2_WELCOME", 14, -42, 320)
    BindMiscToggle(startup, "Enable version check (peer-to-peer)", "versionCheckEnabled", true, "MSUF2_VERSION_CHECK", 14, -76, 360, nil,
        function()
            Call("MSUF_ApplyModules")
        end)
    local nicknameIntegration = b:CollapsibleSection("misc_nickname_integration", "Nickname Integration", 124, true)
    local nsrtNicknames = BindMiscToggle(nicknameIntegration, "Use NSRT nicknames on MSUF frames",
        "nsrtNicknameIntegration", true, "MSUF2_NSRT_NICKNAMES", 14, -42, 430, PREVIEW_FALSE,
        function()
            Call("MSUF_NSRTNicknames_ApplySetting")
        end)
    M.AddTooltip(nsrtNicknames, "NSRT nickname integration",
        "On (default): names supplied by Northern Sky Raid Tools replace character names on MSUF unit and group frames. Turn this off to always show character names in MSUF. NSRT and its settings are not modified.",
        { hook = true })
    if type(_G.MSUF_EllesmereEditMode_IsAvailable) == "function"
        and _G.MSUF_EllesmereEditMode_IsAvailable() then
        local ellesmere = b:CollapsibleSection("misc_ellesmere_ui", "EllesmereUI", 138, true)
        local integration = BindMiscToggle(ellesmere, "Use EllesmereUI Unlock Mode for MSUF",
            "ellesmereEditModeIntegration", true, "MSUF2_ELLESMERE_EDIT_MODE", 14, -42, 430, PREVIEW_FALSE,
            function(value)
                if type(_G.MSUF_EllesmereEditMode_SetEnabled) == "function" then
                    _G.MSUF_EllesmereEditMode_SetEnabled(value)
                end
            end)
        M.AddTooltip(integration, "EllesmereUI Unlock Mode",
            "On (default): MSUF frames appear in EllesmereUI Unlock Mode. Turn this off to keep using the native MSUF Edit Mode. MSUF profile positions remain the source of truth.",
            { hook = true })
        local ellesmereHelp = W.Text(ellesmere,
            "This switch is shown only while EllesmereUI is loaded. Disabling it immediately returns MSUF to its own Edit Mode.",
            30, -88, (ellesmere._msuf2Width or ctx.width or 720) - 70, T.colors.muted)
        if ellesmereHelp.SetWordWrap then ellesmereHelp:SetWordWrap(true) end
    end
    local external = b:CollapsibleSection("misc_external_edit_mode", "External Edit Mode", 298, true)
    local grid2 = BindMiscToggle(external, "Show Grid2 in MSUF Edit Mode",
        "grid2EditModeIntegration", true, "MSUF2_GRID2_EDIT_MODE", 14, -42, 430, PREVIEW_FALSE,
        function(value)
            if type(_G.MSUF_Grid2EditMode_SetEnabled) == "function" then
                _G.MSUF_Grid2EditMode_SetEnabled(value)
            end
        end)
    M.AddTooltip(grid2, "Grid2 Edit Mode integration",
        "On (default): MSUF Edit Mode can move the Grid2 layout and its active detached groups. Grid2 remains the owner of its layout and saved positions.",
        { hook = true })
    local details = BindMiscToggle(external, "Show Details! in MSUF Edit Mode",
        "detailsEditModeIntegration", true, "MSUF2_DETAILS_EDIT_MODE", 14, -78, 430, PREVIEW_FALSE,
        function(value)
            if type(_G.MSUF_DetailsEditMode_SetEnabled) == "function" then
                _G.MSUF_DetailsEditMode_SetEnabled(value)
            end
        end)
    M.AddTooltip(details, "Details! Edit Mode integration",
        "On (default): MSUF Edit Mode can move every active Details! window. Windows snapped together by Details! move as one native group.",
        { hook = true })
    local dominos = BindMiscToggle(external, "Show Dominos in MSUF Edit Mode",
        "dominosEditModeIntegration", true, "MSUF2_DOMINOS_EDIT_MODE", 14, -114, 430, PREVIEW_FALSE,
        function(value)
            if type(_G.MSUF_DominosEditMode_SetEnabled) == "function" then
                _G.MSUF_DominosEditMode_SetEnabled(value)
            end
        end)
    M.AddTooltip(dominos, "Dominos Edit Mode integration",
        "On (default): MSUF Edit Mode can move every Dominos bar that is not docked to another bar. Docked bars follow their host bar, and Dominos remains the owner of all bar positions.",
        { hook = true })
    local danders = BindMiscToggle(external, "Show DandersFrames in MSUF Edit Mode",
        "dandersEditModeIntegration", true, "MSUF2_DANDERS_EDIT_MODE", 14, -150, 430, PREVIEW_FALSE,
        function(value)
            if type(_G.MSUF_DandersEditMode_SetEnabled) == "function" then
                _G.MSUF_DandersEditMode_SetEnabled(value)
            end
        end)
    M.AddTooltip(danders, "DandersFrames Edit Mode integration",
        "On (default): MSUF Edit Mode can move the DandersFrames party and raid containers and free pinned sets. Sets glued to the frames follow them, and DandersFrames remains the owner of all saved positions.",
        { hook = true })
    local blizzardEM = BindMiscToggle(external, "Show Blizzard frames in MSUF Edit Mode",
        "blizzardEditModeIntegration", true, "MSUF2_BLIZZARD_EDIT_MODE", 14, -186, 430, PREVIEW_FALSE,
        function(value)
            if type(_G.MSUF_BlizzardEditMode_SetEnabled) == "function" then
                _G.MSUF_BlizzardEditMode_SetEnabled(value)
            end
        end)
    M.AddTooltip(blizzardEM, "Blizzard Edit Mode integration",
        "On (default): MSUF Edit Mode can move the Blizzard Minimap, Chat, Micro Menu and Tooltip through the game's own Edit Mode layout. If a Blizzard preset is active, selecting an element creates and activates a saved 'MSUF' layout automatically.",
        { hook = true })
    local externalHelp = W.Text(external,
        "Turn any of these switches off to remove only those external movers. The third-party addons and their settings are not modified.",
        30, -232, (external._msuf2Width or ctx.width or 720) - 70, T.colors.muted)
    if externalHelp.SetWordWrap then externalHelp:SetWordWrap(true) end
    local mouseover = b:CollapsibleSection("misc_mouseover_highlight", "Frame Highlights", 340, true)
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
    local size = W.Slider(mouseover, "Effect size", 1, 16, 1, mouseoverRightW)
    if size.SetValueFormatter then
        size:SetValueFormatter(function(value) return M.Format("%d px", floor((tonumber(value) or 6) + 0.5)) end)
    end
    M.BindNumberWidget(ctx, size,
        function() return floor((tonumber(ReadG("highlightThickness", 6)) or 6) + 0.5) end,
        function(value)
            SetG("highlightThickness", floor((tonumber(value) or 6) + 0.5),
                "MSUF2_MOUSEOVER_SIZE", MOUSEOVER_WRITE_OPTS)
        end,
        6,
        Meta("mouseover.size", "setting", { min = 1, max = 16, step = 1, format = "%d px" }))
    W.MoveWidget(size, mouseover, mouseoverRightX, -58, mouseoverRightW, "CENTER")
    local mouseoverHelp = W.Text(mouseover,
        "Soft gradient gives the whole frame a clear, portrait-safe hover cue. Solid border keeps a crisp edge. Choose its color in Global Style > Colors > Unit Frames.",
        mouseoverLeftX, -142, mouseoverW - 68, T.colors.muted)
    if mouseoverHelp.SetWordWrap then mouseoverHelp:SetWordWrap(true) end
    local function RefreshMouseoverControls()
        local on = ReadGBool("highlightEnabled", true)
        M.CallIf(W.SetControlEnabled, style, on)
        M.CallIf(W.SetControlEnabled, size, on)
    end
    if enabled and enabled.HookScript then enabled:HookScript("OnClick", RefreshMouseoverControls) end
    M.TrackRefresh(ctx, RefreshMouseoverControls)
    local targetCardW = max(320, mouseoverW - 28)
    local targetCard = W.ControlCard(mouseover, "Group Target Highlight",
        "Independent of mouseover. Marks your current target in the selected group-frame types.",
        14, -198, targetCardW, 116)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(targetCard, { "group.target" }, {
            title = "Target Highlight Color",
            note = "Shared by Party, Raid and Mythic Raid.",
            historySource = "menu:group-target-highlight-color",
            offsetX = -76,
        })
    end
    local targetColumnW = math.floor((targetCardW - 36) / 3)
    BindGroupTargetSwitch(targetCard, "Party frames", "party", 18, -78, targetColumnW - 42)
    BindGroupTargetSwitch(targetCard, "Raid frames", "raid", 18 + targetColumnW, -78, targetColumnW - 42)
    BindGroupTargetSwitch(targetCard, "Mythic Raid frames", "mythicraid", 18 + (targetColumnW * 2), -78, targetColumnW - 42)
    local tooltips = b:CollapsibleSection("misc_tooltips", "Unitframe tooltips", 236, false)
    local tooltipW = tooltips._msuf2Width or ctx.width or 720
    local tooltipLeftX = 30
    local tooltipRightX = max(tooltipLeftX + 300, floor(tooltipW * 0.52))
    local tooltipLeftW = max(240, min(300, tooltipRightX - tooltipLeftX - 48))
    local tooltipRightW = max(220, min(300, tooltipW - tooltipRightX - 36))
    BindMiscDropdown(tooltips, "Tooltip source", VT("GAME", "GameTooltip (addon-compatible)", "MSUF", "MSUF custom panel"), tooltipLeftW, tooltipLeftX, -44,
        function() return ReadTooltipProvider() end,
        function(v) WriteTooltipSettings(v, ReadTooltipAnchor()) end,
        "tooltips.provider")
    BindMiscDropdown(tooltips, "Tooltip anchor", VT("EXTERNAL", "Addon / Blizzard controlled", "FIXED", "MSUF fixed position", "CURSOR", "MSUF cursor"), tooltipRightW, tooltipRightX, -44,
        function() return ReadTooltipAnchor() end,
        function(v) WriteTooltipSettings(ReadTooltipProvider(), v) end,
        "tooltips.anchor")
    local tooltipModifier
    local function RefreshTooltipControls()
        M.CallIf(W.SetControlEnabled, tooltipModifier, ReadTooltipMode() == "MODIFIER")
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
    local tooltipHelp = W.Text(tooltips, "Visibility modes apply only to unit and group frames. Aura tooltips use their own Show Tooltip switches; even Never does not override them. Auras only reuse the selected Blizzard/MSUF look and cursor placement.", tooltipLeftX, -174, tooltipW - 68, T.colors.muted)
    if tooltipHelp.SetWordWrap then tooltipHelp:SetWordWrap(true) end
    --- Blizzard frame ownership is per unit ("Force Blizzard frame on" in each
    --- unit's Frame Basics), so this section only carries the remaining
    --- Blizzard-adjacent chrome toggles.
    local blizzard = b:CollapsibleSection("misc_blizzard_frames", "Blizzard Frames", 170, false)
    BindMiscToggle(blizzard, "Show MSUF minimap icon", "showMinimapIcon", true, "MSUF2_MINIMAP_ICON", nil, nil, nil, nil,
        function(v)
            if type(_G.MSUF_SetMinimapIconEnabled) == "function" then
                _G.MSUF_SetMinimapIconEnabled(v)
            else
                local g = G()
                g.minimapIconDB = g.minimapIconDB or {}
                g.minimapIconDB.hide = not v
            end
        end)
    BindMiscToggle(blizzard, "Play sound on Target/Target Lost", "playTargetSelectLostSounds", false, "MSUF2_TARGET_SOUNDS", nil, nil, nil, nil,
        function(v)
            Call("MSUF_TargetSoundDriver_ResetState")
            if v then Call("MSUF_TargetSoundDriver_Ensure") end
        end)
    local resourcePing = BindMiscToggle(blizzard, "Enable native Player resource pings (12.1)",
        "playerResourcePingEnabled", true, "MSUF2_PLAYER_RESOURCE_PING", nil, nil, nil, PREVIEW_FALSE,
        function()
            Call("MSUF_RefreshPlayerResourcePing")
        end)
    M.AddTooltip(resourcePing, "Native Player resource pings",
        "Contextual pings over the MSUF Player frame can call out health and, when Blizzard supports it, mana. Blizzard does not expose separate Health/Power selection or Energy, Rage and Focus pings. The portrait keeps the normal Player unit ping and radial wheel.",
        { hook = true })
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_misc", { title = "MSUF Miscellaneous", build = BuildMisc, version = 17 })
