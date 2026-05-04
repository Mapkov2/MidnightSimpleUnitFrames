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
    local function EnsureUnitAlphaDefaults(conf)
        if not conf then  return end
        if conf.alphaInCombat == nil then conf.alphaInCombat = 1 end
        if conf.alphaOutOfCombat == nil then conf.alphaOutOfCombat = 1 end
        if conf.alphaSync == nil then conf.alphaSync = false end
        if conf.alphaExcludeTextPortrait == nil then conf.alphaExcludeTextPortrait = false end
        if conf.alphaLayerMode == nil then conf.alphaLayerMode = 0 end
        if conf.alphaFGInCombat == nil then conf.alphaFGInCombat = 1 end
        if conf.alphaFGOutOfCombat == nil then conf.alphaFGOutOfCombat = 1 end
        if conf.alphaBGInCombat == nil then conf.alphaBGInCombat = 1 end
        if conf.alphaBGOutOfCombat == nil then conf.alphaBGOutOfCombat = 1 end
        if conf.alphaHPInCombat == nil then conf.alphaHPInCombat = 1 end
        if conf.alphaHPOutOfCombat == nil then conf.alphaHPOutOfCombat = 1 end
        if conf.alphaPreserveHPColor == nil then conf.alphaPreserveHPColor = false end
     end
    EnsureUnitAlphaDefaults(db.player)
    -- Fresh-install default: player name hidden
    if type(db.player) == "table" then
        db.player.showName = false
    end
    EnsureUnitAlphaDefaults(db.target)
    EnsureUnitAlphaDefaults(db.focus)
    EnsureUnitAlphaDefaults(db.pet)
    EnsureUnitAlphaDefaults(db.boss)
    EnsureUnitAlphaDefaults(db.targettarget)
    EnsureUnitAlphaDefaults(db.tot)
    -- Fresh-install defaults: status indicators (AFK/DND) off by default
    local g = db.general
    if type(g) == 'table' then
        g.statusIndicators = g.statusIndicators or {}
        local si = g.statusIndicators
        si.showAFK = false
        si.showDND = false

        -- Fresh-install scaling defaults:
        -- Always start in Auto (Blizzard decides the global UI scale), with MSUF scaling disabled.
        g.disableScaling = true
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
-- Default: Auto global UI scale (Blizzard handles it), with MSUF scaling disabled.
if g.disableScaling == nil then
    g.disableScaling = true
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
        if u.alphaSync == nil then u.alphaSync = false end
        if u.alphaExcludeTextPortrait == nil then u.alphaExcludeTextPortrait = false end
        if u.alphaLayerMode == nil then u.alphaLayerMode = 0 end
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
