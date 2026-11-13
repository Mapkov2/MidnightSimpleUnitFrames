-- Profile payload validation, category ownership and Wago compatibility projection.
local _, MSUF = ...
local Parts = MSUF.ProfilesParts
local MSUF_PROFILE_IMPORT_LIMITS = Parts.MSUF_PROFILE_IMPORT_LIMITS
local MSUF_ProfileIO_RunEnsureDB = Parts.MSUF_ProfileIO_RunEnsureDB
local Normalize = Parts.Normalize
local StateHelpers = Parts.StateHelpers
local function MSUF_WipeTable(t)
    if not t then  return end
    for k in pairs(t) do
        t[k] = nil
    end
 end
local MSUF_DeepCopy = Normalize.DeepCopy

MSUF.ProfileIOValidateImportValue = function(root)
    local seen, nodes, stringBytes = {}, 0, 0
    local function Walk(value, depth)
        nodes = nodes + 1
        if nodes > MSUF_PROFILE_IMPORT_LIMITS.nodes then return false, "profile has too many values" end
        local valueType = type(value)
        if valueType == "string" then
            stringBytes = stringBytes + #value
            if stringBytes > MSUF_PROFILE_IMPORT_LIMITS.decodedBytes then return false, "profile strings are too large" end
            return true
        end
        if valueType == "number" then
            if value ~= value or value == math.huge or value == -math.huge then return false, "profile contains an invalid number" end
            return true
        end
        if valueType == "nil" or valueType == "boolean" then return true end
        -- The template and the type name ride along, so the chat line translates the sentence first.
        if valueType ~= "table" then return false, "profile contains unsupported " .. valueType, "profile contains unsupported %s", valueType end
        if depth > MSUF_PROFILE_IMPORT_LIMITS.depth then return false, "profile is too deep" end
        if seen[value] then return false, "profile contains a cyclic or shared table" end
        seen[value] = true
        for key, child in pairs(value) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then return false, "profile contains an unsupported table key" end
            local ok, why, template, inserted = Walk(key, depth + 1)
            if not ok then return false, why, template, inserted end
            ok, why, template, inserted = Walk(child, depth + 1)
            if not ok then return false, why, template, inserted end
        end
        return true
    end
    if type(root) ~= "table" then return false, "profile is not a table" end
    return Walk(root, 1)
end

local MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = Normalize.CURRENT_PROFILE_SCHEMA
local MSUF_PROFILEIO_UNIT_KEYS = Normalize.UNIT_KEYS
local MSUF_ProfileIO_NormalizeImportedFontSizes = Normalize.NormalizeImportedFontSizes
local MSUF_ProfileIO_NormalizeGFAuraFilterToken = Normalize.NormalizeGFAuraFilterToken

--- Deterministic-ish Lua serializer (good enough for UI copy/paste strings).

--- Key ownership for general settings lives in one registry
--- (State/MSUF_ProfileFields.lua, F.GeneralOwner): partial exports and imports
--- carry exactly the keys their kind owns, and profile sync asks the same owner.
local function MSUF_GeneralKeysOfKind(kind)
    local fields = MSUF.ProfileFields
    return function(key) return fields.GeneralKeyInKind(key, kind) end
end
--- Aura colour keys in general (owner auraColors in the registry); an import
--- that carries one refreshes every aura scope.
local MSUF_AURA_GENERAL_KEYS = {
aurasOwnBuffHighlightColor = true,
    aurasOwnDebuffHighlightColor = true,
    aurasStackCountColor = true,
}
-- Unified, coldpath alpha keys: HP fill opacity, power fill opacity, background
-- opacity, and opt-in exclusions for informational elements. They are unit
-- frame settings, not colours (the registry declares them unitframes).
local MSUF_UNITFRAME_ALPHA_KEYS = {
    hpBarAlpha = true,
    powerBarAlpha = true,
    hpBgAlpha = true,
    powerBarBgAlpha = true,
    alphaExcludeTextPortrait = true,
    alphaExcludePredictionBars = true,
}
local MSUF_UNITFRAME_ALPHA_DEFAULTS = {
    hpBarAlpha = 1,
    powerBarAlpha = 1,
    hpBgAlpha = 0.85,
    powerBarBgAlpha = 0.85,
    alphaExcludeTextPortrait = false,
    alphaExcludePredictionBars = false,
}
local MSUF_UNITFRAME_UNIT_KEYS = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local function MSUF_CopyGeneralSubset(filterFn, profile)
    local out = {}
    local g = ((profile or MSUF_DB) and (profile or MSUF_DB).general) or {}
    for k, v in pairs(g) do
        if filterFn(k, v) then
            out[k] = MSUF_DeepCopy(v)
        end
    end
     return out
end
--- db is the profile table an import stages into (never nil).
local function MSUF_WipeGeneralSubset(filterFn, db)
    if type(db.general) ~= "table" then
        db.general = {}
    end
    local g = db.general
    for k in pairs(g) do
        if filterFn(k, g[k]) then
            g[k] = nil
        end
    end
 end
