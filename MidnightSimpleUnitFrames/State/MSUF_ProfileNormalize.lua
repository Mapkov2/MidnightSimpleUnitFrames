-- Profile normalization: one profile table is brought to the current schema
-- (unit position aliases, text and status scopes, the aura model resets,
-- imported font sizes, group aura filter tokens). The same pipeline runs on
-- stored, factory and imported profiles; the caller says how far the
-- profile's own metadata is trusted (see TranslateProfileToCurrent).
-- State/MSUF_Profiles.lua owns the profile lifecycle, import and export and
-- the public API and reads everything below through MSUF.ProfileNormalize.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local StateHelpers = MSUF.StateHelpers
if type(StateHelpers) ~= "table" then
    error("State/MSUF_StateHelpers.lua must load before State/MSUF_ProfileNormalize.lua")
end
local MSUF_PROFILE_IMPORT_LIMITS = MSUF.ProfileIOImportLimits
if type(MSUF_PROFILE_IMPORT_LIMITS) ~= "table" then
    error("State/MSUF_ProfileCodec.lua must load before State/MSUF_ProfileNormalize.lua")
end

--- Deep copy bounded by the import depth limit: normalization copies parts
--- of imported tables, which may be arbitrarily nested.
local function MSUF_DeepCopy(v, seen, depth)
    if not v then  return v end
    if type(v) ~= "table" then
        return v
    end
    depth = (depth or 0) + 1
    if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then error("profile table is too deep") end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, vv in pairs(v) do
        out[MSUF_DeepCopy(k, seen, depth)] = MSUF_DeepCopy(vv, seen, depth)
    end
     return out
end

local function MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
    if type(profile) ~= "table" then return end
    if type(profile.general) ~= "table" then
        profile.general = {}
    end
    if profile.general.showGameMenuButton == nil then
        profile.general.showGameMenuButton = true
    end
    if profile.general.previewDragHintAnimationEnabled == nil then
        profile.general.previewDragHintAnimationEnabled = true
    end
    -- Factory-created profiles explicitly start at false. Profiles predating
    -- the drag cue have already taught their owners the preview workflow, so a
    -- missing marker is migrated to the experienced cadence.
    if profile.general._msufPreviewDragHintExperienced == nil then
        profile.general._msufPreviewDragHintExperienced = true
    end
end

local MSUF_ProfileIO_TranslateProfileToCurrent
local MSUF_ProfileIO_TranslateProfilesToCurrent

local MSUF_PROFILEIO_POSITIVE_FONT_SIZE_KEYS = {
    fontSize = 14,
    nameFontSize = 14,
    hpFontSize = 14,
    powerFontSize = 14,
    auraFontSize = 25,
    levelIndicatorSize = 12,
    bossNumberIndicatorSize = 14,
    classificationIndicatorSize = 12,
    statusIndicatorSize = 14,
    statusTextSize = 14,
    statusGhostTextSize = 14,
    statusAFKTextSize = 14,
    statusAFKTimerSize = 12,
    statusAFKTimerTextSize = 10,
    statusDNDTextSize = 14,
    playerHPBarTextSize = 14,
    combatFontSize = 24,
    combatStateFontSize = 24,
    focusKickTextSize = 12,
    stackTextSize = 14,
    cooldownTextSize = 14,
    buffStackTextSize = 14,
    buffCooldownTextSize = 14,
    debuffStackTextSize = 14,
    debuffCooldownTextSize = 14,
}
local function MSUF_ProfileIO_ClampPositiveFontSize(tbl, key, fallback)
    if type(tbl) ~= "table" or tbl[key] == nil then
        return
    end
    local n = tonumber(tbl[key])
    if n == nil then
        return
    end
    fallback = tonumber(fallback) or 14
    if n <= 0 then
        n = fallback
    elseif n < 6 then
        n = 6
    elseif n > 128 then
        n = 128
    end
    tbl[key] = n
end
local function MSUF_ProfileIO_NormalizeImportedFontSizes(profile)
    if type(profile) ~= "table" then
        return profile
    end
    local seen = {}
    local function Walk(tbl, depth)
        if type(tbl) ~= "table" or seen[tbl] or depth > 8 then
            return
        end
        seen[tbl] = true
        for key, fallback in pairs(MSUF_PROFILEIO_POSITIVE_FONT_SIZE_KEYS) do
            MSUF_ProfileIO_ClampPositiveFontSize(tbl, key, fallback)
        end
        for _, value in pairs(tbl) do
            if type(value) == "table" then
                Walk(value, depth + 1)
            end
        end
    end
    Walk(profile, 0)
    return profile
end

