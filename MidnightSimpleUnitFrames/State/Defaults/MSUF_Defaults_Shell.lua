-- Shared shell defaults. Client-specific policy is bound once, outside gameplay paths.
local _, MSUF = ...
-- The factory default profile: one MSUF3 export (Base64, raw Deflate, CBOR) that every
-- client this repo builds starts from. Both MSUF_Defaults.lua files read it from here.
MSUF.DefaultsStageFactories = MSUF.DefaultsStageFactories or {}
MSUF.DefaultsStageFactories.Shell = function(dependencies)
local MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = dependencies.MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION
local MSUF_Defaults_GetMenuFontDefault = dependencies.MSUF_Defaults_GetMenuFontDefault
local MSUF_Defaults_MigrateUnitDispelOwnership = dependencies.MSUF_Defaults_MigrateUnitDispelOwnership
local MSUF_Defaults_NormalizeFontShadowScope = dependencies.MSUF_Defaults_NormalizeFontShadowScope
local function MSUF_Defaults_Stage_SeedShellDefaults(profileDB, g)
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_01")
    --- New install defaults (UI scale + Flash menu anchor)
    --- Default: Unhalted-style global UI scale disabled; local MSUF scales remain independent.
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_02")
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
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_03")
    --- Minimap icon (LibDBIcon) defaults
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellShowMinimapIcon)
    --- WoW 12.1 can turn contextual pings on the MSUF Player frame into native
    --- player-resource callouts. Match Blizzard's PlayerFrame by default while
    --- retaining an explicit opt-out; the client still chooses health or supported
    --- mana contexts and does not expose energy pings.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellPlayerResourcePingEnabled)
    --- Login greeting in chat (Runtime/MSUF_WelcomeMessage.lua)
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellShowWelcomeMessage)
    --- Native 12.1 "spell IDs in aura tooltips" CVar, re-applied at login because
    --- the client resets it every session (Runtime/MSUF_TooltipSpellIDs.lua).
    --- Off by default: MSUF must not touch the CVar unless the user opts in here.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellTooltipShowAuraSpellIDs)
--- 12.1.5 caster names in aura tooltips (Runtime/MSUF_TooltipSpellIDs.lua).
--- Off by default for the same reason: MSUF must not claim the CVar unopted.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellTooltipShowAuraCasterNames)
    --- EllesmereUI may own the visible Unlock Mode shell while MSUF keeps its own
    --- profile geometry and preview transaction. Users can opt out only when the
    --- EllesmereUI integration is actually available.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellEllesmereEditModeIntegration)
    --- Northern Sky Raid Tools nicknames are enabled for MSUF by default to
    --- preserve the established integration behavior, with a profile-local opt-out.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellNsrtNicknameIntegration)
    --- Optional native Edit Mode adapters. The third-party addons remain the sole
    --- owners of their frames and saved positions; these switches only control
    --- whether MSUF registers movers for them.
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_04")
    if g.dropdownStyleMode == nil then
        g.dropdownStyleMode = "msuf"
    elseif g.dropdownStyleMode ~= "old" and g.dropdownStyleMode ~= "msuf" and g.dropdownStyleMode ~= "blizzard" and g.dropdownStyleMode ~= "legacy" then
        g.dropdownStyleMode = "msuf"
    end
    if g.pendingDropdownStyleMode ~= nil and g.pendingDropdownStyleMode ~= "old"
        and g.pendingDropdownStyleMode ~= "msuf" and g.pendingDropdownStyleMode ~= "blizzard" and g.pendingDropdownStyleMode ~= "legacy" then
        g.pendingDropdownStyleMode = nil
    end
    if type(g.minimapIconDB) ~= "table" then
        g.minimapIconDB = { hide = false, minimapPos = 220, radius = 80 }
    else
        MSUF.DefaultsSchema.Fill(g.minimapIconDB, MSUF.DefaultsSchema.Values.ShellHide)
    end
    --- Target select / target lost sounds (opt-in; matches default Blizzard UI behavior)
    --- Default OFF to avoid changing behavior for existing users.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellPlayTargetSelectLostSounds)
    --- Fonts: color the compact power text by the unit's current power type
    --- (mana/rage/energy/etc.) so it stays identifiable without a larger label.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellColorPowerTextByType)
    --- Fonts: optionally color the *health text* by current health percentage.
    --- Default OFF to preserve existing behavior.
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_05")
    --- Navigation icons became the standard Menu2 presentation in Defaults
    --- revision 7. Upgrade older stored profiles once, but preserve an explicit
    --- user choice made after that migration.
    if (tonumber(profileDB._msufDefaultsRevision) or 0) < MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION then
        g.showNavigationIcons = true
    elseif g.showNavigationIcons == nil then
        g.showNavigationIcons = true
    end
    -- Keep explicit guide choices, including profiles created before this default.
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_06")
    if g.menuFontKey == nil then
        g.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellEditModeSnapToGrid)
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_07")
end