--- Only the keys the import kind owns land: a payload that carries more (an
--- export from a build that guessed ownership by name) cannot overwrite keys
--- another kind or the receiving profile owns.
local function MSUF_ApplyGeneralSubset(tbl, db, filterFn)
    if not tbl then  return end
    if type(db.general) ~= "table" then
        db.general = {}
    end
    local g = db.general
    for k, v in pairs(tbl) do
        if filterFn(k, v) then
            g[k] = MSUF_DeepCopy(v)
        end
    end
 end
--- Legacy combat/layered alpha keys retired by the unified alpha rewrite. Imported
--- profiles may still carry them; strip them so they never resurrect the old model.
local MSUF_UNITFRAME_LEGACY_ALPHA_KEYS = {
    "alphaInCombat", "alphaOutOfCombat", "alphaSync", "alphaSyncBoth", "alphaLayerMode",
    "alphaFGInCombat", "alphaFGOutOfCombat", "alphaBGInCombat", "alphaBGOutOfCombat",
    "alphaHPInCombat", "alphaHPOutOfCombat", "alphaPreserveHPColor", "bgA", "hpTextIgnoreAlpha",
}
local function MSUF_ProfileIO_EnsureUnitframeAlphaDB(profile)
    profile = profile or _G.MSUF_DB
    if type(profile) ~= "table" then  return end
    local function ensureAlpha(conf)
        if type(conf) ~= "table" then  return end
        for i = 1, #MSUF_UNITFRAME_LEGACY_ALPHA_KEYS do
            conf[MSUF_UNITFRAME_LEGACY_ALPHA_KEYS[i]] = nil
        end
        for k, v in pairs(MSUF_UNITFRAME_ALPHA_DEFAULTS) do
            if conf[k] == nil then
                conf[k] = v
            end
        end
    end
    for _, unitKey in ipairs(MSUF_UNITFRAME_UNIT_KEYS) do
        if type(profile[unitKey]) ~= "table" then
            profile[unitKey] = {}
        end
        ensureAlpha(profile[unitKey])
    end
 end
local function MSUF_ProfileIO_EnsureGroupFramesDB()
    local ensureGF = MSUF.PublicGlobals.MSUF_GF_EnsureDB
    if type(ensureGF) == "function" then
        ensureGF()
        return
    end
    local gf = _G.MSUF_NS and _G.MSUF_NS.GF
    if gf and type(gf.EnsureDB) == "function" then
        gf.EnsureDB()
    end
end
local function MSUF_ProfileIO_EnsureCompleteProfileDB()
    MSUF_ProfileIO_RunEnsureDB()
    MSUF_ProfileIO_EnsureUnitframeAlphaDB()
    MSUF_ProfileIO_EnsureGroupFramesDB()
    local auras = MSUF and MSUF.MSUF_Auras3
    if auras then
        if type(auras.EnsureDB) == "function" then
            auras.EnsureDB()
        end
        local aurasDB = auras.DB
        if aurasDB and type(aurasDB.Ensure) == "function" then
            aurasDB.Ensure()
        end
    end
end
--- Variant recording takes its base only after this complete pass.
MSUF.ProfileIOEnsureCompleteProfileDB = MSUF_ProfileIO_EnsureCompleteProfileDB

--- Export normalization does not try to make the live DB pretty. It creates a
--- clean payload copy, translates old aliases, and strips runtime/cache-only
--- state so copied profile strings stay portable across characters and clients.
local MSUF_GF_BLIZZARD_TYPE_DEFAULTS = {
    buffs = true,
    debuffs = true,
    dispels = true,
    externals = true,
}

local function MSUF_ProfileIO_EnsureBlizzardAuraPositionDefaults(auras)
    if type(auras) ~= "table" then return end
    if auras.blizzardContainerAnchor == nil then auras.blizzardContainerAnchor = "FRAME" end
    if auras.blizzardContainerX == nil then auras.blizzardContainerX = 0 end
    if auras.blizzardContainerY == nil then auras.blizzardContainerY = 0 end
end


local function MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, groupKey, defaultToken)
    local group = auras and auras[groupKey]
    if type(group) ~= "table" then return end

    if group.filterToken == nil then
        local fm = group.filterMode
        if fm == "RAID_PLAYER" or fm == "RAID_IN_COMBAT" or fm == "ALL_PLAYER" then
            group.filterToken = "ALL"
        elseif fm == "ALL" or fm == "PLAYER" or fm == "RAID" then
            group.filterToken = fm
        elseif fm == "NOT_PLAYER" then
            group.filterToken = "ALL"
        else
            group.filterToken = defaultToken
        end
    end
    group.filterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken(groupKey, group.filterToken)

    -- No default categories: MSUF_GF_AuraFilter.DEFAULT_BLACKLIST_BUFF/DEBUFF,
    -- which this used to copy, are gone since 6.0 alpha 1 and read as nil.
    if type(group.blacklistCats) ~= "table" then
        group.blacklistCats = {}
    end
    if group.strata == nil then group.strata = "AUTO" end
    if groupKey == "buff" and group.trackedStrata == nil then group.trackedStrata = "AUTO" end
    if group.cooldownSwipeReverse == nil then group.cooldownSwipeReverse = false end
    if type(group.blacklist) ~= "table" then group.blacklist = {} end
    if type(group.blacklist.spells) ~= "table" then group.blacklist.spells = {} end
