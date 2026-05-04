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
    local payload = tbl.payload
    if not payload then  return end
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
