local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

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
    if anchor == "EXTERNAL" or anchor == "FIXED" or anchor == "CURSOR" then
        return anchor
    end
    if ReadTooltipProvider() == "MSUF" then
        return (ReadG("unitInfoTooltipStyle", "classic") == "modern") and "CURSOR" or "FIXED"
    end
    if type(ReadG("tooltipPosX", nil)) == "number" and type(ReadG("tooltipPosY", nil)) == "number" then
        return "FIXED"
    end
    if ReadG("unitInfoTooltipStyle", "classic") == "modern" then
        return "CURSOR"
    end
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
    if tooltips and type(tooltips.Refresh) == "function" then
        tooltips.Refresh()
    end
    local editActive = (_G.MSUF_UnitEditModeActive == true)
    if not editActive and type(_G.MSUF_IsMSUFEditModeActive) == "function" then
        editActive = _G.MSUF_IsMSUFEditModeActive() and true or false
    end
    if editActive and type(_G.MSUF_Tooltip_ShowEditPreview) == "function" then
        _G.MSUF_Tooltip_ShowEditPreview()
    end
end

local function WriteTooltipSettings(provider, anchor)
    provider = (provider == "MSUF") and "MSUF" or "GAME"
    if anchor ~= "FIXED" and anchor ~= "CURSOR" and anchor ~= "EXTERNAL" then
        anchor = "EXTERNAL"
    end
    if provider == "MSUF" and anchor == "EXTERNAL" then
        anchor = "FIXED"
    end
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

    if _G.StaticPopupDialogs and not _G.StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        _G.StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = M.Tr("This changes how MSUF hides the Blizzard PlayerFrame.\n\nA UI reload is required."),
            button1 = RELOADUI or M.Tr("Reload"),
            button2 = CANCEL or M.Tr("Cancel"),
            OnAccept = function() if ReloadUI then ReloadUI() end end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local language = b:CollapsibleSection("misc_language", "Language", 146, true)
    local languageW = language._msuf2Width or ctx.width or 720
    local languageDropW = max(260, min(360, languageW - 70))
    local languageDrop = W.Dropdown(language, "Menu language", function()
        return (M.GetLocaleDropdownValues and M.GetLocaleDropdownValues()) or {
            { value = "auto", text = "Follow Blizzard" },
        }
    end, languageDropW)
    M.BindDropdown(ctx, languageDrop,
        function()
            return (M.GetLocaleSelection and M.GetLocaleSelection()) or "auto"
        end,
        function(value)
            value = value or "auto"
            SetG("menuLocale", value, "MSUF2_LOCALE", { preview = false, applyAll = false })
            if M.ApplyLocaleSelection then M.ApplyLocaleSelection(value) end
            local function RebuildLocalePages()
                if M.InvalidatePage then M.InvalidatePage() end
                if M.SelectPage then M.SelectPage("opt_misc") end
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, RebuildLocalePages)
            else
                RebuildLocalePages()
            end
        end)
    W.MoveWidget(languageDrop, language, 30, -44, languageDropW, "LEFT")
    local languageHelp = W.Text(language, "Follow Blizzard uses the WoW client language. Manual selection affects only MSUF menus.", 30, -96, languageW - 70, T.colors.muted)
    if languageHelp.SetWordWrap then languageHelp:SetWordWrap(true) end

    local menuBehavior = b:CollapsibleSection("misc_menu_behavior", "Menu behavior", 194, true)
    local menuSnap = W.Toggle(menuBehavior, "Enable Windows-style edge snap for this menu")
    M.BindToggle(ctx, menuSnap,
        function() return ReadGBool("slashMenuSnapEnabled", true) end,
        function(v) SetGBool("slashMenuSnapEnabled", v, "MSUF2_MENU_SNAP", { preview = false, applyAll = false, notify = false }) end)
    local menuSnapHelp = W.Text(menuBehavior, "Drag the MSUF menu to a screen side for a half-screen layout, to a corner for a quarter layout, or to the top edge for a maximized layout.", 30, -72, (menuBehavior._msuf2Width or ctx.width or 720) - 70, T.colors.muted)
    if menuSnapHelp.SetWordWrap then menuSnapHelp:SetWordWrap(true) end
    local advancedHidden = W.Toggle(menuBehavior, "Hide Advanced menu section")
    M.BindToggle(ctx, advancedHidden,
        function() return ReadGBool("hideAdvancedMenu", true) end,
        function(v)
            SetGBool("hideAdvancedMenu", v, "MSUF2_ADVANCED_MENU_VISIBILITY", { preview = false, applyAll = false, notify = false })
            if M.RefreshAdvancedNavVisibility then M.RefreshAdvancedNavVisibility() end
        end)
    W.MoveWidget(advancedHidden, menuBehavior, 14, -118, 280, "LEFT")

    local reduceMotion = W.Toggle(menuBehavior, "Reduce menu motion")
    M.BindToggle(ctx, reduceMotion,
        function() return ReadGBool("reduceMotion", false) end,
        function(v) SetGBool("reduceMotion", v, "MSUF2_REDUCE_MOTION", { preview = false, applyAll = false, notify = false }) end)
    W.MoveWidget(reduceMotion, menuBehavior, 14, -148, 280, "LEFT")

    local startup = b:CollapsibleSection("misc_startup", "Startup", 124, true)
    local welcome = W.Toggle(startup, "Show welcome message")
    M.BindToggle(ctx, welcome,
        function() return ReadGBool("showWelcomeMessage", true) end,
        function(v) SetGBool("showWelcomeMessage", v, "MSUF2_WELCOME", { preview = false }) end)
    W.MoveWidget(welcome, startup, 14, -42, 320, "LEFT")

    local version = W.Toggle(startup, "Enable version check (peer-to-peer)")
    M.BindToggle(ctx, version,
        function() return ReadGBool("versionCheckEnabled", true) end,
        function(v) SetGBool("versionCheckEnabled", v, "MSUF2_VERSION_CHECK", { preview = false }) end)
    W.MoveWidget(version, startup, 14, -76, 360, "LEFT")

    local tooltips = b:CollapsibleSection("misc_tooltips", "Unitframe tooltips", 236, false)
    local tooltipW = tooltips._msuf2Width or ctx.width or 720
    local tooltipLeftX = 30
    local tooltipRightX = max(tooltipLeftX + 300, floor(tooltipW * 0.52))
    local tooltipLeftW = max(240, min(300, tooltipRightX - tooltipLeftX - 48))
    local tooltipRightW = max(220, min(300, tooltipW - tooltipRightX - 36))
    local tooltipProvider = W.Dropdown(tooltips, "Tooltip source", VT("GAME", "GameTooltip (addon-compatible)", "MSUF", "MSUF custom panel"), tooltipLeftW)
    M.BindDropdown(ctx, tooltipProvider,
        function() return ReadTooltipProvider() end,
        function(v) WriteTooltipSettings(v, ReadTooltipAnchor()) end)
    W.MoveWidget(tooltipProvider, tooltips, tooltipLeftX, -44, tooltipLeftW, "LEFT")
    local tooltipAnchor = W.Dropdown(tooltips, "Tooltip anchor", VT("EXTERNAL", "Addon / Blizzard controlled", "FIXED", "MSUF fixed position", "CURSOR", "MSUF cursor"), tooltipRightW)
    M.BindDropdown(ctx, tooltipAnchor,
        function() return ReadTooltipAnchor() end,
        function(v) WriteTooltipSettings(ReadTooltipProvider(), v) end)
    W.MoveWidget(tooltipAnchor, tooltips, tooltipRightX, -44, tooltipRightW, "LEFT")

    local tooltipModifier
    local tooltipMode = W.Dropdown(tooltips, "Show unitframe tooltips", TOOLTIP_MODES, tooltipLeftW)
    M.BindDropdown(ctx, tooltipMode,
        function() return ReadTooltipMode() end,
        function(v)
            WriteTooltipBehavior(v, ReadTooltipModifier())
            if W.SetControlEnabled then W.SetControlEnabled(tooltipModifier, ReadTooltipMode() == "MODIFIER") end
        end)
    W.MoveWidget(tooltipMode, tooltips, tooltipLeftX, -112, tooltipLeftW, "LEFT")

    tooltipModifier = W.Dropdown(tooltips, "Modifier key", TOOLTIP_MODIFIERS, tooltipRightW)
    M.BindDropdown(ctx, tooltipModifier,
        function() return ReadTooltipModifier() end,
        function(v) WriteTooltipBehavior(ReadTooltipMode(), v) end)
    W.MoveWidget(tooltipModifier, tooltips, tooltipRightX, -112, tooltipRightW, "LEFT")

    local function RefreshTooltipControls()
        if W.SetControlEnabled then W.SetControlEnabled(tooltipModifier, ReadTooltipMode() == "MODIFIER") end
    end
    M.AddRefresher(ctx, RefreshTooltipControls)
    RefreshTooltipControls()
    local tooltipHelp = W.Text(tooltips, "These settings apply to MSUF unit frames and group frames. GameTooltip keeps addon compatibility; MSUF custom panel uses the fixed or cursor position.", tooltipLeftX, -174, tooltipW - 68, T.colors.muted)
    if tooltipHelp.SetWordWrap then tooltipHelp:SetWordWrap(true) end

    local blizzard = b:CollapsibleSection("misc_blizzard_frames", "Blizzard Frames", 190, false)
    local blizzUF = W.Toggle(blizzard, "Disable Blizzard unitframes")
    M.BindToggle(ctx, blizzUF,
        function() return ReadGBool("disableBlizzardUnitFrames", true) end,
        function(v)
            SetGBool("disableBlizzardUnitFrames", v, "MSUF2_DISABLE_BLIZZARD_UF", { preview = false })
            if print then print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.") end
        end)
    local hardKill = W.Toggle(blizzard, "Fully Hide Blizzard PlayerFrame - resource bar compatibility")
    M.BindToggle(ctx, hardKill,
        function() return ReadGBool("hardKillBlizzardPlayerFrame", false) end,
        function(v)
            SetGBool("hardKillBlizzardPlayerFrame", v, "MSUF2_HARDKILL_PLAYERFRAME", { preview = false })
            if StaticPopup_Show then StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE") end
        end)
    local minimap = W.Toggle(blizzard, "Show MSUF minimap icon")
    M.BindToggle(ctx, minimap,
        function() return ReadGBool("showMinimapIcon", true) end,
        function(v)
            SetGBool("showMinimapIcon", v, "MSUF2_MINIMAP_ICON", { preview = false })
            if type(_G.MSUF_SetMinimapIconEnabled) == "function" then
                pcall(_G.MSUF_SetMinimapIconEnabled, v)
            else
                local g = G()
                g.minimapIconDB = g.minimapIconDB or {}
                g.minimapIconDB.hide = not v
            end
        end)
    local sounds = W.Toggle(blizzard, "Play sound on Target/Target Lost")
    M.BindToggle(ctx, sounds,
        function() return ReadGBool("playTargetSelectLostSounds", false) end,
        function(v)
            SetGBool("playTargetSelectLostSounds", v, "MSUF2_TARGET_SOUNDS", { preview = false })
            Call("MSUF_TargetSoundDriver_ResetState")
            if v then Call("MSUF_TargetSoundDriver_Ensure") end
        end)

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("opt_misc", { title = "MSUF Miscellaneous", build = BuildMisc, version = 8 })
