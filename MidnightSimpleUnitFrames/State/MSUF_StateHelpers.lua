local addonName, addonNS = ...
local MSUF = (_G.MSUF_NS) or addonNS or {}

--- State/MSUF_StateHelpers.lua
---
--- Shared coldpath field helpers for the two profile normalization pipelines:
--- * State/MSUF_Defaults.lua  (MSUF_EnsureDB_Heavy, "Defaults revision")
--- * State/MSUF_Profiles.lua  (MSUF_ProfileIO_TranslateProfileToCurrent,
---   "profile normalization revision")
---
--- Both pipelines used to carry their own copy of every helper below, and the
--- copies diverged on purpose in a few places: whether an empty string is
--- dropped or kept, whether a non-boolean source is coerced or rejected, and
--- which keys each pipeline touches. One implementation now lives here; every
--- behaviour difference is an explicit flag or key list on a per-pipeline spec
--- table (DefaultsSpec / ProfileIOSpec), so each caller reproduces its previous
--- semantics exactly. Do not merge the two specs without a migration plan.
---
--- Loads before MSUF_Defaults.lua; nothing here touches MSUF_DB at load time.

local StateHelpers = {}
MSUF.StateHelpers = StateHelpers

-- ---------------------------------------------------------------------------
-- Field helpers
-- ---------------------------------------------------------------------------

local function ToNumber(value)
    return tonumber(value)
end
StateHelpers.ToNumber = ToNumber

local function CopyIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    tbl[toKey] = tbl[fromKey]
    return true
end
StateHelpers.CopyIfMissing = CopyIfMissing

--- coerceNonBoolean = nil/false: a non-boolean source is rejected (Defaults
--- pipeline). coerceNonBoolean = true: the source is read as `== true`, so any
--- non-boolean value inverts to true (ProfileIO pipeline).
local function CopyInverseBoolIfMissing(tbl, toKey, fromKey, coerceNonBoolean)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    if coerceNonBoolean then
        tbl[toKey] = not (tbl[fromKey] == true)
        return true
    end
    if type(tbl[fromKey]) ~= "boolean" then return false end
    tbl[toKey] = not tbl[fromKey]
    return true
end
StateHelpers.CopyInverseBoolIfMissing = CopyInverseBoolIfMissing

local function CopyNumberAliasIfMissing(tbl, toKey, fromKey)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil or tbl[fromKey] == nil then return false end
    local n = ToNumber(tbl[fromKey])
    if n == nil then return false end
    tbl[toKey] = n
    return true
end
StateHelpers.CopyNumberAliasIfMissing = CopyNumberAliasIfMissing

local function NormalizeNumberField(tbl, key, minValue, maxValue)
    if type(tbl) ~= "table" or tbl[key] == nil then return false end
    local n = ToNumber(tbl[key])
    if n == nil then return false end
    if minValue ~= nil and n < minValue then
        n = minValue
    elseif maxValue ~= nil and n > maxValue then
        n = maxValue
    end
    if tbl[key] ~= n then
        tbl[key] = n
        return true
    end
    return false
end
StateHelpers.NormalizeNumberField = NormalizeNumberField

--- nilEmpty = nil/false: an empty string is kept as-is (Defaults pipeline).
--- nilEmpty = true: an empty string is removed from the table and reported as
--- a change (ProfileIO pipeline).
local function UpperStringField(tbl, key, nilEmpty)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "string" then return false end
    local value = tbl[key]
    if nilEmpty and value == "" then
        tbl[key] = nil
        return true
    end
    local upper = string.upper(value)
    if upper ~= value then
        tbl[key] = upper
        return true
    end
    return false
end
StateHelpers.UpperStringField = UpperStringField

local function TableHasAnyValue(tbl)
    return type(tbl) == "table" and next(tbl) ~= nil
end
StateHelpers.TableHasAnyValue = TableHasAnyValue

local AURA_GROWTH_PARTS = {
    RIGHTDOWN = { "RIGHT", "DOWN" }, LEFTDOWN = { "LEFT", "DOWN" },
    RIGHTUP = { "RIGHT", "UP" }, LEFTUP = { "LEFT", "UP" },
    RIGHT = { "RIGHT", nil }, LEFT = { "LEFT", nil },
    UP = { "UP", "UP" }, DOWN = { "DOWN", "DOWN" },
}
StateHelpers.AURA_GROWTH_PARTS = AURA_GROWTH_PARTS

local function CopyAuraGrowthAlias(tbl, fromKey, toGrowthKey, toWrapKey)
    if type(tbl) ~= "table" or tbl[fromKey] == nil then return false end
    local parts = AURA_GROWTH_PARTS[tostring(tbl[fromKey] or ""):upper()]
    if not parts then return false end
    local changed = false
    if tbl[toGrowthKey] == nil then
        tbl[toGrowthKey] = parts[1]
        changed = true
    end
    if parts[2] ~= nil and tbl[toWrapKey] == nil then
        tbl[toWrapKey] = parts[2]
        changed = true
    end
    return changed