end

local function MSUF_ProfileIO_NormalizeGroupFrameForExport(conf)
    if type(conf) ~= "table" then return end
    if type(conf.auras) ~= "table" then return end

    if MSUF.ProfileMigrations then MSUF.ProfileMigrations.SeedGroupBuffStrata(conf) end
    local auras = conf.auras
    if auras.renderer ~= "CUSTOM" and auras.renderer ~= "NATIVE_12_1" then
        auras.renderer = "NATIVE_12_1"
    end
    MSUF.StateHelpers.SeedBlizzardAuraTypes(auras, MSUF_GF_BLIZZARD_TYPE_DEFAULTS)
    MSUF_ProfileIO_EnsureBlizzardAuraPositionDefaults(auras)

    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "buff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "debuff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForExport(auras, "externals", "RAID")
end

local function MSUF_ProfileIO_NormalizeGroupFramePayloadForExport(payload)
    if type(payload) ~= "table" then return payload end
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_party)
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_raid)
    MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_mythicraid)
    return payload
end

local MSUF_PROFILEIO_WAGO_SCHEMA = 1
local MSUF_PROFILEIO_WAGO_FULL_KEY = "msuf6"
local MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS = {
    -- The dispel data-format stamps: without them an import of the portable
    -- payload runs both dispel migrations again (TOP -> ALL, By me -> Dispel type).
    _msufDispelPriorityMigration = true,
    _msufNativeDispelTriggerMigration = true,
    _msufForeverFiveSecondDefault_v1 = true,
    _msufForeverManaTickDefault_v1 = true,
    arena = true,
    profileVariants = true,
    auras2 = true,
    bars = true,
    boss = true,
    classColors = true,
    classPowerPerSpec = true,
    classPowerPresets = true,
    focus = true,
    gameplay = true,
    general = true,
    gf_mythicraid = true,
    gf_party = true,
    gf_priority = true,
    gf_raid = true,
    group = true,
    groupFrames = true,
    groupframes = true,
    npcColors = true,
    party = true,
    pet = true,
    pettarget = true,
    player = true,
    shortenNames = true,
    target = true,
    targettarget = true,
    tot = true,
}
local MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS = {
    buffGroupOffsetX = true,
    buffGroupOffsetY = true,
    debuffGroupOffsetX = true,
    debuffGroupOffsetY = true,
    buffGroupIconSize = true,
    debuffGroupIconSize = true,
    buffGrowthX = true,
    buffGrowthY = true,
    debuffGrowthX = true,
    debuffGrowthY = true,
    showCooldownText = true,
    cooldownSwipeReverse = true,
    showDurationBar = true,
    durationBarHeight = true,
    durationBarDisplay = true,
    durationBarPosition = true,
    durationBarDirection = true,
    stackTextOffsetX = true,
    stackTextOffsetY = true,
    cooldownTextAnchor = true,
    cooldownTextOffsetX = true,
    cooldownTextOffsetY = true,
    cooldownDecimalSeconds = true,
    buffAnchor = true,
    debuffAnchor = true,
    -- buffLayer/debuffLayer intentionally remain portable. Some external tools
    -- keep only this compatibility payload and omit the embedded msuf6 table.
    debuffTypeBorderMode = true,
    useDebuffTypeBorders = true,
}

local function MSUF_ProfileIO_CopyIfMissingValue(tbl, toKey, ...)
    if type(tbl) ~= "table" or tbl[toKey] ~= nil then return end
    for i = 1, select("#", ...) do
        local fromKey = select(i, ...)
        if tbl[fromKey] ~= nil then
            tbl[toKey] = MSUF_DeepCopy(tbl[fromKey])
            return
        end
    end
end