local MSUF_PROFILEIO_UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
--- Arena slot ledgers: arena1..3 stay literal on every flavor (pinned by
--- tools/arena_unit_scope_smoke.lua) and arena4..N follow the client fact
--- published by Game/Shared/Initialize.lua (5 on TBC/Mists, 3 on Mainline,
--- 0 on Vanilla). Clamped to 3..5 so Mainline and Vanilla keep the exact
--- arena1..3 import, reset and text-scope behavior.
local MSUF_PROFILEIO_ARENA_SLOTS = math.max(3, math.min(5, math.floor(tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)))
local MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES = {
    { canonical = "targettarget", aliases = { "tot", "targetoftarget", "target_of_target" } },
    { canonical = "focustarget", aliases = { "focus_target", "focustargettarget" } },
}
local function MSUF_ProfileIO_NormalizeUnitFramePositionDB(profile, preferLegacyAliases)
    if type(profile) ~= "table" then return profile end
    local changed = false

    local function SelectAlias(container, aliases)
        local best
        for i = 1, #aliases do
            local alias = container[aliases[i]]
            if type(alias) == "table" and (best == nil or (alias.enabled == true and best.enabled ~= true)) then
                best = alias
            end
        end
        return best
    end

    local function SelectUnitSource(container, def)
        local current = container[def.canonical]
        local alias = SelectAlias(container, def.aliases)
        if type(current) ~= "table"
            or (preferLegacyAliases == true and type(alias) == "table"
                and alias.enabled == true and current.enabled ~= true) then
            return alias
        end
        return current
    end

    local nested = (type(profile.unitframes) == "table" and profile.unitframes)
        or (type(profile.unitFrames) == "table" and profile.unitFrames)
        or nil
    if nested and (type(nested.player) == "table" or type(nested.target) == "table") then
        for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
            local key = MSUF_PROFILEIO_UNIT_KEYS[i]
            if key ~= "targettarget" and key ~= "focustarget"
                and type(profile[key]) ~= "table" and type(nested[key]) == "table" then
                profile[key] = MSUF_DeepCopy(nested[key])
                changed = true
            end
        end
        for i = 1, #MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES do
            local def = MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES[i]
            if type(profile[def.canonical]) ~= "table" then
                local source = SelectUnitSource(nested, def)
                if type(source) == "table" then
                    profile[def.canonical] = MSUF_DeepCopy(source)
                    changed = true
                end
            end
        end
    end

    --- Aliases are accepted only as migration input. Once a canonical scope has
    --- been selected, retire every alias so future edits and reloads cannot
    --- create two independently serialized owners for the same unit frame.
    for i = 1, #MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES do
        local def = MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES[i]
        local source = SelectUnitSource(profile, def)
        if type(source) == "table" and source ~= profile[def.canonical] then
            profile[def.canonical] = MSUF_DeepCopy(source)
            changed = true
        end
        for j = 1, #def.aliases do
            local aliasKey = def.aliases[j]
            if profile[aliasKey] ~= nil then
                profile[aliasKey] = nil
                changed = true
            end
        end
    end
    if type(profile.boss) ~= "table" then
        for i = 1, 5 do
            local boss = profile["boss" .. i]
            if type(boss) == "table" then
                profile.boss = MSUF_DeepCopy(boss)
                changed = true
                break
            end
        end
    end

    local function NormalizeAnchorTo(conf)
        local anchor = conf.anchorToUnitframe
        if type(anchor) ~= "string" or anchor == "" then return end
        if anchor == "global" then
            conf.anchorToUnitframe = "GLOBAL"
        elseif anchor == "free" then
            conf.anchorToUnitframe = "FREE"
        elseif anchor == "tot" or anchor == "targetoftarget" then
            conf.anchorToUnitframe = "targettarget"
        elseif anchor == "focus_target" or anchor == "focustargettarget" then
            conf.anchorToUnitframe = "focustarget"
        elseif anchor:match("^boss%d+$") then
            conf.anchorToUnitframe = "boss"
        elseif anchor:match("^arena%d+$") then
            conf.anchorToUnitframe = "arena"
        end
    end

    local function NormalizeNumber(conf, key, minValue, maxValue)
        local n = tonumber(conf[key])
        if n == nil then return end
        if minValue ~= nil and n < minValue then
            n = minValue
        elseif maxValue ~= nil and n > maxValue then
            n = maxValue
        end
        conf[key] = n
    end

    local function NormalizeUnit(conf)
        if type(conf) ~= "table" then return end
        if conf.anchorFrameName == "UI_Parent" then conf.anchorFrameName = "UIParent" end
        if conf.point == nil and conf.anchorMyPoint ~= nil then conf.point = conf.anchorMyPoint end
        if conf.relativePoint == nil and conf.anchorRelPoint ~= nil then conf.relativePoint = conf.anchorRelPoint end
        if conf.offsetX == nil and conf.x ~= nil then conf.offsetX = conf.x end
        if conf.offsetY == nil and conf.y ~= nil then conf.offsetY = conf.y end
        if conf.width == nil and conf.frameWidth ~= nil then conf.width = conf.frameWidth end
        if conf.height == nil and conf.frameHeight ~= nil then conf.height = conf.frameHeight end
        NormalizeNumber(conf, "offsetX", -4096, 4096)
        NormalizeNumber(conf, "offsetY", -4096, 4096)
        NormalizeNumber(conf, "x", -4096, 4096)
        NormalizeNumber(conf, "y", -4096, 4096)
        NormalizeNumber(conf, "width", 1, 4096)
        NormalizeNumber(conf, "height", 1, 4096)
        NormalizeNumber(conf, "frameWidth", 1, 4096)
        NormalizeNumber(conf, "frameHeight", 1, 4096)
        NormalizeNumber(conf, "spacing", -4096, 4096)
        if conf.point == "" then conf.point = nil end
        if conf.relativePoint == "" then conf.relativePoint = nil end
        if type(conf.point) == "string" then conf.point = string.upper(conf.point) end
        if type(conf.relativePoint) == "string" then conf.relativePoint = string.upper(conf.relativePoint) end
        NormalizeAnchorTo(conf)
    end

    for i = 1, #MSUF_PROFILEIO_UNIT_KEYS do
        NormalizeUnit(profile[MSUF_PROFILEIO_UNIT_KEYS[i]])
    end
    for i = 1, 5 do
        NormalizeUnit(profile["boss" .. i])
    end
    for i = 1, MSUF_PROFILEIO_ARENA_SLOTS do
        NormalizeUnit(profile["arena" .. i])
    end
    if type(profile.general) == "table" and profile.general.anchorName == "UI_Parent" then
        profile.general.anchorName = "UIParent"
    end
    return profile, changed
end

local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = 600
--- This revision describes the normalization performed by
--- MSUF_ProfileIO_TranslateProfileToCurrent, independently from the broad
--- default-fill revision owned by MSUF_Defaults.lua. Bump it whenever that
--- translation pipeline gains a new mandatory repair.
--- Cross-reference: State/MSUF_Defaults.lua runs a second, independent alias
--- normalization pipeline (MSUF_EnsureDB_Heavy, gated by
--- MSUF_DEFAULTS_CURRENT_REVISION) over the same text/status/aura alias keys,
--- using the narrower StateHelpers.DefaultsSpec. The two revisions are bumped
--- independently and are deliberately not merged; keep both in mind when a
--- key alias changes.
local MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION = 21
local MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY = "profileModelRevision"
--- RC17's destructive hard cut established revision 1 as the canonical Unit
--- Aura baseline. Later revisions may migrate ownership or storage in place;
--- they must never make an already-canonical profile eligible for this reset.
local MSUF_PROFILEIO_UNIT_AURA_RESET_BASELINE_REVISION = 1
local MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION = 1
local MSUF_PROFILEIO_GROUP_AURA_SCOPES = { "gf_party", "gf_raid", "gf_mythicraid" }
local MSUF_PROFILEIO_GROUP_AURA_FILTER_LANES = { "buff", "debuff" }
local MSUF_PROFILEIO_GF_CURRENT_FILTER_TOKENS = {
    buff = {
        ALL = "ALL",
        MSUFGROUPHIGHLIGHTSV1 = "MSUF_GROUP_HIGHLIGHTS_V1",
        PLAYER = "Player",
        BIGDEFENSIVE = "BigDefensive",
        BIGDEFENSIVEPLAYER = "BigDefensivePlayer",
        EXTERNALDEFENSIVE = "ExternalDefensive",
        EXTERNALDEFENSIVEPLAYER = "ExternalDefensivePlayer",
        RAIDINCOMBAT = "RaidInCombat",
        RAID = "Raid",
        RAIDPLAYER = "RaidPlayer",
    },
    debuff = {
        ALL = "ALL",
        PLAYER = "Player",
        RAID = "Raid",
        RAIDINCOMBAT = "RaidInCombat",
        RAIDPLAYERDISPELLABLE = "RAID_PLAYER_DISPELLABLE",
        DISPELLABLE = "DISPELLABLE",
        CROWDCONTROL = "CROWD_CONTROL",
        NONPLAYER = "NonPlayer",
    },
}

local function MSUF_ProfileIO_HasCanonicalUnitAuraBaseline(auras)
    return type(auras) == "table"
        and (tonumber(auras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) or 0)
            >= MSUF_PROFILEIO_UNIT_AURA_RESET_BASELINE_REVISION
end
local function MSUF_ProfileIO_NormalizeGFAuraFilterToken(lane, token)
    if lane ~= "buff" and lane ~= "debuff" then return token end
    local auraFilter = (type(MSUF) == "table" and type(MSUF.GF) == "table" and MSUF.GF.AuraFilter)
        or _G.MSUF_GF_AuraFilter
    local normalize = auraFilter and auraFilter.NormalizeFilterToken
    if type(normalize) == "function" then
        return normalize(lane, token)
    end
    local key = tostring(token or "ALL"):upper():gsub("[^A-Z0-9]", "")
    return MSUF_PROFILEIO_GF_CURRENT_FILTER_TOKENS[lane][key] or "ALL"