end
StateHelpers.CopyAuraGrowthAlias = CopyAuraGrowthAlias

-- ---------------------------------------------------------------------------
-- Key lists shared verbatim by both pipelines
-- ---------------------------------------------------------------------------

local LEGACY_UNIT_NAME_ANCHORS = {
    LEFT = "TOPLEFT",
    CENTER = "TOP",
    RIGHT = "TOPRIGHT",
}
local UNIT_STATUS_BOOL_ALIASES = {
    { "showLeaderIcon", "leaderIcon" },
    { "showRaidMarker", "raidMarker" },
    { "showLevelIndicator", "levelIndicator" },
    { "showEliteIcon", "eliteIcon" },
    { "statusTextEnabled", "statusText" },
    { "showCombatStateIndicator", "combatStateIndicator" },
    { "showRestingIndicator", "restedStateIndicator" },
    { "showRestingIndicator", "restingStateIndicator" },
    { "showIncomingResIndicator", "incomingResIndicator" },
    { "showPvpIndicator", "pvpIndicator" },
    { "showRaidGroupInName", "raidGroupName" },
}
local UNIT_STATUS_OFFSET_ALIASES = {
    { "leaderIconOffsetX", "leaderIconX" },
    { "leaderIconOffsetY", "leaderIconY" },
    { "raidMarkerOffsetX", "raidMarkerX" },
    { "raidMarkerOffsetY", "raidMarkerY" },
    { "statusTextOffsetX", "statusOffsetX" },
    { "statusTextOffsetY", "statusOffsetY" },
    { "raidGroupNameOffsetX", "groupNumberX" },
    { "raidGroupNameOffsetY", "groupNumberY" },
    { "raidGroupNameLayer", "groupNumberLayer" },
}
local GROUP_STATUS_BOOL_ALIASES = {
    { "roleIcon", "showRoleIcon" },
    { "leaderIcon", "showLeaderIcon" },
    { "assistIcon", "showAssistIcon" },
    { "raidMarker", "showRaidMarker" },
    { "statusText", "statusTextEnabled" },
    { "statusGhostText", "statusGhostTextEnabled" },
    { "statusAFKText", "statusAFKTextEnabled" },
    { "statusDNDText", "statusDNDTextEnabled" },
    { "showGroupNumber", "showRaidGroupInName" },
}
local GROUP_STATUS_OFFSET_ALIASES = {
    { "roleIconX", "roleIconOffsetX" },
    { "roleIconY", "roleIconOffsetY" },
    { "leaderIconX", "leaderIconOffsetX" },
    { "leaderIconY", "leaderIconOffsetY" },
    { "assistIconX", "assistIconOffsetX" },
    { "assistIconY", "assistIconOffsetY" },
    { "raidMarkerX", "raidMarkerOffsetX" },
    { "raidMarkerY", "raidMarkerOffsetY" },
    { "statusOffsetX", "statusTextOffsetX" },
    { "statusOffsetY", "statusTextOffsetY" },
    { "statusGhostOffsetX", "statusGhostTextOffsetX" },
    { "statusGhostOffsetY", "statusGhostTextOffsetY" },
    { "statusAFKOffsetX", "statusAFKTextOffsetX" },
    { "statusAFKOffsetY", "statusAFKTextOffsetY" },
    { "statusDNDOffsetX", "statusDNDTextOffsetX" },
    { "statusDNDOffsetY", "statusDNDTextOffsetY" },
    { "groupNumberX", "raidGroupNameOffsetX" },
    { "groupNumberY", "raidGroupNameOffsetY" },
    { "groupNumberLayer", "raidGroupNameLayer" },
}
local GROUP_STATUS_ANCHOR_KEYS = {
    "roleIconAnchor",
    "raidMarkerAnchor",
    "leaderIconAnchor",
    "assistIconAnchor",
    "statusTextAnchor",
    "statusGhostTextAnchor",
    "statusAFKTextAnchor",
    "statusAFKTimerTextAnchor",
    "statusDNDTextAnchor",
    "groupNumberAnchor",
}
--- Group-frame scopes that carry the AFK/DND status pair (split-status
--- migration). Unit scopes take the per-state split instead.
local GROUP_STATUS_SCOPES = { gf_party = true, gf_raid = true, gf_mythicraid = true }
local UNIT_STATUS_TEXT_SPLIT = {
    { "statusDeadTextEnabled", "showDead", true, nil },
    { "statusGhostTextEnabled", "showGhost", true, "statusGhostText" },
    { "statusAFKTextEnabled", "showAFK", false, "statusAFKText" },
    { "statusDNDTextEnabled", "showDND", false, "statusDNDText" },
}
local STATUS_TEXT_LAYOUT_SUFFIXES = { "Size", "Anchor", "OffsetX", "OffsetY", "Layer" }

