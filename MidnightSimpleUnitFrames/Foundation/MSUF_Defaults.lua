local addonName, addonNS = ...
local ns = (_G.MSUF_NS) or addonNS or {}
_G.MSUF_NS = ns

-- MSUF default class-resource colors
-- Keep this tiny and global so:
-- 1) class power fallback colors use the new defaults
-- 2) reset-to-default in the Colors menu also lands on these defaults
-- 3) no runtime overhead in hot paths (one-time table write at load)
do
    local pbc = _G.PowerBarColor
    if type(pbc) == "table" then
        pbc.RUNES = pbc.RUNES or {}
        pbc.RUNES.r, pbc.RUNES.g, pbc.RUNES.b = 128/255, 0, 17/255      -- #800011

        pbc.SOUL_SHARDS = pbc.SOUL_SHARDS or {}
        pbc.SOUL_SHARDS.r, pbc.SOUL_SHARDS.g, pbc.SOUL_SHARDS.b = 135/255, 136/255, 238/255 -- #8788EE
    end
end

-- MSUF Defaults / DB initialization
-- ---------------------------------------------------------------------------
-- Factory default profile (MSUF compact string)
--
-- If MSUF_DB is NEW (fresh install / full reset), we seed it from this payload
-- so the addon boots with your preferred baseline.
--
-- Existing installs are NOT overwritten. This only runs when MSUF_DB was
-- created empty in this session.
-- ---------------------------------------------------------------------------
-- Current factory default profile.
local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = [[MSUF3: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]]

-- Expose the factory compact string for diagnostics and future tooling.
if type(ns) == "table" then
    ns.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
end
if _G then
    _G.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
end

local function MSUF_Defaults_TryDecodeCompactString(str)
    if type(str) ~= "string" then  return nil end
    local E = _G.C_EncodingUtil
    if not E then  return nil end
    if type(E.DeserializeCBOR) ~= "function" then  return nil end
    if type(E.DecodeBase64) ~= "function" then  return nil end
    local ok, prefix, b64 = pcall(string.match, str, "^%s*(MSUF%d+):%s*(.-)%s*$")
    if not ok or (prefix ~= "MSUF2" and prefix ~= "MSUF3") or type(b64) ~= "string" or b64 == "" then  return nil end
    local ok2, cleaned = pcall(string.gsub, b64, "%s+", "")
    if not ok2 or type(cleaned) ~= "string" or cleaned == "" then  return nil end
    local rem = #cleaned % 4
    if rem == 1 then
        return nil
    elseif rem == 2 then
        cleaned = cleaned .. "=="
    elseif rem == 3 then
        cleaned = cleaned .. "="
    end
    local ok3, blob = pcall(E.DecodeBase64, cleaned)
    if not ok3 or type(blob) ~= "string" then  return nil end
    local function TryDeserialize(payload)
        if type(payload) ~= "string" then  return nil end
        local okD, tbl = pcall(E.DeserializeCBOR, payload)
        if okD and type(tbl) == "table" then  return tbl end
        return nil
    end
    local tbl = TryDeserialize(blob)
    if tbl then  return tbl end
    if type(E.DecompressString) ~= "function" then  return nil end
    local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil
    local ok4, plain
    if method ~= nil then
        ok4, plain = pcall(E.DecompressString, blob, method)
        tbl = ok4 and TryDeserialize(plain) or nil
        if tbl then  return tbl end
    end
    ok4, plain = pcall(E.DecompressString, blob)
    tbl = ok4 and TryDeserialize(plain) or nil
    return tbl
end
local function MSUF_Defaults_WipeInPlace(t)
    if not t then  return end
    for k in pairs(t) do t[k] = nil end
 end