end
local function MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, apply)
    if type(profile) ~= "table" then return false end
    local changed = false
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_SCOPES do
        local conf = profile[MSUF_PROFILEIO_GROUP_AURA_SCOPES[i]]
        local auras = type(conf) == "table" and conf.auras or nil
        if type(auras) == "table" then
            for j = 1, #MSUF_PROFILEIO_GROUP_AURA_FILTER_LANES do
                local lane = MSUF_PROFILEIO_GROUP_AURA_FILTER_LANES[j]
                local group = auras[lane]
                if type(group) == "table" and group.filterToken ~= nil then
                    local normalized = MSUF_ProfileIO_NormalizeGFAuraFilterToken(lane, group.filterToken)
                    if normalized ~= group.filterToken then
                        changed = true
                        if apply then group.filterToken = normalized end
                    end
                end
            end
        end
    end
    return changed
end
function MSUF.ProfileIOGroupHasRetiredAuraFields(conf)
    return type(conf) == "table" and (
        conf.aurasEnabled ~= nil or conf.auraMaxIcons ~= nil or conf.auraIconSize ~= nil
        or conf.auraAnchor ~= nil or conf.auraGrowthX ~= nil or conf.auraGrowthY ~= nil
        or conf.auraSpacing ~= nil or conf.auraPerRow ~= nil
        or conf.privateAurasEnabled ~= nil or conf.privateAuraMax ~= nil
        or conf.privateAuraSize ~= nil or conf.privateAuraAnchor ~= nil
        or conf.privateAuraX ~= nil or conf.privateAuraY ~= nil
        or conf.privateAuraCountdown ~= nil or conf._auraMigV2 ~= nil)
end
function MSUF.ProfileIOGroupHasAuraPayload(conf)
    return type(conf) == "table" and (
        type(conf.auras) == "table" or type(conf.privateAuras) == "table"
        or type(conf.spellIndicators) == "table"
        or MSUF.ProfileIOGroupHasRetiredAuraFields(conf))
