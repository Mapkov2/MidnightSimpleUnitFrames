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
    local function ForceFreshGroupAuraBlizzardRenderer(conf)
        if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
        local auras = conf.auras
        auras.renderer = "BLIZZARD"
        if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
        local types = auras.blizzardTypes
        if types.buffs == nil then types.buffs = true end
        if types.debuffs == nil then types.debuffs = true end
        if types.dispels == nil then types.dispels = true end
        if types.externals == nil then types.externals = true end
        if types.privateAuras == nil then types.privateAuras = true end
        if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
        if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
        if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
        if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
        auras.blizzardContainerAnchor = "FRAME"
        auras.blizzardContainerX = 0
        auras.blizzardContainerY = 0
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
    ForceFreshGroupAuraBlizzardRenderer(db.gf_party)
    ForceFreshGroupAuraBlizzardRenderer(db.gf_raid)
    ForceFreshGroupAuraBlizzardRenderer(db.gf_mythicraid)
    db.bars = db.bars or {}
    db.bars.showAltMana = false
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
        g.fontKey = "FRIZQT"
    end
 end
local function MSUF_Defaults_CreateFactoryProfile()
    local tbl = MSUF_Defaults_TryDecodeCompactString(MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    if not tbl then  return nil end
    local payload = MSUF_Defaults_GetProfilePayload(tbl)
    if type(payload) ~= "table" then  return nil end

    local out = {}
    MSUF_Defaults_DeepCopy(out, payload)
    MSUF_Defaults_ApplyFreshInstallOverrides(out)
    out.general = out.general or {}
    out.general._msufFactoryProfileApplied = true
    return out
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
    local payload = MSUF_Defaults_CreateFactoryProfile()
    if type(payload) ~= "table" then  return end
    -- Replace the empty DB with the decoded payload.
    MSUF_Defaults_DeepCopy(MSUF_DB, payload)
 end
local MSUF_DB_LastHeavyRun
local MSUF_DEFAULTS_FONT_KEY_ALIASES = {
    ["Friz Quadrata TT"]        = "FRIZQT",
    ["Arial Narrow"]            = "ARIALN",
    ["Morpheus"]                = "MORPHEUS",
    ["Skurri"]                  = "SKURRI",
    ["Friz Quadrata (default)"] = "FRIZQT",
    ["Arial (default)"]         = "ARIALN",
    ["Morpheus (default)"]      = "MORPHEUS",
    ["Skurri (default)"]        = "SKURRI",
}

local function MSUF_Defaults_NormalizeFontKey(key)
    if type(key) ~= "string" or key == "" then return key end
    return MSUF_DEFAULTS_FONT_KEY_ALIASES[key] or key
end

local function MSUF_Defaults_NormalizeFontField(tbl)
    if type(tbl) ~= "table" then return end
    local normalized = MSUF_Defaults_NormalizeFontKey(tbl.fontKey)
    if normalized ~= tbl.fontKey then
        tbl.fontKey = normalized
    end
end

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
        g.fontKey = MSUF_Defaults_NormalizeFontKey("FRIZQT")
    else
        MSUF_Defaults_NormalizeFontField(g)
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
-- Unit castbar width matching:
-- nil/"manual" = manual, "unitframe" = own MSUF unitframe,
-- "essential" = CDM essential row, "utility" = CDM utility bar.
local function NormalizeCastbarWidthSourceKey(key, legacyUnitWidthKey, aliasKey)
    if aliasKey and g[key] == nil and g[aliasKey] ~= nil then
        g[key] = g[aliasKey]
    end
    if g[key] == nil and legacyUnitWidthKey and g[legacyUnitWidthKey] == true then
        g[key] = "unitframe"
    end
    if g[key] == "manual" then
        g[key] = nil
    elseif g[key] ~= nil
        and g[key] ~= "unitframe"
        and g[key] ~= "essential"
        and g[key] ~= "utility"
    then
        g[key] = nil
    end
end
NormalizeCastbarWidthSourceKey("castbarPlayerMatchWidth", "castbarPlayerMatchUnitWidth")
NormalizeCastbarWidthSourceKey("castbarTargetMatchWidth", "castbarTargetMatchUnitWidth")
NormalizeCastbarWidthSourceKey("castbarFocusMatchWidth", "castbarFocusMatchUnitWidth")
NormalizeCastbarWidthSourceKey("bossCastbarMatchWidth", "castbarBossMatchUnitWidth", "castbarBossMatchWidth")
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
    if MSUF_DB.bars.classPowerComboPointColorMode == nil then
        MSUF_DB.bars.classPowerComboPointColorMode = "default"
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
    for _, key in ipairs({
        "general",
        "player", "target", "targettarget", "focus", "pet", "boss",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        MSUF_Defaults_NormalizeFontField(MSUF_DB[key])
    end
    if g._msufUFLocalFontKeyMigration_v407 ~= true then
        for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss" }) do
            local u = MSUF_DB[key]
            if type(u) == "table" then
                u.fontKey = nil
            end
        end
        g._msufUFLocalFontKeyMigration_v407 = true
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
ns.MSUF_CreateFactoryDefaultProfile = MSUF_Defaults_CreateFactoryProfile
ns.MSUF_EnsureDB_Heavy = MSUF_EnsureDB_Heavy
ns.EnsureDB = EnsureDB
_G.MSUF_CreateFactoryDefaultProfile = MSUF_Defaults_CreateFactoryProfile