local function MSUF_ProfileIO_CopyMissingFrom(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for key, value in pairs(defaults) do
        if tbl[key] == nil then
            tbl[key] = MSUF_DeepCopy(value)
        end
    end
end

local function MSUF_ProfileIO_StripPrivateMSUFKeys(tbl, seen)
    if type(tbl) ~= "table" then return end
    seen = seen or {}
    if seen[tbl] then return end
    seen[tbl] = true
    for key, value in pairs(tbl) do
        if type(key) == "string" and key:match("^_msuf") then
            tbl[key] = nil
        elseif type(value) == "table" then
            MSUF_ProfileIO_StripPrivateMSUFKeys(value, seen)
        end
    end
end

local function MSUF_ProfileIO_NormalizeAuraFilterForWago(filter)
    if type(filter) ~= "table" then return end
    filter.onlyImportantAuras = nil
    local function normalizeGroup(group)
        if type(group) ~= "table" then return end
        group.includeNameplateOnly = nil
        group.cancelable = nil
        group.notCancelable = nil
        group.externalDefensive = nil
        group.bigDefensive = nil
        group.exclusive = nil
        group.crowdControl = nil
        if group.filterToken == nil then
            group.filterToken = "ALL"
        end
    end
    normalizeGroup(filter.buffs)
    normalizeGroup(filter.debuffs)
end

local function MSUF_ProfileIO_NormalizeAuraLayoutForWago(layout, layoutShared)
    if type(layout) ~= "table" then return end
    MSUF_ProfileIO_CopyMissingFrom(layout, layoutShared)
    MSUF_ProfileIO_CopyIfMissingValue(layout, "iconSize", "buffGroupIconSize", "debuffGroupIconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffIconSize", "buffGroupIconSize", "iconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffIconSize", "debuffGroupIconSize", "iconSize")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffOffsetX", "buffGroupOffsetX", "offsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "buffOffsetY", "buffGroupOffsetY", "offsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffOffsetX", "debuffGroupOffsetX", "offsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "debuffOffsetY", "debuffGroupOffsetY", "offsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "offsetX", "buffGroupOffsetX", "debuffGroupOffsetX")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "offsetY", "debuffGroupOffsetY", "buffGroupOffsetY")
    MSUF_ProfileIO_CopyIfMissingValue(layout, "growth", "buffGrowthX", "debuffGrowthX")
    if layout.layoutMode == "SEPARATE" then
        layout.layoutMode = "SINGLE"
    end
    for key in pairs(MSUF_PROFILEIO_WAGO_AURA_DROP_KEYS) do
        layout[key] = nil
    end
end

local function MSUF_ProfileIO_NormalizeAurasForWago(auras)
    if type(auras) ~= "table" then return end
    MSUF_ProfileIO_StripPrivateMSUFKeys(auras)
    MSUF_ProfileIO_NormalizeAuraLayoutForWago(auras.shared)
    MSUF_ProfileIO_NormalizeAuraFilterForWago(auras.shared and auras.shared.filters)
    if type(auras.perUnit) == "table" then
        for _, unit in pairs(auras.perUnit) do
            if type(unit) == "table" then
                MSUF_ProfileIO_NormalizeAuraLayoutForWago(unit.layout, unit.layoutShared)
                unit.layoutShared = nil
                unit.overrideSharedLayout = nil
                MSUF_ProfileIO_NormalizeAuraFilterForWago(unit.filters)
            end
        end
    end
end

local function MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, groupKey, defaultToken)
    local group = auras and auras[groupKey]
    if type(group) ~= "table" then return end
    if group.filterToken == nil then
        group.filterToken = defaultToken
    end
    group.filterToken = MSUF_ProfileIO_NormalizeGFAuraFilterToken(groupKey, group.filterToken)
    if type(group.blacklist) == "table" then
        group.blacklist.spells = nil
    end
    group.cooldownSwipeReverse = nil
end

local function MSUF_ProfileIO_NormalizeGroupFrameForWago(conf)
    if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
    if MSUF.ProfileMigrations then MSUF.ProfileMigrations.SeedGroupBuffStrata(conf) end
    local auras = conf.auras
    if auras.renderer ~= "CUSTOM" and auras.renderer ~= "BLIZZARD" then
        auras.renderer = "BLIZZARD"
    end
    if auras.renderer == nil then auras.renderer = "BLIZZARD" end
    MSUF.StateHelpers.SeedBlizzardAuraTypes(auras, MSUF_GF_BLIZZARD_TYPE_DEFAULTS)
    auras.blizzardContainerAnchor = "FRAME"
    auras.blizzardContainerX = 0
    auras.blizzardContainerY = 0
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "buff", "RAID")
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "debuff", "ALL")
    MSUF_ProfileIO_NormalizeGFAuraGroupForWago(auras, "externals", "RAID")
end

local function MSUF_ProfileIO_MakeWagoPayload(payload)
    if type(payload) ~= "table" then return {} end
    local out = {}
    for key, value in pairs(payload) do
        if MSUF_PROFILEIO_WAGO_PAYLOAD_KEYS[key] then
            out[key] = MSUF_DeepCopy(value)
        end
    end
    if type(payload.auras3) == "table" then
        out.auras2 = MSUF_DeepCopy(payload.auras3)
    end
    out.auras3 = nil
    out.auras = nil
    out._msufProfileSchema = nil
    out._msufLegacyProfileSchema = nil
    MSUF_ProfileIO_NormalizeAurasForWago(out.auras2)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_party)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_raid)
    MSUF_ProfileIO_NormalizeGroupFrameForWago(out.gf_mythicraid)
    return out
end