end
local MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS = {
    "player", "target", "focus",
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3",
}
local MSUF_PROFILEIO_TEXT_SCOPE_KEYS = {
    "general",
    "player", "target", "targettarget",
    "focus", "focustarget",
    "pet", "pettarget", "boss", "boss1", "boss2", "boss3", "boss4",
    "arena", "arena1", "arena2", "arena3",
    "gf_party", "gf_raid", "gf_mythicraid",
}
for i = 4, MSUF_PROFILEIO_ARENA_SLOTS do
    MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[#MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS + 1] = "arena" .. i
    MSUF_PROFILEIO_TEXT_SCOPE_KEYS[#MSUF_PROFILEIO_TEXT_SCOPE_KEYS + 1] = "arena" .. i
end
local MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS = {
    "player", "target", "targettarget", "tot", "targetoftarget",
    "focus", "focustarget", "focus_target", "focustargettarget",
    "pet", "pettarget", "boss", "boss1", "boss2", "boss3", "boss4",
}
--- The field helpers, the text/status scope normalizers, the aura layout
--- normalizer and the split-status migration are shared with
--- State/MSUF_Defaults.lua through MSUF.StateHelpers. This pipeline always
--- passes StateHelpers.ProfileIOSpec, which keeps the import-side semantics:
--- empty strings are dropped, non-boolean inverse sources are coerced, and
--- the wider import key sets are normalized. See the cross-reference note
--- above MSUF_ProfileIO_TranslateProfileToCurrent for the Defaults twin.

local function MSUF_ProfileIO_AuraOverridesNeedRepair(profile)
    local auras = type(profile) == "table" and profile.auras3 or nil
    local perUnit = type(auras) == "table" and auras.perUnit or nil
    if type(perUnit) ~= "table" then return false end
    for _, unitCfg in pairs(perUnit) do
        if type(unitCfg) == "table" then
            if StateHelpers.TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout == nil then return true end
            if StateHelpers.TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout == nil then return true end
        end
    end
    return false
end

local function MSUF_ProfileIO_ProfileHasDeprecatedUnitAliases(profile)
    if type(profile) ~= "table" then return false end
    for i = 1, #MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES do
        local aliases = MSUF_PROFILEIO_DEPRECATED_UNIT_ALIASES[i].aliases
        for j = 1, #aliases do
            if profile[aliases[j]] ~= nil then
                return true
            end
        end
    end
    return false
end

local function MSUF_ProfileIO_ProfileNeedsNormalization(profile)
    if type(profile) ~= "table" then return false end
    if MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, false) then return true end
    if profile.auras ~= nil or type(profile.auras2) == "table" then return true end
    local auras = type(profile.auras3) == "table" and profile.auras3 or nil
    if auras and not MSUF_ProfileIO_HasCanonicalUnitAuraBaseline(auras) then
        return true
    end
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_SCOPES do
        local conf = profile[MSUF_PROFILEIO_GROUP_AURA_SCOPES[i]]
        if type(conf) == "table" then
            local groupAuras = type(conf.auras) == "table" and conf.auras or nil
            local hasAuraPayload = MSUF.ProfileIOGroupHasAuraPayload(conf)
            if hasAuraPayload and (not groupAuras
                or tonumber(groupAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) ~= MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION
                or MSUF.ProfileIOGroupHasRetiredAuraFields(conf)) then
                return true
            end
        end
    end
    if MSUF_ProfileIO_AuraOverridesNeedRepair(profile) then return true end
    if MSUF_ProfileIO_ProfileHasDeprecatedUnitAliases(profile) then return true end
    for i = 1, #MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS do
        local scope = profile[MSUF_PROFILEIO_LEGACY_SIGNAL_UNIT_KEYS[i]]
        if type(scope) == "table"
            and ((scope.anchorMyPoint ~= nil and scope.point == nil)
                or (scope.anchorRelPoint ~= nil and scope.relativePoint == nil)) then
            return true
        end
    end
    return false
end

local function MSUF_ProfileIO_NormalizeLegacyRootNameShortening(profile, createGeneral)
    if type(profile) ~= "table" then return false end
    local changed = false
    changed = StateHelpers.CopyIfMissing(profile, "shortenNames", "nameShortenEnabled") or changed
    local general = profile.general
    if type(general) ~= "table" then
        if createGeneral == false then
            return changed
        end
        general = {}
        profile.general = general
        changed = true
    end
    if profile.shortenNames == nil and general.shortenNames ~= nil then
        profile.shortenNames = general.shortenNames
        changed = true
    elseif profile.shortenNames == nil and general.nameShortenEnabled ~= nil then
        profile.shortenNames = general.nameShortenEnabled
        changed = true
    end
    if general.shortenNameMaxChars == nil and profile.shortenNameMaxChars ~= nil then
        general.shortenNameMaxChars = profile.shortenNameMaxChars
        changed = true
    end
    if general.shortenNameClipSide == nil and profile.shortenNameClipSide ~= nil then
        general.shortenNameClipSide = profile.shortenNameClipSide
        changed = true
    end
    if general.shortenNameShowDots == nil and profile.shortenNameShowDots ~= nil then
        general.shortenNameShowDots = profile.shortenNameShowDots
        changed = true
    end
    if general.shortenNameFrontMaskPx == nil and profile.shortenNameFrontMaskPx ~= nil then
        general.shortenNameFrontMaskPx = profile.shortenNameFrontMaskPx
        changed = true
    end
    changed = StateHelpers.NormalizeNumberField(general, "shortenNameMaxChars", 0, 256) or changed
    changed = StateHelpers.NormalizeNumberField(general, "shortenNameFrontMaskPx", 0, 128) or changed
    changed = StateHelpers.UpperStringField(general, "shortenNameClipSide", true) or changed
    return changed
end

local MSUF_PROFILEIO_AURA_RESETTERS = {}
do
local MSUF_PROFILEIO_UNIT_AURA_RESET_LANES = {
    buff = {
        sizeKey = "buffGroupIconSize",
        xKey = "buffGroupOffsetX",
        yKey = "buffGroupOffsetY",
        anchorKey = "buffAnchor",
        spacingKey = "buffSpacing",
        perRowKey = "buffPerRow",
        maxKey = "maxBuffs",
        growthKey = "buffGrowthX",
        wrapKey = "buffGrowthY",
        legacyGrowthKey = "buffGrowth",
        defaultX = 0,
        defaultY = 36,
        defaultAnchor = "BOTTOMRIGHT",
    },
    debuff = {
        sizeKey = "debuffGroupIconSize",
        xKey = "debuffGroupOffsetX",
        yKey = "debuffGroupOffsetY",
        anchorKey = "debuffAnchor",
        spacingKey = "debuffSpacing",
        perRowKey = "debuffPerRow",
        maxKey = "maxDebuffs",
        growthKey = "debuffGrowthX",
        wrapKey = "debuffGrowthY",
        legacyGrowthKey = "debuffGrowth",
        defaultX = 0,
        defaultY = 6,
        defaultAnchor = "TOPLEFT",
    },
}
local MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER = { "buff", "debuff" }
local MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local function MSUF_ProfileIO_AuraResetNumber(value, fallback, minValue, maxValue)
    value = tonumber(value)
    if value == nil or value ~= value then value = tonumber(fallback) or 0 end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function MSUF_ProfileIO_AuraResetRound(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function MSUF_ProfileIO_AuraResetReadRaw(primary, secondary, key)
    local value = type(primary) == "table" and primary[key] or nil
    if value ~= nil then return value end
    return type(secondary) == "table" and secondary[key] or nil
end

local function MSUF_ProfileIO_AuraResetGrowthParts(growth, rowWrap)
    growth = tostring(growth or "RIGHT")
    rowWrap = tostring(rowWrap or "DOWN")
    if growth == "LEFTUP" then return -1, 1, false end
    if growth == "LEFTDOWN" then return -1, -1, false end
    if growth == "RIGHTUP" then return 1, 1, false end
    if growth == "RIGHTDOWN" then return 1, -1, false end
    if growth == "LEFT" then return -1, rowWrap == "UP" and 1 or -1, false end
    if growth == "UP" then return 1, 1, true end
    if growth == "DOWN" then return 1, -1, true end
    return 1, rowWrap == "UP" and 1 or -1, false
end

local function MSUF_ProfileIO_AuraResetGridShape(maxCount, perRow, verticalGrowth)
    maxCount = MSUF_ProfileIO_AuraResetRound(maxCount)
    perRow = math.max(MSUF_ProfileIO_AuraResetRound(perRow), 1)
    if maxCount <= 0 then return 1, 1 end
    if verticalGrowth then return 1, maxCount end
    return math.min(perRow, maxCount), math.floor((maxCount + perRow - 1) / perRow)
end

local function MSUF_ProfileIO_AuraResetAnchor(value, fallback)
    if type(value) == "string" and MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS[value] then
        return value
    end
    return fallback
end

--- Reproduce the current Auras3 compiler's effective layout on the profile
--- translation cold path. No runtime module is loaded or called here: this is
--- only used once to preserve the visible first icon while the rest of the old
--- Aura tree is discarded.
local function MSUF_ProfileIO_AuraResetA3LaneMetrics(auras, unit, kind, sizeOverride)
    local spec = MSUF_PROFILEIO_UNIT_AURA_RESET_LANES[kind]
    local rootShared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or {}
    local perUnit = type(auras) == "table" and type(auras.perUnit) == "table" and auras.perUnit or nil
    local unitCfg = perUnit and type(perUnit[unit]) == "table" and perUnit[unit] or nil
    local layout = unitCfg and unitCfg.overrideLayout == true and type(unitCfg.layout) == "table"
        and unitCfg.layout or nil
    local layoutShared = unitCfg and unitCfg.overrideSharedLayout == true
        and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or nil

    local function LayoutRaw(key)
        return MSUF_ProfileIO_AuraResetReadRaw(layout, rootShared, key)
    end
    local function SharedRaw(key)
        return MSUF_ProfileIO_AuraResetReadRaw(layoutShared, rootShared, key)
    end

    local sizeRaw = LayoutRaw(spec.sizeKey)
    if sizeRaw == nil then sizeRaw = LayoutRaw("iconSize") end
    local size = MSUF_ProfileIO_AuraResetNumber(
        sizeOverride ~= nil and sizeOverride or sizeRaw, 26, 1, 128)
    local genericSpacing = MSUF_ProfileIO_AuraResetNumber(LayoutRaw("spacing"), 2, 0, 64)
    local spacing = MSUF_ProfileIO_AuraResetNumber(LayoutRaw(spec.spacingKey), genericSpacing, 0, 64)
    local perRowFallback = SharedRaw("perRow")
    if perRowFallback == nil then perRowFallback = 12 end
    local perRow = MSUF_ProfileIO_AuraResetNumber(SharedRaw(spec.perRowKey), perRowFallback, 1, 40)
    local maxCount = MSUF_ProfileIO_AuraResetNumber(SharedRaw(spec.maxKey), 12, 0, 80)
    local growth = SharedRaw(spec.growthKey)
    if growth == nil then growth = SharedRaw("growth") end
    if growth == nil then growth = "RIGHT" end
    local rowWrap = SharedRaw(spec.wrapKey)
    if rowWrap == nil then rowWrap = SharedRaw("rowWrap") end
    if rowWrap == nil then rowWrap = "DOWN" end
    local xSign, ySign, verticalGrowth = MSUF_ProfileIO_AuraResetGrowthParts(growth, rowWrap)
    local cols, rows = MSUF_ProfileIO_AuraResetGridShape(maxCount, perRow, verticalGrowth)

    local styleActive = false
    if unitCfg then
        if unitCfg.overrideStyle ~= nil then
            styleActive = unitCfg.overrideStyle == true
        elseif layout and layout.stylePadding ~= nil then
            -- stylePadding itself is a Style-layout key, so its presence is
            -- sufficient to activate legacy nil-gate style ownership.
            styleActive = true
        end
    end
    local paddingRaw = styleActive and layout and layout.stylePadding or rootShared.stylePadding
    local padding = MSUF_ProfileIO_AuraResetRound(
        MSUF_ProfileIO_AuraResetNumber(paddingRaw, 0, 0, 16))
    local width = math.max(1, cols * size + math.max(cols - 1, 0) * spacing + 2 * padding)
    local height = math.max(1, rows * size + math.max(rows - 1, 0) * spacing + 2 * padding)
    local x = MSUF_ProfileIO_AuraResetRound(
        MSUF_ProfileIO_AuraResetNumber(LayoutRaw(spec.xKey), spec.defaultX, -4096, 4096))
    local y = MSUF_ProfileIO_AuraResetRound(
        MSUF_ProfileIO_AuraResetNumber(LayoutRaw(spec.yKey), spec.defaultY, -4096, 4096))
    local anchor = MSUF_ProfileIO_AuraResetAnchor(LayoutRaw(spec.anchorKey), spec.defaultAnchor)
    return {
        size = size,
        spacing = spacing,
        width = width,
        height = height,
        padding = padding,
        xSign = xSign,
        ySign = ySign,
        x = x,
        y = y,
        anchor = anchor,
    }
end

local function MSUF_ProfileIO_AuraResetFirstOffset(metrics, anchor)
    local anchorParts = MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS[anchor]
        or MSUF_PROFILEIO_UNIT_AURA_RESET_ANCHORS.CENTER
    local ax, ay = anchorParts[1], anchorParts[2]
    local ix = metrics.xSign < 0 and 1 or 0
    local iy = metrics.ySign > 0 and 0 or 1
    local dx = (ix - ax) * metrics.width + metrics.padding * metrics.xSign - ix * metrics.size
    local dy = (iy - ay) * metrics.height + metrics.padding * metrics.ySign - iy * metrics.size
    return dx, dy
end

local function MSUF_ProfileIO_AuraResetSnapshotA3(auras)
    local snapshots = {}
    for i = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS do
        local unit = MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[i]
        local unitSnapshot = {}
        snapshots[unit] = unitSnapshot
        for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
            local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
            local metrics = MSUF_ProfileIO_AuraResetA3LaneMetrics(auras, unit, kind)
            local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(metrics, metrics.anchor)
            unitSnapshot[kind] = {
                size = metrics.size,
                anchor = metrics.anchor,
                firstX = metrics.x + dx,
                firstY = metrics.y + dy,
            }
        end
    end
    return snapshots
end

local MSUF_PROFILEIO_A2_VALID_GROWTH = { RIGHT = true, LEFT = true, UP = true, DOWN = true }
local function MSUF_ProfileIO_AuraResetSnapshotA2(auras)
    local snapshots = {}
    local shared = type(auras) == "table" and type(auras.shared) == "table" and auras.shared or {}
    local perUnit = type(auras) == "table" and type(auras.perUnit) == "table" and auras.perUnit or nil
    for i = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS do
        local unit = MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[i]
        local unitCfg = perUnit and type(perUnit[unit]) == "table" and perUnit[unit] or nil
        local layout = unitCfg and unitCfg.overrideLayout == true and type(unitCfg.layout) == "table"
            and unitCfg.layout or nil
        local layoutShared = unitCfg and unitCfg.overrideSharedLayout == true
            and type(unitCfg.layoutShared) == "table" and unitCfg.layoutShared or nil
        local baseX = type(shared.offsetX) == "number" and shared.offsetX or 0
        local baseY = type(shared.offsetY) == "number" and shared.offsetY or 6
        if layout and type(layout.offsetX) == "number" then baseX = layout.offsetX end
        if layout and type(layout.offsetY) == "number" then baseY = layout.offsetY end

        local function GroupOffset(key)
            local value = layout and layout[key] ~= nil and layout[key] or shared[key]
            return MSUF_ProfileIO_AuraResetRound(
                MSUF_ProfileIO_AuraResetNumber(value, 0, -2000, 2000))
        end
        local function ValidGrowth(tbl, key)
            local value = type(tbl) == "table" and tbl[key] or nil
            return MSUF_PROFILEIO_A2_VALID_GROWTH[value] and value or nil
        end
        local sharedGenericGrowth = ValidGrowth(shared, "growth") or "RIGHT"
        local localGenericGrowth = ValidGrowth(layoutShared, "growth")
        local unitSnapshot = {}
        snapshots[unit] = unitSnapshot
        for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
            local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
            local spec = MSUF_PROFILEIO_UNIT_AURA_RESET_LANES[kind]
            local size = type(shared.iconSize) == "number" and shared.iconSize or 26
            if layout and type(layout.iconSize) == "number" and layout.iconSize > 1 then
                size = layout.iconSize
            end
            if type(shared[spec.sizeKey]) == "number" and shared[spec.sizeKey] > 1 then
                size = shared[spec.sizeKey]
            end
            if layout and type(layout[spec.sizeKey]) == "number" and layout[spec.sizeKey] > 1 then
                size = layout[spec.sizeKey]
            end
            size = MSUF_ProfileIO_AuraResetNumber(size, 26, 1, 128)
            local growth = ValidGrowth(layoutShared, spec.legacyGrowthKey)
                or ValidGrowth(shared, spec.legacyGrowthKey)
                or localGenericGrowth
                or sharedGenericGrowth
            local rx = baseX + GroupOffset(spec.xKey)
            local ry = baseY + GroupOffset(spec.yKey)
            local ix = growth == "LEFT" and 1 or 0
            local iy = growth == "DOWN" and 1 or 0
            unitSnapshot[kind] = {
                size = size,
                anchor = "TOPLEFT",
                firstX = rx + ix * (1 - size),
                firstY = ry + iy * (1 - size),
            }
        end
    end
    return snapshots
end

local function MSUF_ProfileIO_AuraResetRebaseLane(cleanAuras, unit, kind, snapshot)
    local target = MSUF_ProfileIO_AuraResetA3LaneMetrics(cleanAuras, unit, kind, snapshot.size)
    local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(target, snapshot.anchor)
    return {
        size = snapshot.size,
        anchor = snapshot.anchor,
        x = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetRound(snapshot.firstX - dx))),
        y = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetRound(snapshot.firstY - dy))),
    }