-- ---------------------------------------------------------------------------
-- Pipeline specs. Each key list below is the exact set its pipeline touched
-- before the helpers were shared; the lists are intentionally not merged.
-- ---------------------------------------------------------------------------

local DEFAULTS_STATUS_PREFIXES = {
    "leaderIcon", "raidMarker", "levelIndicator", "bossNumberIndicator", "eliteIcon", "statusText",
    "statusGhostText", "statusAFKText", "statusAFKTimer", "statusAFKTimerText", "statusDNDText",
    "combatStateIndicator", "restedStateIndicator", "restingStateIndicator",
    "incomingResIndicator", "pvpIndicator", "stanceIndicator", "raidGroupName",
}
local PROFILEIO_STATUS_PREFIXES = {
    "leaderIcon",
    "raidMarker",
    "levelIndicator",
    "bossNumberIndicator",
    "eliteIcon",
    "statusText",
    "statusGhostText",
    "statusAFKText",
    "statusAFKTimer",
    "statusDNDText",
    "combatStateIndicator",
    "restedStateIndicator",
    "restingStateIndicator",
    "incomingResIndicator",
    "pvpIndicator",
    "stanceIndicator",
    "raidGroupName",
}

local DEFAULTS_TEXT_NUMERIC_KEYS = {
    nameOffsetX = { -500, 500 },
    nameOffsetY = { -500, 500 },
    hpOffsetX = { -500, 500 },
    hpOffsetY = { -500, 500 },
    powerOffsetX = { -500, 500 },
    powerOffsetY = { -500, 500 },
}
local PROFILEIO_TEXT_NUMERIC_KEYS = {
    nameOffsetX = { -500, 500 },
    nameOffsetY = { -500, 500 },
    nameTextOffsetX = { -500, 500 },
    nameTextOffsetY = { -500, 500 },
    hpOffsetX = { -500, 500 },
    hpOffsetY = { -500, 500 },
    hpTextOffsetX = { -500, 500 },
    hpTextOffsetY = { -500, 500 },
    powerOffsetX = { -500, 500 },
    powerOffsetY = { -500, 500 },
    powerTextOffsetX = { -500, 500 },
    powerTextOffsetY = { -500, 500 },
    nameFontSize = { 6, 128 },
    hpFontSize = { 6, 128 },
    powerFontSize = { 6, 128 },
    fontBaselineOffset = { -4, 4 },
    nameMaxChars = { 0, 256 },
    shortenNameMaxChars = { 0, 256 },
    shortenNameFrontMaskPx = { 0, 128 },
    nameTextLayer = { 0, 30 },
    hpTextLayer = { 0, 30 },
    textLayer = { 0, 30 },
    powerTextLayer = { 0, 30 },
}
local PROFILEIO_TEXT_SIDE_PREFIXES = {
    "hpTextLeft", "hpTextCenter", "hpTextRight",
    "hpLeft", "hpCenter", "hpRight",
    "powerTextLeft", "powerTextCenter", "powerTextRight",
    "powerLeft", "powerCenter", "powerRight",
}
local PROFILEIO_DIRECT_TEXT_SUFFIXES = {
    "Name",
    "HealthLeft", "HealthCenter", "HealthRight",
    "PowerLeft", "PowerCenter", "PowerRight",
}
local PROFILEIO_TEXT_MODE_KEYS = {
    "textLeft", "textCenter", "textRight",
    "hpTextLeft", "hpTextCenter", "hpTextRight",
    "hpTextMode",
    "powerTextLeft", "powerTextCenter", "powerTextRight",
    "powerTextMode",
}

