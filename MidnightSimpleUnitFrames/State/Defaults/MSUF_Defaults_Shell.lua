-- Shared shell defaults. Client-specific policy is bound once, outside gameplay paths.
local _, MSUF = ...
MSUF.DefaultsStageFactories = MSUF.DefaultsStageFactories or {}
MSUF.DefaultsStageFactories.Shell = function(dependencies)
local MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = dependencies.MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION
local MSUF_Defaults_GetMenuFontDefault = dependencies.MSUF_Defaults_GetMenuFontDefault
local MSUF_Defaults_MigrateUnitDispelOwnership = dependencies.MSUF_Defaults_MigrateUnitDispelOwnership
local MSUF_Defaults_NormalizeFontShadowScope = dependencies.MSUF_Defaults_NormalizeFontShadowScope
local function MSUF_Defaults_Stage_SeedShellDefaults(profileDB, g)
    if g.anchorName == nil then
        g.anchorName = "UIParent"
    end
    if g.anchorToCooldown == nil then
        g.anchorToCooldown = false
    end
    --- New install defaults (UI scale + Flash menu anchor)
    --- Default: Unhalted-style global UI scale disabled; local MSUF scales remain independent.
    if g.disableScaling == nil then
        g.disableScaling = false
    end
    if g.globalUiScalePreset == nil then
        g.globalUiScalePreset = "auto"
    end
    --- Migrate global UI scale storage to the Unhalted-style table:
    --- General.UIScale.Enabled + General.UIScale.Scale. Keep the legacy preset keys
    --- populated so older exports/tools can still reason about the profile.
    do
        local legacyScalingDisabled = (g.disableScaling == true)
        local function PresetScale(preset, fallback)
            if preset == "1080p" then return 768 / 1080 end
            if preset == "1440p" then return 768 / 1440 end
            if preset == "4k" then return 768 / 2160 end
            if preset == "pixel" and type(GetPhysicalScreenSize) == "function" then
                local _, h = GetPhysicalScreenSize()
                h = tonumber(h)
                if h and h > 0 then return 768 / h end
            end
            return tonumber(fallback)
        end
        local ui = (type(g.UIScale) == "table") and g.UIScale or nil
        if not ui then
            ui = {}
            g.UIScale = ui
            local preset = g.globalUiScalePreset
            local scale = PresetScale(preset, g.globalUiScaleValue) or 1.0
            local enabled = (not legacyScalingDisabled)
                and (preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom")
            ui.Enabled = enabled and true or false
            ui.Scale = scale
            ui._migratedFromGlobalPreset_v1 = true
        end
        if ui.Enabled == nil then
            local preset = g.globalUiScalePreset
            ui.Enabled = (not legacyScalingDisabled)
                and (preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom")
        end
        ui.Enabled = (ui.Enabled == true)
        ui.Scale = tonumber(ui.Scale) or PresetScale(g.globalUiScalePreset, g.globalUiScaleValue) or 1.0
        if ui.Scale < 0.3 then ui.Scale = 0.3 elseif ui.Scale > 1.5 then ui.Scale = 1.5 end
        if legacyScalingDisabled then
            ui.Enabled = false
        end
        g.disableScaling = false
        if ui.Enabled then
            g.globalUiScaleValue = ui.Scale
            if g.globalUiScalePreset ~= "1080p" and g.globalUiScalePreset ~= "1440p"
                and g.globalUiScalePreset ~= "4k" and g.globalUiScalePreset ~= "pixel" and g.globalUiScalePreset ~= "custom" then
                g.globalUiScalePreset = "custom"
            end
        elseif g.globalUiScalePreset == nil then
            g.globalUiScalePreset = "auto"
        end
    end
    --- Nil value = Off (Unhalted-style global UI scale disabled)
    --- (Do NOT seed a default globalUiScaleValue on fresh installs.)
    if g.msufUiScale == nil then
        g.msufUiScale = 1.0
    end
    if g.flashFullPoint == nil then g.flashFullPoint = "CENTER" end
    if g.flashFullRelPoint == nil then g.flashFullRelPoint = "CENTER" end
    if g.flashFullX == nil then g.flashFullX = -60 end
    if g.flashFullY == nil then g.flashFullY = 10 end
    if g.flashFullW == nil then g.flashFullW = 900 end
    if g.flashFullH == nil then g.flashFullH = 700 end
    if g.flashFullXpx == nil then g.flashFullXpx = -60 end
    if g.flashFullYpx == nil then g.flashFullYpx = 10 end
    if g.tipCycleIndex == nil then
        g.tipCycleIndex = 11
    end
    --- Minimap icon (LibDBIcon) defaults
    if g.showMinimapIcon == nil then
        g.showMinimapIcon = true
    end
    --- WoW 12.1 can turn contextual pings on the MSUF Player frame into native
    --- player-resource callouts. Match Blizzard's PlayerFrame by default while
    --- retaining an explicit opt-out; the client still chooses health or supported
    --- mana contexts and does not expose energy pings.
    if g.playerResourcePingEnabled == nil then
        g.playerResourcePingEnabled = true
    end
    --- Login greeting in chat (Runtime/MSUF_WelcomeMessage.lua)
    if g.showWelcomeMessage == nil then
        g.showWelcomeMessage = true
    end
    --- Native 12.1 "spell IDs in aura tooltips" CVar, re-applied at login because
    --- the client resets it every session (Runtime/MSUF_TooltipSpellIDs.lua).
    --- Off by default: MSUF must not touch the CVar unless the user opts in here.
    if g.tooltipShowAuraSpellIDs == nil then
        g.tooltipShowAuraSpellIDs = false
end
--- 12.1.5 caster names in aura tooltips (Runtime/MSUF_TooltipSpellIDs.lua).
--- Off by default for the same reason: MSUF must not claim the CVar unopted.
if g.tooltipShowAuraCasterNames == nil then
    g.tooltipShowAuraCasterNames = false
    end
    --- EllesmereUI may own the visible Unlock Mode shell while MSUF keeps its own
    --- profile geometry and preview transaction. Users can opt out only when the
    --- EllesmereUI integration is actually available.
    if g.ellesmereEditModeIntegration == nil then
        g.ellesmereEditModeIntegration = true
    end
    --- Northern Sky Raid Tools nicknames are enabled for MSUF by default to
    --- preserve the established integration behavior, with a profile-local opt-out.
    if g.nsrtNicknameIntegration == nil then
        g.nsrtNicknameIntegration = true
    end
    --- Optional native Edit Mode adapters. The third-party addons remain the sole
    --- owners of their frames and saved positions; these switches only control
    --- whether MSUF registers movers for them.
    if g.grid2EditModeIntegration == nil then
        g.grid2EditModeIntegration = true
    end
    if g.detailsEditModeIntegration == nil then
        g.detailsEditModeIntegration = true
    end
    if g.dominosEditModeIntegration == nil then
        g.dominosEditModeIntegration = true
    end
    if g.dandersEditModeIntegration == nil then
        g.dandersEditModeIntegration = true
    end
    if g.blizzardEditModeIntegration == nil then
        g.blizzardEditModeIntegration = true
    end
    if g.dropdownStyleMode == nil then
        g.dropdownStyleMode = "msuf"
    elseif g.dropdownStyleMode ~= "old" and g.dropdownStyleMode ~= "msuf" and g.dropdownStyleMode ~= "blizzard" and g.dropdownStyleMode ~= "legacy" then
        g.dropdownStyleMode = "msuf"
    end
    if g.pendingDropdownStyleMode ~= nil and g.pendingDropdownStyleMode ~= "old" and g.pendingDropdownStyleMode ~= "msuf" and g.pendingDropdownStyleMode ~= "blizzard" and g.pendingDropdownStyleMode ~= "legacy" then
        g.pendingDropdownStyleMode = nil
    end
    if type(g.minimapIconDB) ~= "table" then
        g.minimapIconDB = { hide = false, minimapPos = 220, radius = 80 }
    else
        if g.minimapIconDB.hide == nil then g.minimapIconDB.hide = false end
        if g.minimapIconDB.minimapPos == nil then g.minimapIconDB.minimapPos = 220 end
        if g.minimapIconDB.radius == nil then g.minimapIconDB.radius = 80 end
    end
    --- Target select / target lost sounds (opt-in; matches default Blizzard UI behavior)
    --- Default OFF to avoid changing behavior for existing users.
    if g.playTargetSelectLostSounds == nil then
        g.playTargetSelectLostSounds = false
    end
    --- Fonts: color the compact power text by the unit's current power type
    --- (mana/rage/energy/etc.) so it stays identifiable without a larger label.
    if g.colorPowerTextByType == nil then
        g.colorPowerTextByType = true
    end
    --- Fonts: optionally color the *health text* by current health percentage.
    --- Default OFF to preserve existing behavior.
    if g.colorHealthTextByHealth == nil then
        g.colorHealthTextByHealth = false
    end
    if g.slashMenuSnapEnabled == nil then
        g.slashMenuSnapEnabled = true
    end
    if g.previewDragHintAnimationEnabled == nil then
        g.previewDragHintAnimationEnabled = true
    end
    if g.hideAdvancedMenu == nil then
        g.hideAdvancedMenu = true
    end
    --- Navigation icons became the standard Menu2 presentation in Defaults
    --- revision 7. Upgrade older stored profiles once, but preserve an explicit
    --- user choice made after that migration.
    if (tonumber(profileDB._msufDefaultsRevision) or 0) < MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION then
        g.showNavigationIcons = true
    elseif g.showNavigationIcons == nil then
        g.showNavigationIcons = true
    end
    -- Keep explicit guide choices, including profiles created before this default.
    if g.classPowerPreviewGuidesEnabled == nil then
        g.classPowerPreviewGuidesEnabled = false
    end
    if g.unitPreviewGuidesEnabled == nil then
        g.unitPreviewGuidesEnabled = false
    end
    if g.showGameMenuButton == nil then
        g.showGameMenuButton = true
    end
    if g.menuFontKey == nil then
        g.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
    end
    if g.editModeSnapToGrid == nil then
        g.editModeSnapToGrid = false --- Default: Snap OFF
    end
    if g.editModeGridStep == nil then
        g.editModeGridStep = 20
    end
    if g.editModeGridEnabled == nil then
        g.editModeGridEnabled = true
    end
    if g.editModeSnapEnabled == nil then
        g.editModeSnapEnabled = false
    end
    if g.editModeSnapMode == nil then
        g.editModeSnapMode = "grid"
    end
    if g.editModeSnapModeGrid == nil then
        g.editModeSnapModeGrid = true
    end
    if g.editModeSnapModeFrames == nil then
        g.editModeSnapModeFrames = false
    end
    if g.editModeHideWhiteArrows == nil then
        g.editModeHideWhiteArrows = true
    end
    if g.linkEditModes == nil then
        g.linkEditModes = true
    end
end

local function MSUF_Defaults_Stage_SeedFontDefaults(profileDB, g)
    if g.boldText == nil then
        g.boldText = false
    end
    if g.noOutline == nil then
        g.noOutline = false
    end
    if g.nameClassColor == nil then
        g.nameClassColor = false
    end
    if g.npcNameRed == nil then
        g.npcNameRed = false
    end
    if g.nameNpcClassColor == nil then
        g.nameNpcClassColor = false
    end
    if g.fontColor == nil then
        g.fontColor = "white"
    end
    if g.shortenNameMaxChars == nil then
        g.shortenNameMaxChars = 6
    end
    if g.shortenNameClipSide == nil then
        g.shortenNameClipSide = "LEFT" --- default: clip LEFT, keep name end (R41z0r-style)
    end
    if g.shortenNameFrontMaskPx == nil then
        g.shortenNameFrontMaskPx = 8 --- px eaten from the clipped side (secret-safe, viewport inset)
    end
    if g.shortenNameShowDots == nil then
        g.shortenNameShowDots = true --- show '...' on the clipped edge (secret-safe)
    end
    --- GAME keeps Blizzard's locale-dependent abbreviation; COMPACT switches to
    --- MSUF's locale-independent breakpoints. Never default to COMPACT: CJK
    --- clients abbreviate on purpose differently.
    if g.numberAbbrevStyle ~= "COMPACT" then
        g.numberAbbrevStyle = "GAME"
    end
    if g.useCustomFontColor == nil then
        g.useCustomFontColor = false
    end
    if g.useCustomFontColor and (g.fontColorCustomR == nil or g.fontColorCustomG == nil or g.fontColorCustomB == nil) then
        g.useCustomFontColor = false
        g.fontColorCustomR = nil
        g.fontColorCustomG = nil
        g.fontColorCustomB = nil
    end
    if g.textBackdrop == nil then
        g.textBackdrop = true
    end
    if g.fontMonochrome == nil then
        g.fontMonochrome = false
    end
    if g.fontSlug == nil then
        g.fontSlug = false
    end
    if g.fontSlug == true then
        g.fontMonochrome = false
        if g.boldText == true then g.boldText = false end
    end
    MSUF_Defaults_NormalizeFontShadowScope(g, true)
    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        local scope = profileDB[key]
        if type(scope) == "table" and scope.fontSlug == true then
            scope.fontMonochrome = false
            if scope.boldText == true then scope.boldText = false end
            if scope.fontOutline == "THICKOUTLINE" then scope.fontOutline = "OUTLINE" end
        end
        MSUF_Defaults_NormalizeFontShadowScope(scope, false)
    end
    if type(g.fontTextAlpha) ~= "number" then
        g.fontTextAlpha = 1
    elseif g.fontTextAlpha < 0.7 then
        g.fontTextAlpha = 0.7
    elseif g.fontTextAlpha > 1 then
        g.fontTextAlpha = 1
    end
    if type(g.fontBaselineOffset) ~= "number" then
        g.fontBaselineOffset = 0
    elseif g.fontBaselineOffset < -4 then
        g.fontBaselineOffset = -4
    elseif g.fontBaselineOffset > 4 then
        g.fontBaselineOffset = 4
    end
end

local function MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults(profileDB, g)
    if g.highlightEnabled == nil then
        g.highlightEnabled = true
    end
    local highlightStyle = type(g.highlightStyle) == "string" and string.upper(g.highlightStyle) or "GRADIENT"
    g.highlightStyle = highlightStyle == "BORDER" and "BORDER" or "GRADIENT"
    local highlightThickness = math.floor((tonumber(g.highlightThickness) or 6) + 0.5)
    if highlightThickness < 1 then highlightThickness = 1 end
    if highlightThickness > 16 then highlightThickness = 16 end
    g.highlightThickness = highlightThickness
    local fontColors = (MSUF and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
    if type(g.highlightColor) == "table" then
        local color = g.highlightColor
            local r = tonumber(color[1] or color.r or color["1"])
        local green = tonumber(color[2] or color.g or color["2"])
        local b = tonumber(color[3] or color.b or color["3"])
        if r and green and b then
            g.highlightColor = {
                math.max(0, math.min(1, r)),
                math.max(0, math.min(1, green)),
                math.max(0, math.min(1, b)),
            }
        else
            g.highlightColor = "white"
        end
    elseif type(g.highlightColor) ~= "string" then
        g.highlightColor = "white"
    else
        g.highlightColor = string.lower(g.highlightColor)
        if not (fontColors and fontColors[g.highlightColor]) then
            g.highlightColor = "white"
        end
    end
    --- Status indicators (AFK/DND/Dead/Ghost toggles)
    if g.statusIndicators == nil then
        g.statusIndicators = {}
    end

    --- Boss Target Highlight: colored border on the boss unitframe you currently target
    if g.bossTargetHighlightEnabled == nil then
        g.bossTargetHighlightEnabled = true
    end
    if type(g.bossTargetHighlightColor) ~= "table" then
        g.bossTargetHighlightColor = { 1, 0.82, 0 }   --- gold
    end
    --- Border system integration (0=off, 1=on; synced with bossTargetHighlightEnabled)
    if g.bossTargetOutlineMode == nil then
        g.bossTargetOutlineMode = g.bossTargetHighlightEnabled and 1 or 0
    end
    --- UnitFrame dispel overlay (health-bar tint driven by native 12.1 aura visual state)
    if g.dispelOutlineMode == nil then g.dispelOutlineMode = 1 end
    if g.dispelBorderTrigger == nil then g.dispelBorderTrigger = "DISPEL_TYPE" end
    if g.dispelBorderShowOn == nil then g.dispelBorderShowOn = "BOTH" end
    if g.unitDispelOverlayEnabled == nil then g.unitDispelOverlayEnabled = false end
    if g.unitDispelOverlayStyle == nil then g.unitDispelOverlayStyle = "FULL" end
    if g.unitDispelOverlayOnHealth == nil then g.unitDispelOverlayOnHealth = true end
    if g.unitDispelOverlayAlpha == nil then g.unitDispelOverlayAlpha = 0.35 end
    if g.unitDispelOverlayTrigger == nil then g.unitDispelOverlayTrigger = "BORDER" end
    --- UnitFrame dispel-type symbol (placed icon naming the debuff type)
    if g.unitDispelSymbolEnabled == nil then g.unitDispelSymbolEnabled = false end
    if g.unitDispelSymbolStyle == nil then g.unitDispelSymbolStyle = "BLIZZARD" end
    if g.unitDispelSymbolMode == nil then g.unitDispelSymbolMode = "ALL" end
    if g.unitDispelSymbolTrigger == nil then g.unitDispelSymbolTrigger = "BORDER" end
    if g.unitDispelSymbolSize == nil then g.unitDispelSymbolSize = 14 end
    if g.unitDispelSymbolSpacing == nil then g.unitDispelSymbolSpacing = 2 end
    if g.unitDispelSymbolGrowth == nil then g.unitDispelSymbolGrowth = "RIGHT" end
    if g.unitDispelSymbolAnchor == nil then g.unitDispelSymbolAnchor = "TOPRIGHT" end
    if g.unitDispelSymbolX == nil then g.unitDispelSymbolX = 0 end
    if g.unitDispelSymbolY == nil then g.unitDispelSymbolY = 0 end
    if g.unitDispelSymbolAlpha == nil then g.unitDispelSymbolAlpha = 1 end
    if g.unitDispelSymbolLayer == nil then g.unitDispelSymbolLayer = 8 end
    if g.unitDispelSymbolStrata == nil then g.unitDispelSymbolStrata = "AUTO" end
    -- Overlay/Symbol controls now belong to their corresponding UnitFrame.
    -- Flatten the former Shared-vs-Bars-override result once so upgrading does
    -- not change any frame's appearance while future edits stay independent.
    MSUF_Defaults_MigrateUnitDispelOwnership(profileDB)
    local si = g.statusIndicators
    if si.showAFK == nil then si.showAFK = false end
    if si.showDND == nil then si.showDND = false end
    if si.showDead == nil then si.showDead = true end
    if si.showGhost == nil then si.showGhost = true end
    --- Drop obsolete update tuning keys. The 6.0 runtime is event-driven and no
    --- longer reads these values.
    g.miscUpdatesPreset = nil
    g.frameUpdateInterval = nil
    g.castbarUpdateInterval = nil
    g.ufcoreFlushBudgetMs = nil
    g.ufcoreUrgentMaxPerFlush = nil
    MSUF_FrameUpdateInterval = nil
    MSUF_CastbarUpdateInterval = nil
    local hadLegacyTooltipDisable = (g.disableUnitInfoTooltips ~= nil)
    local hadLegacyTooltipStyle = (g.unitInfoTooltipStyle ~= nil)
    local hadTooltipProvider = (g.unitTooltipProvider ~= nil)
    local hadTooltipAnchor = (g.unitTooltipAnchor ~= nil)
    if g.disableUnitInfoTooltips == nil then
        g.disableUnitInfoTooltips = true
    end
    if g.unitInfoTooltipStyle == nil then
        g.unitInfoTooltipStyle = "classic"
    end
    if (not hadTooltipProvider) and (not hadTooltipAnchor)
        and (not hadLegacyTooltipDisable) and (not hadLegacyTooltipStyle)
        and g.tooltipPosX == nil and g.tooltipPosY == nil then
        g.unitTooltipProvider = "GAME"
        g.unitTooltipAnchor = "EXTERNAL"
    end
    if g.unitTooltipProvider == nil then
        if g.disableUnitInfoTooltips == false then
            g.unitTooltipProvider = "MSUF"
        else
            g.unitTooltipProvider = "GAME"
        end
    elseif g.unitTooltipProvider ~= "GAME" and g.unitTooltipProvider ~= "MSUF" then
        g.unitTooltipProvider = "GAME"
    end
    if g.unitTooltipAnchor == nil then
        if g.unitTooltipProvider == "MSUF" then
            g.unitTooltipAnchor = (g.unitInfoTooltipStyle == "modern") and "CURSOR" or "FIXED"
        elseif (type(g.tooltipPosX) == "number") and (type(g.tooltipPosY) == "number") then
            g.unitTooltipAnchor = "FIXED"
        elseif g.unitInfoTooltipStyle == "modern" then
            g.unitTooltipAnchor = "CURSOR"
        elseif g.disableUnitInfoTooltips == true then
            g.unitTooltipAnchor = "EXTERNAL"
        else
            g.unitTooltipAnchor = "EXTERNAL"
        end
    elseif g.unitTooltipAnchor ~= "EXTERNAL" and g.unitTooltipAnchor ~= "FIXED" and g.unitTooltipAnchor ~= "CURSOR" then
        g.unitTooltipAnchor = "EXTERNAL"
    end
    if g.unitTooltipProvider == "MSUF" and g.unitTooltipAnchor == "EXTERNAL" then
        g.unitTooltipAnchor = "FIXED"
    end
    if g.unitTooltipMode == nil then
        g.unitTooltipMode = "ALWAYS"
    elseif g.unitTooltipMode == "OFF" then
        g.unitTooltipMode = "NEVER"
    elseif g.unitTooltipMode ~= "ALWAYS" and g.unitTooltipMode ~= "OOC"
        and g.unitTooltipMode ~= "MODIFIER" and g.unitTooltipMode ~= "NEVER" then
        g.unitTooltipMode = "ALWAYS"
    end
    if g.unitTooltipModifier == nil then
        g.unitTooltipModifier = "ALT"
    elseif g.unitTooltipModifier ~= "ALT" and g.unitTooltipModifier ~= "CTRL" and g.unitTooltipModifier ~= "SHIFT" then
        g.unitTooltipModifier = "ALT"
    end
    g.disableUnitInfoTooltips = (g.unitTooltipProvider ~= "MSUF")
    g.unitInfoTooltipStyle = (g.unitTooltipAnchor == "CURSOR") and "modern" or "classic"
    --- Tooltip custom position (set via Edit Mode drag).
    --- nil / false = use default style-based positioning (classic/modern).
    --- When set, these are BOTTOMLEFT-relative pixel coordinates on UIParent.
    --- Intentionally NOT defaulted: absence means "no custom position".
    if g.tooltipPosX ~= nil and type(g.tooltipPosX) ~= "number" then g.tooltipPosX = nil end
    if g.tooltipPosY ~= nil and type(g.tooltipPosY) ~= "number" then g.tooltipPosY = nil end
end

local function MSUF_Defaults_Stage_MigrateUnitTextModes(profileDB, g)
    --- Power text mode: migrate legacy modes to EQoL-style keys.
    local function _MSUF_MigratePowerMode(v)
        if v == nil then return nil end
        if v == "FULL_SLASH_MAX" then return "CURMAX" end
        if v == "FULL_ONLY" then return "CURRENT" end
        if v == "PERCENT_ONLY" then return "PERCENT" end
        if v == "FULL_PLUS_PERCENT" or v == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
        return v
    end

    g.powerTextMode = _MSUF_MigratePowerMode(g.powerTextMode)
    for _, unitKey in ipairs({"player","target","focus","targettarget","focustarget","pet","boss", "arena"}) do
        local u = profileDB[unitKey]
        if type(u) == "table" then
            u.powerTextMode = _MSUF_MigratePowerMode(u.powerTextMode)
        end
    end

    if g.powerTextMode == nil then
        g.powerTextMode = "CURPERCENT"
    end

    --- Unit Frame text is per-unit as of the Unit Frame UX refactor.
    --- Older profiles could inherit HP/Power pattern settings from general.* unless
    --- hpPowerTextOverride was enabled. Flatten that inherited value once so saved
    --- profiles keep their exact look while the new UI edits only the selected unit.
    do
        local function _MSUF_MigrateHpMode(v)
            if v == nil then return nil end
            if v == "FULL_ONLY" then return "CURRENT" end
            if v == "PERCENT_ONLY" then return "PERCENT" end
            if v == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
            if v == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
            return v
        end
        g.hpTextMode = _MSUF_MigrateHpMode(g.hpTextMode) or "CURPERCENT"
        local defaults = {
            hpTextMode = g.hpTextMode or "CURPERCENT",
            textLeft = "NONE",
            textCenter = "NONE",
            textRight = g.hpTextMode or "CURPERCENT",
            hpTextReverse = (g.hpTextReverse == true),
            powerTextMode = g.powerTextMode or "CURPERCENT",
            powerTextLeft = "NONE",
            powerTextCenter = "NONE",
            powerTextRight = g.powerTextMode or "CURPERCENT",
            hpTextLeftOffsetX = 0,
            hpTextLeftOffsetY = 0,
            hpTextCenterOffsetX = 0,
            hpTextCenterOffsetY = 0,
            hpTextRightOffsetX = 0,
            hpTextRightOffsetY = 0,
            powerTextLeftOffsetX = 0,
            powerTextLeftOffsetY = 0,
            powerTextCenterOffsetX = 0,
            powerTextCenterOffsetY = 0,
            powerTextRightOffsetX = 0,
            powerTextRightOffsetY = 0,
            hpTextSeparator = (g.hpTextSeparator ~= nil) and g.hpTextSeparator or "-",
            powerTextSeparator = (g.powerTextSeparator ~= nil) and g.powerTextSeparator or ((g.hpTextSeparator ~= nil) and g.hpTextSeparator or "-"),
            nameTextLayer = tonumber(g.nameTextLayer) or 5,
            hpTextLayer = tonumber(g.hpTextLayer) or tonumber(g.textLayer) or 5,
            powerTextLayer = tonumber(g.powerTextLayer) or 2,
        }
        for _, unitKey in ipairs({"player","target","focus","targettarget","focustarget","pet","boss", "arena"}) do
            profileDB[unitKey] = profileDB[unitKey] or {}
            local u = profileDB[unitKey]
            if type(u) == "table" then
                for field, fallback in pairs(defaults) do
                    if field ~= "textLeft" and field ~= "textCenter" and field ~= "textRight"
                        and field ~= "powerTextLeft" and field ~= "powerTextCenter" and field ~= "powerTextRight"
                        and u[field] == nil
                    then
                        u[field] = fallback
                    end
                end
                u.hpTextMode = _MSUF_MigrateHpMode(u.hpTextMode) or defaults.hpTextMode
                u.powerTextMode = _MSUF_MigratePowerMode(u.powerTextMode) or defaults.powerTextMode
                if u.textLeft == nil and u.textCenter == nil and u.textRight == nil then
                    u.textLeft = "NONE"
                    u.textCenter = "NONE"
                    u.textRight = u.hpTextMode or defaults.textRight
                else
                    if u.textLeft == nil then u.textLeft = defaults.textLeft end
                    if u.textCenter == nil then u.textCenter = defaults.textCenter end
                    if u.textRight == nil then u.textRight = defaults.textRight end
                end
                if u.powerTextLeft == nil and u.powerTextCenter == nil and u.powerTextRight == nil then
                    u.powerTextLeft = "NONE"
                    u.powerTextCenter = "NONE"
                    u.powerTextRight = u.powerTextMode or defaults.powerTextRight
                else
                    if u.powerTextLeft == nil then u.powerTextLeft = defaults.powerTextLeft end
                    if u.powerTextCenter == nil then u.powerTextCenter = defaults.powerTextCenter end
                    if u.powerTextRight == nil then u.powerTextRight = defaults.powerTextRight end
                end
                u.hpPowerTextOverride = nil
            end
        end
        g._msufUFTextPerUnitMigrated_v4325 = true
    end
end

local function MSUF_Defaults_Stage_SeedGameplayDefaults(profileDB)
    --- Gameplay defaults (module-safe: some modules expect MSUF_DB.gameplay to exist)
    if profileDB.gameplay == nil then
        profileDB.gameplay = {}
    end
    local gp = profileDB.gameplay
    if gp.enableCombatTimer == nil then gp.enableCombatTimer = false end
    if gp.lockCombatTimer == nil then gp.lockCombatTimer = false end
    if gp.combatFontSize == nil then gp.combatFontSize = 24 end
    if gp.combatOffsetX == nil then gp.combatOffsetX = 0 end
    if gp.combatOffsetY == nil then gp.combatOffsetY = -200 end
    if gp.enableCombatStateText == nil then gp.enableCombatStateText = false end
    if gp.lockCombatState == nil then gp.lockCombatState = false end
    if gp.combatStateFontSize == nil then gp.combatStateFontSize = 24 end
    if gp.combatStateOffsetX == nil then gp.combatStateOffsetX = 0 end
    if gp.combatStateOffsetY == nil then gp.combatStateOffsetY = 80 end
    if gp.combatStateDuration == nil then gp.combatStateDuration = 1.5 end
    if gp.enableCombatCrosshair == nil then gp.enableCombatCrosshair = false end
    if gp.enableCombatCrosshairMeleeRangeColor == nil then gp.enableCombatCrosshairMeleeRangeColor = false end
    if gp.crosshairSize == nil then gp.crosshairSize = 40 end
    if gp.crosshairThickness == nil then gp.crosshairThickness = 2 end
    if gp.cooldownIcons == nil then gp.cooldownIcons = false end
    if gp.nameplateMeleeSpellID == nil then gp.nameplateMeleeSpellID = 0 end
    --- Unitframe range-fade defaults are assigned with the unitframe defaults below.
    --- Gameplay: Crosshair melee range spell can optionally be stored per class.
    --- This lets users run a single profile across multiple characters without
    --- having to swap the spell whenever they change class.
    if gp.meleeSpellPerClass == nil then gp.meleeSpellPerClass = false end
    if gp.meleeSpellPerSpec == nil then gp.meleeSpellPerSpec = false end
    if gp.nameplateMeleeSpellIDByClass == nil then gp.nameplateMeleeSpellIDByClass = {} end
    if gp.nameplateMeleeSpellIDBySpec == nil then gp.nameplateMeleeSpellIDBySpec = {} end
end
return {
    MSUF_Defaults_Stage_SeedShellDefaults = MSUF_Defaults_Stage_SeedShellDefaults,
    MSUF_Defaults_Stage_SeedFontDefaults = MSUF_Defaults_Stage_SeedFontDefaults,
    MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults = MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults,
    MSUF_Defaults_Stage_MigrateUnitTextModes = MSUF_Defaults_Stage_MigrateUnitTextModes,
    MSUF_Defaults_Stage_SeedGameplayDefaults = MSUF_Defaults_Stage_SeedGameplayDefaults,
}
end