end

local function MSUF_ProfileIO_AuraResetWriteLane(layout, kind, geometry)
    local spec = MSUF_PROFILEIO_UNIT_AURA_RESET_LANES[kind]
    layout[spec.sizeKey] = geometry.size
    layout[spec.anchorKey] = geometry.anchor
    layout[spec.xKey] = geometry.x
    layout[spec.yKey] = geometry.y
end

local function MSUF_ProfileIO_AuraResetSnapshotMatches(cleanAuras, unit, kind, desired)
    local metrics = MSUF_ProfileIO_AuraResetA3LaneMetrics(cleanAuras, unit, kind)
    local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(metrics, metrics.anchor)
    return math.abs(metrics.size - desired.size) < 0.0001
        and metrics.anchor == desired.anchor
        and math.abs((metrics.x + dx) - desired.firstX) <= 0.51
        and math.abs((metrics.y + dy) - desired.firstY) <= 0.51
end

local function MSUF_ProfileIO_ResetUnitAuras(profile)
    if type(profile) ~= "table" then return false end
    local sourceA3 = type(profile.auras3) == "table" and profile.auras3 or nil
    if sourceA3 and next(sourceA3) == nil and type(profile.auras2) == "table" then
        -- A few hybrid beta/import payloads carried an empty Auras3 placeholder
        -- beside the still-live Aura2 tree. Match the old EnsureDB fallback so
        -- its position/size source is not discarded merely by that placeholder.
        sourceA3 = nil
    end
    if MSUF_ProfileIO_HasCanonicalUnitAuraBaseline(sourceA3) then
        local changed = false
        if profile.auras ~= nil then profile.auras, changed = nil, true end
        if profile.auras2 ~= nil then profile.auras2, changed = nil, true end
        return changed
    end
    local sourceA2 = not sourceA3 and type(profile.auras2) == "table" and profile.auras2 or nil
    if not sourceA3 and not sourceA2 and profile.auras == nil then return false end

    local snapshots = sourceA3 and MSUF_ProfileIO_AuraResetSnapshotA3(sourceA3)
        or sourceA2 and MSUF_ProfileIO_AuraResetSnapshotA2(sourceA2) or nil
    local createCanonical = (type(MSUF) == "table" and MSUF.MSUF_CreateCanonicalUnitAuras)
        or _G.MSUF_CreateCanonicalUnitAuras
    local cleanAuras = createCanonical()
    if type(cleanAuras) ~= "table" then
        -- Never destroy the old data if the Defaults-owned factory is missing.
        -- The absent revision keeps this profile eligible for a retry.
        return false
    end
    cleanAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY] = MSUF_PROFILEIO_UNIT_AURA_RESET_BASELINE_REVISION

    if snapshots then
        local shared = type(cleanAuras.shared) == "table" and cleanAuras.shared or {}
        cleanAuras.shared = shared
        local playerSnapshot = snapshots.player
        if playerSnapshot then
            for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
                local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
                MSUF_ProfileIO_AuraResetWriteLane(shared, kind,
                    MSUF_ProfileIO_AuraResetRebaseLane(cleanAuras, "player", kind, playerSnapshot[kind]))
            end
        end

        local perUnit = type(cleanAuras.perUnit) == "table" and cleanAuras.perUnit or {}
        cleanAuras.perUnit = perUnit
        for i = 2, #MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS do
            local unit = MSUF_PROFILEIO_UNIT_AURA_RESET_UNITS[i]
            local desired = snapshots[unit]
            if desired then
                local unitCfg = type(perUnit[unit]) == "table" and perUnit[unit] or {}
                perUnit[unit] = unitCfg
                local needsLocal = unitCfg.overrideLayout == true
                for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
                    local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
                    needsLocal = needsLocal
                        or not MSUF_ProfileIO_AuraResetSnapshotMatches(cleanAuras, unit, kind, desired[kind])
                end
                if needsLocal then
                    if unitCfg.overrideLayout ~= true then unitCfg.layout = {} end
                    local layout = type(unitCfg.layout) == "table" and unitCfg.layout or {}
                    unitCfg.layout = layout
                    unitCfg.overrideLayout = true
                    for j = 1, #MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER do
                        local kind = MSUF_PROFILEIO_UNIT_AURA_RESET_LANE_ORDER[j]
                        MSUF_ProfileIO_AuraResetWriteLane(layout, kind,
                            MSUF_ProfileIO_AuraResetRebaseLane(cleanAuras, unit, kind, desired[kind]))
                    end
                end
            end
        end
    end

    profile.auras3 = cleanAuras
    profile.auras = nil
    profile.auras2 = nil
    return true