-- An export's aura owners describe its source client. Only full profiles
-- carry foreign sections. Runtime configuration reads the active owners.
local AuraTransfer = { StorageKey = "_msufAuraClients" }
local AURA_CLIENTS = { Mainline = true, Forever = true, Vanilla = true, TBC = true, Mists = true }
local CURRENT_AURA_CLIENT = MSUF.Client.IsForever and "Forever" or MSUF.Client.Flavor
local AURA_PARTIAL_KINDS = { unitselection = true, unitframe = true, groupframe = true, groupframes = true }
local CLIENT_LABELS = { Mainline = "Retail", Forever = "WoW Forever", Vanilla = "Classic Era", TBC = "TBC", Mists = "Mists" }
local GROUP_SCOPES = { gf_party = true, gf_raid = true, gf_mythicraid = true, gf_priority = true }
local GROUP_AURA_FIELDS = {
    auras = "table", privateAuras = "table", spellIndicators = "table",
    ciCustomTL = "table", ciCustomTR = "table", ciCustomBL = "table", ciCustomBR = "table", ciCustomC = "table",
    ciSlotTL = "string", ciSlotTR = "string", ciSlotBL = "string", ciSlotBR = "string", ciSlotC = "string",
}
local NO_CARRIED = {}
local PORTABLE_STYLE = {
    "iconSize", "spacing", "iconZoom", "iconHeightPercent", "iconShape", "buffGroupIconSize", "debuffGroupIconSize",
    "buffSpacing", "debuffSpacing", "styleBorderEnabled", "styleBorderStyle", "styleBorderThickness", "styleBorderColor",
    "styleShadowEnabled", "styleShadowSize", "styleShadowColor",
}

local function IsAuraVariantField(field)
    local path = field.path
    local root, key = path[1], path[2]
    return root == "auras3" or root == "auras2" or (GROUP_SCOPES[root] and GROUP_AURA_FIELDS[key]) ~= nil
end

local function AuraVariantSectionValid(value)
    local clean = MSUF.ProfileVariants.Validate(value)
    if not clean then return false end
    for _, entry in ipairs(clean.entries) do
        for _, field in ipairs(entry.patch) do
            if not IsAuraVariantField(field) then return false end
        end
    end
    return true
end

local function AuraSectionValid(section)
    if type(section) ~= "table" then return false end
    for key, value in pairs(section) do
        if key == "legacyRetail" then
            if value ~= true then return false end
        elseif key ~= "auras3" and key ~= "profileVariants" and not GROUP_SCOPES[key]
            and (section.legacyRetail ~= true or (key ~= "auras2" and key ~= "auras")) then
            return false
        end
        if key ~= "legacyRetail" and type(value) ~= "table" then return false end
        if key == "profileVariants" and not AuraVariantSectionValid(value) then return false end
        if GROUP_SCOPES[key] then
            for field, settings in pairs(value) do
                if GROUP_AURA_FIELDS[field] ~= type(settings) then return false end
            end
        end
    end
    return true
end

function AuraTransfer.Validate(decoded, selected, isSnapshot, legacyRetail)
    local full = not isSnapshot or selected.kind == "all"
    local payload = isSnapshot and selected.payload or selected
    if legacyRetail == true and not full then
        return false, nil, nil, "The Retail option applies only to full MSUF profile strings."
    end
    local storage = payload[AuraTransfer.StorageKey]
    local envelope = decoded
    if isSnapshot and type(decoded.msuf6) == "table" and decoded.msuf6.payload == payload then envelope = decoded.msuf6 end
    local source
    if type(envelope) == "table" then source = envelope.auraClient end
    if source ~= nil and (type(source) ~= "string" or not AURA_CLIENTS[source]
        or (not full and not AURA_PARTIAL_KINDS[selected.kind])) then return false end
    if storage == nil then
        if not source and full and legacyRetail == true then return true, "Mainline", true end
        return true, source
    end
    if not full or not source or not AURA_CLIENTS[CURRENT_AURA_CLIENT] or type(storage) ~= "table" or storage.version ~= 1
        or type(storage.clients) ~= "table" then return false end
    for key in pairs(storage) do
        if key ~= "version" and key ~= "clients" then return false end
    end
    for client, section in pairs(storage.clients) do
        if not AURA_CLIENTS[client] or client == source or not AuraSectionValid(section) then return false end
        if section.legacyRetail and client ~= "Mainline" then return false end
    end
    return true, source
end