local DEFAULTS_GROUP_STATUS_NUMERIC_KEYS = {
    roleIconX = { -500, 500 }, roleIconY = { -500, 500 },
    raidMarkerX = { -500, 500 }, raidMarkerY = { -500, 500 },
    leaderIconX = { -500, 500 }, leaderIconY = { -500, 500 },
    assistIconX = { -500, 500 }, assistIconY = { -500, 500 },
    statusOffsetX = { -500, 500 }, statusOffsetY = { -500, 500 },
    statusGhostOffsetX = { -500, 500 }, statusGhostOffsetY = { -500, 500 },
    statusAFKOffsetX = { -500, 500 }, statusAFKOffsetY = { -500, 500 },
    statusAFKTimerOffsetX = { -500, 500 }, statusAFKTimerOffsetY = { -500, 500 },
    statusDNDOffsetX = { -500, 500 }, statusDNDOffsetY = { -500, 500 },
    groupNumberX = { -500, 500 }, groupNumberY = { -500, 500 },
    groupNumberLayer = { 0, 30 },
}
local PROFILEIO_GROUP_STATUS_NUMERIC_KEYS = {
    roleIconSize = { 1, 256 },
    roleIconX = { -500, 500 },
    roleIconY = { -500, 500 },
    roleIconLayer = { 0, 30 },
    raidMarkerSize = { 1, 256 },
    raidMarkerX = { -500, 500 },
    raidMarkerY = { -500, 500 },
    raidMarkerLayer = { 0, 30 },
    leaderIconSize = { 1, 256 },
    leaderIconX = { -500, 500 },
    leaderIconY = { -500, 500 },
    leaderIconLayer = { 0, 30 },
    assistIconSize = { 1, 256 },
    assistIconX = { -500, 500 },
    assistIconY = { -500, 500 },
    assistIconLayer = { 0, 30 },
    statusTextSize = { 1, 256 },
    statusOffsetX = { -500, 500 },
    statusOffsetY = { -500, 500 },
    statusTextLayer = { 0, 30 },
    statusGhostTextSize = { 1, 256 },
    statusGhostOffsetX = { -500, 500 },
    statusGhostOffsetY = { -500, 500 },
    statusGhostTextLayer = { 0, 30 },
    statusAFKTextSize = { 1, 256 },
    statusAFKOffsetX = { -500, 500 },
    statusAFKOffsetY = { -500, 500 },
    statusAFKTextLayer = { 0, 30 },
    statusAFKTimerTextSize = { 1, 256 },
    statusAFKTimerOffsetX = { -500, 500 },
    statusAFKTimerOffsetY = { -500, 500 },
    statusAFKTimerTextLayer = { 0, 30 },
    statusDNDTextSize = { 1, 256 },
    statusDNDOffsetX = { -500, 500 },
    statusDNDOffsetY = { -500, 500 },
    statusDNDTextLayer = { 0, 30 },
    groupNumberSize = { 1, 256 },
    groupNumberX = { -500, 500 },
    groupNumberY = { -500, 500 },
    groupNumberLayer = { 0, 30 },
}

local DEFAULTS_AURA_NUMERIC_KEYS = {
    offsetX = { -4096, 4096 }, offsetY = { -4096, 4096 },
    buffOffsetX = { -4096, 4096 }, buffOffsetY = { -4096, 4096 },
    debuffOffsetX = { -4096, 4096 }, debuffOffsetY = { -4096, 4096 },
    buffGroupOffsetX = { -4096, 4096 }, buffGroupOffsetY = { -4096, 4096 },
    debuffGroupOffsetX = { -4096, 4096 }, debuffGroupOffsetY = { -4096, 4096 },
    iconSize = { 1, 256 }, buffIconSize = { 1, 256 }, debuffIconSize = { 1, 256 },
    iconZoom = { 100, 200 }, buffIconZoom = { 100, 200 }, debuffIconZoom = { 100, 200 },
    buffGroupIconSize = { 1, 256 }, debuffGroupIconSize = { 1, 256 },
    spacing = { 0, 128 }, splitSpacing = { 0, 256 },
    buffSpacing = { 0, 128 }, debuffSpacing = { 0, 128 },
    perRow = { 1, 80 }, buffPerRow = { 1, 80 }, debuffPerRow = { 1, 80 },
    maxIcons = { 0, 80 }, maxBuffs = { 0, 80 }, maxDebuffs = { 0, 80 },
    stackTextSize = { 1, 128 }, cooldownTextSize = { 1, 128 },
    stackTextOffsetX = { -2000, 2000 }, stackTextOffsetY = { -2000, 2000 },
    cooldownTextOffsetX = { -2000, 2000 }, cooldownTextOffsetY = { -2000, 2000 },
    cooldownDecimalSeconds = { 0, 30 }, buffLayer = { 0, 30 }, debuffLayer = { 0, 30 },
}
local DEFAULTS_AURA_STRING_KEYS = {
    "growth", "rowWrap", "buffGrowth", "debuffGrowth",
    "buffGrowthX", "buffGrowthY", "debuffGrowthX", "debuffGrowthY",
    "buffRowWrap", "debuffRowWrap", "layoutMode", "buffDebuffAnchor",
    "stackCountAnchor", "cooldownTextAnchor", "buffAnchor", "debuffAnchor",
    "buffStrata", "debuffStrata",
    "debuffTypeBorderMode", "dispelBorderMode", "pandemicMode", "buffStealableStyle",
}
local PROFILEIO_AURA_NUMERIC_KEYS = {
    offsetX = { -4096, 4096 },
    offsetY = { -4096, 4096 },
    buffOffsetX = { -4096, 4096 },
    buffOffsetY = { -4096, 4096 },
    debuffOffsetX = { -4096, 4096 },
    debuffOffsetY = { -4096, 4096 },
    buffGroupOffsetX = { -4096, 4096 },
    buffGroupOffsetY = { -4096, 4096 },
    debuffGroupOffsetX = { -4096, 4096 },
    debuffGroupOffsetY = { -4096, 4096 },
    iconSize = { 1, 256 },
    buffIconSize = { 1, 256 },
    debuffIconSize = { 1, 256 },
    iconZoom = { 100, 200 },
    buffIconZoom = { 100, 200 },
    debuffIconZoom = { 100, 200 },
    buffGroupIconSize = { 1, 256 },
    debuffGroupIconSize = { 1, 256 },
    privateSize = { 1, 256 },
    spacing = { 0, 128 },
    splitSpacing = { 0, 256 },
    buffSpacing = { 0, 128 },
    debuffSpacing = { 0, 128 },
    perRow = { 1, 80 },
    buffPerRow = { 1, 80 },
    debuffPerRow = { 1, 80 },
    maxIcons = { 0, 80 },
    maxBuffs = { 0, 80 },
    maxDebuffs = { 0, 80 },
    stackTextSize = { 1, 128 },
    cooldownTextSize = { 1, 128 },
    stackTextOffsetX = { -2000, 2000 },
    stackTextOffsetY = { -2000, 2000 },
    cooldownTextOffsetX = { -2000, 2000 },
    cooldownTextOffsetY = { -2000, 2000 },
    cooldownDecimalSeconds = { 0, 30 },
    buffLayer = { 0, 30 },
    debuffLayer = { 0, 30 },
    buffStackTextSize = { 1, 128 },
    debuffStackTextSize = { 1, 128 },
    buffCooldownTextSize = { 1, 128 },
    debuffCooldownTextSize = { 1, 128 },
    buffStackTextOffsetX = { -2000, 2000 },
    buffStackTextOffsetY = { -2000, 2000 },
    debuffStackTextOffsetX = { -2000, 2000 },
    debuffStackTextOffsetY = { -2000, 2000 },
    buffCooldownTextOffsetX = { -2000, 2000 },
    buffCooldownTextOffsetY = { -2000, 2000 },
    debuffCooldownTextOffsetX = { -2000, 2000 },
    debuffCooldownTextOffsetY = { -2000, 2000 },
    buffCooldownDecimalSeconds = { 0, 30 },
    debuffCooldownDecimalSeconds = { 0, 30 },
}
local PROFILEIO_AURA_STRING_KEYS = {
    "growth", "rowWrap", "buffGrowth", "debuffGrowth", "privateGrowth",
    "buffGrowthX", "buffGrowthY", "debuffGrowthX", "debuffGrowthY",
    "buffRowWrap", "debuffRowWrap", "layoutMode", "buffDebuffAnchor",
    "stackCountAnchor", "cooldownTextAnchor", "buffAnchor", "debuffAnchor",
    "buffStackCountAnchor", "debuffStackCountAnchor",
    "buffCooldownTextAnchor", "debuffCooldownTextAnchor",
    "buffStrata", "debuffStrata",
    "debuffTypeBorderMode", "dispelBorderMode", "pandemicMode",
}