end

local MSUF_PROFILEIO_GROUP_AURA_RESET_LANES = {
    buff = {
        groupKey = "buff", defaultSizeParty = 22, defaultSizeRaid = 16,
        defaultMax = 4, defaultPerRow = 4, defaultGrowth = "LEFTUP", defaultAnchor = "BOTTOMRIGHT",
    },
    debuff = {
        groupKey = "debuff", defaultSizeParty = 20, defaultSizeRaid = 16,
        defaultMax = 4, defaultPerRow = 3, defaultGrowth = "RIGHTDOWN", defaultAnchor = "TOPLEFT",
    },
    externals = {
        groupKey = "externals", defaultSizeParty = 28, defaultSizeRaid = 22,
        defaultMax = 2, defaultPerRow = 3, defaultGrowth = "RIGHTDOWN", defaultAnchor = "CENTER",
    },
}
local MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER = { "buff", "debuff", "externals" }
local MSUF_PROFILEIO_GROUP_AURA_RETIRED_FLAT_KEYS = {
    "aurasEnabled", "auraMaxIcons", "auraIconSize", "auraAnchor",
    "auraGrowthX", "auraGrowthY", "auraSpacing", "auraPerRow",
    "privateAurasEnabled", "privateAuraMax", "privateAuraSize",
    "privateAuraAnchor", "privateAuraX", "privateAuraY", "privateAuraCountdown",
}

local function MSUF_ProfileIO_ClearRetiredGroupAuraFields(conf)
    local changed = false
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_RETIRED_FLAT_KEYS do
        local key = MSUF_PROFILEIO_GROUP_AURA_RETIRED_FLAT_KEYS[i]
        if conf[key] ~= nil then conf[key], changed = nil, true end
    end
    if conf._auraMigV2 ~= nil then conf._auraMigV2, changed = nil, true end
    return changed
end

local function MSUF_ProfileIO_AuraResetGroupRound(value)
    value = tonumber(value) or 0
    if value >= 0 then return math.floor(value + 0.5) end
    return -math.floor((-value) + 0.5)
end

--- Dynamic Group Aura scaling never persisted the roster count that selected
--- its 1.00/0.85/0.70 factor. Capture the live count once on this cold
--- translation path, using the same API and thresholds as the current Group
--- compiler. Missing/invalid API data deliberately resolves to zero.
local function MSUF_ProfileIO_AuraResetCurrentGroupCount()
    local getter = _G.GetNumGroupMembers
    if type(getter) ~= "function" then return 0 end
    local value = getter()

    value = tonumber(value)
    if value == nil or value ~= value then return 0 end
    value = math.floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 40 then return 40 end
    return value
end

local function MSUF_ProfileIO_AuraResetGroupDynamicScale(root, groupCount)
    if not (type(root) == "table" and root.dynamicScale == true) then return 1 end
    groupCount = MSUF_ProfileIO_AuraResetNumber(groupCount, 0, 0, 40)
    if groupCount <= 15 then return 1 end
    if groupCount <= 25 then return 0.85 end
    return 0.70
end

--- Matches Group Config's SplitAuraGrowth exactly. Values such as a bare
--- LEFT were never a distinct Group mode and therefore rendered RIGHT/DOWN.
local function MSUF_ProfileIO_AuraResetGroupGrowth(value, fallback)
    value = value or fallback or "RIGHTDOWN"
    if value == "LEFTUP" then return "LEFTUP" end
    if value == "LEFTDOWN" then return "LEFTDOWN" end
    if value == "RIGHTUP" then return "RIGHTUP" end
    if value == "UP" then return "UP" end
    if value == "DOWN" then return "DOWN" end
    return "RIGHTDOWN"
end