local function ProjectVariantFields(schema, auras)
    if not schema then return nil end
    local projected = { version = schema.version, entries = {} }
    for index, entry in ipairs(schema.entries) do
        local patch, removed = {}, false
        for _, field in ipairs(entry.patch) do
            if IsAuraVariantField(field) == auras then patch[#patch + 1] = field else removed = true end
        end
        if #patch > 0 or (not auras and not removed) then
            projected.entries[#projected.entries + 1] = {
                name = entry.name, conditions = entry.conditions, enabled = entry.enabled, hotkey = entry.hotkey,
                patch = patch, auraOrder = auras and index or nil,
            }
        end
    end
    if auras and #projected.entries == 0 then return nil end
    return projected
end

local function CaptureAuraSection(profile, variants, legacyRetail)
    local result = { auras3 = MSUF_DeepCopy(profile.auras3) }
    if legacyRetail then
        result.legacyRetail = true
        result.auras2 = MSUF_DeepCopy(profile.auras2)
        result.auras = MSUF_DeepCopy(profile.auras)
    end
    if variants then
        local schema = MSUF.ProfileVariants.Validate(profile.profileVariants)
        result.profileVariants = MSUF_DeepCopy(ProjectVariantFields(schema, true))
    end
    for key in pairs(GROUP_SCOPES) do
        local scope = profile[key]
        if type(scope) == "table" then
            local aura = {}
            for field in pairs(GROUP_AURA_FIELDS) do aura[field] = MSUF_DeepCopy(scope[field]) end
            if next(aura) then result[key] = aura end
        end
    end
    return result
end

local function SameAuraVariantConditions(a, b)
    local fields = MSUF.ProfileFields
    for key, value in pairs(a) do
        if key ~= "manual" and not fields.Equal(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if key ~= "manual" and a[key] == nil then return false end
    end
    return true
end

local function ApplyAuraVariants(profile, section)
    local variants = ProjectVariantFields(profile.profileVariants, false)
    local auraVariants = MSUF.ProfileVariants.Validate(section.profileVariants)
    if not auraVariants then
        profile.profileVariants = variants
        return true
    end
    variants = variants or { version = auraVariants.version, entries = {} }
    local byName = {}
    for _, entry in ipairs(variants.entries) do byName[entry.name] = entry end
    for index, entry in ipairs(auraVariants.entries) do
        local match = byName[entry.name]
        if match then
            if not SameAuraVariantConditions(match.conditions, entry.conditions) then return false, "invalid variant conditions" end
            for _, field in ipairs(entry.patch) do match.patch[#match.patch + 1] = field end
        else
            local order = section.profileVariants.entries[index].auraOrder
            local tail = #variants.entries + 1
            if type(order) ~= "number" or order % 1 ~= 0 or order < 1 or order > tail then order = tail end
            table.insert(variants.entries, order, entry)
        end
    end
    profile.profileVariants = variants
    return true
end

local function ApplyGroupAura(profile, key, aura)
    local scope = profile[key]
    if type(scope) ~= "table" then
        if not aura then return end
        scope = {}
        profile[key] = scope
    end
    for field in pairs(GROUP_AURA_FIELDS) do scope[field] = aura and MSUF_DeepCopy(aura[field]) or nil end
end

local function ApplyAuraSection(profile, section)
    profile.auras, profile.auras2 = nil, nil
    profile.auras3 = MSUF_DeepCopy(section.auras3)
    for key in pairs(GROUP_SCOPES) do ApplyGroupAura(profile, key, section[key]) end
end

local function LegacyAuraRoot(section)
    local aura = section.auras3
    if section.legacyRetail and (not aura or (type(aura.shared) ~= "table" and type(aura.perUnit) ~= "table")) then
        aura = section.auras2 or section.auras or aura
    end
    return aura
end

local function PortableAuraStyle(section)
    local auras = LegacyAuraRoot(section)
    local shared = type(auras) == "table" and auras.shared or nil
    local defaults = MSUF.MSUF_CreateCanonicalUnitAuras()
    if type(shared) == "table" then
        for _, key in ipairs(PORTABLE_STYLE) do
            if shared[key] ~= nil then defaults.shared[key] = shared[key] end
        end
    end
    return { auras3 = defaults }
end

function AuraTransfer.Prepare(plan, source, variants, legacyRetail)
    plan.auraPrepared = true
    plan.auraClient = source
    plan.auraVariants = variants
    if source == CURRENT_AURA_CLIENT and legacyRetail then
        -- Explicit legacy Retail imports use the same rule migration as a
        -- Retail section carried home through another client.
        plan.localLegacyAura = CaptureAuraSection(plan.payload, variants, true)
    end
    if not source or source == CURRENT_AURA_CLIENT then return true end
    if not AURA_CLIENTS[CURRENT_AURA_CLIENT] then return true end
    if AURA_PARTIAL_KINDS[plan.kind] then
        plan.foreignAuraPartial = true
        ApplyAuraSection(plan.payload, {})
        return true
    end
    local section = CaptureAuraSection(plan.payload, variants, legacyRetail)
    if not AuraSectionValid(section) then return false end
    plan.foreignAura = section
    ApplyAuraSection(plan.payload, {})
    return true
end

-- The compatibility envelope can contain Auras3 data under the older Auras2
-- key. Use the current client's baseline to migrate geometry, then retain the
-- saved aura fields supported by that baseline.
local function RestoreLegacyAuras(profile, section)
    profile.auras2 = MSUF_DeepCopy(section.auras2)
    profile.auras = MSUF_DeepCopy(section.auras)
    Normalize.RestoreLegacyAuraTransfer(profile, LegacyAuraRoot(section), section)
end

local function MatchesAuraFactory(current, factory)
    local fields = MSUF.ProfileFields
    local defaults = CaptureAuraSection(factory)
    local preset = { "auras3", "customContainers", "perUnit", "player", "items", MSUF.MSUF_Auras3.PRESET_CUSTOM_CONTAINER_INDEX }
    local defaultItem, currentItem = fields.Read(defaults, preset), fields.Read(current, preset)
    -- The defensive preset's first runtime compile marks its style as materialized.
    if defaultItem and currentItem then defaultItem._msufA3LocalStyleFromShared_v1 = currentItem._msufA3LocalStyleFromShared_v1 end
    return fields.Equal(current, defaults)
end

local function CarriedAuraSections(profile)
    local storage = profile[AuraTransfer.StorageKey]
    return type(storage) == "table" and type(storage.clients) == "table" and storage.clients or NO_CARRIED
end

function AuraTransfer.Stage(plan, candidate, base, factoryBase)
    if not plan.auraPrepared then return true end
    if plan.localLegacyAura then RestoreLegacyAuras(candidate, plan.localLegacyAura) end
    local key, source = AuraTransfer.StorageKey, plan.auraClient
    local incoming, localSections = CarriedAuraSections(candidate), CarriedAuraSections(base)
    if not next(incoming) and not next(localSections) and not plan.foreignAura then return true end
    local carried = {}
    for client, section in pairs(incoming) do
        carried[client] = MSUF_DeepCopy(section)
        if not plan.auraVariants then
            carried[client].profileVariants = MSUF_DeepCopy(localSections[client] and localSections[client].profileVariants)
        end
    end
    for client, section in pairs(localSections) do
        if carried[client] == nil then carried[client] = MSUF_DeepCopy(section) end
    end
    if plan.foreignAura then
        local active = incoming[CURRENT_AURA_CLIENT]
        if next(base) and not active then
            local current = CaptureAuraSection(base, plan.auraVariants)
            local factory = factoryBase()
            if not factory or not MatchesAuraFactory(current, factory) then active = current end
        end
        local section = active or PortableAuraStyle(plan.foreignAura)
        ApplyAuraSection(candidate, section)
        if section.legacyRetail then RestoreLegacyAuras(candidate, section) end
        if plan.auraVariants then
            local ok, why = ApplyAuraVariants(candidate, section)
            if not ok then return false, why end
        end
        carried[source] = MSUF_DeepCopy(plan.foreignAura)
        if not plan.auraVariants then
            carried[source].profileVariants = MSUF_DeepCopy(localSections[source] and localSections[source].profileVariants)
        end
    end
    if source and AURA_CLIENTS[CURRENT_AURA_CLIENT] then carried[CURRENT_AURA_CLIENT] = nil end
    candidate[key] = next(carried) and { version = 1, clients = carried } or nil
    return true
end

function AuraTransfer.RestorePartial(plan, candidate, base)
    if not plan.foreignAuraPartial then return end
    for key in pairs(GROUP_SCOPES) do
        local localScope = type(base[key]) == "table" and base[key] or nil
        if plan.payload[key] then ApplyGroupAura(candidate, key, localScope) end
    end
end

function AuraTransfer.ReviewChanges(changes, before, after)
    local fields = MSUF.ProfileFields
    before, after = CarriedAuraSections(before), CarriedAuraSections(after)
    for _, client in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
        if not fields.Equal(before[client], after[client]) then
            changes[#changes + 1] = { path = { "Auras", CLIENT_LABELS[client] }, auraClient = client,
                before = fields.CopySnapshot(before[client]), value = fields.CopySnapshot(after[client]), selected = true }
        end
    end
end

function AuraTransfer.ApplyReview(profile, client, value)
    local key = AuraTransfer.StorageKey
    local clients = CarriedAuraSections(profile)
    if clients == NO_CARRIED then clients = {} end
    clients[client] = value
    profile[key] = next(clients) and { version = 1, clients = clients } or nil
end

function AuraTransfer.ForExport(payload, full, variants)
    local key = AuraTransfer.StorageKey
    if not full then
        payload[key] = nil
    elseif not variants and type(payload[key]) == "table" and type(payload[key].clients) == "table" then
        for _, section in pairs(payload[key].clients) do
            if type(section) == "table" then section.profileVariants = nil end
        end
    end
end

Parts.AuraTransfer = AuraTransfer

local function MSUF_ProfileIO_MakeWagoSnapshot(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.payload) ~= "table" then return snapshot, false end
    if snapshot.kind ~= "all" then
        if AURA_CLIENTS[CURRENT_AURA_CLIENT] and AURA_PARTIAL_KINDS[snapshot.kind] then
            snapshot.auraClient = CURRENT_AURA_CLIENT
        end
        return snapshot, false
    end
    local export = {
        addon   = "MSUF",
        fmt     = 2,
        schema  = MSUF_PROFILEIO_WAGO_SCHEMA,
        kind    = "all",
        profile = snapshot.profile,
        payload = MSUF_ProfileIO_MakeWagoPayload(snapshot.payload),
        [MSUF_PROFILEIO_WAGO_FULL_KEY] = {
            schema  = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA,
            kind    = "all",
            profile = snapshot.profile,
            payload = MSUF_DeepCopy(snapshot.payload),
        },
    }
    -- Keep Wago's outer payload portable. The full snapshot records the
    -- active aura owner even on its first trip to another client.
    if AURA_CLIENTS[CURRENT_AURA_CLIENT] then
        export[MSUF_PROFILEIO_WAGO_FULL_KEY].auraClient = CURRENT_AURA_CLIENT
    end
    return export, true
end

local function MSUF_ProfileIO_SelectWagoFullSnapshot(snapshot)
    if type(snapshot) ~= "table" then return snapshot end
    local full = snapshot[MSUF_PROFILEIO_WAGO_FULL_KEY]
    if type(full) == "table"
        and tonumber(full.schema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and type(full.payload) == "table" then
        return {
            addon   = "MSUF",
            fmt     = 2,
            schema  = full.schema,
            kind    = type(full.kind) == "string" and full.kind or snapshot.kind,
            profile = type(full.profile) == "string" and full.profile or snapshot.profile,
            payload = full.payload,
        }
    end
    return snapshot
end

local function MSUF_ProfileIO_SelectSupportedProfile(decoded)
    local policy = type(MSUF) == "table" and MSUF.ProfilePolicy or nil
    local selectSupported = type(policy) == "table" and policy.SelectSupportedDecodedProfile or nil
    if type(selectSupported) == "function" then
        return selectSupported(decoded)
    end
    if type(decoded) == "table"
        and tonumber(decoded._msufProfileSchema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA then
        return decoded
    end
    if type(decoded) == "table"
        and decoded.addon == "MSUF"
        and tonumber(decoded.fmt) == 2
        and tonumber(decoded.schema) == MSUF_PROFILEIO_WAGO_SCHEMA
        and type(decoded.kind) == "string"
        and type(decoded.payload) == "table"
        and decoded[MSUF_PROFILEIO_WAGO_FULL_KEY] == nil then
        return decoded
    end
    local snapshot = MSUF_ProfileIO_SelectWagoFullSnapshot(decoded)
    if type(snapshot) == "table"
        and snapshot.addon == "MSUF"
        and tonumber(snapshot.fmt) == 2
        and tonumber(snapshot.schema) == MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
        and type(snapshot.kind) == "string"
        and type(snapshot.payload) == "table" then
        return snapshot
    end
    return nil
end

local function MSUF_CopyGroupFramePayload(profile)
    local MSUF_DB = profile or _G.MSUF_DB
    local payload = {}
    if type(MSUF_DB) ~= "table" then
        return payload
    end
    if type(MSUF_DB.gf_party) == "table" then
        payload.gf_party = MSUF_DeepCopy(MSUF_DB.gf_party)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_party)
    end
    if type(MSUF_DB.gf_raid) == "table" then
        payload.gf_raid = MSUF_DeepCopy(MSUF_DB.gf_raid)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_raid)
    end
    if type(MSUF_DB.gf_mythicraid) == "table" then
        payload.gf_mythicraid = MSUF_DeepCopy(MSUF_DB.gf_mythicraid)
        MSUF_ProfileIO_NormalizeGroupFrameForExport(payload.gf_mythicraid)
    end
    if type(MSUF_DB.gf_priority) == "table" then
        payload.gf_priority = MSUF_DeepCopy(MSUF_DB.gf_priority)
    end
    return payload
end
--- Blizzard Edit Mode data in profile strings is strictly opt-in, per

Parts.MSUF_AURA_GENERAL_KEYS = MSUF_AURA_GENERAL_KEYS
Parts.MSUF_ApplyGeneralSubset = MSUF_ApplyGeneralSubset
Parts.MSUF_CopyGeneralSubset = MSUF_CopyGeneralSubset
Parts.MSUF_CopyGroupFramePayload = MSUF_CopyGroupFramePayload
Parts.MSUF_DeepCopy = MSUF_DeepCopy
Parts.MSUF_GeneralKeysOfKind = MSUF_GeneralKeysOfKind
Parts.MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA = MSUF_PROFILEIO_CURRENT_PROFILE_SCHEMA
Parts.MSUF_PROFILEIO_UNIT_KEYS = MSUF_PROFILEIO_UNIT_KEYS
Parts.MSUF_ProfileIO_EnsureCompleteProfileDB = MSUF_ProfileIO_EnsureCompleteProfileDB
Parts.MSUF_ProfileIO_EnsureGroupFramesDB = MSUF_ProfileIO_EnsureGroupFramesDB
Parts.MSUF_ProfileIO_EnsureUnitframeAlphaDB = MSUF_ProfileIO_EnsureUnitframeAlphaDB
Parts.MSUF_ProfileIO_MakeWagoSnapshot = MSUF_ProfileIO_MakeWagoSnapshot
Parts.MSUF_ProfileIO_NormalizeGroupFramePayloadForExport = MSUF_ProfileIO_NormalizeGroupFramePayloadForExport
Parts.MSUF_ProfileIO_NormalizeImportedFontSizes = MSUF_ProfileIO_NormalizeImportedFontSizes
Parts.MSUF_ProfileIO_SelectSupportedProfile = MSUF_ProfileIO_SelectSupportedProfile
Parts.MSUF_UNITFRAME_ALPHA_KEYS = MSUF_UNITFRAME_ALPHA_KEYS
Parts.MSUF_UNITFRAME_UNIT_KEYS = MSUF_UNITFRAME_UNIT_KEYS
Parts.MSUF_WipeGeneralSubset = MSUF_WipeGeneralSubset
Parts.MSUF_WipeTable = MSUF_WipeTable