--- Defaults pipeline: keeps empty strings, rejects non-boolean inverse
--- sources, treats only nameNoEllipsis == true as a scoped font override, and
--- normalizes the narrower key sets EnsureDB always owned.
StateHelpers.DefaultsSpec = {
    name = "defaults",
    nilEmptyStrings = false,
    coerceInverseBool = false,
    noEllipsisAnyValue = false,
    statusPrefixes = DEFAULTS_STATUS_PREFIXES,
    textNumericKeys = DEFAULTS_TEXT_NUMERIC_KEYS,
    textSidePrefixes = nil,
    directTextSuffixes = nil,
    textModeKeys = nil,
    groupStatusNumericKeys = DEFAULTS_GROUP_STATUS_NUMERIC_KEYS,
    auraNumericKeys = DEFAULTS_AURA_NUMERIC_KEYS,
    auraStringKeys = DEFAULTS_AURA_STRING_KEYS,
}

--- ProfileIO pipeline: drops empty strings, coerces non-boolean inverse
--- sources, treats any explicit nameNoEllipsis as a scoped font override, and
--- also normalizes the per-side text offsets, direct text anchors, text mode
--- keys and per-lane aura text keys that only imports carry.
StateHelpers.ProfileIOSpec = {
    name = "profileio",
    nilEmptyStrings = true,
    coerceInverseBool = true,
    noEllipsisAnyValue = true,
    statusPrefixes = PROFILEIO_STATUS_PREFIXES,
    textNumericKeys = PROFILEIO_TEXT_NUMERIC_KEYS,
    textSidePrefixes = PROFILEIO_TEXT_SIDE_PREFIXES,
    directTextSuffixes = PROFILEIO_DIRECT_TEXT_SUFFIXES,
    textModeKeys = PROFILEIO_TEXT_MODE_KEYS,
    groupStatusNumericKeys = PROFILEIO_GROUP_STATUS_NUMERIC_KEYS,
    auraNumericKeys = PROFILEIO_AURA_NUMERIC_KEYS,
    auraStringKeys = PROFILEIO_AURA_STRING_KEYS,
}

-- ---------------------------------------------------------------------------
-- Scope normalizers
-- ---------------------------------------------------------------------------