local function MSUF_Defaults_DeepCopy(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then  return end
    for k, v in pairs(src) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            local tv = type(v)
            if tv == "table" then
                local d = dst[k]
                if type(d) ~= "table" then
                    d = {}
                    dst[k] = d
                else
                    MSUF_Defaults_WipeInPlace(d)
                end
                MSUF_Defaults_DeepCopy(d, v)
            elseif tv == "string" or tv == "number" or tv == "boolean" then
                dst[k] = v
            end
        end
    end
 end
local function MSUF_Defaults_GetProfilePayload(tbl)
    if type(tbl) ~= "table" then
        return nil
    end
    -- Current exports wrap profile data as a snapshot. Older/tooling exports may
    -- decode directly to the profile table; keep both valid for factory defaults.
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" then
        return tbl.payload
    end
    return tbl
end
-- Fresh-install overrides (applied only when the factory profile payload is seeded).
-- Keep this tiny and explicit: these are the "real defaults" for a wiped/new DB.
local function MSUF_Defaults_ApplyFreshInstallOverrides(db)
    if not db then  return end
    local function ForceUnitAlpha100(conf)
        if not conf then  return end
        -- Main alpha (used when layered alpha is off)
        conf.alphaInCombat = 1
        conf.alphaOutOfCombat = 1
        -- Layered alpha (used when "Keep text/portrait visible" is on)
        conf.alphaFGInCombat = 1
        conf.alphaFGOutOfCombat = 1
        conf.alphaBGInCombat = 1
        conf.alphaBGOutOfCombat = 1
        conf.alphaHPInCombat = 1
        conf.alphaHPOutOfCombat = 1
        conf.alphaPreserveHPColor = false
     end
    ForceUnitAlpha100(db.player)
    -- Fresh-install default: player name hidden
    if type(db.player) == "table" then
        db.player.showName = false
    end
    ForceUnitAlpha100(db.target)
    ForceUnitAlpha100(db.focus)
    ForceUnitAlpha100(db.pet)
    ForceUnitAlpha100(db.boss)
    ForceUnitAlpha100(db.targettarget)
    ForceUnitAlpha100(db.tot)
    -- Fresh-install defaults: status indicators (AFK/DND) off by default
    local g = db.general
    if type(g) == 'table' then
        g.statusIndicators = g.statusIndicators or {}
        local si = g.statusIndicators
        si.showAFK = false
        si.showDND = false

        -- Fresh-install scaling defaults:
        -- Always start in Auto (Blizzard decides the global UI scale), and keep MSUF scaling enabled.
        g.disableScaling = false
        g.globalUiScalePreset = "auto"
        g.globalUiScaleValue = nil
        g.UIScale = { Enabled = false, Scale = 1.0 }
        g.msufUiScale = 1.0
    end
 end
local function MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall()
    if not MSUF_DB then  return end
    local g = (type(MSUF_DB.general) == "table") and MSUF_DB.general or nil
    if g and g._msufFactoryProfileApplied then
         return
    end
    -- Only seed when the DB was just created empty.
    -- (Existing installs always already have keys before EnsureDB_Heavy runs.)
    local isEmpty = (next(MSUF_DB) == nil)
    if not isEmpty then return end
    local tbl = MSUF_Defaults_TryDecodeCompactString(MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    if not tbl then  return end
    local payload = MSUF_Defaults_GetProfilePayload(tbl)
    if type(payload) ~= "table" then  return end
    -- Replace the empty DB with the decoded payload.
    MSUF_Defaults_DeepCopy(MSUF_DB, payload)
    MSUF_Defaults_ApplyFreshInstallOverrides(MSUF_DB)
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general._msufFactoryProfileApplied = true
 end
local MSUF_DB_LastHeavyRun
function MSUF_EnsureDB_Heavy()
    if not MSUF_DB then
        MSUF_DB = {}
    end
    -- Seed brand-new installs / hard-resets from the factory profile payload.
    MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    MSUF_DB.classColors = MSUF_DB.classColors or {}
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}
    if g.fontKey == nil then
        g.fontKey = "FRIZQT"
    end
    if g.hardKillBlizzardPlayerFrame == nil then
        -- Default: Hard-hide Blizzard PlayerFrame (compat mode OFF).
        g.hardKillBlizzardPlayerFrame = true
    end
if g.anchorName == nil then
    g.anchorName = "UIParent"
end
if g.anchorToCooldown == nil then
    g.anchorToCooldown = false
end
-- New install defaults (UI scale + Flash menu anchor)
-- Default: Auto global UI scale (Blizzard handles it). MSUF scaling is enabled unless the user turns it off.
if g.disableScaling == nil then
    g.disableScaling = false
end
if g.globalUiScalePreset == nil then
    g.globalUiScalePreset = "auto"
end
-- Migrate global UI scale storage to the Unhalted-style table:
-- General.UIScale.Enabled + General.UIScale.Scale. Keep the legacy preset keys
-- populated so older exports/tools can still reason about the profile.
do
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
        local enabled = (g.disableScaling ~= true)
            and (preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom")
        ui.Enabled = enabled and true or false
        ui.Scale = scale
        ui._migratedFromGlobalPreset_v1 = true
    end
    if ui.Enabled == nil then
        local preset = g.globalUiScalePreset
        ui.Enabled = (g.disableScaling ~= true)
            and (preset == "1080p" or preset == "1440p" or preset == "4k" or preset == "pixel" or preset == "custom")
    end
    ui.Enabled = (ui.Enabled == true)
    ui.Scale = tonumber(ui.Scale) or PresetScale(g.globalUiScalePreset, g.globalUiScaleValue) or 1.0
    if ui.Scale < 0.3 then ui.Scale = 0.3 elseif ui.Scale > 2.0 then ui.Scale = 2.0 end
    if g.disableScaling == true then
        ui.Enabled = false
    end
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
-- Nil value = Auto (no enforced custom global UI scale)
-- (Do NOT seed a default globalUiScaleValue on fresh installs.)
if g.msufUiScale == nil then
    g.msufUiScale = 1.0
end
if g.flashFullPoint == nil then g.flashFullPoint = "CENTER" end
if g.flashFullRelPoint == nil then g.flashFullRelPoint = "CENTER" end
if g.flashFullX == nil then g.flashFullX = -60 end
if g.flashFullY == nil then g.flashFullY = 10 end
if g.flashFullW == nil then g.flashFullW = 900 end
if g.flashFullH == nil then g.flashFullH = 650 end
if g.flashFullXpx == nil then g.flashFullXpx = -60 end
if g.flashFullYpx == nil then g.flashFullYpx = 10 end
if g.tipCycleIndex == nil then
    g.tipCycleIndex = 11
end
-- Minimap icon (LibDBIcon) defaults
if g.showMinimapIcon == nil then
    g.showMinimapIcon = true
end
if g.rangeFadePortrait == nil then
    g.rangeFadePortrait = false
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
-- Target select / target lost sounds (opt-in; matches default Blizzard UI behavior)
-- Default OFF to avoid changing behavior for existing users.
if g.playTargetSelectLostSounds == nil then
    g.playTargetSelectLostSounds = false
end
-- Fonts: optionally color the *power text* by the unit's current power type (mana/rage/energy/etc).
-- Default OFF to preserve existing behavior.
if g.colorPowerTextByType == nil then
    g.colorPowerTextByType = false
end
    if g.editModeSnapToGrid == nil then
        g.editModeSnapToGrid = false -- Default: Snap OFF
    end
    if g.editModeGridStep == nil then
        g.editModeGridStep = 20
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
 if g.darkMode == nil then
        g.darkMode = false
    end
    if g.darkBarTone == nil then
        g.darkBarTone = "black"
    end
    if g.darkBgBrightness == nil then
        g.darkBgBrightness = 0.25      -- 25% Grau als Standard
    end
    -- When true, dark mode uses the bar-background tint color directly (no brightness dimming).
    -- Allows fully custom background colors (including white) in dark mode.
    if g.darkBgCustomColor == nil then
        g.darkBgCustomColor = false
    end
    if g.classBarBgR == nil or g.classBarBgG == nil or g.classBarBgB == nil then
        g.classBarBgR = 0.0   -- default: black background
        g.classBarBgG = 0.0
        g.classBarBgB = 0.0
    end
    -- If enabled, bar background tint color follows the current HP bar color (class/reaction/unified),
    -- instead of using the custom tint swatch.
    if g.barBgMatchHPColor == nil then
        g.barBgMatchHPColor = false
    end
    if g.enableGradient == nil then
        g.enableGradient = true
    end
    if g.enablePowerGradient == nil then
        g.enablePowerGradient = false
    end
    -- Bars: Aggro highlight overlay (Target/Focus/Boss)
    -- Aggro indicator: re-uses the HP outline border as an orange warning when YOU have aggro (target/focus/boss).
    if g.aggroIndicatorMode == nil then
        if g.enableAggroHighlight == true then
            g.aggroIndicatorMode = "border" -- legacy migrate
        else
            g.aggroIndicatorMode = "off"
        end
    end
    if g.aggroIndicatorMode ~= "border" then
        g.aggroIndicatorMode = "off"
    end

    if g.gradientStrength == nil then
        g.gradientStrength = 0.45
    end
do
    local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
    if not hasNew then
        local dir = g.gradientDirection
        if type(dir) ~= "string" or dir == "" then
            dir = "RIGHT"
        else
            dir = string.upper(dir)
        end
        if dir == "LEFT" then
            g.gradientDirLeft = true
        elseif dir == "UP" then
            g.gradientDirUp = true
        elseif dir == "DOWN" then
            g.gradientDirDown = true
        else
            g.gradientDirRight = true
        end
    end
    if g.gradientDirLeft == nil then g.gradientDirLeft = false end
    if g.gradientDirRight == nil then g.gradientDirRight = false end
    if g.gradientDirUp == nil then g.gradientDirUp = false end
    if g.gradientDirDown == nil then g.gradientDirDown = false end
    if (not g.gradientDirLeft) and (not g.gradientDirRight) and (not g.gradientDirUp) and (not g.gradientDirDown) then
        g.gradientDirRight = true
    end
    -- Keep legacy key as a reasonable fallback for older builds/tools.
    if type(g.gradientDirection) ~= "string" or g.gradientDirection == "" then
        g.gradientDirection = "RIGHT"
    end
end
    if g.editModeBgAlpha == nil or type(g.editModeBgAlpha) ~= "number" then
        g.editModeBgAlpha = 0.5
    else
        if g.editModeBgAlpha < 0.1 then
            g.editModeBgAlpha = 0.1
        elseif g.editModeBgAlpha > 0.8 then
            g.editModeBgAlpha = 0.8
        end
    end
    if g.useClassColors == nil then
        g.useClassColors = true
    end
    if g.barMode == nil then
        if g.useClassColors then
            g.barMode = "class"
        elseif g.darkMode then
            g.barMode = "dark"
        else
            g.barMode = "dark"
            g.darkMode = true
            g.useClassColors = false
        end
    end
    -- Normalize Bar mode (supports: dark / class / unified / gradient) and keep legacy flags in sync
    if g.barMode ~= "dark" and g.barMode ~= "class" and g.barMode ~= "unified" and g.barMode ~= "gradient" then
        g.barMode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
    end
    if g.barMode == "dark" then
        g.darkMode = true
        g.useClassColors = false
    elseif g.barMode == "class" then
        g.darkMode = false
        g.useClassColors = true
    elseif g.barMode == "gradient" then
        -- Gradient mode is HP-derived; neither legacy flag applies.
        g.darkMode = false
        g.useClassColors = false
    else -- unified
        g.darkMode = false
        g.useClassColors = false
    end
    -- NPC Color Mode: "reaction" (classic friendly/neutral/enemy) or "type" (boss/miniboss/caster/melee/regular).
    -- When "type", enemy NPC health bars in barMode "class" show classification-based colors.
    if g.npcColorMode == nil then
        g.npcColorMode = "reaction"
    end
    if g.npcColorMode ~= "reaction" and g.npcColorMode ~= "type" then
        g.npcColorMode = "reaction"
    end
    if g.npcTypeColorBar == nil then
        g.npcTypeColorBar = true
    end
    if g.npcTypeColorText == nil then
        g.npcTypeColorText = true
    end
    -- Per-unit NPC Type enable (nil/true = on, false = off)
    if g.npcTypeTarget == nil then g.npcTypeTarget = true end
    if g.npcTypeFocus  == nil then g.npcTypeFocus  = true end
    if g.npcTypeBoss   == nil then g.npcTypeBoss   = true end
    if g.npcTypeToT    == nil then g.npcTypeToT    = true end
        if type(g.unifiedBarR) ~= "number" then g.unifiedBarR = 0.10 end
        if type(g.unifiedBarG) ~= "number" then g.unifiedBarG = 0.60 end
        if type(g.unifiedBarB) ~= "number" then g.unifiedBarB = 0.90 end
    if g.useBarBorder == nil then
        g.useBarBorder = true
    end
    if g.barBorderStyle == nil then
        g.barBorderStyle = "THIN"
    end
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
    if g.fontColor == nil then
        g.fontColor = "white"
    end
    if g.shortenNameMaxChars == nil then
        g.shortenNameMaxChars = 6
    end
    if g.shortenNameClipSide == nil then
        g.shortenNameClipSide = "LEFT" -- default: clip LEFT, keep name end (R41z0r-style)
    end
    if g.shortenNameFrontMaskPx == nil then
        g.shortenNameFrontMaskPx = 8 -- px eaten from the clipped side (secret-safe, viewport inset)
    end
    if g.shortenNameShowDots == nil then
        g.shortenNameShowDots = true -- show '...' on the clipped edge (secret-safe)
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
    if g.highlightEnabled == nil then
        g.highlightEnabled = true
    end
    local fontColors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
    if type(g.highlightColor) ~= "string" then
        g.highlightColor = "white"
    else
        g.highlightColor = string.lower(g.highlightColor)
        if not (fontColors and fontColors[g.highlightColor]) then
            g.highlightColor = "white"
        end
    end
    -- Status indicators (AFK/DND/Dead/Ghost toggles)
    if g.statusIndicators == nil then
        g.statusIndicators = {}
    end

    -- Boss Target Highlight: colored border on the boss unitframe you currently target
    if g.bossTargetHighlightEnabled == nil then
        g.bossTargetHighlightEnabled = true
    end
    if type(g.bossTargetHighlightColor) ~= "table" then
        g.bossTargetHighlightColor = { 1, 0.82, 0 }   -- gold
    end
    -- Border system integration (0=off, 1=on; synced with bossTargetHighlightEnabled)
    if g.bossTargetOutlineMode == nil then
        g.bossTargetOutlineMode = g.bossTargetHighlightEnabled and 1 or 0
    end
    local si = g.statusIndicators
    if si.showAFK == nil then si.showAFK = false end
    if si.showDND == nil then si.showDND = false end
    if si.showDead == nil then si.showDead = true end
    if si.showGhost == nil then si.showGhost = true end
    if g.frameUpdateInterval == nil or type(g.frameUpdateInterval) ~= "number" then
        g.frameUpdateInterval = 0.05
    end
    MSUF_FrameUpdateInterval = g.frameUpdateInterval
    if g.castbarUpdateInterval == nil or type(g.castbarUpdateInterval) ~= "number" then
        g.castbarUpdateInterval = 0.02
    end
    MSUF_CastbarUpdateInterval = g.castbarUpdateInterval
    -- UFCore flush budgeting (spike cap)
    if g.ufcoreFlushBudgetMs == nil or type(g.ufcoreFlushBudgetMs) ~= "number" then
        g.ufcoreFlushBudgetMs = 2.0
    end
    if g.ufcoreUrgentMaxPerFlush == nil or type(g.ufcoreUrgentMaxPerFlush) ~= "number" then
        g.ufcoreUrgentMaxPerFlush = 10
    end
    if g.disableUnitInfoTooltips == nil then
        g.disableUnitInfoTooltips = true
    end
    if g.unitInfoTooltipStyle == nil then
        g.unitInfoTooltipStyle = "classic"
    end
    -- Tooltip custom position (set via Edit Mode drag).
    -- nil / false = use default style-based positioning (classic/modern).
    -- When set, these are BOTTOMLEFT-relative pixel coordinates on UIParent.
    -- Intentionally NOT defaulted: absence means "no custom position".
    if g.tooltipPosX ~= nil and type(g.tooltipPosX) ~= "number" then g.tooltipPosX = nil end
    if g.tooltipPosY ~= nil and type(g.tooltipPosY) ~= "number" then g.tooltipPosY = nil end
    if g.castbarInterruptibleColor == nil then
        g.castbarInterruptibleColor = "turquoise"
    end
    if g.castbarNonInterruptibleColor == nil then
        g.castbarNonInterruptibleColor = "red"
    end
    if g.castbarInterruptColor == nil then
        g.castbarInterruptColor = "red"
    end
    if g.playerCastbarOverrideEnabled == nil then
        g.playerCastbarOverrideEnabled = true
    end
    if g.playerCastbarOverrideMode == nil then
        g.playerCastbarOverrideMode = "CLASS" -- "CLASS" or "CUSTOM"
    end
    if g.playerCastbarOverrideR == nil then g.playerCastbarOverrideR = 1 end
    if g.playerCastbarOverrideG == nil then g.playerCastbarOverrideG = 1 end
    if g.playerCastbarOverrideB == nil then g.playerCastbarOverrideB = 1 end
    if g.castbarFillDirection == nil then
        g.castbarFillDirection = "RTL"
    end
if g.castbarUnifiedFillDirection ~= nil then
        if g.castbarUnifiedDirection == nil then
            g.castbarUnifiedDirection = (g.castbarUnifiedFillDirection == true)
        end
        g.castbarUnifiedFillDirection = nil
    end
    if g.castbarUnifiedDirection == nil then
        g.castbarUnifiedDirection = false
    end
    -- Channeled casts: show 5 tick lines (channel tick markers)
    if g.castbarShowChannelTicks == nil then
        g.castbarShowChannelTicks = false
    end
    -- Opposite fill-direction for enemy castbar
    if g.castbarOpositeDirectionTarget == nil then
        g.castbarOpositeDirectionTarget = false
    end
    -- GCD/Instant-cast bar (disabled by default; options treat nil as enabled)
    if g.showGCDBar == nil then g.showGCDBar = false end
    if g.showGCDBarTime == nil then g.showGCDBarTime = true end
    if g.showGCDBarSpell == nil then g.showGCDBarSpell = true end
    if g.empowerColorStages == nil then
        g.empowerColorStages = true
    end
    if g.empowerStageBlink == nil then
        g.empowerStageBlink = true
    end
    if g.empowerStageBlinkTime == nil or type(g.empowerStageBlinkTime) ~= "number" then
        g.empowerStageBlinkTime = 0.25
    end
    if g.enableTargetCastbar == nil then
        g.enableTargetCastbar = true
    end
    if g.enableFocusCastbar == nil then
        g.enableFocusCastbar = true
    end
    if g.enablePlayerCastbar == nil then
        g.enablePlayerCastbar = true
    end
    if g.enableBossCastbar == nil then
        g.enableBossCastbar = true
    end
if g.showPlayerCastTime == nil then
    g.showPlayerCastTime = true
end
if g.showTargetCastTime == nil then
    g.showTargetCastTime = true
end
if g.showFocusCastTime == nil then
    g.showFocusCastTime = true
end
if g.showBossCastTime == nil then
    g.showBossCastTime = true
end
if g.bossCastbarOffsetX == nil then
    g.bossCastbarOffsetX = 2
end
if g.bossCastbarOffsetY == nil then
    g.bossCastbarOffsetY = -46
end
if g.bossCastbarWidth == nil then
    g.bossCastbarWidth = 176
end
if g.bossCastbarHeight == nil then
    g.bossCastbarHeight = 12
end
    if g.castbarShowIcon == nil then
        g.castbarShowIcon = true
    end
    if g.castbarShowSpellName == nil then
        g.castbarShowSpellName = true
    end
    if g.castbarShakeStrength == nil then
        g.castbarShakeStrength = 8   -- pixels; 0 = no movement
    end
    if g.castbarSpellNameFontSize == nil then
        g.castbarSpellNameFontSize = 0
    end
    if g.castbarIconOffsetX == nil then
        g.castbarIconOffsetX = 0
    end
    if g.castbarIconOffsetY == nil then
        g.castbarIconOffsetY = 0
    end
    if g.castbarTargetOffsetX == nil then
        g.castbarTargetOffsetX = 0
    end
    if g.castbarTargetOffsetY == nil then
        g.castbarTargetOffsetY = -60
    end
    if g.castbarFocusOffsetX == nil then
        g.castbarFocusOffsetX = 2
    end
    if g.castbarFocusOffsetY == nil then
        g.castbarFocusOffsetY = -50
    end
    if g.castbarPlayerOffsetX == nil then
        g.castbarPlayerOffsetX = -2
    end
    if g.castbarPlayerOffsetY == nil then
        g.castbarPlayerOffsetY = -59
    end
    if g.castbarPlayerTimeOffsetX == nil then
        g.castbarPlayerTimeOffsetX = -2
    end
    if g.castbarPlayerTimeOffsetY == nil then
        g.castbarPlayerTimeOffsetY = 0
    end
    if g.castbarFocusTimeOffsetX == nil then
        g.castbarFocusTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarFocusTimeOffsetY == nil then
        g.castbarFocusTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    if g.castbarTargetTimeOffsetX == nil then
        g.castbarTargetTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarTargetTimeOffsetY == nil then
        g.castbarTargetTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    if g.castbarGlobalWidth == nil then
        g.castbarGlobalWidth = 200   -- Standardbreite
    end
    if g.castbarGlobalHeight == nil then
        g.castbarGlobalHeight = 18   -- Standardhöhe
    end
    -- Per-castbar default sizes (match Edit Mode preview defaults)
    if g.castbarPlayerBarWidth == nil then g.castbarPlayerBarWidth = 271 end
    if g.castbarPlayerBarHeight == nil then g.castbarPlayerBarHeight = 18 end
    if g.castbarTargetBarWidth == nil then g.castbarTargetBarWidth = 272 end
    if g.castbarTargetBarHeight == nil then g.castbarTargetBarHeight = 18 end
    if g.castbarFocusBarWidth == nil then g.castbarFocusBarWidth = 175 end
    if g.castbarFocusBarHeight == nil then g.castbarFocusBarHeight = 18 end
    if g.castbarPlayerPreviewEnabled == nil then
        g.castbarPlayerPreviewEnabled = true
    end
-- Legacy Auras 1.x DB cleanup (Patch 6D Step 2)
g.targetAuraFilter = nil
g.targetAuraWidth = nil
g.targetAuraHeight = nil
g.targetAuraScale = nil
g.targetAuraAlpha = nil
g.targetAuraOffsetX = nil
g.targetAuraOffsetY = nil
g.targetAuraDisplay = nil
if g.fontSize == nil then
        g.fontSize = 14
    end
    -- Per-text font sizes (0 means "use global" in some menus, but these are explicit defaults)
    if g.nameFontSize == nil then g.nameFontSize = 14 end
    if g.hpFontSize == nil then g.hpFontSize = 14 end
    if g.powerFontSize == nil then g.powerFontSize = 14 end
    if g.auraFontSize == nil then g.auraFontSize = 25 end
    if g.castbarBackgroundTexture == nil then
        g.castbarBackgroundTexture = "Solid"
    end
-- Textures (explicit defaults)
if g.castbarTexture == nil then
    g.castbarTexture = "Solid"
end
-- Castbar visuals
if g.castbarShowGlow == nil then
    g.castbarShowGlow = false
end
if g.castbarShowSpark == nil then
    g.castbarShowSpark = false
end
if g.castbarSparkOverflow == nil then
    g.castbarSparkOverflow = true
end
-- Player castbar width matching: nil = manual, "essential" = CDM essential row, "utility" = CDM utility bar
if g.castbarPlayerMatchWidth == nil then
    g.castbarPlayerMatchWidth = nil
end
-- Interrupt Ready Indicator
if g.kickReadyShowTarget == nil then g.kickReadyShowTarget = false end
if g.kickReadyShowFocus  == nil then g.kickReadyShowFocus  = false end
if g.kickReadyShowBoss   == nil then g.kickReadyShowBoss   = false end
if g.kickReadySize       == nil then g.kickReadySize       = 8 end
if g.kickReadyAnchor     == nil then g.kickReadyAnchor     = "RIGHT" end
if g.kickReadyOffsetX    == nil then g.kickReadyOffsetX    = 4 end
if g.kickReadyOffsetY    == nil then g.kickReadyOffsetY    = 0 end
if g.kickReadyColor      == nil then g.kickReadyColor      = { ["1"] = 0, ["2"] = 1, ["3"] = 0 } end
if g.kickNotReadyColor   == nil then g.kickNotReadyColor   = { ["1"] = 1, ["2"] = 0, ["3"] = 0 } end
-- Aura highlight colors (used by Auras 2.0 highlight pipeline)
if g.aurasOwnBuffHighlightColor == nil then
    g.aurasOwnBuffHighlightColor = { ["1"] = 1, ["2"] = 0.85, ["3"] = 0.2 }
end
if g.aurasOwnDebuffHighlightColor == nil then
    g.aurasOwnDebuffHighlightColor = { ["1"] = 1, ["2"] = 0.85, ["3"] = 0.2 }
end
if g.aurasStackCountColor == nil then
    g.aurasStackCountColor = { ["1"] = 1, ["2"] = 1, ["3"] = 1 }
end
    -- Per-castbar toggles + offsets
    if g.castbarTargetShowIcon == nil then g.castbarTargetShowIcon = true end
    if g.castbarFocusShowIcon == nil then g.castbarFocusShowIcon = true end
    if g.castbarPlayerShowIcon == nil then g.castbarPlayerShowIcon = true end
    if g.castbarTargetShowSpellName == nil then g.castbarTargetShowSpellName = true end
    if g.castbarFocusShowSpellName == nil then g.castbarFocusShowSpellName = true end
    if g.castbarPlayerShowSpellName == nil then g.castbarPlayerShowSpellName = true end
    if g.castbarTargetTextOffsetX == nil then g.castbarTargetTextOffsetX = 0 end
    if g.castbarTargetTextOffsetY == nil then g.castbarTargetTextOffsetY = 0 end
    if g.castbarFocusTextOffsetX == nil then g.castbarFocusTextOffsetX = 0 end
    if g.castbarFocusTextOffsetY == nil then g.castbarFocusTextOffsetY = 0 end
    if g.castbarPlayerTextOffsetX == nil then g.castbarPlayerTextOffsetX = 0 end
    if g.castbarPlayerTextOffsetY == nil then g.castbarPlayerTextOffsetY = 0 end
    if g.castbarTargetIconOffsetX == nil then g.castbarTargetIconOffsetX = 0 end
    if g.castbarTargetIconOffsetY == nil then g.castbarTargetIconOffsetY = 0 end
    if g.castbarFocusIconOffsetX == nil then g.castbarFocusIconOffsetX = 0 end
    if g.castbarFocusIconOffsetY == nil then g.castbarFocusIconOffsetY = 0 end
    if g.castbarPlayerIconOffsetX == nil then g.castbarPlayerIconOffsetX = 0 end
    if g.castbarPlayerIconOffsetY == nil then g.castbarPlayerIconOffsetY = 0 end
    -- Boss castbar UI bits (BossCastbars module reads these from general)
    if g.showBossCastIcon == nil then g.showBossCastIcon = true end
    if g.showBossCastName == nil then g.showBossCastName = true end
    if g.bossPreviewEnabled == nil then g.bossPreviewEnabled = true end
    if g.bossCastIconOffsetX == nil then g.bossCastIconOffsetX = 0 end
    if g.bossCastIconOffsetY == nil then g.bossCastIconOffsetY = 0 end
    if g.bossCastTextOffsetX == nil then g.bossCastTextOffsetX = 0 end
    if g.bossCastTextOffsetY == nil then g.bossCastTextOffsetY = 0 end
    if g.bossCastTimeOffsetX == nil then g.bossCastTimeOffsetX = 0 end
    if g.bossCastTimeOffsetY == nil then g.bossCastTimeOffsetY = 0 end
    -- Focus Kick Icon defaults
    if g.enableFocusKickIcon == nil then g.enableFocusKickIcon = false end
    if g.focusKickIconWidth == nil then g.focusKickIconWidth = 40 end
    if g.focusKickIconHeight == nil then g.focusKickIconHeight = 40 end
    if g.focusKickIconOffsetX == nil then g.focusKickIconOffsetX = 300 end
    if g.focusKickIconOffsetY == nil then g.focusKickIconOffsetY = 0 end
    if g.barTexture == nil then
        g.barTexture = "Solid"
    end
    if g.barBackgroundTexture == nil then
        g.barBackgroundTexture = "Solid"
    end
    -- Absorb bar texture overrides (optional; nil/"" = follow foreground texture)
    if g.absorbBarTexture ~= nil and type(g.absorbBarTexture) ~= "string" then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture ~= nil and type(g.healAbsorbBarTexture) ~= "string" then
        g.healAbsorbBarTexture = nil
    end
    if g.absorbBarTexture == "" then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture == "" then
        g.healAbsorbBarTexture = nil
    end
    -- Best-effort validation: if we can confidently resolve a statusbar key and it fails,
    -- fall back to nil ("follow foreground") so users don't get broken textures after removing SharedMedia packs.
    local function _MSUF_IsValidStatusbarKey(key)
        if type(key) ~= "string" or key == "" then  return false end
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
            local ok, tex = pcall(_G.MSUF_ResolveStatusbarTextureKey, key)
            if ok and type(tex) == "string" and tex ~= "" then
                 return true
            end
             return false
        end
        local LSM = (ns and ns.LSM) or _G.MSUF_LSM
        if LSM and type(LSM.Fetch) == "function" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", key, true)
            if ok and type(tex) == "string" and tex ~= "" then
                 return true
            end
             return false
        end
        -- Can't validate in this session (no resolver/LSM yet): keep the value to avoid unintended resets.
         return true
    end
    if g.absorbBarTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.absorbBarTexture) then
        g.absorbBarTexture = nil
    end
    if g.healAbsorbBarTexture ~= nil and not _MSUF_IsValidStatusbarKey(g.healAbsorbBarTexture) then
        g.healAbsorbBarTexture = nil
    end
    if g.hpTextMode == nil then
        g.hpTextMode = "FULL_PLUS_PERCENT"
    end
    if g.hpTextSeparator == nil then
        g.hpTextSeparator = "-"
    end
    if g.powerTextSeparator == nil then
        g.powerTextSeparator = g.hpTextSeparator
    end
    if g.hpTextSpacerEnabled == nil then
        g.hpTextSpacerEnabled = false
    end
    if g.hpTextSpacerX == nil then
        g.hpTextSpacerX = 140
    end
    -- Bar settings scope: always default to Shared so users edit globally first.
    if g.hpPowerTextSelectedKey == nil then
        g.hpPowerTextSelectedKey = "shared"
    end
    -- Portrait Decoration shared defaults (scope fallback for MSUF_Options_Portraits scope system)
    if g.portraitShape == nil then g.portraitShape = "SQUARE" end
    if g.portraitSizeOverride == nil then g.portraitSizeOverride = 0 end
    if g.portraitOffsetX == nil then g.portraitOffsetX = 0 end
    if g.portraitOffsetY == nil then g.portraitOffsetY = 0 end
    if g.portraitBorderStyle == nil then g.portraitBorderStyle = "NONE" end
    if g.portraitBorderThickness == nil then g.portraitBorderThickness = 2 end
    if g.portraitBorderColorR == nil then g.portraitBorderColorR = 1 end
    if g.portraitBorderColorG == nil then g.portraitBorderColorG = 1 end
    if g.portraitBorderColorB == nil then g.portraitBorderColorB = 1 end
    if g.portraitBorderColorA == nil then g.portraitBorderColorA = 1 end
    if g.portraitBgEnabled == nil then g.portraitBgEnabled = false end
    if g.portraitBgColorR == nil then g.portraitBgColorR = 0.05 end
    if g.portraitBgColorG == nil then g.portraitBgColorG = 0.05 end
    if g.portraitBgColorB == nil then g.portraitBgColorB = 0.05 end
    if g.portraitBgColorA == nil then g.portraitBgColorA = 0.85 end
    if g.portraitClassStyle == nil then g.portraitClassStyle = "BLIZZARD" end
    if g.portraitFillBorder == nil then g.portraitFillBorder = false end
    -- Portrait panel UI state (scope dropdown selection, shared render type)
    if g._portraitScopeKey == nil then g._portraitScopeKey = "shared" end
    -- Initialize _portraitSharedRender from player's actual render type (migration from old layout)
    if g._portraitSharedRender == nil then
        local pConf = MSUF_DB.player
        if pConf and pConf.portraitRender then
            g._portraitSharedRender = pConf.portraitRender
        else
            g._portraitSharedRender = "2D"
        end
    end
    -- Which unit's portrait settings are currently shown in the Portraits menu (UI state only).
    -- Moved from positional tabs to scope dropdown (Bars pattern).
    -- Which unit's HP spacer settings are currently shown/edited in the Bars menu.
    -- This is purely a UI selection state (does not change gameplay behavior).
    if g.hpSpacerSelectedUnitKey == nil then
        g.hpSpacerSelectedUnitKey = "player"
    end
    if g.hpSpacerSelectedUnitKey == "tot" then
        g.hpSpacerSelectedUnitKey = "targettarget"
    end
    -- HP spacer is now per-unit (Step 4). Keep legacy general.* values as fallback,
    -- but migrate them into per-unit fields once (without overwriting per-unit edits).
    local legacyHpSpacerEnabled = g.hpTextSpacerEnabled
    local legacyHpSpacerX = g.hpTextSpacerX
    for _, unitKey in ipairs({"player","target","focus","targettarget","pet","boss"}) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        local u = MSUF_DB[unitKey]
        if u.hpTextSpacerEnabled == nil and legacyHpSpacerEnabled ~= nil then
            u.hpTextSpacerEnabled = legacyHpSpacerEnabled
        end
        if u.hpTextSpacerX == nil and legacyHpSpacerX ~= nil then
            u.hpTextSpacerX = legacyHpSpacerX
        end
        if u.hpTextSpacerEnabled == nil then
            u.hpTextSpacerEnabled = false
        end
        if u.hpTextSpacerX == nil then
            u.hpTextSpacerX = 140
        end
    end
    -- Power text spacer (per-unit; matches HP spacer behavior)
    if g.powerTextSpacerEnabled == nil then
        g.powerTextSpacerEnabled = false
    end
    if g.powerTextSpacerX == nil then
        g.powerTextSpacerX = 140
    end
    do
        local legacyEnabled = g.powerTextSpacerEnabled
        local legacyX = g.powerTextSpacerX
        for _, unitKey in ipairs({"player","target","focus","targettarget","pet","boss"}) do
            local u = MSUF_DB[unitKey]
            if type(u) == "table" then
                if u.powerTextSpacerEnabled == nil and legacyEnabled ~= nil then
                    u.powerTextSpacerEnabled = legacyEnabled
                end
                if u.powerTextSpacerX == nil and legacyX ~= nil then
                    u.powerTextSpacerX = legacyX
                end
                if u.powerTextSpacerEnabled == nil then
                    u.powerTextSpacerEnabled = false
                end
                if u.powerTextSpacerX == nil then
                    u.powerTextSpacerX = 140
                end
            end
        end
    end

    -- Power text mode: migrate legacy modes to EQoL-style keys.
    local function _MSUF_MigratePowerMode(v)
        if v == nil then return nil end
        if v == "FULL_SLASH_MAX" then return "CURMAX" end
        if v == "FULL_ONLY" then return "CURRENT" end
        if v == "PERCENT_ONLY" then return "PERCENT" end
        if v == "FULL_PLUS_PERCENT" or v == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
        return v
    end

    g.powerTextMode = _MSUF_MigratePowerMode(g.powerTextMode)
    for _, unitKey in ipairs({"player","target","focus","targettarget","pet","boss"}) do
        local u = MSUF_DB[unitKey]
        if type(u) == "table" then
            u.powerTextMode = _MSUF_MigratePowerMode(u.powerTextMode)
        end
    end

    if g.powerTextMode == nil then
        g.powerTextMode = "CURPERCENT"
    end
    if g.showTotalAbsorbAmount == nil then
        g.showTotalAbsorbAmount = false
    end
    if g.enableAbsorbBar == nil then
        g.enableAbsorbBar = true
    end
    if g.showSelfHealPrediction == nil then
        g.showSelfHealPrediction = false
    end

    -- Absorb display dropdown stores a mode; keep runtime flags in sync on load.
    if g.absorbTextMode ~= nil then
        local mode = tonumber(g.absorbTextMode)
        if mode == 1 then
            g.enableAbsorbBar = false
            g.showTotalAbsorbAmount = false
        elseif mode == 2 then
            g.enableAbsorbBar = true
            g.showTotalAbsorbAmount = false
        elseif mode == 3 then
            g.enableAbsorbBar = true
            g.showTotalAbsorbAmount = true
        elseif mode == 4 then
            g.enableAbsorbBar = false
            g.showTotalAbsorbAmount = true
        end
    end
	    if g.absorbAnchorMode == nil then
	        -- 1 = Left Absorb, Right Heal-Absorb; 2 = Right Absorb, Left Heal-Absorb (default); 3 = Follow current HP edge (Blizzard-style)
        g.absorbAnchorMode = 2
    end

    -- v2 absorb-colour cleanup. Pre-v2 the picker in MSUF_ColorsCore wrote to
    -- absorbColor* / healAbsorbColor*, but every reader (UF, GF, Reset) used
    -- the absorbBarColor* / healAbsorbBarColor* keys — so the picker had no
    -- visible effect. The v1 patch tried to migrate by copying old → new,
    -- which surfaced picker-default white into now-live keys and made
    -- absorbs blend into the HP bar. v2 wipes both key sets once, so the
    -- defaults render again until the user explicitly picks a colour via
    -- the (now functional) picker. The marker keeps this idempotent and
    -- preserves any choices made AFTER the marker is set.
    if g.absorbBarColorMigrationV2 ~= true then
        g.absorbBarColorMigrationV2 = true
        g.absorbColorR,        g.absorbColorG,        g.absorbColorB,        g.absorbColorA        = nil, nil, nil, nil
        g.healAbsorbColorR,    g.healAbsorbColorG,    g.healAbsorbColorB,    g.healAbsorbColorA    = nil, nil, nil, nil
        g.absorbBarColorR,     g.absorbBarColorG,     g.absorbBarColorB,     g.absorbBarColorA     = nil, nil, nil, nil
        g.healAbsorbBarColorR, g.healAbsorbBarColorG, g.healAbsorbBarColorB, g.healAbsorbBarColorA = nil, nil, nil, nil
    end
    if g.showLeaderIcon == nil then
        g.showLeaderIcon = true
    end
    if g.leaderIconOffsetX == nil then
        g.leaderIconOffsetX = 0
    end
    if g.leaderIconOffsetY == nil then
        g.leaderIconOffsetY = 3
    end
    if g.leaderIconLayer == nil then
        g.leaderIconLayer = 7
    end
    -- Level indicator offset (global)
    if g.levelIndicatorOffsetX == nil then
        g.levelIndicatorOffsetX = 0
    end
    if g.levelIndicatorOffsetY == nil then
        g.levelIndicatorOffsetY = 0
    end
    if g.levelIndicatorAnchor == nil then
        g.levelIndicatorAnchor = 'NAMERIGHT'
    end
    if g.levelIndicatorLayer == nil then
        g.levelIndicatorLayer = 7
    end
    -- Misc -> Indicators
    if g.showIncomingResIndicator == nil then
        g.showIncomingResIndicator = true
    end
    if g.incomingResIndicatorPos == nil then
        g.incomingResIndicatorPos = 'TOPRIGHT'
    end
    if g.incomingResIndicatorLayer == nil then
        g.incomingResIndicatorLayer = 7
    end
    if g.showCombatStateIndicator == nil then
        g.showCombatStateIndicator = true
    end
    if g.combatStateIndicatorPos == nil then
        g.combatStateIndicatorPos = 'TOPLEFT'
    end
    if g.combatStateIndicatorLayer == nil then
        g.combatStateIndicatorLayer = 7
    end
    -- Status Icons (Summon / Resting)
    -- These are used by the Unitframe Status element (player/target) and can be overridden per-unit in the Frames menu.
    if g.showRestingIndicator == nil then
        g.showRestingIndicator = true
    end
	-- Rested icon defaults ("Moon Zzzz")
	-- Requirement: default size 30 and anchored TOPLEFT.
	-- Only apply when the profile does not already carry explicit values (no regression for users who moved it).
	if g.restedStateIndicatorSymbol == nil then
		g.restedStateIndicatorSymbol = "rested_moonzzz"
	end
	if g.restedStateIndicatorAnchor == nil then
		g.restedStateIndicatorAnchor = "TOPLEFT"
	end
	if g.restedStateIndicatorOffsetX == nil or type(g.restedStateIndicatorOffsetX) ~= "number" then
		g.restedStateIndicatorOffsetX = 0
	end
	if g.restedStateIndicatorOffsetY == nil or type(g.restedStateIndicatorOffsetY) ~= "number" then
		g.restedStateIndicatorOffsetY = 0
	end
	if g.restedStateIndicatorSize == nil or type(g.restedStateIndicatorSize) ~= "number" or g.restedStateIndicatorSize <= 0 then
		g.restedStateIndicatorSize = 30
	end
    if g.restedStateIndicatorLayer == nil then
        g.restedStateIndicatorLayer = 7
    end
    if g.stateIconsTestMode == nil then
        g.stateIconsTestMode = false
    end
    -- Player indicators (Frames -> Player)
    if g.showLevel == nil then
        g.showLevel = true
    end
    if g.showRaidMarker == nil then
        g.showRaidMarker = true
    end
    local legacyShowRaidMarker = g.showRaidMarker
    for _, key in ipairs({"player","target","focus","targettarget","pet","boss"}) do
        MSUF_DB[key] = MSUF_DB[key] or {}
        if MSUF_DB[key].showRaidMarker == nil and legacyShowRaidMarker ~= nil then
            MSUF_DB[key].showRaidMarker = legacyShowRaidMarker
        end
        if MSUF_DB[key].showRaidMarker == nil then
            MSUF_DB[key].showRaidMarker = true
        end
end
local legacyRaidMarkerOffsetX = g.raidMarkerOffsetX
local legacyRaidMarkerOffsetY = g.raidMarkerOffsetY
local legacyRaidMarkerAnchor  = g.raidMarkerAnchor
local legacyRaidMarkerSize    = g.raidMarkerSize
for _, key in ipairs({"player","target","focus","targettarget","pet","boss"}) do
    MSUF_DB[key] = MSUF_DB[key] or {}
    local conf = MSUF_DB[key]
    if conf.raidMarkerOffsetX == nil and legacyRaidMarkerOffsetX ~= nil then
        conf.raidMarkerOffsetX = legacyRaidMarkerOffsetX
    end
    if conf.raidMarkerOffsetY == nil and legacyRaidMarkerOffsetY ~= nil then
        conf.raidMarkerOffsetY = legacyRaidMarkerOffsetY
    end
    if conf.raidMarkerAnchor == nil and legacyRaidMarkerAnchor ~= nil then
        conf.raidMarkerAnchor = legacyRaidMarkerAnchor
    end
    if conf.raidMarkerSize == nil and legacyRaidMarkerSize ~= nil then
        conf.raidMarkerSize = legacyRaidMarkerSize
    end
    if conf.raidMarkerOffsetX == nil then
        if key == "player" then
            conf.raidMarkerOffsetX = 21
        elseif key == "target" then
            conf.raidMarkerOffsetX = -15
        else
            conf.raidMarkerOffsetX = 16
        end
    end
    if conf.raidMarkerOffsetY == nil then conf.raidMarkerOffsetY = 3 end
    if conf.raidMarkerAnchor == nil then
        if key == "target" then
            conf.raidMarkerAnchor = "TOPRIGHT"
        else
            conf.raidMarkerAnchor = "TOPLEFT"
        end
    end
    if conf.raidMarkerSize == nil then conf.raidMarkerSize = 14 end
    if conf.raidMarkerLayer == nil then conf.raidMarkerLayer = 7 end
end
-- Elite / Rare icon defaults (per-unit)
for _, key in ipairs({"target","focus","targettarget","boss"}) do
    MSUF_DB[key] = MSUF_DB[key] or {}
    local u = MSUF_DB[key]
    if u.showEliteIcon    == nil then u.showEliteIcon    = true       end
    if u.eliteIconSize    == nil then u.eliteIconSize    = 20         end
    if u.eliteIconAnchor  == nil then u.eliteIconAnchor  = "TOPRIGHT" end
    if u.eliteIconOffsetX == nil then u.eliteIconOffsetX = 2          end
    if u.eliteIconOffsetY == nil then u.eliteIconOffsetY = 2          end
    if u.eliteIconLayer   == nil then u.eliteIconLayer   = 7          end
end
if MSUF_DB.bars == nil then
        MSUF_DB.bars = {}
    end
    if MSUF_DB.bars.showTargetPowerBar == nil then
        MSUF_DB.bars.showTargetPowerBar = true
    end
        if MSUF_DB.bars.showBossPowerBar == nil then
        MSUF_DB.bars.showBossPowerBar = true
    end
    if MSUF_DB.bars.showFocusPowerBar == nil then
        MSUF_DB.bars.showFocusPowerBar = true
    end
    if MSUF_DB.bars.showPlayerPowerBar == nil then
        MSUF_DB.bars.showPlayerPowerBar = true
    end
    if MSUF_DB.bars.showBarBorder == nil then
        MSUF_DB.bars.showBarBorder = true
    end
    if MSUF_DB.bars.powerBarHeight == nil then
        MSUF_DB.bars.powerBarHeight = 3
    end
    if MSUF_DB.bars.smoothPowerBar == nil then
        MSUF_DB.bars.smoothPowerBar = true
    end
    if MSUF_DB.bars.realtimePowerText == nil then
        MSUF_DB.bars.realtimePowerText = true
    end
    if MSUF_DB.bars.embedPowerBarIntoHealth == nil then
        -- Pixel-perfect default: keep the power bar *inside* the unitframe bounds.
        -- This prevents the power bar from extending below the frame and breaking
        -- pixel-accurate layouts when toggling power bars on.
        -- Users who want the legacy behavior can disable this in Bars.
        MSUF_DB.bars.embedPowerBarIntoHealth = true
    end
if MSUF_DB.bars.barOutlineThickness == nil then
    -- New slider-based bar outline. Backwards compatible default:
    -- - If legacy border is off -> 0
    -- - Else map legacy style to a sensible thickness
    local enabled = true
    if MSUF_DB.general and MSUF_DB.general.useBarBorder == false then
        enabled = false
    end
    if MSUF_DB.bars.showBarBorder ~= nil then
        enabled = (MSUF_DB.bars.showBarBorder ~= false)
    end
    if not enabled then
        MSUF_DB.bars.barOutlineThickness = 0
    else
        local style = (MSUF_DB.general and MSUF_DB.general.barBorderStyle) or "THIN"
        local map = { THIN = 2, THICK = 3, SHADOW = 4, GLOW = 4 }
        MSUF_DB.bars.barOutlineThickness = map[style] or 2
    end
end
-- Bar background alpha (0..100). Independent from unit alpha in/out of combat.
if MSUF_DB.bars.barBackgroundAlpha == nil then
    MSUF_DB.bars.barBackgroundAlpha = 90
end
    -- Gameplay defaults (module-safe: some modules expect MSUF_DB.gameplay to exist)
    if MSUF_DB.gameplay == nil then
        MSUF_DB.gameplay = {}
    end
    local gp = MSUF_DB.gameplay
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
    if gp.enableFirstDanceTimer == nil then gp.enableFirstDanceTimer = false end
    if gp.nameplateMeleeSpellID == nil then gp.nameplateMeleeSpellID = 0 end
    -- Gameplay: Range fade for Target/Focus (default ON)
    -- Dims Target/Focus unitframes to a fixed alpha when the unit is out of range.
-- Gameplay: Crosshair melee range spell can optionally be stored per class.
    -- This lets users run a single profile across multiple characters without
    -- having to swap the spell whenever they change class.
    if gp.meleeSpellPerClass == nil then gp.meleeSpellPerClass = false end
    if gp.meleeSpellPerSpec == nil then gp.meleeSpellPerSpec = false end
    if gp.nameplateMeleeSpellIDByClass == nil then gp.nameplateMeleeSpellIDByClass = {} end
    if gp.nameplateMeleeSpellIDBySpec == nil then gp.nameplateMeleeSpellIDBySpec = {} end
    -- Auras: legacy auras DB removed in Patch 6D Step 2 (Auras 2.0 uses MSUF_DB.auras2)
    if MSUF_DB.auras ~= nil then MSUF_DB.auras = nil end
-- Root toggle: Shorten unit names (Frames -> General)
if MSUF_DB.shortenNames == nil then
    MSUF_DB.shortenNames = false
end
-- Auras 2.0 defaults (new installs / reset profile)
    if MSUF_DB.auras2 == nil then
        MSUF_DB.auras2 = {
            enabled = true,
            showTarget = true,
            showFocus = true,
            showBoss = true,
            bossHealAuras = {
                highlightOwn = false,
                hideOthers = false,
            },
            shared = {
                _msufA2_migrated_v11f = true,
                bossEditTogether = true,
                buffOffsetY = 30,
                cooldownTextSize = 14,
                iconSize = 26,
                offsetX = 0,
                offsetY = 6,
                spacing = 2,
                stackTextSize = 14,
                growth = "RIGHT",
                layoutMode = "SINGLE",
                perRow = 11,
                maxIcons = 12,
                maxBuffs = 8,
                maxDebuffs = 15,
                showBuffs = true,
                showDebuffs = true,
                showCooldownSwipe = true,
                showStackCount = true,
                showTooltip = true,
                showInEditMode = true,
                stackCountAnchor = "TOPRIGHT",
                hidePermanent = false,
                onlyMyBuffs = false,
                onlyMyDebuffs = false,
                masqueEnabled = false,
                pandemicMode = "OFF",
                pandemicR = 0.0, pandemicG = 0.4, pandemicB = 1.0,
highlightOwnBuffs = false,
                highlightOwnDebuffs = false,
filters = {
                    _msufA2_sharedFiltersMigrated_v1 = true,
                    enabled = true,
                    hidePermanent = false,
                    onlyBossAuras = false,
                    onlyImportantAuras = false,
                    buffs = {
                        includeBoss = false,
                        includeStealable = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                    debuffs = {
                        dispelCurse = false,
                        dispelDisease = false,
                        dispelEnrage = false,
                        dispelMagic = false,
                        dispelPoison = false,
                        includeBoss = false,
                        includeDispellable = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                },
            },
            perUnit = {
                target = {
                    overrideLayout = true,
                    overrideFilters = false,
                    layout = {
                        cooldownTextSize = 14,
                        iconSize = 26,
                        offsetX = -1,
                        offsetY = 0,
                        spacing = 2,
                        stackTextSize = 14,
                    },
                    filters = {
                        _msufA2_filtersMigrated_v2 = true,
                        enabled = true,
                        hidePermanent = false,
                        onlyBossAuras = false,
                        onlyImportantAuras = false,
                        buffs = {
                            includeBoss = false,
                            includeStealable = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                        debuffs = {
                            dispelCurse = false,
                            dispelDisease = false,
                            dispelEnrage = false,
                            dispelMagic = false,
                            dispelPoison = false,
                            includeBoss = false,
                            includeDispellable = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                    },
                },
                focus = {
                    overrideLayout = true,
                    overrideFilters = false,
                    layout = {
                        cooldownTextSize = 14,
                        iconSize = 26,
                        offsetX = 0,
                        offsetY = -1,
                        spacing = 2,
                        stackTextSize = 14,
                    },
                    filters = {
                        _msufA2_filtersMigrated_v2 = true,
                        enabled = true,
                        hidePermanent = false,
                        onlyBossAuras = false,
                        onlyImportantAuras = false,
                        buffs = {
                            includeBoss = false,
                            includeStealable = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                        debuffs = {
                            dispelCurse = false,
                            dispelDisease = false,
                            dispelEnrage = false,
                            dispelMagic = false,
                            dispelPoison = false,
                            includeBoss = false,
                            includeDispellable = false,
                            onlyMine = false,
                            onlyImportant = false,
                        },
                    },
                },
            },
        }
        -- Boss per-unit defaults (1-5)
        for i = 1, 5 do
            local key = "boss" .. i
            MSUF_DB.auras2.perUnit[key] = {
                overrideLayout = true,
                overrideFilters = false,
                layout = {
                    cooldownTextSize = 14,
                    iconSize = 26,
                    offsetX = 0,
                    offsetY = 0,
                    spacing = 2,
                    stackTextSize = 14,
                },
                filters = {
                    _msufA2_filtersMigrated_v2 = true,
                    enabled = true,
                    hidePermanent = false,
                    onlyBossAuras = false,
                    onlyImportantAuras = false,
                    buffs = {
                        includeBoss = false,
                        includeStealable = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                    debuffs = {
                        dispelCurse = false,
                        dispelDisease = false,
                        dispelEnrage = false,
                        dispelMagic = false,
                        dispelPoison = false,
                        includeBoss = false,
                        includeDispellable = false,
                        onlyMine = false,
                        onlyImportant = false,
                    },
                },
            }
        end
    end
    -- Auras 2.0: ensure curated IMPORTANT filter keys exist for existing profiles
    -- IMPORTANT = Blizzard curated "important" aura list for unitframe aura APIs.
    -- Split toggles: Buffs + Debuffs have their own IMPORTANT toggle (like Unhalted).
    if MSUF_DB and MSUF_DB.auras2 then
        local a2 = MSUF_DB.auras2
        if type(a2.bossHealAuras) ~= "table" then a2.bossHealAuras = {} end
        if a2.bossHealAuras.highlightOwn == nil then a2.bossHealAuras.highlightOwn = false end
        if a2.bossHealAuras.hideOthers == nil then a2.bossHealAuras.hideOthers = false end

        local function EnsureImportantSplit(f)
            if not f then return end
            f.buffs = (type(f.buffs) == "table") and f.buffs or {}
            f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
            local b, d = f.buffs, f.debuffs

            -- One-time migration: legacy onlyImportantAuras -> per-type toggles
            if f._msufA2_onlyImportantSplitMigrated_v1 ~= true then
                if f.onlyImportantAuras == true then
                    if b.onlyImportant == nil then b.onlyImportant = true end
                    if d.onlyImportant == nil then d.onlyImportant = true end
                    f.onlyImportantAuras = false
                end
                f._msufA2_onlyImportantSplitMigrated_v1 = true
            end

            if f.onlyImportantAuras == nil then f.onlyImportantAuras = false end
            if b.onlyImportant == nil then b.onlyImportant = false end
            if d.onlyImportant == nil then d.onlyImportant = false end
        end

        if a2.shared and a2.shared.filters then
            EnsureImportantSplit(a2.shared.filters)
        end
        if a2.perUnit then
            for _, pu in pairs(a2.perUnit) do
                if pu and pu.filters then
                    EnsureImportantSplit(pu.filters)
                end
            end
        end
    end

local function fill(key, defaults)
        MSUF_DB[key] = MSUF_DB[key] or {}
        local t = MSUF_DB[key]
        for k, v in pairs(defaults) do
            if t[k] == nil then
                t[k] = v
            end
        end
     end
    local textDefaults = {
        nameOffsetX   = 4,
        nameOffsetY   = -4,
        hpOffsetX     = -4,
        hpOffsetY     = -4,
        powerOffsetX  = -4,
        powerOffsetY  = 4,
    }
    fill("player", {
        width     = 275,
        height    = 40,
        offsetX   = -256,
        offsetY   = -180,
        portraitMode = "LEFT",
        portraitClassStyle = "BLIZZARD",
        showName  = false,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        showInterrupt = true,
        -- Per-unitframe: reverse fill direction for HP + Power bars.
        -- (false = normal left->right fill)
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.player[k] == nil then MSUF_DB.player[k] = v end
    end
    -- Player castbar: custom channel tick markers (PLAYER ONLY)
    -- Stored under MSUF_DB.player.castbar.* so it does not touch general castbar settings.
    MSUF_DB.player.castbar = MSUF_DB.player.castbar or {}
    do
        local pc = MSUF_DB.player.castbar
        if pc.channelTickUseCustom == nil then pc.channelTickUseCustom = false end
        if type(pc.channelTickCount) ~= "number" then pc.channelTickCount = 5 end
        if type(pc.channelTickPreviewDuration) ~= "number" then pc.channelTickPreviewDuration = 2.5 end
        if pc.channelTickPreviewLoop == nil then pc.channelTickPreviewLoop = true end
        if type(pc.channelTickPosPct) ~= "table" then pc.channelTickPosPct = {} end
    end
    fill("target", {
        width     = 275,
        height    = 40,
        offsetX   = 320,
        offsetY   = -180,
        portraitMode = "RIGHT",
        portraitClassStyle = "BLIZZARD",
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        showInterrupt = true,
        -- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.target[k] == nil then MSUF_DB.target[k] = v end
    end
    fill("focus", {
        width     = 180,
        height    = 30,
        offsetX   = -260,
        offsetY   = -300,
        portraitMode = "OFF",
        portraitClassStyle = "BLIZZARD",
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = false,
        showInterrupt = true,
        -- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
        -- Focus-only: optional relative anchor for positioning.
        -- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        -- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.focus[k] == nil then MSUF_DB.focus[k] = v end
    end
    fill("targettarget", {
        width     = 180,
        height    = 30,
        offsetX   = 220,
        offsetY   = -300,
        showName  = false,
        showLevelIndicator = true,
        showHP    = true,
        showPower = false,
        -- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    if MSUF_DB.targettarget.showToTInTargetName == nil then MSUF_DB.targettarget.showToTInTargetName = false end
    -- Target-of-Target inline-in-Target separator token (rendered with spaces around it).
    -- Keep the default as the legacy behavior (" | ") by storing the token "|".
    if MSUF_DB.targettarget.totInlineSeparator == nil then MSUF_DB.targettarget.totInlineSeparator = "|" end
    for k, v in pairs(textDefaults) do
        if MSUF_DB.targettarget[k] == nil then MSUF_DB.targettarget[k] = v end
    end
    fill("pet", {
        width     = 220,
        height    = 30,
        offsetX   = -275,
        offsetY   = -250,
        -- Pet-only: optional relative anchor for positioning.
        -- "GLOBAL" keeps the classic behavior (anchored to the MSUF global anchor).
        -- Other supported values: "player", "target".
        anchorToUnitframe = "GLOBAL",
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        -- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.pet[k] == nil then MSUF_DB.pet[k] = v end
    end
    fill("boss", {
        width        = 180,
        height       = 30,
        offsetX      = 507,
        offsetY      = 309,
        spacing      = -96,
        -- Layout mode: "VERTICAL_DOWN" | "VERTICAL_UP" | "HORIZONTAL_RIGHT" | "HORIZONTAL_LEFT"
        -- Kept invertBossOrder for one-shot migration (see below).
        bossLayoutMode = "VERTICAL_DOWN",
        invertBossOrder = false,
        showName     = true,
        showLevelIndicator = false,
        showHP       = true,
        showPower    = false,
        showInterrupt = true,
        portraitMode = "OFF",
        -- Per-unitframe: reverse fill direction for HP + Power bars.
        reverseFillBars = false,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.boss[k] == nil then MSUF_DB.boss[k] = v end
    end
    -- One-shot migration: old invertBossOrder checkbox → new bossLayoutMode dropdown.
    -- Runs once on first login with v4.0 Beta 5+; converts legacy saved setting.
    if MSUF_DB.boss._bossLayoutMigrated ~= true then
        if MSUF_DB.boss.invertBossOrder == true then
            MSUF_DB.boss.bossLayoutMode = "VERTICAL_UP"
        end
        MSUF_DB.boss._bossLayoutMigrated = true
    end
    -- Range fade: also fade castbar / auras when boss is out of range (off by default).
    if MSUF_DB.boss.rangeFadeCastbar == nil then MSUF_DB.boss.rangeFadeCastbar = false end
    if MSUF_DB.boss.rangeFadeAuras   == nil then MSUF_DB.boss.rangeFadeAuras   = false end
    do
        local bars = MSUF_DB.bars or {}
        local showKeys = {
            player = "showPlayerPowerBar",
            target = "showTargetPowerBar",
            focus  = "showFocusPowerBar",
            boss   = "showBossPowerBar",
        }
        for _, unitKey in ipairs({"player", "target", "focus", "boss"}) do
            MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
            local u = MSUF_DB[unitKey]
            local legacyShowKey = showKeys[unitKey]
            if u.showPowerBar == nil then
                local legacyShow = legacyShowKey and bars[legacyShowKey]
                u.showPowerBar = (legacyShow ~= false)
            end
            if u.powerBarHeight == nil then
                u.powerBarHeight = tonumber(bars.powerBarHeight) or 3
            end
            if u.embedPowerBarIntoHealth == nil then
                u.embedPowerBarIntoHealth = (bars.embedPowerBarIntoHealth == true)
            end
            if u.powerBarBorderEnabled == nil then
                u.powerBarBorderEnabled = (bars.powerBarBorderEnabled == true)
            end
            if u.powerBarBorderThickness == nil then
                u.powerBarBorderThickness = tonumber(bars.powerBarBorderThickness or bars.powerBarBorderSize) or 1
            end
            if u.powerSmoothFill == nil then
                u.powerSmoothFill = (unitKey == "player") and (bars.smoothPowerBar ~= false) or false
            end
        end
    end
    for _, unitKey in ipairs({"player", "target", "targettarget", "focus", "pet", "boss"}) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        local u = MSUF_DB[unitKey]
        if u.enabled == nil then
            u.enabled = true
        end
        -- Per-unitframe: smooth health fill animation (matches Group Frames default).
        if u.smoothFill == nil then
            u.smoothFill = true
        end
        -- Default missing alpha keys to 1 (100%) without overwriting user customizations.
        if u.alphaInCombat == nil then u.alphaInCombat = 1 end
        if u.alphaOutOfCombat == nil then u.alphaOutOfCombat = 1 end
        if u.alphaFGInCombat == nil then u.alphaFGInCombat = 1 end
        if u.alphaFGOutOfCombat == nil then u.alphaFGOutOfCombat = 1 end
        if u.alphaBGInCombat == nil then u.alphaBGInCombat = 1 end
        if u.alphaBGOutOfCombat == nil then u.alphaBGOutOfCombat = 1 end
        if u.alphaHPInCombat == nil then u.alphaHPInCombat = 1 end
        if u.alphaHPOutOfCombat == nil then u.alphaHPOutOfCombat = 1 end
        if u.alphaPreserveHPColor == nil then u.alphaPreserveHPColor = false end
        -- Portrait Decoration defaults (MSUF_PortraitDecoration.lua)
        -- portraitRender: inherit from general._portraitSharedRender if not set (shared/per-unit sync)
        if u.portraitRender == nil then
            u.portraitRender = g._portraitSharedRender or "2D"
        end
        if u.portraitClassStyle == nil then
            u.portraitClassStyle = g.portraitClassStyle or "BLIZZARD"
        end
        if u.portraitShape == nil then u.portraitShape = (g.portraitShape) or "SQUARE" end
        if u.portraitSizeOverride == nil then u.portraitSizeOverride = (g.portraitSizeOverride) or 0 end
        if u.portraitOffsetX == nil then u.portraitOffsetX = (g.portraitOffsetX) or 0 end
        if u.portraitOffsetY == nil then u.portraitOffsetY = (g.portraitOffsetY) or 0 end
        if u.portraitBorderStyle == nil then u.portraitBorderStyle = (g.portraitBorderStyle) or "NONE" end
        if u.portraitBorderThickness == nil then u.portraitBorderThickness = (g.portraitBorderThickness) or 2 end
        if u.portraitBorderColorR == nil then u.portraitBorderColorR = (g.portraitBorderColorR) or 1 end
        if u.portraitBorderColorG == nil then u.portraitBorderColorG = (g.portraitBorderColorG) or 1 end
        if u.portraitBorderColorB == nil then u.portraitBorderColorB = (g.portraitBorderColorB) or 1 end
        if u.portraitBorderColorA == nil then u.portraitBorderColorA = (g.portraitBorderColorA) or 1 end
        if u.portraitBgEnabled == nil then u.portraitBgEnabled = g.portraitBgEnabled or false end
        if u.portraitBgColorR == nil then u.portraitBgColorR = (g.portraitBgColorR) or 0.05 end
        if u.portraitBgColorG == nil then u.portraitBgColorG = (g.portraitBgColorG) or 0.05 end
        if u.portraitBgColorB == nil then u.portraitBgColorB = (g.portraitBgColorB) or 0.05 end
        if u.portraitBgColorA == nil then u.portraitBgColorA = (g.portraitBgColorA) or 0.85 end
        if u.portraitFillBorder == nil then u.portraitFillBorder = g.portraitFillBorder or false end
    end
    MSUF_DB_LastHeavyRun = MSUF_DB
 end
function EnsureDB()
    if MSUF_DB and MSUF_DB_LastHeavyRun == MSUF_DB then
         return
    end
    MSUF_EnsureDB_Heavy()
 end
-- Optional exports for other modules
ns.MSUF_EnsureDB_Heavy = MSUF_EnsureDB_Heavy
ns.EnsureDB = EnsureDB
