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

local function MSUF_Defaults_NormalizePortraitRenderValue(v)
    if v == "CLASS" then return "CLASS" end
    return "2D"
end

local function MSUF_Defaults_NormalizePortraitClassStyleValue(v)
    if v == "class_colored_border" or v == "colored" then return "RONDO_COLOR" end
    if v == "wow_icon_border" or v == "wow" then return "RONDO_WOW" end
    if v == "RONDO_COLOR" or v == "RONDO_WOW" or v == "BLIZZARD" then return v end
    return "BLIZZARD"
end
_G.MSUF_NormalizePortraitClassStyleValue = MSUF_Defaults_NormalizePortraitClassStyleValue

local function MSUF_Defaults_NormalizePortraitRenderDB(db)
    if type(db) ~= "table" then return end
    local g = type(db.general) == "table" and db.general or nil
    if g and g._portraitSharedRender ~= nil then
        g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
    end
    if g and g.portraitClassStyle ~= nil then
        g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    end
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focus", "pet", "boss" }) do
        local u = db[unitKey]
        if type(u) == "table" and u.portraitRender ~= nil then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(u.portraitRender)
        end
        if type(u) == "table" and u.portraitClassStyle ~= nil then
            u.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(u.portraitClassStyle)
        end
    end
end
_G.MSUF_NormalizePortraitRenderDB = MSUF_Defaults_NormalizePortraitRenderDB

local MSUF_DEFAULT_BOSS_OFFSET_X = 360
local MSUF_DEFAULT_BOSS_OFFSET_Y = 230

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
    local function ForceFreshUnitframeScreenPosition(conf, x, y)
        if type(conf) ~= "table" then return end
        conf.anchorFrameName = nil
        conf.anchorToUnitframe = "GLOBAL"
        conf.offsetX = x
        conf.offsetY = y
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
    -- Fresh factory profiles must start from stable screen-center anchors.
    -- Exported profiles can contain external/CDM-relative offsets; those are
    -- correct for that user's live anchor but wrong as universal defaults.
    ForceFreshUnitframeScreenPosition(db.player, -260, 80)
    ForceFreshUnitframeScreenPosition(db.target, 260, 80)
    ForceFreshUnitframeScreenPosition(db.focus, 260, 135)
    ForceFreshUnitframeScreenPosition(db.pet, -260, 135)
    ForceFreshUnitframeScreenPosition(db.targettarget or db.tot, 260, 225)
    ForceFreshUnitframeScreenPosition(db.boss, MSUF_DEFAULT_BOSS_OFFSET_X, MSUF_DEFAULT_BOSS_OFFSET_Y)
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
        -- Match Unhalted-style global UI scale: disabled until the user enables it.
        g.anchorToCooldown = false
        g.anchorName = "UIParent"
        g.disableScaling = false
        g.globalUiScalePreset = "auto"
        g.globalUiScaleValue = nil
        g.UIScale = { Enabled = false, Scale = 1.0 }
        g.msufUiScale = 1.0
        g.fontKey = "FRIZQT"
    end
    MSUF_Defaults_NormalizePortraitRenderDB(db)
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
    ["Expressway Regular (MSUF)"] = "EXPRESSWAY",
    ["Expressway (MSUF)"]         = "EXPRESSWAY",
    ["Expressway Bold (MSUF)"]    = "EXPRESSWAY_BOLD",
    ["Expressway SemiBold (MSUF)"] = "EXPRESSWAY_SEMIBOLD",
    ["Expressway ExtraBold (MSUF)"] = "EXPRESSWAY_EXTRABOLD",
    ["Expressway Condensed Light (MSUF)"] = "EXPRESSWAY_CONDENSED_LIGHT",
}

local function MSUF_Defaults_NormalizeFontKey(key)
    if type(key) ~= "string" or key == "" then return key end
    return MSUF_DEFAULTS_FONT_KEY_ALIASES[key] or key
end

local function MSUF_Defaults_NormalizeFontField(tbl)
    if type(tbl) ~= "table" then return end
    local normalized = MSUF_Defaults_NormalizeFontKey(tbl.fontKey)
    local resolveKeyPath = _G.MSUF_ResolveFontKeyPath
    if type(resolveKeyPath) == "function" then
        local resolved = resolveKeyPath(normalized)
        if type(resolved) == "string" and resolved ~= "" then
            normalized = resolved
        end
    end
    if normalized ~= tbl.fontKey then
        tbl.fontKey = normalized
    end
end