--- True when a unit/group scope carries any value that only makes sense with
--- fontOverride enabled. spec.noEllipsisAnyValue decides whether an explicit
--- nameNoEllipsis = false counts (ProfileIO) or only true does (Defaults).
local function HasScopedFontOverrideValue(scope, spec)
    if type(scope) ~= "table" then return false end
    if scope.fontOutline ~= nil or scope.noOutline ~= nil or scope.boldText ~= nil then return true end
    if scope.fontMonochrome ~= nil or scope.fontSlug ~= nil or scope.fontTextAlpha ~= nil or scope.fontBaselineOffset ~= nil then return true end
    if scope.textBackdrop ~= nil or scope.fontShadowStrength ~= nil or scope.fontShadowOpacity ~= nil or scope.fontShadowDistance ~= nil then return true end
    if scope.colorPowerTextByType ~= nil or scope.colorHealthTextByHealth ~= nil then return true end
    if scope.nameClassColor ~= nil or scope.npcNameRed ~= nil or scope.nameNpcClassColor ~= nil then return true end
    if scope.useGlobalFontColor == false then return true end
    if scope.fontR ~= nil or scope.fontG ~= nil or scope.fontB ~= nil then return true end
    local mode = scope.nameColorMode
    if mode ~= nil and mode ~= "" and mode ~= "DEFAULT" then return true end
    if scope.nameShortenEnabled ~= nil or scope.shortenNames ~= nil then return true end
    if (tonumber(scope.nameMaxChars) or 0) > 0 then return true end
    if scope.shortenNameMaxChars ~= nil or scope.nameClipSide ~= nil or scope.shortenNameClipSide ~= nil then return true end
    if spec.noEllipsisAnyValue then
        if scope.nameNoEllipsis ~= nil then return true end
    elseif scope.nameNoEllipsis == true then
        return true
    end
    if scope.shortenNameShowDots ~= nil or scope.shortenNameFrontMaskPx ~= nil then return true end
    return false
end
StateHelpers.HasScopedFontOverrideValue = HasScopedFontOverrideValue

local function NormalizeNameShorteningScope(scope, groupScope, spec, inferFontOverride)
    if type(scope) ~= "table" then return false end
    local changed = false
    local coerce = spec.coerceInverseBool
    if groupScope then
        changed = CopyIfMissing(scope, "nameShortenEnabled", "shortenNames") or changed
        changed = CopyIfMissing(scope, "nameMaxChars", "shortenNameMaxChars") or changed
        changed = CopyIfMissing(scope, "nameClipSide", "shortenNameClipSide") or changed
        changed = CopyInverseBoolIfMissing(scope, "nameNoEllipsis", "shortenNameShowDots", coerce) or changed
    else
        changed = CopyIfMissing(scope, "shortenNames", "nameShortenEnabled") or changed
        changed = CopyIfMissing(scope, "shortenNameMaxChars", "nameMaxChars") or changed
        changed = CopyIfMissing(scope, "shortenNameClipSide", "nameClipSide") or changed
        changed = CopyInverseBoolIfMissing(scope, "shortenNameShowDots", "nameNoEllipsis", coerce) or changed
    end
    changed = NormalizeNumberField(scope, "shortenNameMaxChars", 0, 256) or changed
    changed = NormalizeNumberField(scope, "nameMaxChars", 0, 256) or changed
    changed = NormalizeNumberField(scope, "shortenNameFrontMaskPx", 0, 128) or changed
    changed = UpperStringField(scope, "shortenNameClipSide", spec.nilEmptyStrings) or changed
    changed = UpperStringField(scope, "nameClipSide", spec.nilEmptyStrings) or changed
    if inferFontOverride and scope.fontOverride == nil and HasScopedFontOverrideValue(scope, spec) then
        scope.fontOverride = true
        changed = true
    end
    return changed
end
StateHelpers.NormalizeNameShorteningScope = NormalizeNameShorteningScope