local function MSUF_Defaults_Stage_SeedFontDefaults(profileDB, g)
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_08")
    if type(g.fontColor) ~= "string" then
        g.fontColor = "white"
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellShortenNameMaxChars)
    --- GAME keeps Blizzard's locale-dependent abbreviation; COMPACT switches to
    --- MSUF's locale-independent breakpoints. Never default to COMPACT: CJK
    --- clients abbreviate on purpose differently.
    if g.numberAbbrevStyle ~= "COMPACT" then
        g.numberAbbrevStyle = "GAME"
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellUseCustomFontColor)
    if g.useCustomFontColor and (g.fontColorCustomR == nil or g.fontColorCustomG == nil or g.fontColorCustomB == nil) then
        g.useCustomFontColor = false
        g.fontColorCustomR = nil
        g.fontColorCustomG = nil
        g.fontColorCustomB = nil
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_09")
    if g.fontSlug == true then
        g.fontMonochrome = false
        if g.boldText == true then g.boldText = false end
    end
    MSUF_Defaults_NormalizeFontShadowScope(g, true)
    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
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
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellHighlightEnabled)
    local highlightStyle = type(g.highlightStyle) == "string" and string.upper(g.highlightStyle) or "GRADIENT"
    g.highlightStyle = highlightStyle == "BORDER" and "BORDER" or "GRADIENT"
    local highlightThickness = math.floor((tonumber(g.highlightThickness) or 6) + 0.5)
    if highlightThickness < 1 then highlightThickness = 1 end
    if highlightThickness > 16 then highlightThickness = 16 end
    g.highlightThickness = highlightThickness
    local fontColors = (MSUF and MSUF.MSUF_FONT_COLORS) or MSUF.PublicGlobals.MSUF_FONT_COLORS
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
    if type(g.statusIndicators) ~= "table" then
        g.statusIndicators = {}
    end

    --- Boss Target Highlight: colored border on the boss unitframe you currently target
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellBossTargetHighlightEnabled)
    if type(g.bossTargetHighlightColor) ~= "table" then
        g.bossTargetHighlightColor = { 1, 0.82, 0 }   --- gold
    end
    --- Border system integration (0=off, 1=on; synced with bossTargetHighlightEnabled)
    if g.bossTargetOutlineMode == nil then
        g.bossTargetOutlineMode = g.bossTargetHighlightEnabled and 1 or 0
    end
    --- UnitFrame dispel overlay (health-bar tint driven by native 12.1 aura visual state)
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_10")
    --- UnitFrame dispel-type symbol (placed icon naming the debuff type)
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_11")
    -- Overlay/Symbol controls now belong to their corresponding UnitFrame.
    -- Flatten the former Shared-vs-Bars-override result once so upgrading does
    -- not change any frame's appearance while future edits stay independent.
    MSUF_Defaults_MigrateUnitDispelOwnership(profileDB)
    local si = g.statusIndicators
    MSUF.DefaultsSchema.Fill(si, MSUF.DefaultsSchema.Values.ShellShowAFK)
    --- Drop obsolete update tuning keys. The 6.0 runtime is event-driven and no
    --- longer reads these values.
    g.miscUpdatesPreset = nil
    g.frameUpdateInterval = nil
    g.castbarUpdateInterval = nil
    g.ufcoreFlushBudgetMs = nil
    g.ufcoreUrgentMaxPerFlush = nil
    MSUF.ExportPublic("MSUF_FrameUpdateInterval", nil)
    MSUF.ExportPublic("MSUF_CastbarUpdateInterval", nil)
    local hadLegacyTooltipDisable = (g.disableUnitInfoTooltips ~= nil)
    local hadLegacyTooltipStyle = (g.unitInfoTooltipStyle ~= nil)
    local hadTooltipProvider = (g.unitTooltipProvider ~= nil)
    local hadTooltipAnchor = (g.unitTooltipAnchor ~= nil)
    MSUF.DefaultsSchema.SeedGeneral(g, "shell_12")
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
    for _, unitKey in ipairs({"player","target","focus","targettarget","focustarget","pet","pettarget","boss", "arena"}) do
        local u = profileDB[unitKey]
        if type(u) == "table" then
            u.powerTextMode = _MSUF_MigratePowerMode(u.powerTextMode)
        end
    end

    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.ShellPowerTextMode)

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
            hpTextSeparator = (g.hpTextSeparator ~= nil) and g.hpTextSeparator or "-",
            powerTextSeparator = (g.powerTextSeparator ~= nil) and g.powerTextSeparator or ((g.hpTextSeparator ~= nil) and g.hpTextSeparator or "-"),
            nameTextLayer = tonumber(g.nameTextLayer) or 5,
            hpTextLayer = tonumber(g.hpTextLayer) or tonumber(g.textLayer) or 5,
            powerTextLayer = tonumber(g.powerTextLayer) or 2,
        }
        MSUF.StateHelpers.SeedTextOffsets(defaults)
        for _, unitKey in ipairs({"player","target","focus","targettarget","focustarget","pet","pettarget","boss", "arena"}) do
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
    MSUF.DefaultsSchema.Fill(gp, MSUF.DefaultsSchema.Values.ShellEnableCombatTimer)
    --- Unitframe range-fade defaults are assigned with the unitframe defaults below.
    --- Gameplay: Crosshair melee range spell can optionally be stored per class.
    --- This lets users run a single profile across multiple characters without
    --- having to swap the spell whenever they change class.
    MSUF.DefaultsSchema.Fill(gp, MSUF.DefaultsSchema.Values.ShellMeleeSpellPerClass)
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
