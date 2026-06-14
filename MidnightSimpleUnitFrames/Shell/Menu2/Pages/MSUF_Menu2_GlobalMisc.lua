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
local Call, G, ReadG, SetG, ReadGBool, SetGBool = M.Pick(GP, [[Call G ReadG SetG ReadGBool SetGBool]])
local VT = M.ValueTextList
local TOOLTIP_MODES = VT("ALWAYS", "Always", "OOC", "Out of Combat", "MODIFIER", "Modifier Key", "NEVER", "Never")
local TOOLTIP_MODIFIERS = VT("ALT", "Alt", "CTRL", "Ctrl", "SHIFT", "Shift")
local MENU_WRITE_OPTS = { preview = false, applyAll = false, notify = false }
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
local function WriteTooltipSettings(provider, anchor)
    provider = (provider == "MSUF") and "MSUF" or "GAME"
    if anchor ~= "FIXED" and anchor ~= "CURSOR" and anchor ~= "EXTERNAL" then anchor = "EXTERNAL" end
    if provider == "MSUF" and anchor == "EXTERNAL" then anchor = "FIXED" end
    SetG("unitTooltipProvider", provider, "MSUF2_TOOLTIP_PROVIDER", { preview = false })
    SetG("unitTooltipAnchor", anchor, "MSUF2_TOOLTIP_ANCHOR", { preview = false })
    SetGBool("disableUnitInfoTooltips", provider ~= "MSUF", "MSUF2_TOOLTIPS", { preview = false })
    SetG("unitInfoTooltipStyle", (anchor == "CURSOR") and "modern" or "classic", "MSUF2_TOOLTIP_STYLE", { preview = false })
    RefreshTooltipPreview()
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
    b:GlobalStyleHeader("Miscellaneous", "Language, menu behavior, tooltips and Blizzard frames.", 72)
    M.InstallStaticPopup("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE", {
        text = M.Tr("This changes how MSUF hides the Blizzard PlayerFrame.\n\nA UI reload is required."),
        button1 = RELOADUI or M.Tr("Reload"),
        button2 = CANCEL or M.Tr("Cancel"),
        OnAccept = function() M.CallIf(ReloadUI) end,
    })
    local function BindMiscToggle(parent, label, key, default, reason, x, y, width, opts, afterSet)
        local control = W.Toggle(parent, label)
        M.BindBoolWidget(ctx, control,
            function() return ReadGBool(key, default) end,
            function(v)
                SetGBool(key, v, reason, opts or PREVIEW_FALSE)
                M.CallIf(afterSet, v)
            end)
        if x then W.MoveWidget(control, parent, x, y, width, "LEFT") end
        return control
    end
    local function BindMiscDropdown(parent, label, values, width, x, y, getValue, setValue)
        local control = M.BindDropdownWidget(ctx, W.Dropdown(parent, label, values, width), getValue, setValue)
        W.MoveWidget(control, parent, x, y, width, "LEFT")
        return control
    end
    local language = b:CollapsibleSection("misc_language", "Language", 146, true)
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
            SetG("menuLocale", value, "MSUF2_LOCALE", { preview = false, applyAll = false })
            M.CallIf(M.ApplyLocaleSelection, value)
            local function RebuildLocalePages()
                M.CallIf(M.InvalidatePage)
                M.CallIf(M.SelectPage, "opt_misc")
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, RebuildLocalePages)
            else
                RebuildLocalePages()
            end
        end)
    local languageHelp = W.Text(language, "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus.", 30, -96, languageW - 70, T.colors.muted)
    if languageHelp.SetWordWrap then languageHelp:SetWordWrap(true) end
    local menuBehavior = b:CollapsibleSection("misc_menu_behavior", "Menu behavior", 194, true)
    BindMiscToggle(menuBehavior, "Enable Windows-style edge snap for this menu", "slashMenuSnapEnabled", true, "MSUF2_MENU_SNAP", nil, nil, nil, MENU_WRITE_OPTS)
    local menuSnapHelp = W.Text(menuBehavior, "Drag the MSUF menu to a screen side for a half-screen layout, to a corner for a quarter layout, or to the top edge for a maximized layout.", 30, -72, (menuBehavior._msuf2Width or ctx.width or 720) - 70, T.colors.muted)
    if menuSnapHelp.SetWordWrap then menuSnapHelp:SetWordWrap(true) end
    BindMiscToggle(menuBehavior, "Hide Advanced menu section", "hideAdvancedMenu", true, "MSUF2_ADVANCED_MENU_VISIBILITY", 14, -118, 280, MENU_WRITE_OPTS,
        function() M.CallIf(M.RefreshAdvancedNavVisibility) end)
    BindMiscToggle(menuBehavior, "Reduce menu motion", "reduceMotion", false, "MSUF2_REDUCE_MOTION", 14, -148, 280, MENU_WRITE_OPTS)
    local startup = b:CollapsibleSection("misc_startup", "Startup", 124, true)
    BindMiscToggle(startup, "Show welcome message", "showWelcomeMessage", true, "MSUF2_WELCOME", 14, -42, 320)
    BindMiscToggle(startup, "Enable version check (peer-to-peer)", "versionCheckEnabled", true, "MSUF2_VERSION_CHECK", 14, -76, 360)
    local tooltips = b:CollapsibleSection("misc_tooltips", "Unitframe tooltips", 236, false)
    local tooltipW = tooltips._msuf2Width or ctx.width or 720
    local tooltipLeftX = 30
    local tooltipRightX = max(tooltipLeftX + 300, floor(tooltipW * 0.52))
    local tooltipLeftW = max(240, min(300, tooltipRightX - tooltipLeftX - 48))
    local tooltipRightW = max(220, min(300, tooltipW - tooltipRightX - 36))
    BindMiscDropdown(tooltips, "Tooltip source", VT("GAME", "GameTooltip (addon-compatible)", "MSUF", "MSUF custom panel"), tooltipLeftW, tooltipLeftX, -44,
        function() return ReadTooltipProvider() end,
        function(v) WriteTooltipSettings(v, ReadTooltipAnchor()) end)
    BindMiscDropdown(tooltips, "Tooltip anchor", VT("EXTERNAL", "Addon / Blizzard controlled", "FIXED", "MSUF fixed position", "CURSOR", "MSUF cursor"), tooltipRightW, tooltipRightX, -44,
        function() return ReadTooltipAnchor() end,
        function(v) WriteTooltipSettings(ReadTooltipProvider(), v) end)
    local tooltipModifier
    local function RefreshTooltipControls()
        M.CallIf(W.SetControlEnabled, tooltipModifier, ReadTooltipMode() == "MODIFIER")
    end
    BindMiscDropdown(tooltips, "Show unitframe tooltips", TOOLTIP_MODES, tooltipLeftW, tooltipLeftX, -112,
        function() return ReadTooltipMode() end,
        function(v)
            WriteTooltipBehavior(v, ReadTooltipModifier())
            RefreshTooltipControls()
        end)
    tooltipModifier = BindMiscDropdown(tooltips, "Modifier key", TOOLTIP_MODIFIERS, tooltipRightW, tooltipRightX, -112,
        function() return ReadTooltipModifier() end,
        function(v) WriteTooltipBehavior(ReadTooltipMode(), v) end)
    M.TrackRefresh(ctx, RefreshTooltipControls)
    local tooltipHelp = W.Text(tooltips, "These settings apply to MSUF unit frames and group frames. GameTooltip keeps addon compatibility; MSUF custom panel uses the fixed or cursor position.", tooltipLeftX, -174, tooltipW - 68, T.colors.muted)
    if tooltipHelp.SetWordWrap then tooltipHelp:SetWordWrap(true) end
    local blizzard = b:CollapsibleSection("misc_blizzard_frames", "Blizzard Frames", 190, false)
    BindMiscToggle(blizzard, "Disable Blizzard unitframes", "disableBlizzardUnitFrames", true, "MSUF2_DISABLE_BLIZZARD_UF", nil, nil, nil, nil,
        function() M.CallIf(print, "|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.") end)
    BindMiscToggle(blizzard, "Fully Hide Blizzard PlayerFrame - resource bar compatibility", "hardKillBlizzardPlayerFrame", false, "MSUF2_HARDKILL_PLAYERFRAME", nil, nil, nil, nil,
        function() M.CallIf(StaticPopup_Show, "MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end)
    BindMiscToggle(blizzard, "Show MSUF minimap icon", "showMinimapIcon", true, "MSUF2_MINIMAP_ICON", nil, nil, nil, nil,
        function(v)
            if type(_G.MSUF_SetMinimapIconEnabled) == "function" then
                pcall(_G.MSUF_SetMinimapIconEnabled, v)
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
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("opt_misc", { title = "MSUF Miscellaneous", build = BuildMisc, version = 8 })