local function NormalizeTextScope(scope, groupScope, spec, inferFontOverride)
    if type(scope) ~= "table" then return false end
    local changed = false
    local nilEmpty = spec.nilEmptyStrings
    if groupScope then
        changed = CopyIfMissing(scope, "nameAnchor", "nameTextAnchor") or changed
    else
        changed = CopyIfMissing(scope, "nameTextAnchor", "nameAnchor") or changed
    end
    changed = CopyIfMissing(scope, "nameOffsetX", "nameTextOffsetX") or changed
    changed = CopyIfMissing(scope, "nameOffsetY", "nameTextOffsetY") or changed
    changed = CopyIfMissing(scope, "hpOffsetX", "hpTextOffsetX") or changed
    changed = CopyIfMissing(scope, "hpOffsetY", "hpTextOffsetY") or changed
    changed = CopyIfMissing(scope, "powerOffsetX", "powerTextOffsetX") or changed
    changed = CopyIfMissing(scope, "powerOffsetY", "powerTextOffsetY") or changed
    changed = CopyIfMissing(scope, "textLeft", "hpTextLeft") or changed
    changed = CopyIfMissing(scope, "textCenter", "hpTextCenter") or changed
    changed = CopyIfMissing(scope, "textRight", "hpTextRight") or changed
    if groupScope then
        changed = CopyIfMissing(scope, "textDelimiter", "hpTextSeparator") or changed
        changed = CopyIfMissing(scope, "powerTextDelimiter", "powerTextSeparator") or changed
    else
        changed = CopyIfMissing(scope, "hpTextSeparator", "textDelimiter") or changed
        changed = CopyIfMissing(scope, "powerTextSeparator", "powerTextDelimiter") or changed
    end
    for key, limits in pairs(spec.textNumericKeys) do
        changed = NormalizeNumberField(scope, key, limits[1], limits[2]) or changed
    end
    local sidePrefixes = spec.textSidePrefixes
    if sidePrefixes then
        for i = 1, #sidePrefixes do
            local prefix = sidePrefixes[i]
            changed = NormalizeNumberField(scope, prefix .. "OffsetX", -500, 500) or changed
            changed = NormalizeNumberField(scope, prefix .. "OffsetY", -500, 500) or changed
        end
    end
    local directSuffixes = spec.directTextSuffixes
    if directSuffixes then
        for i = 1, #directSuffixes do
            local key = "direct" .. directSuffixes[i]
            changed = CopyIfMissing(scope, key .. "OffsetX", key .. "X") or changed
            changed = CopyIfMissing(scope, key .. "OffsetY", key .. "Y") or changed
            changed = NormalizeNumberField(scope, key .. "OffsetX", -500, 500) or changed
            changed = NormalizeNumberField(scope, key .. "OffsetY", -500, 500) or changed
            changed = UpperStringField(scope, key .. "Point", nilEmpty) or changed
            changed = UpperStringField(scope, key .. "RelativePoint", nilEmpty) or changed
        end
    end
    local modeKeys = spec.textModeKeys
    if modeKeys then
        for i = 1, #modeKeys do
            changed = UpperStringField(scope, modeKeys[i], nilEmpty) or changed
        end
    end
    changed = UpperStringField(scope, "nameTextAnchor", nilEmpty) or changed
    changed = UpperStringField(scope, "nameAnchor", nilEmpty) or changed
    if not groupScope then
        local legacyAnchor = LEGACY_UNIT_NAME_ANCHORS[scope.nameTextAnchor]
        if legacyAnchor then
            scope.nameTextAnchor = legacyAnchor
            changed = true
        end
    end
    changed = NormalizeNameShorteningScope(scope, groupScope == true, spec, inferFontOverride == true) or changed
    return changed
end
StateHelpers.NormalizeTextScope = NormalizeTextScope

local function NormalizeStatusScope(scope, groupScope, spec)
    if type(scope) ~= "table" then return false end
    local changed = false
    local nilEmpty = spec.nilEmptyStrings
    local boolAliases = groupScope and GROUP_STATUS_BOOL_ALIASES or UNIT_STATUS_BOOL_ALIASES
    for i = 1, #boolAliases do
        changed = CopyIfMissing(scope, boolAliases[i][1], boolAliases[i][2]) or changed
    end
    local offsetAliases = groupScope and GROUP_STATUS_OFFSET_ALIASES or UNIT_STATUS_OFFSET_ALIASES
    for i = 1, #offsetAliases do
        changed = CopyIfMissing(scope, offsetAliases[i][1], offsetAliases[i][2]) or changed
    end
    local prefixes = spec.statusPrefixes
    for i = 1, #prefixes do
        local prefix = prefixes[i]
        changed = NormalizeNumberField(scope, prefix .. "Size", 1, 256) or changed
        changed = NormalizeNumberField(scope, prefix .. "OffsetX", -500, 500) or changed
        changed = NormalizeNumberField(scope, prefix .. "OffsetY", -500, 500) or changed
        changed = NormalizeNumberField(scope, prefix .. "Layer", 0, 30) or changed
        changed = UpperStringField(scope, prefix .. "Anchor", nilEmpty) or changed
    end
    if groupScope then
        for key, limits in pairs(spec.groupStatusNumericKeys) do
            changed = NormalizeNumberField(scope, key, limits[1], limits[2]) or changed
        end
        for i = 1, #GROUP_STATUS_ANCHOR_KEYS do
            changed = UpperStringField(scope, GROUP_STATUS_ANCHOR_KEYS[i], nilEmpty) or changed
        end
    end
    return changed
end
StateHelpers.NormalizeStatusScope = NormalizeStatusScope