local function MSUF_ProfileIO_AuraResetGroupLaneMetrics(conf, laneName, sizeOverride, groupCount)
    local spec = MSUF_PROFILEIO_GROUP_AURA_RESET_LANES[laneName]
    local root = type(conf) == "table" and type(conf.auras) == "table" and conf.auras or {}
    local group = type(root[spec.groupKey]) == "table" and root[spec.groupKey] or {}
    local isRaid = conf and conf._msufAuraResetScope ~= "gf_party"
    local defaultSize = isRaid and spec.defaultSizeRaid or spec.defaultSizeParty
    local dynamicScale = MSUF_ProfileIO_AuraResetGroupDynamicScale(root, groupCount)
    local iconScale = MSUF_ProfileIO_AuraResetNumber(group.iconScale, 100, 20, 300) / 100
    local rawSize = sizeOverride ~= nil and sizeOverride
        or (MSUF_ProfileIO_AuraResetNumber(group.size, defaultSize) * iconScale)
    rawSize = rawSize * dynamicScale
    local size = MSUF_ProfileIO_AuraResetNumber(
        MSUF_ProfileIO_AuraResetGroupRound(rawSize), defaultSize,
        1, 256)
    local spacing = MSUF_ProfileIO_AuraResetNumber(group.spacing, 1, 0, 64)
    spacing = MSUF_ProfileIO_AuraResetNumber(
        MSUF_ProfileIO_AuraResetGroupRound(spacing * dynamicScale), 1, 0, 64)
    local maxCount = MSUF_ProfileIO_AuraResetNumber(group.max,
        laneName == "externals" and 2 or MSUF_ProfileIO_AuraResetNumber(conf and conf.auraMaxIcons, spec.defaultMax),
        0, 80)
    local perRow = MSUF_ProfileIO_AuraResetNumber(group.perRow, spec.defaultPerRow, 1, 40)
    local growth = MSUF_ProfileIO_AuraResetGroupGrowth(group.growth, spec.defaultGrowth)
    local xSign, ySign, verticalGrowth = MSUF_ProfileIO_AuraResetGrowthParts(growth, "DOWN")
    local cols, rows = MSUF_ProfileIO_AuraResetGridShape(maxCount, perRow, verticalGrowth)
    local anchor = MSUF_ProfileIO_AuraResetAnchor(group.anchor, spec.defaultAnchor)
    return {
        size = size,
        spacing = spacing,
        width = math.max(1, cols * size + math.max(cols - 1, 0) * spacing),
        height = math.max(1, rows * size + math.max(rows - 1, 0) * spacing),
        padding = 0,
        xSign = xSign,
        ySign = ySign,
        x = MSUF_ProfileIO_AuraResetGroupRound((tonumber(group.x) or 0) * dynamicScale),
        y = MSUF_ProfileIO_AuraResetGroupRound((tonumber(group.y) or 0) * dynamicScale),
        anchor = anchor,
    }
end

local function MSUF_ProfileIO_AuraResetSnapshotGroup(conf, scope, groupCount)
    if type(conf) ~= "table" then return nil end
    if type(conf.auras) ~= "table" then return nil end
    local proxy = { auras = conf.auras, auraMaxIcons = conf.auraMaxIcons, _msufAuraResetScope = scope }
    local snapshot = {}
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER do
        local laneName = MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER[i]
        local metrics = MSUF_ProfileIO_AuraResetGroupLaneMetrics(proxy, laneName, nil, groupCount)
        local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(metrics, metrics.anchor)
        snapshot[laneName] = {
            size = metrics.size,
            anchor = metrics.anchor,
            firstX = metrics.x + dx,
            firstY = metrics.y + dy,
        }
    end
    return snapshot
end

local function MSUF_ProfileIO_AuraResetRebaseGroupLane(state, scope, laneName, snapshot)
    local proxy = { auras = state.auras, _msufAuraResetScope = scope }
    local target = MSUF_ProfileIO_AuraResetGroupLaneMetrics(proxy, laneName, snapshot.size)
    local dx, dy = MSUF_ProfileIO_AuraResetFirstOffset(target, snapshot.anchor)
    return {
        size = snapshot.size,
        anchor = snapshot.anchor,
        x = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetGroupRound(snapshot.firstX - dx))),
        y = math.max(-4096, math.min(4096,
            MSUF_ProfileIO_AuraResetGroupRound(snapshot.firstY - dy))),
    }
end

local function MSUF_ProfileIO_ResetGroupAuras(profile, groupCount)
    if type(profile) ~= "table" then return false end
    local createCanonical = (type(MSUF) == "table" and MSUF.MSUF_CreateCanonicalGroupAuraState)
        or _G.MSUF_CreateCanonicalGroupAuraState
    local canonical
    local changed = false
    for i = 1, #MSUF_PROFILEIO_GROUP_AURA_SCOPES do
        local scope = MSUF_PROFILEIO_GROUP_AURA_SCOPES[i]
        local conf = profile[scope]
        if type(conf) == "table" then
            local sourceAuras = type(conf.auras) == "table" and conf.auras or nil
            local hasAuraPayload = MSUF.ProfileIOGroupHasAuraPayload(conf)
            if hasAuraPayload and (not sourceAuras
                or tonumber(sourceAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) ~= MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION) then
                if groupCount == nil and sourceAuras and sourceAuras.dynamicScale == true then
                    groupCount = MSUF_ProfileIO_AuraResetCurrentGroupCount()
                end
                local snapshot = MSUF_ProfileIO_AuraResetSnapshotGroup(conf, scope, groupCount)
                if canonical == nil then
                    local value = createCanonical(true)
                    if type(value) == "table" then canonical = value else canonical = false end
                end
                local state = canonical and canonical[scope]
                if type(state) == "table" and type(state.auras) == "table" then
                    if snapshot then
                        for j = 1, #MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER do
                            local laneName = MSUF_PROFILEIO_GROUP_AURA_RESET_LANE_ORDER[j]
                            local laneSnapshot = snapshot[laneName]
                            if laneSnapshot then
                                local group = type(state.auras[laneName]) == "table" and state.auras[laneName] or {}
                                state.auras[laneName] = group
                                if laneSnapshot.sizeOnly == true then
                                    group.size = laneSnapshot.size
                                else
                                    local geometry = MSUF_ProfileIO_AuraResetRebaseGroupLane(
                                        state, scope, laneName, laneSnapshot)
                                    group.size = geometry.size
                                    group.anchor = geometry.anchor
                                    group.x = geometry.x
                                    group.y = geometry.y
                                end
                            end
                        end
                    end
                    conf.auras = MSUF_DeepCopy(state.auras)
                    conf.privateAuras = type(state.privateAuras) == "table"
                        and MSUF_DeepCopy(state.privateAuras) or nil
                    conf.spellIndicators = type(state.spellIndicators) == "table"
                        and MSUF_DeepCopy(state.spellIndicators) or nil
                    MSUF_ProfileIO_ClearRetiredGroupAuraFields(conf)
                    changed = true
                end
            elseif sourceAuras
                and tonumber(sourceAuras[MSUF_PROFILEIO_UNIT_AURA_MODEL_KEY]) == MSUF_PROFILEIO_GROUP_AURA_MODEL_REVISION then
                changed = MSUF_ProfileIO_ClearRetiredGroupAuraFields(conf) or changed
            end
        end
    end
    return changed
end

