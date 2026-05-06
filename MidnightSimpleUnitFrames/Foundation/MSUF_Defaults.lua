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
        if auras.blizzardContainerAnchor == nil then auras.blizzardContainerAnchor = "FRAME" end
        if auras.blizzardContainerX == nil then auras.blizzardContainerX = 0 end
        if auras.blizzardContainerY == nil then auras.blizzardContainerY = 0 end
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