local function MSUF_Defaults_HasScopedFontOverrideValue(scope)
    if type(scope) ~= "table" then return false end
    if scope.fontOutline ~= nil or scope.noOutline ~= nil or scope.boldText ~= nil then return true end
    if scope.textBackdrop ~= nil or scope.colorPowerTextByType ~= nil then return true end
    if scope.nameClassColor ~= nil or scope.npcNameRed ~= nil then return true end
    if scope.useGlobalFontColor == false then return true end
    if scope.fontR ~= nil or scope.fontG ~= nil or scope.fontB ~= nil then return true end
    local mode = scope.nameColorMode
    if mode ~= nil and mode ~= "" and mode ~= "DEFAULT" then return true end
    if scope.nameShortenEnabled ~= nil then return true end
    if (tonumber(scope.nameMaxChars) or 0) > 0 then return true end
    if scope.nameClipSide ~= nil or scope.nameNoEllipsis == true then return true end
    if scope.shortenNames ~= nil or scope.shortenNameMaxChars ~= nil then return true end
    if scope.shortenNameClipSide ~= nil or scope.shortenNameFrontMaskPx ~= nil then return true end
    if scope.shortenNameShowDots ~= nil then return true end
    return false
end

local function MSUF_Defaults_ClearScopedFontKeys()
    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focus", "pet", "boss",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        local scope = MSUF_DB and MSUF_DB[key]
        if type(scope) == "table" then
            scope.fontKey = nil
            scope.nameShortenOverride = nil
            scope._msufGFNameTruncationOverride = nil
            if scope.fontOverride == true and not MSUF_Defaults_HasScopedFontOverrideValue(scope) then
                scope.fontOverride = false
            end
        end
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
    MSUF_Defaults_NormalizePortraitRenderDB(MSUF_DB)
    local legacyPortraitOverrideState = false
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focus", "pet", "boss" }) do
        local u = MSUF_DB[unitKey]
        if type(u) == "table" and u.portraitDecoOverride ~= nil then
            legacyPortraitOverrideState = true
            break
        end
    end
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
-- Default: Unhalted-style global UI scale disabled; local MSUF scales remain independent.
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
-- Nil value = Off (Unhalted-style global UI scale disabled)
-- (Do NOT seed a default globalUiScaleValue on fresh installs.)
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
if g.slashMenuSnapEnabled == nil then
    g.slashMenuSnapEnabled = true
end
if g.hideAdvancedMenu == nil then
    g.hideAdvancedMenu = true