local function NormalizeAuraLayoutTable(tbl, spec)
    if type(tbl) ~= "table" then return false end
    local changed = false
    changed = CopyNumberAliasIfMissing(tbl, "maxBuffs", "maxIcons") or changed
    changed = CopyNumberAliasIfMissing(tbl, "maxDebuffs", "maxIcons") or changed
    changed = CopyNumberAliasIfMissing(tbl, "buffGroupIconSize", "buffIconSize") or changed
    changed = CopyNumberAliasIfMissing(tbl, "debuffGroupIconSize", "debuffIconSize") or changed
    changed = CopyNumberAliasIfMissing(tbl, "buffGroupIconSize", "iconSize") or changed
    changed = CopyNumberAliasIfMissing(tbl, "debuffGroupIconSize", "iconSize") or changed
    changed = CopyNumberAliasIfMissing(tbl, "buffGroupOffsetX", "buffOffsetX") or changed
    changed = CopyNumberAliasIfMissing(tbl, "buffGroupOffsetY", "buffOffsetY") or changed
    changed = CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetX", "debuffOffsetX") or changed
    changed = CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetY", "debuffOffsetY") or changed
    changed = CopyNumberAliasIfMissing(tbl, "buffGroupOffsetX", "offsetX") or changed
    changed = CopyNumberAliasIfMissing(tbl, "buffGroupOffsetY", "offsetY") or changed
    changed = CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetX", "offsetX") or changed
    changed = CopyNumberAliasIfMissing(tbl, "debuffGroupOffsetY", "offsetY") or changed
    changed = CopyAuraGrowthAlias(tbl, "buffGrowth", "buffGrowthX", "buffGrowthY") or changed
    changed = CopyAuraGrowthAlias(tbl, "debuffGrowth", "debuffGrowthX", "debuffGrowthY") or changed
    changed = CopyIfMissing(tbl, "buffGrowthY", "buffRowWrap") or changed
    changed = CopyIfMissing(tbl, "debuffGrowthY", "debuffRowWrap") or changed
    changed = CopyIfMissing(tbl, "buffGrowthY", "rowWrap") or changed
    changed = CopyIfMissing(tbl, "debuffGrowthY", "rowWrap") or changed
    for key, limits in pairs(spec.auraNumericKeys) do
        changed = NormalizeNumberField(tbl, key, limits[1], limits[2]) or changed
    end
    local stringKeys = spec.auraStringKeys
    local nilEmpty = spec.nilEmptyStrings
    for i = 1, #stringKeys do
        changed = UpperStringField(tbl, stringKeys[i], nilEmpty) or changed
    end
    return changed
end
StateHelpers.NormalizeAuraLayoutTable = NormalizeAuraLayoutTable

--- Split the single legacy status text toggle into the per-state Dead/Ghost/
--- AFK/DND toggles (unit scopes) and seed the DND pair from the AFK pair
--- (group scopes). scopeKeys is the caller's own scope list; "general" is
--- skipped and group scopes are recognised by name.
local function MigrateSplitStatusText(profile, scopeKeys)
    if type(profile) ~= "table" then return false end
    local changed = false
    local general = type(profile.general) == "table" and profile.general or {}
    local states = type(general.statusIndicators) == "table" and general.statusIndicators or {}
    for i = 1, #scopeKeys do
        local scopeKey = scopeKeys[i]
        local scope = profile[scopeKey]
        if type(scope) == "table" and GROUP_STATUS_SCOPES[scopeKey] then
            if scope.statusDNDText == nil and scope.statusAFKText ~= nil then
                scope.statusDNDText = scope.statusAFKText
                scope.statusDNDTextSize = scope.statusAFKTextSize
                scope.statusDNDTextAnchor = scope.statusAFKTextAnchor
                scope.statusDNDTextLayer = scope.statusAFKTextLayer
                scope.statusDNDOffsetX = scope.statusAFKOffsetX
                scope.statusDNDOffsetY = scope.statusAFKOffsetY
                changed = true
            end
        elseif type(scope) == "table" and scopeKey ~= "general" then
            local master = scope.statusTextEnabled
            if master == nil then master = general.statusTextEnabled end
            if master == nil then master = true end
            for j = 1, #UNIT_STATUS_TEXT_SPLIT do
                local def = UNIT_STATUS_TEXT_SPLIT[j]
                if scope[def[1]] == nil then
                    local state = states[def[2]]
                    if state == nil then state = def[3] end
                    scope[def[1]] = master == true and state == true
                    changed = true
                end
                local prefix = def[4]
                if prefix then
                    for k = 1, #STATUS_TEXT_LAYOUT_SUFFIXES do
                        local suffix = STATUS_TEXT_LAYOUT_SUFFIXES[k]
                        local key, legacyKey = prefix .. suffix, "statusText" .. suffix
                        if scope[key] == nil then
                            local value = scope[legacyKey]
                            if value == nil then value = general[legacyKey] end
                            if value ~= nil then scope[key], changed = value, true end
                        end
                    end
                end
            end
        end
    end
    return changed
end
StateHelpers.MigrateSplitStatusText = MigrateSplitStatusText