MSUF_PROFILEIO_AURA_RESETTERS.ResetUnit = MSUF_ProfileIO_ResetUnitAuras
MSUF_PROFILEIO_AURA_RESETTERS.ResetGroup = MSUF_ProfileIO_ResetGroupAuras
end

local function MSUF_ProfileIO_NormalizeProfileAuras(profile)
    if type(profile) ~= "table" then return false end
    local changed = MSUF_PROFILEIO_AURA_RESETTERS.ResetUnit(profile)
    changed = MSUF_PROFILEIO_AURA_RESETTERS.ResetGroup(profile) or changed
    local auras = profile.auras3
    if type(auras) ~= "table" then return changed end
    local repairAuraOverrides = MSUF_ProfileIO_AuraOverridesNeedRepair(profile)
    changed = StateHelpers.NormalizeAuraLayoutTable(auras.shared, StateHelpers.ProfileIOSpec) or changed
    if type(auras.perUnit) == "table" then
        for _, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                changed = StateHelpers.NormalizeAuraLayoutTable(unitCfg.layout, StateHelpers.ProfileIOSpec) or changed
                changed = StateHelpers.NormalizeAuraLayoutTable(unitCfg.layoutShared, StateHelpers.ProfileIOSpec) or changed
                if repairAuraOverrides then
                    if StateHelpers.TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout == nil then
                        unitCfg.overrideLayout = true
                        changed = true
                    end
                    if StateHelpers.TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout == nil then
                        unitCfg.overrideSharedLayout = true
                        changed = true
                    end
                end
            end
        end
    end
    return changed
end

--- Profile-side alias normalization pipeline (see the cross-reference note
--- above MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION for its Defaults twin).
MSUF_ProfileIO_TranslateProfileToCurrent = function(profile, context)
    if type(profile) ~= "table" then return profile, false end
    context = type(context) == "table" and context or {}
    --- Only internal callers operating on an already-stored profile may trust
    --- the persisted marker. Import payloads are deliberately never trusted:
    --- an external table can contain copied/spoofed internal metadata and must
    --- still receive the complete schema-600 normalization pass.
    if context.trustNormalizationMarker == true
        and tonumber(profile._msufProfileSchema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and tonumber(profile._msufProfileNormalizationRevision) == MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION
        and type(profile.general) == "table"
        and not MSUF_ProfileIO_ProfileNeedsNormalization(profile) then
        return profile, false
    end
    local changed = false
    --- trustProfileMetadata: a local pass over a stored or factory profile (the
    --- defaults pass). It still runs every normalizer below, but the profile's
    --- own migration stamps and Menu2 choices are not import metadata.
    if context.trustNormalizationMarker ~= true and context.trustProfileMetadata ~= true then
        --- Defaults migrations have their own fast-path markers. Drop them on
        --- untrusted payloads so a later EnsureDB cannot be tricked into
        --- skipping validation by metadata copied from an exported profile.
        if profile._msufDefaultsRevision ~= nil then
            profile._msufDefaultsRevision = nil
            changed = true
        end
        --- The dispel priority stamp is the payload's portable data-format
        --- version, not a fast-path marker: dropping it re-ran the one-time
        --- TOP -> ALL lift on every import of a current profile. Migrate the
        --- payload from its own version now; the forced run still repeats
        --- every idempotent normalization, so a copied stamp skips nothing
        --- but the lift.
        if profile._msufDispelPriorityMigration ~= nil then
            MSUF.Require("MSUF_MigrateDispelPriorityProfile", "State/MSUF_ProfileNormalize.lua")(profile, true)
            changed = true
        end
        --- Navigation icons are the supported Menu2 baseline for imports.
        --- Normalize the payload itself so full and Unit Frame imports cannot
        --- restore an older explicit false value before the final EnsureDB.
        if type(profile.general) == "table" and profile.general.showNavigationIcons ~= true then
            profile.general.showNavigationIcons = true
            changed = true
        end
    end
    MSUF_ProfileIO_NormalizeImportedFontSizes(profile)
    if context.normalizePositions ~= false then
        local _, aliasesChanged = MSUF_ProfileIO_NormalizeUnitFramePositionDB(profile, false)
        changed = aliasesChanged or changed
    end
    changed = MSUF_ProfileIO_NormalizeLegacyRootNameShortening(profile, context.createGeneral ~= false) or changed
    if type(profile.general) == "table" and profile.general.fontBaselineOffset == nil then
        profile.general.fontBaselineOffset = 0
        changed = true
    end
    for i = 1, #MSUF_PROFILEIO_TEXT_SCOPE_KEYS do
        local key = MSUF_PROFILEIO_TEXT_SCOPE_KEYS[i]
        local scope = profile[key]
        if type(scope) == "table" then
            local isGroupScope = key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid"
            local inferFontOverride = key ~= "general"
            changed = StateHelpers.NormalizeTextScope(scope, isGroupScope, StateHelpers.ProfileIOSpec, inferFontOverride) or changed
            changed = StateHelpers.NormalizeStatusScope(scope, isGroupScope, StateHelpers.ProfileIOSpec) or changed
        end
    end
    changed = StateHelpers.MigrateSplitStatusText(profile, MSUF_PROFILEIO_TEXT_SCOPE_KEYS) or changed
    changed = MSUF_ProfileIO_NormalizeProfileAuras(profile) or changed
    changed = MSUF_ProfileIO_NormalizeGFAuraFilterTokens(profile, true) or changed
    local normalizeLayers = _G.MSUF_NormalizeNumericLayers
    if type(normalizeLayers) ~= "function" and type(MSUF) == "table" then
        normalizeLayers = MSUF.MSUF_NormalizeNumericLayers
    end
    if type(normalizeLayers) == "function" then
        changed = normalizeLayers(profile) or changed
    end
    if context.markProfile ~= false then
        if profile._msufProfileSchema ~= MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
            profile._msufProfileSchema = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
            changed = true
        end
        if profile._msufProfileNormalizationRevision ~= MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION then
            profile._msufProfileNormalizationRevision = MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION
            changed = true
        end
    end
    return profile, changed
end

MSUF_ProfileIO_TranslateProfilesToCurrent = function(profiles, source)
    if type(profiles) ~= "table" then return false end
    local changed = false
    for _, profile in pairs(profiles) do
        if type(profile) == "table" then
            local _, profileChanged = MSUF_ProfileIO_TranslateProfileToCurrent(profile, {
                source = source or "profiles",
                markProfile = true,
                trustNormalizationMarker = true,
            })
            changed = profileChanged or changed
            MSUF_ProfileIO_EnsureProfileMenuDefaults(profile)
        end
    end
    return changed
end

MSUF.ProfileNormalize = {
    CURRENT_PROFILE_SCHEMA = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
    UNIT_KEYS = MSUF_PROFILEIO_UNIT_KEYS,
    DeepCopy = MSUF_DeepCopy,
    EnsureProfileMenuDefaults = MSUF_ProfileIO_EnsureProfileMenuDefaults,
    NormalizeImportedFontSizes = MSUF_ProfileIO_NormalizeImportedFontSizes,
    NormalizeGFAuraFilterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken,
    TranslateProfileToCurrent = MSUF_ProfileIO_TranslateProfileToCurrent,
    TranslateProfilesToCurrent = MSUF_ProfileIO_TranslateProfilesToCurrent,
}