end
    if g.editModeSnapToGrid == nil then
        g.editModeSnapToGrid = false -- Default: Snap OFF
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
    -- If enabled, the HP background uses the unit's class color while the HP
    -- foreground can stay in Dark/Unified/Gradient mode.
    if g.barBgClassColor == nil then
        g.barBgClassColor = false
    end
    if g.enableGradient == nil then
        g.enableGradient = false
    end
    if g.enableHealthGradient == nil then
        g.enableHealthGradient = true
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
        g.editModeBgAlpha = 0.75
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
            g.unitTooltipAnchor = "FIXED"
        else
            g.unitTooltipAnchor = "EXTERNAL"
        end
    elseif g.unitTooltipAnchor ~= "EXTERNAL" and g.unitTooltipAnchor ~= "FIXED" and g.unitTooltipAnchor ~= "CURSOR" then
        g.unitTooltipAnchor = "EXTERNAL"
    end
    if g.unitTooltipProvider == "MSUF" and g.unitTooltipAnchor == "EXTERNAL" then
        g.unitTooltipAnchor = "FIXED"
    end
    g.disableUnitInfoTooltips = (g.unitTooltipProvider ~= "MSUF")
    g.unitInfoTooltipStyle = (g.unitTooltipAnchor == "CURSOR") and "modern" or "classic"
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
    -- Bar settings scope: always default to Shared so users edit globally first.
    if g.hpPowerTextSelectedKey == nil then
        g.hpPowerTextSelectedKey = "shared"
    end
    -- Legacy portrait baseline. Kept only as a migration source for older profiles;
    -- runtime and Unit Frame options use per-unit portrait fields directly.
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
    g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    if g.portraitFillBorder == nil then g.portraitFillBorder = false end
    -- Retired Portrait panel UI state / old shared render value. Kept for imports only.
    if g._portraitScopeKey == nil then g._portraitScopeKey = "shared" end
    -- Initialize _portraitSharedRender from player's actual render type (migration from old layout)
    if g._portraitSharedRender == nil then
        local pConf = MSUF_DB.player
        if pConf and pConf.portraitRender then
            g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(pConf.portraitRender)
        else
            g._portraitSharedRender = "2D"
        end
    else
        g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
    end
    -- Which unit's portrait settings are currently shown in the Portraits menu (UI state only).
    -- Moved from positional tabs to scope dropdown (Bars pattern).

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

    -- Unit Frame text is per-unit as of the Unit Frame UX refactor.
    -- Older profiles could inherit HP/Power pattern settings from general.* unless
    -- hpPowerTextOverride was enabled. Flatten that inherited value once so saved
    -- profiles keep their exact look while the new UI edits only the selected unit.
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
        for _, unitKey in ipairs({"player","target","focus","targettarget","pet","boss"}) do
            MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
            local u = MSUF_DB[unitKey]
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
        textLeft      = "NONE",
        textCenter    = "NONE",
        textRight     = "CURPERCENT",
        hpTextLeftOffsetX = 0,
        hpTextLeftOffsetY = 0,
        hpTextCenterOffsetX = 0,
        hpTextCenterOffsetY = 0,
        hpTextRightOffsetX = 0,
        hpTextRightOffsetY = 0,
        powerTextLeft   = "NONE",
        powerTextCenter = "NONE",
        powerTextRight  = "CURPERCENT",
        powerTextLeftOffsetX = 0,
        powerTextLeftOffsetY = 0,
        powerTextCenterOffsetX = 0,
        powerTextCenterOffsetY = 0,
        powerTextRightOffsetX = 0,
        powerTextRightOffsetY = 0,
        nameTextLayer = 5,
        hpTextLayer = 5,
        powerTextLayer = 2,
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
    if MSUF_DB.targettarget.totInlineCustomSeparator == nil then MSUF_DB.targettarget.totInlineCustomSeparator = "" end
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
        offsetX      = MSUF_DEFAULT_BOSS_OFFSET_X,
        offsetY      = MSUF_DEFAULT_BOSS_OFFSET_Y,
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
        -- Portrait Decoration defaults (MSUF_PortraitDecoration.lua).
        -- v4.324+: portraits are always per-unit. Older shared/override profiles
        -- are flattened once: override=true keeps unit values, non-overrides adopt
        -- the old baseline, then the override marker is retired.
        local flattenLegacyPortrait = legacyPortraitOverrideState and g._msufPortraitPerUnitMigrated_v4324 ~= true
        local useLegacyBaseline = flattenLegacyPortrait and u.portraitDecoOverride ~= true
        local function PortraitDefault(field, fallback)
            local shared = g[field]
            if shared == nil then shared = fallback end
            if useLegacyBaseline then
                u[field] = shared
            elseif u[field] == nil then
                u[field] = shared
            end
        end
        if useLegacyBaseline then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender or g.portraitRender)
        elseif u.portraitRender == nil then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
        else
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(u.portraitRender)
        end
        PortraitDefault("portraitClassStyle", "BLIZZARD")
        u.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(u.portraitClassStyle)
        PortraitDefault("portraitShape", "SQUARE")
        PortraitDefault("portraitSizeOverride", 0)
        PortraitDefault("portraitOffsetX", 0)
        PortraitDefault("portraitOffsetY", 0)
        PortraitDefault("portraitBorderStyle", "NONE")
        PortraitDefault("portraitBorderThickness", 2)
        PortraitDefault("portraitBorderColorR", 1)
        PortraitDefault("portraitBorderColorG", 1)
        PortraitDefault("portraitBorderColorB", 1)
        PortraitDefault("portraitBorderColorA", 1)
        PortraitDefault("portraitBgEnabled", false)
        PortraitDefault("portraitBgColorR", 0.05)
        PortraitDefault("portraitBgColorG", 0.05)
        PortraitDefault("portraitBgColorB", 0.05)
        PortraitDefault("portraitBgColorA", 0.85)
        PortraitDefault("portraitFillBorder", false)
        u.portraitDecoOverride = nil
    end
    g._msufPortraitPerUnitMigrated_v4324 = true
    for _, key in ipairs({
        "general",
        "player", "target", "targettarget", "focus", "pet", "boss",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        MSUF_Defaults_NormalizeFontField(MSUF_DB[key])
    end
    MSUF_Defaults_ClearScopedFontKeys()
    if g._msufUFLocalFontKeyMigration_v407 ~= true then
        for _, key in ipairs({ "player", "target", "targettarget", "focus", "pet", "boss" }) do
            local u = MSUF_DB[key]
            if type(u) == "table" then
                u.fontKey = nil
            end
        end
        g._msufUFLocalFontKeyMigration_v407 = true
    end
    if g._msufSharedGlobalFontFamilyMigration_v501 ~= true then
        g._msufSharedGlobalFontFamilyMigration_v501 = true
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
