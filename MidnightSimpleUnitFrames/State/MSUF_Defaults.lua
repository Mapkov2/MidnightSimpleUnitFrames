local addonName, addonNS = ...
local MSUF = (_G.MSUF_NS) or addonNS or {}
local ExportPublic = MSUF.ExportPublic

--- Client facts, read once when this file loads. Every client loads this file;
--- the Classic flavors (Vanilla, TBC, Mists) differ from Mainline (Midnight and
--- WoW Forever) only in the small hunks gated on these two locals. Nothing here
--- reads WOW_PROJECT_ID: Game/Shared/Initialize.lua owns that.
local IS_CLASSIC_FAMILY = MSUF.Client ~= nil and MSUF.Client.Family == "Classic"
--- Arena Aura owners this client keeps: three on Midnight, five on TBC and
--- Mists. Classic Era and WoW Forever publish no arena slots at all
--- (Game/Shared/Initialize.lua), so the floor holds them at the same three
--- owners Midnight authors and the extra lanes below stay unwritten.
local ARENA_AURA_SLOTS = math.max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3)

--- State/MSUF_Defaults.lua
---
--- Owns schema bootstrap and client-specific migrations for MSUF_DB. Shared
--- seed stages live in State/Defaults/. This cold path runs at login, profile creation,
--- profile switch, import, and explicit default repair. Runtime modules should
--- consume the normalized DB or compiled config, not read migration rules from
--- here during gameplay events.
---
--- Rules for future changes:
--- * Add new saved fields here with nil-preserving defaults.
--- * Put one-shot profile repairs in this file, guarded by migration flags.
--- * Keep factory-profile seeding separate from normal default filling so
---   existing users are never overwritten by a new shipped baseline.

--- MSUF default class-resource colors
--- Keep this tiny and global so:
--- 1) class power fallback colors use the new defaults
--- 2) reset-to-default in the Colors menu also lands on these defaults
--- 3) no runtime overhead in hot paths (one-time table write at load)
do
    local pbc = _G.PowerBarColor
    if type(pbc) == "table" then
        pbc.RUNES = pbc.RUNES or {}
        pbc.RUNES.r, pbc.RUNES.g, pbc.RUNES.b = 128/255, 0, 17/255      --- #800011

        pbc.SOUL_SHARDS = pbc.SOUL_SHARDS or {}
        pbc.SOUL_SHARDS.r, pbc.SOUL_SHARDS.g, pbc.SOUL_SHARDS.b = 135/255, 136/255, 238/255 --- #8788EE
    end
end

--- MSUF Defaults / DB initialization
--- ---
--- Factory default profile (MSUF compact string)
---
--- If MSUF_DB is NEW (fresh install / full reset), we seed it from this payload
--- so the addon boots with your preferred baseline.
---
--- Existing installs are NOT overwritten. This only runs when MSUF_DB was
--- created empty in this session.
--- ---
--- Current factory default profile (v46).
--- Player defensives are a product-level factory invariant. Keep this true for
--- future factory payload replacements unless the requested baseline explicitly
--- calls for defensive tracking to start disabled.
local MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED = true
--- One factory string for every client of this repo: it lives in
--- State/Defaults/MSUF_Defaults_Shell.lua, which the TOCs load before this file.
local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT

--- Expose the factory compact string for diagnostics and future tooling.
if type(MSUF) == "table" then
    MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
end
ExportPublic("MSUF_FACTORY_DEFAULT_PROFILE_COMPACT", MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)

local function MSUF_Defaults_TryDecodeCompactString(str)
    if type(str) ~= "string" then  return nil end
    local E = _G.C_EncodingUtil
    if not E then  return nil end
    if type(E.DeserializeCBOR) ~= "function" then  return nil end
    if type(E.DecodeBase64) ~= "function" then  return nil end
    -- Fixed, valid patterns: string.match/gsub cannot raise here regardless of
    -- what the user pasted. The decode/decompress steps below CAN.
    local prefix, b64 = string.match(str, "^%s*(MSUF%d+):%s*(.-)%s*$")
    if (prefix ~= "MSUF2" and prefix ~= "MSUF3" and prefix ~= "MSUF4") or type(b64) ~= "string" or b64 == "" then  return nil end
    local cleaned = string.gsub(b64, "%s+", "")
    if type(cleaned) ~= "string" or cleaned == "" then  return nil end
    local rem = #cleaned % 4
    if rem == 1 then
        return nil
    elseif rem == 2 then
        cleaned = cleaned .. "=="
    elseif rem == 3 then
        cleaned = cleaned .. "="
    end
    -- MSUF3/4 is deflate(CBOR). Forever's DeserializeCBOR raises
    -- "attempted to deserialize an unknown cbor value" on the compressed
    -- bytes (the factory blob starts 0xEC). Blizzard's own readers inflate
    -- first; never offer the compressed blob to CBOR.
    local blob = E.DecodeBase64(cleaned)
    if type(blob) ~= "string" then return nil end
    local payload = blob
    if type(E.DecompressString) == "function" then
        local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil
        local inflated = method ~= nil and E.DecompressString(blob, method) or E.DecompressString(blob)
        if type(inflated) == "string" and inflated ~= "" then
            payload = inflated
        end
    end
    local tbl = E.DeserializeCBOR(payload)
    return type(tbl) == "table" and tbl or nil
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
    --- Current exports wrap profile data as a snapshot. Older/tooling exports may
    --- decode directly to the profile table; keep both valid for factory defaults.
    if tbl.addon == "MSUF" and tonumber(tbl.fmt) == 2 and type(tbl.payload) == "table" then
        return tbl.payload
    end
    return tbl
end

--- Portrait values have changed names more than once. Normalize them before
--- any frame/compiler code sees the DB so downstream modules only need to
--- understand the current enum set.
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
ExportPublic("MSUF_NormalizePortraitClassStyleValue", MSUF_Defaults_NormalizePortraitClassStyleValue)

local function MSUF_Defaults_NormalizePortraitRenderDB(db)
    if type(db) ~= "table" then return end
    local g = type(db.general) == "table" and db.general or nil
    if g and g._portraitSharedRender ~= nil then
        g._portraitSharedRender = MSUF_Defaults_NormalizePortraitRenderValue(g._portraitSharedRender)
    end
    if g and g.portraitClassStyle ~= nil then
        g.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(g.portraitClassStyle)
    end
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena" }) do
        local u = db[unitKey]
        if type(u) == "table" and u.portraitRender ~= nil then
            u.portraitRender = MSUF_Defaults_NormalizePortraitRenderValue(u.portraitRender)
        end
        if type(u) == "table" and u.portraitClassStyle ~= nil then
            u.portraitClassStyle = MSUF_Defaults_NormalizePortraitClassStyleValue(u.portraitClassStyle)
        end
    end
end
ExportPublic("MSUF_NormalizePortraitRenderDB", MSUF_Defaults_NormalizePortraitRenderDB)

local MSUF_DEFAULTS_TEXT_SCOPE_KEYS = { "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena" }
local MSUF_DEFAULTS_GROUP_SCOPE_KEYS = { "gf_party", "gf_raid", "gf_mythicraid" }
--- Field helpers are shared with State/MSUF_Profiles.lua through
--- MSUF.StateHelpers (State/MSUF_StateHelpers.lua, loaded right before this
--- file). This pipeline always passes StateHelpers.DefaultsSpec: empty strings
--- are kept, non-boolean inverse sources are rejected, and only the key sets
--- EnsureDB always owned are normalized. The ProfileIO twin
--- (MSUF_ProfileIO_TranslateProfileToCurrent in MSUF_Profiles.lua) selects the
--- wider import spec; see the cross-reference note above
--- MSUF_DEFAULTS_CURRENT_REVISION.
local StateHelpers = MSUF.StateHelpers
if type(StateHelpers) ~= "table" then
    error("State/MSUF_StateHelpers.lua must load before State/MSUF_Defaults.lua")
end
local MSUF_DEFAULTS_SPEC = StateHelpers.DefaultsSpec
--- Hunter Pet Happiness exists on Classic Era, TBC and WoW Forever. Its status
--- keys are normalized like every other status prefix there; Midnight keeps the
--- shared spec untouched. Mists carries the prefix as well, as the Classic
--- Defaults always did: the normalizers ignore a key that is not there, so it is
--- inert on a client whose seeding below never writes one.
if MSUF.Client and (MSUF.Client.SupportsPetHappiness == true or IS_CLASSIC_FAMILY) then
    local petHappinessSpec = {}
    for key, value in pairs(StateHelpers.DefaultsSpec) do petHappinessSpec[key] = value end
    petHappinessSpec.statusPrefixes = {}
    for i, prefix in ipairs(StateHelpers.DefaultsSpec.statusPrefixes) do
        petHappinessSpec.statusPrefixes[i] = prefix
    end
    petHappinessSpec.statusPrefixes[#petHappinessSpec.statusPrefixes + 1] = "petHappinessIndicator"
    MSUF_DEFAULTS_SPEC = petHappinessSpec
end
local MSUF_Defaults_ToNumber = StateHelpers.ToNumber
local MSUF_Defaults_CopyIfMissing = StateHelpers.CopyIfMissing
local MSUF_Defaults_NormalizeNumberField = StateHelpers.NormalizeNumberField
--- Called with two arguments only: the nilEmpty flag stays off, so an empty
--- string is kept exactly as this file always did.
local MSUF_Defaults_UpperStringField = StateHelpers.UpperStringField
local MSUF_Defaults_TableHasAnyValue = StateHelpers.TableHasAnyValue

local MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE = {
    player = { 275, 40 },
    target = { 276, 40 },
    focus = { 216, 30 },
    targettarget = { 170, 36 },
    focustarget = { 170, 30 },
    boss = { 264, 35 },
}

local function MSUF_Defaults_A2AuraFrameKey(unit)
    if unit == "tot" or unit == "targetoftarget" then return "targettarget" end
    if unit == "focus_target" or unit == "focustargettarget" then return "focustarget" end
    if type(unit) == "string" and unit:match("^boss%d+$") then return "boss" end
    if type(unit) == "string" and unit:match("^arena%d+$") then return "arena" end
    return unit
end

local function MSUF_Defaults_A2AuraFrameSize(profile, unit)
    local key = MSUF_Defaults_A2AuraFrameKey(unit)
    local conf = type(profile) == "table" and type(profile[key]) == "table" and profile[key] or nil
    local defaults = MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE[key] or MSUF_DEFAULTS_A2_AURA_FRAME_DEFAULT_SIZE.player
    local width = MSUF_Defaults_ToNumber(conf and (conf.width or conf.frameWidth)) or defaults[1]
    local height = MSUF_Defaults_ToNumber(conf and (conf.height or conf.frameHeight)) or defaults[2]
    if width < 1 then width = defaults[1] end
    if height < 1 then height = defaults[2] end
    return width, height
end

local function MSUF_Defaults_A2AuraReadNumber(primary, secondary, key, fallback)
    local n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[key]) or nil
    if n ~= nil then return n end
    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[key]) or nil
    if n ~= nil then return n end
    return fallback or 0
end

local function MSUF_Defaults_ConvertLegacyAuras2Geometry(auras, profile)
    if type(auras) ~= "table" or auras._msufAuras3LegacyGeometry_v2 == true then return false end
    local shared = type(auras.shared) == "table" and auras.shared or {}
    auras.shared = shared
    -- Aura2 v11f anchored both lane containers with buff/debuffGroupOffsetX/Y.
    -- The older buff/debuffOffset aliases remained in SavedVariables (notably
    -- the default buffOffsetY = 30) but the 5.57 renderer no longer read them.
    -- Treating those dead aliases as live group offsets moves migrated auras.
    local useRetiredLaneOffsetAliases = shared._msufA2_migrated_v11f ~= true
    local repairV1 = auras._msufAuras3LegacyGeometry_v1 == true
    local changed = false
    if type(auras.perUnit) == "table" then
        for unit, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                local storedLayout = type(unitCfg.layout) == "table" and unitCfg.layout or nil
                local layout = unitCfg.overrideLayout == true and storedLayout or {}
                if unitCfg.layout ~= layout then unitCfg.layout = layout; changed = true end
                if unitCfg.overrideSharedLayout ~= true and type(unitCfg.layoutShared) == "table" then
                    unitCfg.layoutShared = {}
                    changed = true
                end
                local width, height = MSUF_Defaults_A2AuraFrameSize(profile, unit)
                local baseX = MSUF_Defaults_A2AuraReadNumber(layout, shared, "offsetX", 0)
                local baseY = MSUF_Defaults_A2AuraReadNumber(layout, shared, "offsetY", 0)
                local function ReadLaneNumber(primary, secondary, key, aliasKey, fallback)
                    local n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[key]) or nil
                    if n ~= nil then return n end
                    if useRetiredLaneOffsetAliases then
                        n = type(primary) == "table" and MSUF_Defaults_ToNumber(primary[aliasKey]) or nil
                        if n ~= nil then return n end
                    end
                    n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[key]) or nil
                    if n ~= nil then return n end
                    if useRetiredLaneOffsetAliases then
                        n = type(secondary) == "table" and MSUF_Defaults_ToNumber(secondary[aliasKey]) or nil
                        if n ~= nil then return n end
                    end
                    return fallback or 0
                end
                for _, lane in ipairs({
                    { "buffGroupOffsetX", "buffGroupOffsetY", "buffAnchor", "buffOffsetX", "buffOffsetY" },
                    { "debuffGroupOffsetX", "debuffGroupOffsetY", "debuffAnchor", "debuffOffsetX", "debuffOffsetY" },
                }) do
                    local anchor = "BOTTOMLEFT"
                    local x
                    local y
                    if repairV1 then
                        x = ReadLaneNumber(layout, nil, lane[1], lane[4], 0)
                        y = ReadLaneNumber(layout, nil, lane[2], lane[5], 0)
                        local oldAnchor = tostring(layout[lane[3]] or ""):upper()
                        if oldAnchor == "TOPRIGHT" or oldAnchor == "BOTTOMRIGHT" then
                            x = x + width
                        end
                        if oldAnchor == "TOPLEFT" or oldAnchor == "TOPRIGHT" then
                            y = y + height
                        end
                    else
                        x = baseX + ReadLaneNumber(layout, shared, lane[1], lane[4], 0)
                        y = height + baseY + ReadLaneNumber(layout, shared, lane[2], lane[5], 0)
                    end
                    if layout[lane[3]] ~= anchor then layout[lane[3]] = anchor; changed = true end
                    if layout[lane[1]] ~= x then layout[lane[1]] = x; changed = true end
                    if layout[lane[2]] ~= y then layout[lane[2]] = y; changed = true end
                end
                if unitCfg.overrideLayout ~= true then unitCfg.overrideLayout = true; changed = true end
            end
        end
    end
    auras._msufAuras3LegacyGeometry_v1 = true
    auras._msufAuras3LegacyGeometry_v2 = true
    return true
end

local function MSUF_Defaults_NormalizeAuras3Profile(db)
    if type(db) ~= "table" then return false end
    local changed = false
    local fromLegacyAuras2 = false
    if db.auras ~= nil then
        db.auras = nil
        changed = true
    end
    if type(db.auras2) == "table" and (type(db.auras3) ~= "table" or tonumber(db._msufProfileSchema) ~= 600) then
        db.auras3 = {}
        MSUF_Defaults_DeepCopy(db.auras3, db.auras2)
        db.auras3._msufAuras3TranslatedFromLegacyAuras2 = true
        fromLegacyAuras2 = true
        changed = true
    end
    if db.auras2 ~= nil then
        db.auras2 = nil
        changed = true
    end
    local auras = db.auras3
    if type(auras) ~= "table" then return changed end
    if fromLegacyAuras2 or (auras._msufAuras3TranslatedFromLegacyAuras2 == true and auras._msufAuras3LegacyGeometry_v2 ~= true) then
        changed = MSUF_Defaults_ConvertLegacyAuras2Geometry(auras, db) or changed
    end
    changed = StateHelpers.NormalizeAuraLayoutTable(auras.shared, MSUF_DEFAULTS_SPEC) or changed
    if type(auras.perUnit) == "table" then
        for _, unitCfg in pairs(auras.perUnit) do
            if type(unitCfg) == "table" then
                changed = StateHelpers.NormalizeAuraLayoutTable(unitCfg.layout, MSUF_DEFAULTS_SPEC) or changed
                changed = StateHelpers.NormalizeAuraLayoutTable(unitCfg.layoutShared, MSUF_DEFAULTS_SPEC) or changed
                if MSUF_Defaults_TableHasAnyValue(unitCfg.layout) and unitCfg.overrideLayout == nil then
                    unitCfg.overrideLayout = true
                    changed = true
                end
                if MSUF_Defaults_TableHasAnyValue(unitCfg.layoutShared) and unitCfg.overrideSharedLayout == nil then
                    unitCfg.overrideSharedLayout = true
                    changed = true
                end
            end
        end
    end
    return changed
end

local function MSUF_Defaults_NormalizeUnitPositionAliases(db)
    if type(db) ~= "table" then return false end
    local changed = false
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        local u = db[key]
        if type(u) == "table" then
            changed = MSUF_Defaults_CopyIfMissing(u, "point", "anchorMyPoint") or changed
            changed = MSUF_Defaults_CopyIfMissing(u, "relativePoint", "anchorRelPoint") or changed
            changed = MSUF_Defaults_UpperStringField(u, "point") or changed
            changed = MSUF_Defaults_UpperStringField(u, "relativePoint") or changed
            changed = MSUF_Defaults_NormalizeNumberField(u, "offsetX", -10000, 10000) or changed
            changed = MSUF_Defaults_NormalizeNumberField(u, "offsetY", -10000, 10000) or changed
        end
    end
    return changed
end

--- Numeric MSUF element layers share one addon-wide contract. This deliberately
--- ignores Blizzard draw-layer/FrameStrata strings while catching both the
--- common `*Layer` fields and frame-level offsets used by detached bars.
local function MSUF_Defaults_NormalizeNumericLayers(root)
    if type(root) ~= "table" then return false end
    local changed = false
    local seen = {}
    local function IsLayerKey(key)
        if type(key) ~= "string" or key:sub(1, 1) == "_" then return false end
        local lower = string.lower(key)
        return lower == "layer"
            or (lower:sub(-5) == "layer" and lower:sub(-6) ~= "player")
            or lower:sub(-16) == "frameleveloffset"
    end
    local function Visit(tbl)
        if seen[tbl] then return end
        seen[tbl] = true
        for key, value in pairs(tbl) do
            if type(value) == "table" then
                Visit(value)
            elseif IsLayerKey(key) then
                local number = tonumber(value)
                if number ~= nil and (number - number) == 0 then
                    if number < 0 then
                        number = 0
                    elseif number > 30 then
                        number = 30
                    end
                    number = math.floor(number + 0.5)
                    if value ~= number then
                        tbl[key] = number
                        changed = true
                    end
                end
            end
        end
    end
    Visit(root)
    return changed
end
ExportPublic("MSUF_NormalizeNumericLayers", MSUF_Defaults_NormalizeNumericLayers)

--- These fields belonged to an abandoned class-resource text model. The live
--- renderer never consumed them; the reviewed classPowerTextMode setting now
--- owns the central value format. Keep this tiny and allocation-free because
--- the public DB guard also calls it before taking its persisted fast path.
local function MSUF_Defaults_PruneRetiredClassPowerTextFields(db)
    local bars = db.bars
    if type(bars) ~= "table" then return false end
    local changed = bars.classPowerTextAnchor ~= nil
        or bars.classPowerTextFormat ~= nil or bars.continuousTextFormat ~= nil
    bars.classPowerTextAnchor = nil
    bars.classPowerTextFormat = nil
    bars.continuousTextFormat = nil
    return changed == true
end

--- Defaults-side alias normalization. When MSUF_Profiles.lua has loaded, the
--- shared translator (its own pipeline, see the cross-reference note above
--- MSUF_DEFAULTS_CURRENT_REVISION) runs instead of the narrower fallback below.
local function MSUF_Defaults_NormalizeProfileTo60Defaults(db)
    if type(db) ~= "table" then return false end
    local changed = StateHelpers.MigrateSplitStatusText(db, MSUF_DEFAULTS_TEXT_SCOPE_KEYS)
    changed = MSUF_Defaults_PruneRetiredClassPowerTextFields(db) or changed
    --- Masque support was removed from MSUF 6.0. Purge the orphaned toggle
    --- from factory snapshots, imports, and existing profiles without touching
    --- the Masque addon or any settings it owns for other addons.
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        local scope = db[key]
        if type(scope) == "table" and scope.masqueEnabled ~= nil then
            scope.masqueEnabled = nil
            changed = true
        end
    end
    local sharedTranslator = _G.MSUF_ProfileIO_TranslateProfileToCurrent
    if type(sharedTranslator) ~= "function" and type(MSUF) == "table" then
        sharedTranslator = MSUF.MSUF_ProfileIO_TranslateProfileToCurrent
    end
    if type(sharedTranslator) == "function" then
        local _, translated = sharedTranslator(db, { source = "defaults", markProfile = true })
        changed = translated == true or changed
        if db.auras ~= nil then
            db.auras = nil
            changed = true
        end
        if db.auras2 ~= nil then
            db.auras2 = nil
            changed = true
        end
        changed = MSUF_Defaults_NormalizeNumericLayers(db) or changed
        return changed == true
    end
    changed = MSUF_Defaults_NormalizeUnitPositionAliases(db) or changed
    changed = MSUF_Defaults_NormalizeAuras3Profile(db) or changed
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        changed = StateHelpers.NormalizeTextScope(db[key], false, MSUF_DEFAULTS_SPEC) or changed
        changed = StateHelpers.NormalizeStatusScope(db[key], false, MSUF_DEFAULTS_SPEC) or changed
    end
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        changed = StateHelpers.NormalizeTextScope(db[key], true, MSUF_DEFAULTS_SPEC) or changed
        changed = StateHelpers.NormalizeStatusScope(db[key], true, MSUF_DEFAULTS_SPEC) or changed
    end
    changed = MSUF_Defaults_NormalizeNumericLayers(db) or changed
    return changed
end
ExportPublic("MSUF_NormalizeProfileTo60Defaults", MSUF_Defaults_NormalizeProfileTo60Defaults)

local MSUF_DEFAULT_BOSS_OFFSET_X = 360
local MSUF_DEFAULT_BOSS_OFFSET_Y = 230
local MSUF_DEFAULT_ARENA_OFFSET_X = 360
local MSUF_DEFAULT_ARENA_OFFSET_Y = -40

--- Default position offsets per unit, mirrored from the fill() defaults below.
--- Exposed so Edit Mode popups can offer a "Reset position" action that only
--- touches the frame's position, not its size or other settings.
local MSUF_DEFAULT_UNIT_OFFSETS = {
    player       = { -256, -180 },
    target       = { 320, -180 },
    focus        = { -260, -300 },
    targettarget = { 220, -300 },
    focustarget  = { 260, 180 },
    pet          = { -275, -250 },
    boss         = { MSUF_DEFAULT_BOSS_OFFSET_X, MSUF_DEFAULT_BOSS_OFFSET_Y },
    arena        = { MSUF_DEFAULT_ARENA_OFFSET_X, MSUF_DEFAULT_ARENA_OFFSET_Y },
}
local function MSUF_GetDefaultUnitOffsets(unit)
    local o = unit and MSUF_DEFAULT_UNIT_OFFSETS[unit]
    if o then return o[1], o[2] end
    return 0, 0
end
ExportPublic("MSUF_GetDefaultUnitOffsets", MSUF_GetDefaultUnitOffsets)

--- Legal unit-frame size range. Single source of truth for every conf.width/
--- conf.height writer (Edit Mode popup) and renderer (options unit preview
--- mock): both clamp against this table, so the preview can never render a
--- different frame rectangle than a size the writers allow. Coldpath only.
local MSUF_UNIT_FRAME_SIZE_BOUNDS = { minW = 40, maxW = 800, minH = 8, maxH = 200 }
ExportPublic("MSUF_UnitFrameSizeBounds", MSUF_UNIT_FRAME_SIZE_BOUNDS)

local MSUF_DEFAULT_EXPRESSWAY_LOCALES = {
    enUS = true,
    enGB = true,
    deDE = true,
}
local MSUF_DEFAULT_EXPRESSWAY_FONT =
    "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf"

local function MSUF_Defaults_GetEffectiveLocale()
    if type(MSUF) == "table" and type(MSUF.GetEffectiveLocale) == "function" then
        local locale = MSUF.GetEffectiveLocale()
        if type(locale) == "string" and locale ~= "" then
            return locale
        end
    end
    if type(_G.GetLocale) == "function" then
        local locale = _G.GetLocale()
        if type(locale) == "string" and locale ~= "" then
            return locale
        end
    end
    return (type(MSUF) == "table" and MSUF.CLIENT_LOCALE) or "enUS"
end

local function MSUF_Defaults_UseExpresswayByDefault()
    return MSUF_DEFAULT_EXPRESSWAY_LOCALES[MSUF_Defaults_GetEffectiveLocale()] == true
end

local function MSUF_Defaults_GetBlizzardFontPath()
    local fontObject = _G.GameFontNormal
    if fontObject and type(fontObject.GetFont) == "function" then
        local path = fontObject:GetFont()
        if type(path) == "string" and path ~= "" then
            return path
        end
    end
    if type(_G.STANDARD_TEXT_FONT) == "string" and _G.STANDARD_TEXT_FONT ~= "" then
        return _G.STANDARD_TEXT_FONT
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function MSUF_Defaults_GetGlobalFontDefault()
    if MSUF_Defaults_UseExpresswayByDefault() then
        return MSUF_DEFAULT_EXPRESSWAY_FONT
    end
    return MSUF_Defaults_GetBlizzardFontPath()
end

local function MSUF_Defaults_GetMenuFontDefault()
    --- Empty means: preserve the locale-aware Blizzard font inherited by each
    --- menu font object instead of replacing it with a Latin-only font file.
    if MSUF_Defaults_UseExpresswayByDefault() then
        return MSUF_DEFAULT_EXPRESSWAY_FONT
    end
    return ""
end

local MSUF_DEFAULT_PREDICTION_BAR_VALUES = {
    tempMaxHealthEnabled = false,
    tempMaxHealthTexture = "Solid",
    tempMaxHealthColorR = 0.70,
    tempMaxHealthColorG = 0.10,
    tempMaxHealthColorB = 0.10,
    tempMaxHealthOpacity = 1,
    tempMaxHealthBackgroundOpacity = 0.65,
    healPredEnabled = true,
    healPredictionBarHeight = 0,
    healPredictionBarOffsetY = 0,
    healPredictionBarOpacity = 0.45,
    healPredictionBarTexture = "",
    enableAbsorbBar = true,
    healAbsorbEnabled = true,
    absorbTextMode = 2,
    absorbAnchorMode = 5,
    absorbBarHeight = 0,
    absorbBarOffsetY = 0,
    healPredAnchorMode = 3,
    absorbBarOpacity = 1,
    absorbBarTexture = "MSUF Smooth v2",
    healAbsorbAnchorMode = 3,
    healAbsorbBarHeight = 0,
    healAbsorbBarOffsetY = 0,
    healAbsorbBarOpacity = 1,
    healAbsorbBarTexture = "Solid",
    overAbsorbOverlay = true,
}

local function MSUF_Defaults_ApplyPredictionBarBaseline(db)
    if type(db) ~= "table" then return end
    db.general = db.general or {}

    local function Apply(conf)
        if type(conf) ~= "table" then return end
        for key, value in pairs(MSUF_DEFAULT_PREDICTION_BAR_VALUES) do
            conf[key] = value
        end
    end

    Apply(db.general)
    db.general.showSelfHealPrediction = true

    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena",
    }) do
        Apply(db[key])
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local conf = db[key]
        Apply(conf)
        if type(conf) == "table" then
            conf.healPredEnabled = true
        end
    end
end

--- Fresh-install completion (applied only when the factory profile payload is seeded).
--- The compact factory export is the visual source of truth; this pass completes
--- structural fields and locale/runtime-dependent product defaults.
local function MSUF_Defaults_ApplyFreshInstallOverrides(db)
    if not db then  return end
    local function SetDefault(tbl, key, value)
        if type(tbl) == "table" and tbl[key] == nil then
            tbl[key] = value
        end
    end

    MSUF_Defaults_ApplyPredictionBarBaseline(db)

    --- Unified alpha defaults: HP fill opacity, power fill opacity, background
    --- texture opacity, plus opt-in exclusions for informational frame elements.
    --- Group frames still use the HP/background subset plus prediction exclusion.
    local function EnsureUnitAlphaDefaults(conf)
        if not conf then  return end
        if conf.hpBarAlpha == nil then conf.hpBarAlpha = 1 end
        if conf.powerBarAlpha == nil then conf.powerBarAlpha = 1 end
        if conf.hpBgAlpha == nil then conf.hpBgAlpha = 0.85 end
        if conf.powerBarBgAlpha == nil then conf.powerBarBgAlpha = conf.hpBgAlpha or 0.85 end
        if conf.alphaExcludeTextPortrait == nil then conf.alphaExcludeTextPortrait = false end
        if conf.alphaExcludePredictionBars == nil then conf.alphaExcludePredictionBars = false end
        if conf.oocFadeEnabled == nil then conf.oocFadeEnabled = false end
        if conf.oocFadeAlpha == nil then conf.oocFadeAlpha = 0.5 end
    end
    local function EnsureFreshUnitframeScreenPosition(conf, x, y)
        if type(conf) ~= "table" then return end
        if conf.anchorFrameName == nil and conf.anchorToUnitframe == nil then
            conf.anchorToUnitframe = "GLOBAL"
        end
        SetDefault(conf, "offsetX", x)
        SetDefault(conf, "offsetY", y)
    end
    local function EnsureFreshGroupAuraNativeRenderer(conf)
        if type(conf) ~= "table" or type(conf.auras) ~= "table" then return end
        local auras = conf.auras
        SetDefault(auras, "renderer", "NATIVE_12_1")
        if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
        local types = auras.blizzardTypes
        SetDefault(types, "buffs", true)
        SetDefault(types, "debuffs", true)
        SetDefault(types, "dispels", true)
        SetDefault(types, "externals", true)
        SetDefault(auras, "blizzardIconSize", 20)
        SetDefault(auras, "blizzardShowCooldownText", true)
        SetDefault(auras, "blizzardOrganizationType", "default")
        SetDefault(auras, "blizzardDispelMode", "allDispellable")
        SetDefault(auras, "blizzardDispelBorder", false)
        SetDefault(auras, "blizzardContainerAnchor", "FRAME")
        SetDefault(auras, "blizzardContainerX", 0)
        SetDefault(auras, "blizzardContainerY", 0)
        for _, key in ipairs({ "buff", "debuff", "externals" }) do
            if type(auras[key]) ~= "table" then auras[key] = {} end
            SetDefault(auras[key], "strata", "AUTO")
            if key == "buff" then SetDefault(auras[key], "trackedStrata", "AUTO") end
            SetDefault(auras[key], "cooldownSwipeReverse", false)
            SetDefault(auras[key], "sortMethod", "DEFAULT")
            SetDefault(auras[key], "sortReverse", false)
            SetDefault(auras[key], "showDurationBar", false)
            SetDefault(auras[key], "durationBarHeight", 2)
            SetDefault(auras[key], "durationBarDisplay", "BAR_ONLY")
            SetDefault(auras[key], "durationBarPosition", "BOTTOM")
            SetDefault(auras[key], "durationBarDirection", "REMAINING")
            if type(auras[key].blacklist) ~= "table" then auras[key].blacklist = {} end
            if type(auras[key].blacklist.spells) ~= "table" then auras[key].blacklist.spells = {} end
            SetDefault(auras[key].blacklist, "hidePermanent", false)
        end
    end
    EnsureUnitAlphaDefaults(db.player)
    --- Fresh-install default: player name hidden
    if type(db.player) == "table" then
        SetDefault(db.player, "showName", false)
    end
    EnsureUnitAlphaDefaults(db.target)
    EnsureUnitAlphaDefaults(db.focus)
    EnsureUnitAlphaDefaults(db.focustarget)
    EnsureUnitAlphaDefaults(db.pet)
    EnsureUnitAlphaDefaults(db.boss)
    EnsureUnitAlphaDefaults(db.targettarget)
    EnsureUnitAlphaDefaults(db.tot)
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        SetDefault(db[key], "alphaExcludePredictionBars", false)
        --- Raid/Mythic-only sorting toggle, seeded on every group scope like the
        --- GroupFrames PARTY_DEFAULTS so the factory snapshot carries it explicitly.
        SetDefault(db[key], "sortRolesAcrossRaid", false)
    end
    --- Older exports may omit screen positions; in that case provide stable
    --- center anchors without touching positions included by the compact export.
    EnsureFreshUnitframeScreenPosition(db.player, -260, 80)
    EnsureFreshUnitframeScreenPosition(db.target, 260, 80)
    EnsureFreshUnitframeScreenPosition(db.focus, 260, 135)
    EnsureFreshUnitframeScreenPosition(db.focustarget, 260, 180)
    EnsureFreshUnitframeScreenPosition(db.pet, -260, 135)
    EnsureFreshUnitframeScreenPosition(db.targettarget or db.tot, 260, 225)
    EnsureFreshUnitframeScreenPosition(db.boss, MSUF_DEFAULT_BOSS_OFFSET_X, MSUF_DEFAULT_BOSS_OFFSET_Y)
    EnsureFreshGroupAuraNativeRenderer(db.gf_party)
    EnsureFreshGroupAuraNativeRenderer(db.gf_raid)
    EnsureFreshGroupAuraNativeRenderer(db.gf_mythicraid)
    --- Factory profiles keep every frame's health coloring linked to the
    --- shared Global Style instead of carrying per-frame color overrides.
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            db[key].healthColorMode = nil
        end
    end
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            db[key].gfBarMode = nil
        end
    end
    --- Factory-only dispel-symbol policy. "Symbol detects" is owned by the
    --- Unit/Group frame roots, not by the Aura lane filter tables. Override
    --- every scope carried by the factory snapshot so a stale local value
    --- cannot mask the shared "Removable by me" baseline.
    if type(db.general) == "table" then
        db.general.unitDispelSymbolTrigger = "BY_ME"
    end
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            db[key].unitDispelSymbolTrigger = "BY_ME"
        end
    end
    for _, key in ipairs(MSUF_DEFAULTS_GROUP_SCOPE_KEYS) do
        if type(db[key]) == "table" then
            db[key].dispelSymbolTrigger = "BY_ME"
        end
    end
    db.bars = db.bars or {}
    SetDefault(db.bars, "showAltMana", false)
    SetDefault(db.bars, "altManaWidthMode", "player")
    SetDefault(db.bars, "altManaWidth", 0)
    SetDefault(db.bars, "altManaOffsetX", 0)
    SetDefault(db.bars, "showGuardianIronfur", false)
    SetDefault(db.bars, "showSweepingStrikes", false)
    SetDefault(db.bars, "guardianIronfurShowHashLines", true)
    -- Performance baseline: native interpolation is an
    -- explicit visual option, never an implicit cost on a fresh profile.
    db.bars.smoothPowerBar = false
    --- Not adopted on Classic: its fresh profiles have never carried this key,
    --- and the shared bars stage seeds it to false anyway when it is missing.
    if not IS_CLASSIC_FAMILY then
        db.bars.chunkedPowerBar = false
    end
    db.bars.classPowerSmoothFill = false
    db.bars.altManaSmoothFill = false
    for _, key in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena" }) do
        if type(db[key]) == "table" then
            db[key].smoothFill = false
            db[key].chunkedFill = false
            db[key].powerSmoothFill = false
            db[key].powerChunkedFill = false
        end
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        if type(db[key]) == "table" then
            db[key].smoothFill = false
            db[key].chunkedFill = false
            db[key].powerSmoothFill = false
            db[key].powerChunkedFill = false
        end
    end
    --- The factory profile starts with MSUF party frames on and Focus Target
    --- (the focus's target) off, whatever the snapshot ships.
    if type(db.gf_party) ~= "table" then db.gf_party = {} end
    db.gf_party.enabled = true
    if type(db.focustarget) ~= "table" then db.focustarget = {} end
    db.focustarget.enabled = false
    SetDefault(db.bars, "roundedFramesEnabled", false)
    SetDefault(db.bars, "roundedUnitFrames", true)
    SetDefault(db.bars, "roundedGroupFrames", true)
    SetDefault(db.bars, "roundedPowerBars", true)
    SetDefault(db.bars, "roundedCastbars", false)
    SetDefault(db.bars, "roundedClassResources", false)
    SetDefault(db.bars, "roundedMouseover", true)
    SetDefault(db.bars, "roundedCornerStrength", 3)
    --- Fresh-install defaults: status indicators (AFK/DND) off by default
    local g = db.general
    if type(g) == 'table' then
        g.statusIndicators = g.statusIndicators or {}
        local si = g.statusIndicators
        SetDefault(si, "showAFK", false)
        SetDefault(si, "showDND", false)

        --- Fresh-install scaling defaults:
        --- Match Unhalted-style global UI scale: disabled until the user enables it.
        SetDefault(g, "anchorToCooldown", false)
        SetDefault(g, "anchorName", "UIParent")
        SetDefault(g, "disableScaling", false)
        SetDefault(g, "globalUiScalePreset", "auto")
        if type(g.UIScale) ~= "table" then
            g.UIScale = { Enabled = false, Scale = 1.0 }
        else
            SetDefault(g.UIScale, "Enabled", false)
            SetDefault(g.UIScale, "Scale", 1.0)
        end
        g.slashMenuScale = 0.8
        SetDefault(g, "msufUiScale", 1.0)
        --- English/German use MSUF's highly readable UI face. Other locales
        --- retain Blizzard's locale-specific glyph coverage.
        g.fontKey = MSUF_Defaults_GetGlobalFontDefault()
        --- Fresh installs use MSUF's bundled, tint-neutral premium bar surface.
        g.barTexture = "MSUF Lucent"
        g.castbarTexture = "MSUF Lucent"
        SetDefault(g, "unitTooltipProvider", "GAME")
        SetDefault(g, "unitTooltipAnchor", "EXTERNAL")
        SetDefault(g, "unitTooltipMode", "ALWAYS")
        SetDefault(g, "unitTooltipModifier", "ALT")
        SetDefault(g, "disableUnitInfoTooltips", true)
        SetDefault(g, "unitInfoTooltipStyle", "classic")
        SetDefault(g, "showGameMenuButton", true)
        SetDefault(g, "previewDragHintAnimationEnabled", true)
        g._msufPreviewDragHintExperienced = false
        -- Start previews clean; the Guides layer is an explicit user choice.
        g.unitPreviewGuidesEnabled = false
        g.classPowerPreviewGuidesEnabled = false
        --- Factory Edit Mode baseline: grid on at 36px with snap, backdrop
        --- dimmed to 55%. The compact snapshot predates these tuned values,
        --- so they are set unconditionally over its stale ones.
        g.editModeGridEnabled = true
        g.editModeGridStep = 36
        g.editModeSnapEnabled = true
        g.editModeBgAlpha = 0.55
        --- Factory castbars fill left to right. The snapshot carries the
        --- exporter's own choice, and the nil-key default stays RTL so
        --- existing profiles keep their direction.
        g.castbarFillDirection = "LTR"
        --- Factory cleanse border lights up for what the group can dispel,
        --- not for every debuff that carries a dispel type.
        g.dispelBorderTrigger = "BY_RAID"
        g.menuFontKey = MSUF_Defaults_GetMenuFontDefault()
        g._msufFactoryNameShorteningFixed_v1 = true
        g._msufFactoryScopedNameShorteningFixed_v1 = true
    end
    MSUF_Defaults_NormalizePortraitRenderDB(db)
end

--- Canonical Unit Aura baseline for the one-time 6.0 Aura reset and for the
--- no-payload fallback. Factory profiles apply a separate explicit overlay
--- below so product positioning can evolve without changing hard-cut geometry.
--- Classic stayed on model revision 1: every profile its builds ever saved
--- carries that number, and the sparse-owner repair below only recognises a
--- profile at the revision it is stamped with. Bumping it on Classic would
--- re-run the legacy aura migrations over settled profiles.
local MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION = IS_CLASSIC_FAMILY and 1 or 2
local MSUF_DEFAULTS_GROUP_AURA_PROFILE_MODEL_REVISION = 1
local MSUF_DEFAULTS_GROUP_AURA_SCOPES = { "gf_party", "gf_raid", "gf_mythicraid" }
local MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer = assert(MSUF.MSUF_CreateCanonicalPlayerDefensiveAuraContainer, "Aura defaults must load before profile defaults")

-- Unit Aura lanes no longer inherit mutable values from auras3.shared.  This
-- cold-path migration snapshots the profile's previously effective values
-- into the exact Unit + Buff/Debuff owner before runtime or Menu2 reads them.
-- The old Shared fields stay as import compatibility input, but changing them
-- afterwards cannot alter a Unit lane.
local MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS = {
    "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3",
}
-- TBC and Mists field five arena opponents (Game/Shared/Initialize.lua); every
-- other client keeps the three above, so this loop does not run there.
for i = 4, ARENA_AURA_SLOTS do
    MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS[#MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS + 1] = "arena" .. i
end
local MSUF_DEFAULTS_UNIT_AURA_LANES = {
    buff = {
        prefix = "buff",
        showKey = "showBuffs", maxKey = "maxBuffs",
        xKey = "buffGroupOffsetX", yKey = "buffGroupOffsetY",
        sizeKey = "buffGroupIconSize", anchorKey = "buffAnchor",
        layerKey = "buffLayer", strataKey = "buffStrata",
        spacingKey = "buffSpacing", perRowKey = "buffPerRow",
        growthKey = "buffGrowthX", wrapKey = "buffGrowthY",
        defaultAnchor = "BOTTOMRIGHT", defaultLayer = 5,
    },
    debuff = {
        prefix = "debuff",
        showKey = "showDebuffs", maxKey = "maxDebuffs",
        xKey = "debuffGroupOffsetX", yKey = "debuffGroupOffsetY",
        sizeKey = "debuffGroupIconSize", anchorKey = "debuffAnchor",
        layerKey = "debuffLayer", strataKey = "debuffStrata",
        spacingKey = "debuffSpacing", perRowKey = "debuffPerRow",
        growthKey = "debuffGrowthX", wrapKey = "debuffGrowthY",
        defaultAnchor = "TOPLEFT", defaultLayer = 6,
    },
}
local MSUF_DEFAULTS_UNIT_AURA_STYLE_LAYOUT = {
    { "IconZoom", "iconZoom", 100 },
    { "StylePadding", "stylePadding", 0 },
    { "DurationBarHeight", "durationBarHeight", 2 },
    { "StackTextSize", "stackTextSize", 14 },
    { "StackTextOffsetX", "stackTextOffsetX", -1 },
    { "StackTextOffsetY", "stackTextOffsetY", 1 },
    { "CooldownTextSize", "cooldownTextSize", 14 },
    { "CooldownTextOffsetX", "cooldownTextOffsetX", 0 },
    { "CooldownTextOffsetY", "cooldownTextOffsetY", 0 },
}
local MSUF_DEFAULTS_UNIT_AURA_STYLE_SHARED = {
    { "ShowCooldownText", "showCooldownText", true },
    { "ShowCooldownSwipe", "showCooldownSwipe", true },
    { "CooldownSwipeReverse", "cooldownSwipeReverse", false },
    { "SortMethod", "sortMethod", "DEFAULT" },
    { "SortReverse", "sortReverse", false },
    { "ShowDurationBar", "showDurationBar", false },
    { "DurationBarDisplay", "durationBarDisplay", "BAR_ONLY" },
    { "DurationBarPosition", "durationBarPosition", "BOTTOM" },
    { "DurationBarDirection", "durationBarDirection", "REMAINING" },
    { "ShowTooltip", "showTooltip", true },
    { "ShowStackCount", "showStackCount", true },
    { "StackCountAnchor", "stackCountAnchor", "TOPRIGHT" },
    { "CooldownTextAnchor", "cooldownTextAnchor", "CENTER" },
    { "CooldownDecimalSeconds", "cooldownDecimalSeconds", 3 },
}
local MSUF_DEFAULTS_AURA_APPEARANCE_KINDS = {
    "buff", "debuff", "playerDefensives", "targetDots",
}
local MSUF_DEFAULTS_AURA_APPEARANCE_STYLE_DEFAULTS = {
    styleBorderEnabled = false,
    styleBorderStyle = "SOLID",
    styleBorderThickness = 1,
    styleBorderColor = { 0, 0, 0, 1 },
    styleShadowEnabled = false,
    styleShadowSize = 4,
    styleShadowColor = { 0, 0, 0, 0.8 },
}

local function MSUF_Defaults_CopyAuraOwnedValue(value)
    if type(value) ~= "table" then return value end
    local out = {}
    MSUF_Defaults_DeepCopy(out, value)
    return out
end

local function MSUF_Defaults_ReadAuraLegacyOwner(owner, ownerActive, shared, laneKey, genericKey, fallback)
    if ownerActive and type(owner) == "table" then
        if owner[laneKey] ~= nil then return owner[laneKey] end
        if genericKey and owner[genericKey] ~= nil then return owner[genericKey] end
    end
    if type(shared) == "table" then
        if shared[laneKey] ~= nil then return shared[laneKey] end
        if genericKey and shared[genericKey] ~= nil then return shared[genericKey] end
    end
    return fallback
end

local function MSUF_Defaults_WriteAuraOwnedValue(owner, key, value)
    owner[key] = MSUF_Defaults_CopyAuraOwnedValue(value)
end

-- Profiles saved with three arena Aura owners gain arena4..N as copies of
-- arena1 once, on clients with more arena slots (TBC and Mists). Existing
-- owners are never overwritten. Without arena1 the slot marker stays unset,
-- so a later pass seeds once arena1 exists. Mainline (3 slots) is a no-op.
local function MSUF_Defaults_SeedExtraArenaAuraOwners(auras)
    local slots = tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3
    if slots <= 3 or type(auras) ~= "table" then return false end
    if (tonumber(auras._msufA3ArenaAuraSlots) or 3) >= slots then return false end
    local perUnit = auras.perUnit
    local source = type(perUnit) == "table" and perUnit.arena1 or nil
    if type(source) ~= "table" then return false end
    for i = 4, slots do
        if type(perUnit["arena" .. i]) ~= "table" then
            perUnit["arena" .. i] = MSUF_Defaults_CopyAuraOwnedValue(source)
        end
    end
    auras._msufA3ArenaAuraSlots = slots
    return true
end

local function MSUF_Defaults_MaterializeUnitAuraLaneOwners(auras)
    if type(auras) ~= "table" then return false end
    if auras._msufA3UnitLaneOwners_v1 == true then
        return MSUF_Defaults_SeedExtraArenaAuraOwners(auras)
    end
    auras.shared = type(auras.shared) == "table" and auras.shared or {}
    auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
    local shared = auras.shared
    -- Seed before the snapshot too, so a legacy arena1 owner (not the Shared
    -- fallback) becomes the source of the new arena4..N lanes.
    MSUF_Defaults_SeedExtraArenaAuraOwners(auras)

    for i = 1, #MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS do
        local unit = MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS[i]
        local pu = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
        auras.perUnit[unit] = pu
        local oldLayout = type(pu.layout) == "table" and pu.layout or nil
        local oldSharedLayout = type(pu.layoutShared) == "table" and pu.layoutShared or nil
        local layoutActive = pu.overrideLayout == true
        local sharedLayoutActive = pu.overrideSharedLayout == true
        local styleActive = pu.overrideStyle == true
            or (pu.overrideStyle == nil and ((oldLayout and next(oldLayout)) or (oldSharedLayout and next(oldSharedLayout))))
        local layout, layoutShared = {}, {}

        for kind, spec in pairs(MSUF_DEFAULTS_UNIT_AURA_LANES) do
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.xKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.xKey, nil, 0))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.yKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.yKey, nil, kind == "buff" and 36 or 6))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.sizeKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.sizeKey, "iconSize", 26))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.anchorKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.anchorKey, nil, spec.defaultAnchor))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.layerKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.layerKey, nil, spec.defaultLayer))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.strataKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.strataKey, nil, "AUTO"))
            MSUF_Defaults_WriteAuraOwnedValue(layout, spec.spacingKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive, shared, spec.spacingKey, "spacing", 2))

            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.showKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.showKey, nil, true))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.maxKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.maxKey, nil, 12))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.perRowKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.perRowKey, "perRow", 12))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.growthKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.growthKey, "growth", "RIGHT"))
            MSUF_Defaults_WriteAuraOwnedValue(layoutShared, spec.wrapKey,
                MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive, shared, spec.wrapKey, "rowWrap", "DOWN"))

            for j = 1, #MSUF_DEFAULTS_UNIT_AURA_STYLE_LAYOUT do
                local field = MSUF_DEFAULTS_UNIT_AURA_STYLE_LAYOUT[j]
                local laneKey = spec.prefix .. field[1]
                MSUF_Defaults_WriteAuraOwnedValue(layout, laneKey,
                    MSUF_Defaults_ReadAuraLegacyOwner(oldLayout, layoutActive and styleActive,
                        shared, laneKey, field[2], field[3]))
            end
            for j = 1, #MSUF_DEFAULTS_UNIT_AURA_STYLE_SHARED do
                local field = MSUF_DEFAULTS_UNIT_AURA_STYLE_SHARED[j]
                local laneKey = spec.prefix .. field[1]
                MSUF_Defaults_WriteAuraOwnedValue(layoutShared, laneKey,
                    MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                        shared, laneKey, field[2], field[3]))
            end

            local framePrefix = spec.prefix .. "FrameEffect"
            for _, suffix in ipairs({ "Type", "Color", "Priority", "Thickness", "Layer", "Strata" }) do
                local key = framePrefix .. suffix
                local fallback = suffix == "Type" and "none"
                    or (suffix == "Color" and { 0.69, 0.50, 0.88, 0.80 })
                    or (suffix == "Priority" and 5)
                    or (suffix == "Thickness" and 2)
                    or (suffix == "Strata" and "AUTO") or 0
                MSUF_Defaults_WriteAuraOwnedValue(layoutShared, key,
                    MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                        shared, key, nil, fallback))
            end
        end

        MSUF_Defaults_WriteAuraOwnedValue(layoutShared, "buffShowStealable",
            MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                shared, "buffShowStealable", nil, false))
        MSUF_Defaults_WriteAuraOwnedValue(layoutShared, "buffStealableStyle",
            MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                shared, "buffStealableStyle", nil, "BORDER_ICON"))
        MSUF_Defaults_WriteAuraOwnedValue(layoutShared, "debuffTypeBorderMode",
            MSUF_Defaults_ReadAuraLegacyOwner(oldSharedLayout, sharedLayoutActive and styleActive,
                shared, "debuffTypeBorderMode", nil, shared.useDebuffTypeBorders == true and "SYMBOL" or "OFF"))
        layoutShared.useDebuffTypeBorders = layoutShared.debuffTypeBorderMode ~= "OFF"

        local sourceFilters = pu.overrideFilters == true and type(pu.filters) == "table" and pu.filters
            or (type(shared.filters) == "table" and shared.filters) or {}
        local filters = MSUF_Defaults_CopyAuraOwnedValue(sourceFilters)
        filters = type(filters) == "table" and filters or {}
        filters.buffs = type(filters.buffs) == "table" and filters.buffs or {}
        filters.debuffs = type(filters.debuffs) == "table" and filters.debuffs or {}
        if filters.buffs.enabled == nil then filters.buffs.enabled = sourceFilters.enabled ~= false end
        if filters.debuffs.enabled == nil then filters.debuffs.enabled = sourceFilters.enabled ~= false end

        pu.layout = layout
        pu.layoutShared = layoutShared
        pu.filters = filters
        pu.overrideLayout = true
        pu.overrideSharedLayout = true
        pu.overrideStyle = true
        pu.overrideFilters = true
    end

    -- Appearance is the one intentional global Aura owner, keyed by product.
    -- Snapshot legacy flat style/shape values so those old scalars become inert.
    shared.appearanceIconShapes = type(shared.appearanceIconShapes) == "table"
        and shared.appearanceIconShapes or {}
    shared.appearanceIconStyles = type(shared.appearanceIconStyles) == "table"
        and shared.appearanceIconStyles or {}
    for i = 1, #MSUF_DEFAULTS_AURA_APPEARANCE_KINDS do
        local kind = MSUF_DEFAULTS_AURA_APPEARANCE_KINDS[i]
        local harmful = kind == "debuff" or kind == "targetDots"
        if shared.appearanceIconShapes[kind] == nil then
            shared.appearanceIconShapes[kind] = shared[harmful and "debuffIconShape" or "buffIconShape"]
                or shared.iconShape or (kind == "playerDefensives" and "FOLLOW_PORTRAIT" or "RECTANGLE")
        end
        local style = type(shared.appearanceIconStyles[kind]) == "table"
            and shared.appearanceIconStyles[kind] or {}
        shared.appearanceIconStyles[kind] = style
        for key, fallback in pairs(MSUF_DEFAULTS_AURA_APPEARANCE_STYLE_DEFAULTS) do
            if style[key] == nil then
                style[key] = MSUF_Defaults_CopyAuraOwnedValue(
                    shared[key] ~= nil and shared[key] or fallback)
            end
        end
    end

    auras.profileModelRevision = MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
    auras._msufA3UnitLaneOwners_v1 = true
    MSUF_Defaults_SeedExtraArenaAuraOwners(auras)
    return true
end
ExportPublic("MSUF_MaterializeUnitAuraLaneOwners", MSUF_Defaults_MaterializeUnitAuraLaneOwners)
if type(MSUF) == "table" then
    MSUF.MSUF_MaterializeUnitAuraLaneOwners = MSUF_Defaults_MaterializeUnitAuraLaneOwners
end

local function MSUF_Defaults_CreateCanonicalUnitAuras()
    local function Filters()
        return {
            enabled = true,
            hidePermanent = false,
            buffs = {
                onlyMine = false,
                onlyImportant = false,
                includeDispellable = false,
                dispellableAny = false,
                raid = false,
                raidInCombat = false,
                includeNameplateOnly = false,
                cancelable = false,
                notCancelable = false,
                externalDefensive = false,
                bigDefensive = false,
                exclusive = "none",
            },
            debuffs = {
                onlyMine = false,
                onlyImportant = false,
                includeDispellable = false,
                dispellableAny = false,
                raid = false,
                raidInCombat = false,
                includeNameplateOnly = false,
                crowdControl = false,
                exclusive = "none",
            },
        }
    end
    local auras = {
        profileModelRevision = MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION,
        enabled = true,
        showPlayer = false,
        showTarget = true,
        showFocus = false,
        showBoss = true,
        showArena = true,
        customDisplays = {
            serial = 0,
            shared = { items = {} },
            perUnit = {},
        },
        customContainers = {
            perUnit = {
                player = {
                    items = {
                        [4] = MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer(),
                    },
                },
            },
        },
        shared = {
            bossEditTogether = true,
            arenaEditTogether = true,
            hideBlizzardBuffFrame = false,
            hideBlizzardDebuffFrame = false,
            buffGroupOffsetX = 0,
            buffGroupOffsetY = 36,
            debuffGroupOffsetX = 0,
            debuffGroupOffsetY = 6,
            buffGroupIconSize = 26,
            debuffGroupIconSize = 26,
            cooldownTextSize = 14,
            iconSize = 26,
            iconZoom = 100,
            buffIconZoom = 100,
            debuffIconZoom = 100,
            appearanceIconShapes = { playerDefensives = "FOLLOW_PORTRAIT" },
            spacing = 2,
            buffSpacing = 2,
            debuffSpacing = 2,
            stackTextSize = 14,
            growth = "RIGHT",
            buffGrowthX = "RIGHT",
            buffGrowthY = "DOWN",
            debuffGrowthX = "RIGHT",
            debuffGrowthY = "DOWN",
            perRow = 12,
            maxBuffs = 12,
            maxDebuffs = 12,
            showBuffs = true,
            showDebuffs = true,
            showCooldownText = true,
            showCooldownSwipe = true,
            cooldownSwipeReverse = false,
            buffShowStealable = false,
            buffStealableStyle = "BORDER_ICON",
            buffSortMethod = "DEFAULT",
            buffSortReverse = false,
            debuffSortMethod = "DEFAULT",
            debuffSortReverse = false,
            showDurationBar = false,
            durationBarHeight = 2,
            durationBarDisplay = "BAR_ONLY",
            durationBarPosition = "BOTTOM",
            durationBarDirection = "REMAINING",
            showStackCount = true,
            debuffTypeBorderMode = "OFF",
            useDebuffTypeBorders = false,
            showTooltip = true,
            buffFrameEffectType = "none",
            buffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
            buffFrameEffectPriority = 5,
            buffFrameEffectThickness = 2,
            buffFrameEffectLayer = 0,
            buffFrameEffectStrata = "AUTO",
            debuffFrameEffectType = "none",
            debuffFrameEffectColor = { 0.69, 0.50, 0.88, 0.80 },
            debuffFrameEffectPriority = 5,
            debuffFrameEffectThickness = 2,
            debuffFrameEffectLayer = 0,
            debuffFrameEffectStrata = "AUTO",
            showInEditMode = true,
            stackCountAnchor = "TOPRIGHT",
            stackTextOffsetX = -1,
            stackTextOffsetY = 1,
            cooldownTextAnchor = "CENTER",
            cooldownTextOffsetX = 0,
            cooldownTextOffsetY = 0,
            cooldownDecimalSeconds = 3,
            buffAnchor = "BOTTOMRIGHT",
            debuffAnchor = "TOPLEFT",
            buffLayer = 5,
            debuffLayer = 6,
            filters = Filters(),
        },
        perUnit = {
            target = {
                overrideLayout = true,
                overrideFilters = false,
                layout = {
                    buffGroupOffsetX = -3,
                    buffGroupOffsetY = 0,
                    debuffGroupOffsetX = 230,
                    debuffGroupOffsetY = 2,
                    buffGroupIconSize = 34,
                    debuffGroupIconSize = 34,
                    buffSpacing = 2,
                    debuffSpacing = 2,
                },
                overrideSharedLayout = true,
                layoutShared = {
                    maxBuffs = 4,
                    maxDebuffs = 3,
                    perRow = 8,
                    buffGrowthX = "RIGHT",
                    buffGrowthY = "UP",
                    debuffGrowthX = "UP",
                    debuffGrowthY = "UP",
                },
                filters = Filters(),
            },
            focus = {
                overrideLayout = true,
                overrideFilters = false,
                layout = {
                    buffGroupOffsetX = -1,
                    buffGroupOffsetY = 0,
                    debuffGroupOffsetX = 125,
                    debuffGroupOffsetY = 1,
                    buffGroupIconSize = 30,
                    debuffGroupIconSize = 26,
                    buffSpacing = 2,
                    debuffSpacing = 2,
                },
                filters = Filters(),
            },
        },
    }

    --- Boss per-unit defaults (1-5).
    for i = 1, 5 do
        local key = "boss" .. i
        auras.perUnit[key] = {
            overrideLayout = true,
            overrideFilters = false,
            layout = {
                buffGroupOffsetX = -1,
                buffGroupOffsetY = -3,
                debuffGroupOffsetX = 234,
                debuffGroupOffsetY = -45,
                buffGroupIconSize = 40,
                debuffGroupIconSize = 26,
                buffSpacing = 2,
                debuffSpacing = 2,
            },
            filters = Filters(),
        }
    end
    --- Arena per-unit defaults (1-3, 1-5 on TBC and Mists): debuffs matter
    --- most on enemy players, keep the compact boss-style lane geometry.
    for i = 1, ARENA_AURA_SLOTS do
        local key = "arena" .. i
        auras.perUnit[key] = {
            overrideLayout = true,
            overrideFilters = false,
            layout = {
                buffGroupOffsetX = -1,
                buffGroupOffsetY = -3,
                debuffGroupOffsetX = 234,
                debuffGroupOffsetY = -45,
                buffGroupIconSize = 26,
                debuffGroupIconSize = 26,
                buffSpacing = 2,
                debuffSpacing = 2,
            },
            filters = Filters(),
        }
    end
    MSUF_Defaults_MaterializeUnitAuraLaneOwners(auras)
    return auras
end
ExportPublic("MSUF_CreateCanonicalUnitAuras", MSUF_Defaults_CreateCanonicalUnitAuras)
if type(MSUF) == "table" then
    MSUF.MSUF_CreateCanonicalUnitAuras = MSUF_Defaults_CreateCanonicalUnitAuras
end

--- Product-facing factory variant. Keep the hard-cut builder above stable:
--- pre-marker profiles preserve compiler-effective size/position by rebasing
--- against that baseline, while new/reset profiles use the authored 6.0 layout.
local function MSUF_Defaults_CreateFactoryUnitAuras()
    local auras = MSUF_Defaults_CreateCanonicalUnitAuras()
    auras.showPlayer = true
    auras.showFocus = true

    local shared = auras.shared
    shared.buffGroupOffsetX = 0
    shared.buffGroupOffsetY = 34
    shared.debuffGroupOffsetX = 330
    shared.debuffGroupOffsetY = 34
    shared.buffGroupIconSize = 28
    shared.debuffGroupIconSize = 28
    shared.buffAnchor = "BOTTOMLEFT"
    shared.debuffAnchor = "BOTTOMRIGHT"

    local perUnit = auras.perUnit
    local function SetScope(unit, values)
        local scope = type(perUnit[unit]) == "table" and perUnit[unit] or {}
        perUnit[unit] = scope
        scope.overrideLayout = true
        scope.layout = {
            offsetX = 243,
            offsetY = 27,
            iconSize = 28,
            buffGroupOffsetX = values.buffX,
            buffGroupOffsetY = values.buffY,
            debuffGroupOffsetX = values.debuffX,
            debuffGroupOffsetY = values.debuffY,
            buffGroupIconSize = 31,
            debuffGroupIconSize = 32,
            buffSpacing = 0,
            debuffSpacing = 0,
        }
        scope.overrideSharedLayout = true
        scope.layoutShared = {
            maxBuffs = values.maxBuffs,
            maxDebuffs = values.maxDebuffs,
            buffPerRow = 4,
            debuffPerRow = 4,
        }
    end

    SetScope("player", { buffX = -2, buffY = 41, debuffX = 2, debuffY = 40,
        maxBuffs = 3, maxDebuffs = 4 })
    SetScope("target", { buffX = -1, buffY = 42, debuffX = 0, debuffY = 42,
        maxBuffs = 3, maxDebuffs = 4 })
    SetScope("focus", { buffX = -2, buffY = 32, debuffX = 119, debuffY = 2,
        maxBuffs = 3, maxDebuffs = 4 })
    for i = 1, 5 do
        SetScope("boss" .. i, { buffX = -1, buffY = 28, debuffX = 131, debuffY = -2,
            maxBuffs = 3, maxDebuffs = 4 })
    end
    for i = 1, ARENA_AURA_SLOTS do
        SetScope("arena" .. i, { buffX = -1, buffY = 28, debuffX = 131, debuffY = -2,
            maxBuffs = 3, maxDebuffs = 4 })
    end

    local defensive = auras.customContainers.perUnit.player.items[4]
    defensive.portraitIcon = true
    defensive.placed.x = -293
    defensive.placed.y = 11
    auras._msufA3UnitLaneOwners_v1 = nil
    MSUF_Defaults_MaterializeUnitAuraLaneOwners(auras)
    return auras
end

--- Classic only. 6.5-alpha18 to 6.5-beta3 saved the factory scope above without
--- its final re-materialize: every authored owner kept only its sparse tables
--- under a lane-owner marker that was already set, so no pass ever completed it,
--- and the Classic aura compile, which reads only the owner, anchored buffs
--- BOTTOMRIGHT and debuffs TOPLEFT. Up to 6.5-beta2 only New Profile wrote
--- them; 6.5-beta3 also first login and reset, with player and target
--- retuned. Buff x/y and debuff x/y per unit family, as those builds saved them.
--- Midnight and WoW Forever never shipped those builds and never call this.
local MSUF_DEFAULTS_SPARSE_FACTORY_AURA_OFFSETS = {
    player = { { -2, 32, 3, 32 }, { -2, 46, 2, 49 } },
    target = { { -2, 32, 3, 32 }, { -1, 42, 0, 42 } },
    focus = { { -2, 32, 119, 2 } },
    boss = { { -1, 28, 131, -2 } },
    arena = { { -1, 28, 131, -2 } },
}

local function MSUF_Defaults_AuraValuesEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not MSUF_Defaults_AuraValuesEqual(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

--- One-shot repair of those saved owners, decided per owner. An owner is
--- untouched only when it equals, key for key and value for value, what one
--- of those builds saved for its unit; the only extras allowed are the two a
--- mere read of the aura menu writes (_msufA3SparseVisualOverrides_v2 = true,
--- filters.debuffs.nonPlayer = false). An untouched owner is re-materialized in
--- place against the factory shared record, the pass a new profile runs; every
--- other owner, the saved shared record and the lane-owner marker stay as they
--- are. The stamp is written only with a repair, so a profile without an
--- untouched owner stays byte-for-byte unchanged.
local function MSUF_Defaults_RepairSparseFactoryAuraOwners(db)
    local auras = type(db) == "table" and db.auras3 or nil
    if type(auras) ~= "table" or type(auras.perUnit) ~= "table"
        or auras._msufA3UnitLaneOwners_v1 ~= true
        or auras._msufA3SparseLaneOwnersRepaired_v1 == true
        or auras.profileModelRevision ~= MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION then
        return false
    end
    local canonical, scope
    for i = 1, #MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS do
        local unit = MSUF_DEFAULTS_UNIT_AURA_RUNTIME_UNITS[i]
        local owner = auras.perUnit[unit]
        local layout = type(owner) == "table" and owner.layout or nil
        -- Only the sparse factory tables carry these legacy keys, so complete
        -- owners leave here without allocating anything.
        if type(layout) == "table" and layout.offsetX == 243 and layout.offsetY == 27 and layout.iconSize == 28 then
            canonical = canonical or MSUF_Defaults_CreateCanonicalUnitAuras()
            local variants = MSUF_DEFAULTS_SPARSE_FACTORY_AURA_OFFSETS[unit:match("^%a+")] or {}
            local readFilters = type(owner.filters) == "table" and owner.filters.debuffs
            for v = 1, #variants do
                local offsets = variants[v]
                local saved = MSUF_Defaults_CopyAuraOwnedValue(canonical.perUnit[unit])
                saved.layout = {
                    offsetX = 243, offsetY = 27, iconSize = 28,
                    buffGroupOffsetX = offsets[1], buffGroupOffsetY = offsets[2],
                    debuffGroupOffsetX = offsets[3], debuffGroupOffsetY = offsets[4],
                    buffGroupIconSize = 31, debuffGroupIconSize = 32, buffSpacing = 0, debuffSpacing = 0,
                }
                saved.layoutShared = { maxBuffs = 3, maxDebuffs = 4, buffPerRow = 4, debuffPerRow = 4 }
                if owner._msufA3SparseVisualOverrides_v2 == true then saved._msufA3SparseVisualOverrides_v2 = true end
                if type(readFilters) == "table" and readFilters.nonPlayer == false then
                    saved.filters.debuffs.nonPlayer = false
                end
                if MSUF_Defaults_AuraValuesEqual(owner, saved) then
                    scope = scope or { shared = MSUF_Defaults_CreateFactoryUnitAuras().shared, perUnit = {} }
                    scope.perUnit[unit] = owner
                    break
                end
            end
        end
    end
    if not scope then return false end
    -- A scratch scope holding only the untouched owners: the pass completes
    -- them in place and every other table it builds is dropped with it.
    MSUF_Defaults_MaterializeUnitAuraLaneOwners(scope)
    auras._msufA3SparseLaneOwnersRepaired_v1 = true
    return true
end

--- Canonical Group Aura baseline. This is intentionally authored as native
--- 6.0 data instead of being copied from the embedded compatibility snapshot.
--- Spell Indicators start empty and are populated by the current live
--- SpecDefaults seeder, so retired saved icons can never become factory data.
local function MSUF_Defaults_CreateCanonicalGroupAuraState(preserveExistingFilterDefaults)
    local function Lane(values)
        return {
            _filterMigV3 = true,
            enabled = values.enabled ~= false,
            anchor = values.anchor,
            growth = values.growth,
            x = values.x,
            y = values.y,
            size = values.size,
            iconScale = 100,
            iconZoom = 100,
            spacing = values.spacing,
            perRow = values.perRow,
            max = values.max,
            layer = values.layer,
            strata = "AUTO",
            filterToken = values.filterToken,
            blacklistCats = {},
            blacklist = { hidePermanent = false, spells = {} },
            showTooltip = true,
            showCooldownSwipe = true,
            cooldownSwipeReverse = false,
            sortMethod = "DEFAULT",
            sortReverse = false,
            showDurationBar = false,
            durationBarHeight = 2,
            durationBarDisplay = "BAR_ONLY",
            durationBarPosition = "BOTTOM",
            durationBarDirection = "REMAINING",
            showCooldown = true,
            showStacks = values.showStacks ~= false,
            cooldownSize = values.cooldownSize or 10,
            cooldownAnchor = "CENTER",
            cooldownX = 0,
            cooldownY = 0,
            cooldownDecimalSeconds = 3,
            stackSize = values.stackSize or 10,
            stackAnchor = "BOTTOMRIGHT",
            stackX = 0,
            stackY = 0,
        }
    end

    local function Scope(isRaid)
        -- Factory creation/reset opts into MSUF Highlights. Compatibility
        -- callers repairing an already-saved profile explicitly request the
        -- former defaults so a missing legacy field cannot change its display.
        local buffFilterToken = preserveExistingFilterDefaults == true
            and (isRaid and "Raid" or "RaidPlayer")
            or "MSUF_GROUP_HIGHLIGHTS_V1"
        local auras = {
            profileModelRevision = MSUF_DEFAULTS_GROUP_AURA_PROFILE_MODEL_REVISION,
            enabled = true,
            renderer = "NATIVE_12_1",
            dynamicScale = false,
            iconZoom = 100,
            showTooltip = true,
            blizzardTypes = {
                buffs = false,
                debuffs = true,
                dispels = true,
                externals = true,
                privateAuras = true,
            },
            blizzardIconSize = isRaid and 18 or 20,
            blizzardShowCooldownText = true,
            blizzardOrganizationType = "default",
            blizzardDispelMode = "allDispellable",
            blizzardDispelBorder = false,
            blizzardContainerAnchor = "FRAME",
            blizzardContainerX = 0,
            blizzardContainerY = 0,
        }
        if isRaid then
            auras.buff = Lane({
                anchor = "TOPLEFT", growth = "RIGHTDOWN", x = 14, y = -2,
                size = 12, spacing = 0, perRow = 1, max = 1, layer = 8,
                filterToken = buffFilterToken, stackSize = 10,
            })
            auras.debuff = Lane({
                anchor = "BOTTOMLEFT", growth = "RIGHTUP", x = 20, y = 2,
                size = 18, spacing = 0, perRow = 1, max = 1, layer = 10,
                filterToken = "ALL", stackSize = 10,
            })
            auras.externals = Lane({
                anchor = "BOTTOMLEFT", growth = "RIGHTUP", x = 2, y = 2,
                size = 16, spacing = 1, perRow = 1, max = 1, layer = 11,
                filterToken = "RAID", stackSize = 10, showStacks = false,
            })
        else
            auras.buff = Lane({
                anchor = "TOPLEFT", growth = "RIGHTDOWN", x = 44, y = -2,
                size = 14, spacing = 0, perRow = 1, max = 1, layer = 8,
                filterToken = buffFilterToken, stackSize = 10,
            })
            auras.debuff = Lane({
                anchor = "BOTTOMLEFT", growth = "RIGHTUP", x = 22, y = 2,
                size = 20, spacing = 0, perRow = 1, max = 1, layer = 10,
                filterToken = "ALL", stackSize = 12,
            })
            auras.externals = Lane({
                anchor = "BOTTOMLEFT", growth = "RIGHTUP", x = 2, y = 2,
                size = 18, spacing = 1, perRow = 1, max = 1, layer = 11,
                filterToken = "RAID", stackSize = 11, showStacks = false,
            })
        end
        auras.externals.autoBlacklistBuffs = true
        auras.debuff.dispelBorderMode = "OFF"

        return {
            auras = auras,
            -- The retired custom Private-Aura host is kept explicitly off.
            -- Blizzard-owned Private Auras remain governed by blizzardTypes.
            privateAuras = {
                enabled = false, max = 1, size = isRaid and 10 or 12,
                anchor = "RIGHT", direction = "LEFT", spacing = 1,
                x = -4, y = 0, layer = 12,
                showCountdown = true, showNumbers = false,
            },
            -- Current spec defaults are seeded from executable 6.0 data after
            -- profile initialization; no saved spell-icon snapshot is reused.
            spellIndicators = {
                enabled = false, spec = "auto", specs = {},
                layer = 9, strata = "AUTO", iconZoom = 100, iconScale = 100,
                _autoSeededSpecs = {},
            },
        }
    end

    return {
        gf_party = Scope(false),
        gf_raid = Scope(true),
        gf_mythicraid = Scope(true),
    }
end
ExportPublic("MSUF_CreateCanonicalGroupAuraState", MSUF_Defaults_CreateCanonicalGroupAuraState)
if type(MSUF) == "table" then
    MSUF.MSUF_CreateCanonicalGroupAuraState = MSUF_Defaults_CreateCanonicalGroupAuraState
end

--- Factory profile flow:
--- The embedded compact string is a product baseline for brand-new installs.
--- It is decoded only when MSUF_DB is empty or contains only early bootstrap
--- buckets created before the UnitFrame factory runs, then normal defaults
--- and migrations still run afterward to fill fields added after the snapshot.
local function MSUF_Defaults_CreateFactoryProfile()
    -- Prefer the shared codec once it has loaded: it inflates before CBOR, the
    -- same order Blizzard uses. The local decoder is only the pre-codec fallback.
    local decode = _G.MSUF_TryDecodeCompactString
    if type(decode) ~= "function" then
        decode = MSUF_Defaults_TryDecodeCompactString
    end
    local tbl = decode(MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    if not tbl then  return nil end
    local payload = MSUF_Defaults_GetProfilePayload(tbl)
    if type(payload) ~= "table" then  return nil end

    local out = {}
    MSUF_Defaults_DeepCopy(out, payload)
    --- The portable payload predates the Focus Target frame and has no table for
    --- it. A current export carries that frame in its native 6.0 section, so take
    --- it from there instead of falling back to the code defaults.
    if out.focustarget == nil and type(tbl.msuf6) == "table" and type(tbl.msuf6.payload) == "table"
        and type(tbl.msuf6.payload.focustarget) == "table" then
        out.focustarget = {}
        MSUF_Defaults_DeepCopy(out.focustarget, tbl.msuf6.payload.focustarget)
    end
    MSUF_Defaults_ApplyFreshInstallOverrides(out)
    --- The compact factory snapshot intentionally remains portable to older
    --- releases and therefore still contains Aura2 compatibility data. Fresh
    --- 6.0 profiles use the explicit native factory variant, never that
    --- compatibility payload or the migration-only hard-cut geometry.
    out.auras = nil
    out.auras2 = nil
    out.auras3 = MSUF_Defaults_CreateFactoryUnitAuras()
    local groupAuraState = MSUF_Defaults_CreateCanonicalGroupAuraState()
    if type(groupAuraState) == "table" then
        for i = 1, #MSUF_DEFAULTS_GROUP_AURA_SCOPES do
            local scope = MSUF_DEFAULTS_GROUP_AURA_SCOPES[i]
            local state = groupAuraState[scope]
            local conf = type(out[scope]) == "table" and out[scope] or {}
            out[scope] = conf
            if type(state) == "table" then
                conf.auras = state.auras
                conf.privateAuras = state.privateAuras
                conf.spellIndicators = state.spellIndicators
            end
        end
    end
    MSUF_Defaults_NormalizeProfileTo60Defaults(out)
    --- The compact snapshot predates the shared Appearance products, and its
    --- Player Defensive container replaces the portrait (portraitIcon = true).
    --- Factory baselines therefore follow the frame portrait shape instead of
    --- inheriting the rectangular legacy fallback.
    if type(out.auras3) == "table" then
        local auraShared = type(out.auras3.shared) == "table" and out.auras3.shared or {}
        out.auras3.shared = auraShared
        local shapes = type(auraShared.appearanceIconShapes) == "table" and auraShared.appearanceIconShapes or {}
        auraShared.appearanceIconShapes = shapes
        if shapes.playerDefensives == nil then shapes.playerDefensives = "FOLLOW_PORTRAIT" end
    end
    out.general = out.general or {}
    out.general._msufFactoryProfileApplied = true
    out._msufFactoryPlayerDefensivesEnabled_v1 = MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED
    return out
end
local MSUF_DEFAULTS_FACTORY_BOOTSTRAP_ROOTS = {
    gameplay = true,
    general = true,
    _msufProfileSchema = true,
    _msufProfileNormalizationRevision = true,
}
local MSUF_DEFAULTS_FACTORY_BOOTSTRAP_GENERAL_KEYS = {
    fontBaselineOffset = true,
    minimapIconDB = true,
    showGameMenuButton = true,
    showMinimapIcon = true,
    previewDragHintAnimationEnabled = true,
    --- Written by the profile init (State/MSUF_Profiles.lua) on every profile
    --- that lacks it, brand-new ones included; the factory profile resets it.
    _msufPreviewDragHintExperienced = true,
}
local function MSUF_Defaults_TableHasOnlyAllowedKeys(tbl, allowed)
    if type(tbl) ~= "table" then return false end
    for key in pairs(tbl) do
        if not allowed[key] then
            return false
        end
    end
    return true
end
local function MSUF_Defaults_IsFreshInstallProfileDB(db)
    if type(db) ~= "table" then return false end
    if next(db) == nil then return true end

    local g = (type(db.general) == "table") and db.general or nil
    if g and g._msufFactoryProfileApplied then
        return false
    end

    --- On a true first login, startup modules registered before the UF factory
    --- may create harmless roots such as gameplay/general before EnsureDB runs.
    --- Treat only that pre-seed shape as fresh; any unit/config root means this
    --- profile already has real saved data and must not be overwritten.
    for key, value in pairs(db) do
        if not MSUF_DEFAULTS_FACTORY_BOOTSTRAP_ROOTS[key] then
            return false
        end
        if key == "general"
            and not MSUF_Defaults_TableHasOnlyAllowedKeys(value, MSUF_DEFAULTS_FACTORY_BOOTSTRAP_GENERAL_KEYS) then
            return false
        end
    end
    return true
end
local function MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall(profileDB)
    if type(profileDB) ~= "table" then  return end
    local g = (type(profileDB.general) == "table") and profileDB.general or nil
    if g and g._msufFactoryProfileApplied then
         return
    end
    if not MSUF_Defaults_IsFreshInstallProfileDB(profileDB) then return end
    local payload = MSUF_Defaults_CreateFactoryProfile()
    if type(payload) ~= "table" then  return end
    --- Overlay the fresh DB with the decoded payload. DeepCopy replaces known
    --- payload tables and leaves unrelated future bootstrap buckets intact.
    MSUF_Defaults_DeepCopy(profileDB, payload)
end
local function MSUF_Defaults_RepairFactoryNameShortening(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufFactoryProfileApplied == true) then return false end

    --- Modern factory snapshots already contain their intended name settings.
    --- A factory marker is provenance for the original seed, not proof that
    --- every value is still factory-owned: users may have customized any of
    --- these fields before this migration marker existed. Complete the
    --- migration without rewriting divergent SavedVariables.
    if g._msufModernFactoryProfile_v1 == true then
        if g._msufModernFactoryNameShortening_v2 == true then return false end
        g._msufModernFactoryNameShortening_v2 = true
        return false
    end

    local looksLikeFactoryShortening = db.shortenNames == true
        and tonumber(g.shortenNameMaxChars) == 8
        and tostring(g.shortenNameClipSide or ""):upper() == "RIGHT"
        and g.shortenNameShowDots == false
    if g._msufFactoryNameShorteningFixed_v1 == true
        and g._msufFactoryScopedNameShorteningFixed_v1 == true then
        return false
    end
    local changed = false
    if g._msufFactoryNameShorteningFixed_v1 ~= true or looksLikeFactoryShortening then
        if looksLikeFactoryShortening then
            db.shortenNames = false
            changed = true
        end
        g._msufFactoryNameShorteningFixed_v1 = true
    end
    if g._msufFactoryScopedNameShorteningFixed_v1 ~= true then
        --- Scoped values have no complete old-factory signature. Preserve them
        --- instead of treating any enabled scope as proof of factory ownership.
        g._msufFactoryScopedNameShorteningFixed_v1 = true
    end
    return changed
end

local function MSUF_Defaults_RepairModernFactoryPlayerStack(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufModernFactoryProfile_v1 == true)
        or g._msufModernFactoryPlayerStack_v1 == true then
        return false
    end

    local changed = false
    local player = type(db.player) == "table" and db.player or nil
    --- v23 placed the 16 px Player castbar over the detached 8 px powerbar:
    --- frame bottom -> power Y -6..-14, castbar top -> Y -4. Only repair that
    --- exact factory geometry so a manually moved castbar stays untouched.
    if player
        and player.powerBarDetached == true
        and tonumber(player.detachedPowerBarHeight) == 8
        and tonumber(player.detachedPowerBarOffsetY) == -6
        and tonumber(g.castbarPlayerBarHeight) == 16
        and tonumber(g.castbarPlayerOffsetY) == -48 then
        g.castbarPlayerOffsetY = -64
        changed = true
    end
    g._msufModernFactoryPlayerStack_v1 = true
    return changed
end

local function MSUF_Defaults_RepairModernFactoryNamePresentation(db)
    if type(db) ~= "table" then return false end
    local g = type(db.general) == "table" and db.general or nil
    if not (g and g._msufModernFactoryProfile_v1 == true)
        or g._msufModernFactoryNamePresentation_v1 == true then
        return false
    end

    --- The refreshed embedded factory profile already has these values. Older
    --- profiles may have diverged legitimately, so this one-shot marker must
    --- never act as a broad overwrite transaction.
    g._msufModernFactoryNamePresentation_v1 = true
    return false
end

local MSUF_DB_LastHeavyRun
local MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA = 600
--- Persisted completion marker for the broad default-fill/repair pass below.
--- Bump this whenever MSUF_EnsureDB_Heavy gains a new mandatory default or
--- one-shot repair; current profiles can then be repaired exactly once again.
--- Cross-reference: State/MSUF_Profiles.lua runs a second, independent alias
--- normalization pipeline (MSUF_ProfileIO_TranslateProfileToCurrent, gated by
--- MSUF_PROFILEIO_CURRENT_NORMALIZATION_REVISION) over the same text/status/
--- aura alias keys, using the wider StateHelpers.ProfileIOSpec. The two
--- revisions are bumped independently and are deliberately not merged; keep
--- both in mind when a key alias changes.
local MSUF_DEFAULTS_CURRENT_REVISION = 15
local MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = 7

local MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION = 10

--- Root tables are the contract every other module assumes after EnsureDB.
--- Add new top-level SavedVariables buckets here before modules start reading
--- them, then fill nested defaults later in MSUF_EnsureDB_Heavy.
local MSUF_DEFAULTS_ROOT_TABLE_KEYS = {
    "general",
    "classColors",
    "npcColors",
    "bars",
    "gameplay",
    "player",
    "target",
    "targettarget",
    "focustarget",
    "focus",
    "pet",
    "boss",
    "arena",
}
local function MSUF_Defaults_EnsureRootTables(profileDB)
    for _, key in ipairs(MSUF_DEFAULTS_ROOT_TABLE_KEYS) do
        if type(profileDB[key]) ~= "table" then
            profileDB[key] = {}
        end
    end
end

--- Migration helpers live above MSUF_EnsureDB_Heavy so the heavy function reads
--- as "ensure roots, migrate old profile shapes, then fill missing defaults".
--- Keep migrations idempotent: EnsureDB can be forced after imports/profile
--- switches and must be safe to run repeatedly on the same profile table.
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
    ["Fritz Soundscape"] = "SOUNDSCAPE",
}

local MSUF_DEFAULTS_UNIT_DISPEL_KEYS = {
    "unitDispelOverlayEnabled", "unitDispelOverlayStyle", "unitDispelOverlayOnHealth",
    "unitDispelOverlayAlpha", "unitDispelOverlayTrigger",
    "unitDispelSymbolEnabled", "unitDispelSymbolStyle", "unitDispelSymbolMode",
    "unitDispelSymbolTrigger", "unitDispelSymbolSize", "unitDispelSymbolSpacing",
    "unitDispelSymbolGrowth", "unitDispelSymbolAnchor", "unitDispelSymbolX",
    "unitDispelSymbolY", "unitDispelSymbolAlpha", "unitDispelSymbolLayer",
    "unitDispelSymbolStrata",
}

local function MSUF_Defaults_MigrateUnitDispelOwnership(db)
    if type(db) ~= "table" then return end
    local general = type(db.general) == "table" and db.general or {}
    if (tonumber(general.unitDispelOwnershipVersion) or 0) >= 1 then return end
    for _, unitKey in ipairs({ "player", "target", "focus", "boss", "arena" }) do
        local conf = type(db[unitKey]) == "table" and db[unitKey] or {}
        db[unitKey] = conf
        local usedUnitBars = conf.hlOverride == true
        for _, key in ipairs(MSUF_DEFAULTS_UNIT_DISPEL_KEYS) do
            -- Snapshot the value the old Bars-scoped compiler actually used.
            -- This deliberately replaces stale unit values hidden behind a
            -- disabled Bars override, preserving appearance during the split.
            local value = usedUnitBars and conf[key] or nil
            if value == nil then value = general[key] end
            if value ~= nil then conf[key] = value end
        end
    end
    -- This is intentionally a portable profile field, not a private _msuf key:
    -- exports strip private metadata, and replaying this flattening after an
    -- import would overwrite the independent per-unit choices it just created.
    general.unitDispelOwnershipVersion = 1
end

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

local MSUF_DISPEL_PRIORITY_MIGRATION = 5
local MSUF_DISPEL_TYPE_PRIORITY_KEYS = {
    magic = true,
    curse = true,
    disease = true,
    poison = true,
    bleed = true,
}
local MSUF_PRIORITY_KEY_ALIAS = {
    Dispel = "dispel",
    DISPEL = "dispel",
    Magic = "magic",
    MAGIC = "magic",
    Curse = "curse",
    CURSE = "curse",
    Disease = "disease",
    DISEASE = "disease",
    Poison = "poison",
    POISON = "poison",
    Bleed = "bleed",
    BLEED = "bleed",
    Aggro = "aggro",
    AGGRO = "aggro",
    Purge = "purge",
    PURGE = "purge",
    BossTarget = "bossTarget",
    Boss_Target = "bossTarget",
    ["Boss Target"] = "bossTarget",
    ["boss target"] = "bossTarget",
    boss_target = "bossTarget",
    bosstarget = "bossTarget",
    BOSS_TARGET = "bossTarget",
    Target = "target",
    TARGET = "target",
    Focus = "focus",
    FOCUS = "focus",
}

local function MSUF_Defaults_NormalizePriorityKey(key)
    if type(key) ~= "string" then return nil end
    return MSUF_PRIORITY_KEY_ALIAS[key] or key
end

local function MSUF_Defaults_VisualPriorityDefaults(includeTargetFocus)
    if includeTargetFocus then
        return { "dispel", "aggro", "purge", "bossTarget", "target", "focus" }
    end
    return { "dispel", "aggro", "purge", "bossTarget" }
end

local function MSUF_Defaults_CollapseDispelPriorityOrder(raw, includeTargetFocus)
    local defaults = MSUF_Defaults_VisualPriorityDefaults(includeTargetFocus)
    local allowed = {}
    for i = 1, #defaults do allowed[defaults[i]] = true end
    local out, used = {}, {}
    if type(raw) == "table" then
        for i = 1, #raw do
            local key = MSUF_Defaults_NormalizePriorityKey(raw[i])
            if MSUF_DISPEL_TYPE_PRIORITY_KEYS[key] then key = "dispel" end
            if allowed[key] and not used[key] then
                out[#out + 1] = key
                used[key] = true
            end
        end
    end
    for i = 1, #defaults do
        local key = defaults[i]
        if not used[key] then
            out[#out + 1] = key
            used[key] = true
        end
    end
    return out
end

local function MSUF_Defaults_MigratePriorityScope(scope, includeTargetFocus)
    if type(scope) ~= "table" then return end
    local raw = type(scope.hlPrioOrder) == "table" and scope.hlPrioOrder
        or (type(scope.highlightPrioOrder) == "table" and scope.highlightPrioOrder)
        or nil
    if raw then
        local visual = MSUF_Defaults_CollapseDispelPriorityOrder(raw, includeTargetFocus)
        scope.hlPrioOrder = visual
        if type(scope.highlightPrioOrder) == "table" then
            scope.highlightPrioOrder = visual
        end
    end

    --- Debuff-type custom sorting was removed from the visible model. Old
    --- profiles are force-collapsed into the single Dispel layer and all old
    --- overlay/type priority switches are disabled so no hidden state survives.
    scope.hlDispelTypePrioEnabled = nil
    scope.hlDispelTypePrioOrder = nil
    scope.unitDispelOverlayPrioEnabled = nil
    scope.unitDispelOverlayPrioOrder = nil
    scope.unitDispelOverlayUseHighlightPriority = nil
    scope.dispelOverlayPrioEnabled = nil
    scope.dispelOverlayPrioOrder = nil
    scope.dispelOverlayUseHighlightPriority = nil

    --- The dispel symbol shipped in Beta 38 defaulting to a single symbol for the
    --- highest-priority debuff. Beta 39 makes "one per dispel type" the default,
    --- because two debuffs of different types have to read as two symbols. TOP was
    --- only ever the default in the one build that had it, so lift existing
    --- profiles once rather than leaving them silently on the old behaviour. The
    --- marker below keeps it one-time, so a deliberate TOP survives from here on.
    for _, key in ipairs({ "unitDispelSymbolMode", "dispelSymbolMode" }) do
        if tostring(scope[key] or ""):upper() == "TOP" then scope[key] = "ALL" end
    end

    --- PTR 5 replaces the old catch-all debuff choice with the precise native
    --- DISPELLABLE meaning: any aura carrying a dispel type. Preserve old
    --- profiles/imports by translating their former ANY_DEBUFF spelling.
    for _, key in ipairs({ "dispelBorderTrigger", "unitDispelOverlayTrigger", "dispelOverlayTrigger" }) do
        local value = tostring(scope[key] or ""):upper()
        if value == "ANY_DEBUFF" or value == "ALL_DEBUFFS" or value == "DEBUFF" or value == "ANY" then
            scope[key] = "DISPEL_TYPE"
        end
    end
end

local function MSUF_Defaults_MigrateDispelPriorityProfile(db, force)
    if type(db) ~= "table" then return false end
    --- A brand-new profile has nothing to migrate. Stamping it here, before the
    --- heavy pass, made it look used, and first installs and profile resets then
    --- never received the factory profile. The heavy pass runs this migration
    --- again right after seeding, which is when the stamp belongs.
    if MSUF_Defaults_IsFreshInstallProfileDB(db) then return false end
    if force ~= true and tonumber(db._msufDispelPriorityMigration) == MSUF_DISPEL_PRIORITY_MIGRATION then
        return false
    end
    MSUF_Defaults_MigratePriorityScope(db.general, true)
    for _, key in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena" }) do
        MSUF_Defaults_MigratePriorityScope(db[key], false)
    end
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        MSUF_Defaults_MigratePriorityScope(db[key], true)
    end
    db._msufDispelPriorityMigration = MSUF_DISPEL_PRIORITY_MIGRATION
    return true
end

local function MSUF_Defaults_MigrateDispelPriorityProfiles()
    local changed = false
    if not _G.MSUF_ProfileIO_SuppressRuntimeSideEffects
        and type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table" then
        for _, profile in pairs(MSUF_GlobalDB.profiles) do
            changed = MSUF_Defaults_MigrateDispelPriorityProfile(profile) or changed
        end
    end
    if type(MSUF_DB) == "table" then
        changed = MSUF_Defaults_MigrateDispelPriorityProfile(MSUF_DB) or changed
    end
    return changed
end

ExportPublic("MSUF_MigrateDispelPriorityProfile", MSUF_Defaults_MigrateDispelPriorityProfile)
ExportPublic("MSUF_MigrateDispelPriorityProfiles", MSUF_Defaults_MigrateDispelPriorityProfiles)

local function MSUF_Defaults_MigrateGroupTooltipProfile(db)
    if type(db) ~= "table" then return false end
    local changed = false
    for _, key in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
        local scope = db[key]
        if type(scope) == "table" and (scope.tooltipMode ~= nil or scope.tooltipModifier ~= nil) then
            scope.tooltipMode = nil
            scope.tooltipModifier = nil
            changed = true
        end
    end
    return changed
end

local function MSUF_Defaults_MigrateGroupTooltipProfiles()
    local changed = false
    if not _G.MSUF_ProfileIO_SuppressRuntimeSideEffects
        and type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table" then
        for _, profile in pairs(MSUF_GlobalDB.profiles) do
            changed = MSUF_Defaults_MigrateGroupTooltipProfile(profile) or changed
        end
    end
    if type(MSUF_DB) == "table" then
        changed = MSUF_Defaults_MigrateGroupTooltipProfile(MSUF_DB) or changed
    end
    return changed
end

--- Classic only, called from the gate in MSUF_EnsureDB. Every stored profile,
--- not only the active one: the persisted fast path skips the heavy pass for
--- them, and an owner is repaired or kept by its own shape.
local function MSUF_Defaults_RepairSparseFactoryAuraOwnerProfiles()
    local changed = false
    if not _G.MSUF_ProfileIO_SuppressRuntimeSideEffects
        and type(MSUF_GlobalDB) == "table"
        and type(MSUF_GlobalDB.profiles) == "table" then
        for _, profile in pairs(MSUF_GlobalDB.profiles) do
            changed = MSUF_Defaults_RepairSparseFactoryAuraOwners(profile) or changed
        end
    end
    if type(MSUF_DB) == "table" then
        changed = MSUF_Defaults_RepairSparseFactoryAuraOwners(MSUF_DB) or changed
    end
    return changed
end

local function MSUF_ResolveFontShadowMetrics(opacity, distance, legacyStrength, fallbackOpacity, fallbackDistance)
    if legacyStrength ~= nil then
        legacyStrength = tostring(legacyStrength):upper()
        opacity = legacyStrength == "SOFT" and 0.55 or 1
        distance = legacyStrength == "DEEP" and 2 or 1
    else
        opacity = tonumber(opacity)
        if opacity == nil then opacity = tonumber(fallbackOpacity) or 1 end
        distance = tonumber(distance)
        if distance == nil then distance = tonumber(fallbackDistance) or 1 end
    end
    if opacity < 0.20 then opacity = 0.20 elseif opacity > 1 then opacity = 1 end
    distance = math.floor(distance + 0.5)
    if distance <= 1 then distance = 1 else distance = 2 end
    return opacity, distance, -distance
end
ExportPublic("MSUF_ResolveFontShadowMetrics", MSUF_ResolveFontShadowMetrics)

local function MSUF_Defaults_NormalizeFontShadowScope(scope, populateDefaults)
    if type(scope) ~= "table" then return end
    if scope.fontShadowStrength ~= nil then
        scope.fontShadowOpacity, scope.fontShadowDistance =
            MSUF_ResolveFontShadowMetrics(nil, nil, scope.fontShadowStrength)
        scope.fontShadowStrength = nil
        return
    end
    if populateDefaults or scope.fontShadowOpacity ~= nil or scope.fontShadowDistance ~= nil then
        scope.fontShadowOpacity, scope.fontShadowDistance = MSUF_ResolveFontShadowMetrics(
            scope.fontShadowOpacity, scope.fontShadowDistance)
    end
end

local function MSUF_Defaults_ClearScopedFontKeys(profileDB)
    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        local scope = profileDB and profileDB[key]
        if type(scope) == "table" then
            scope.fontKey = nil
            scope.nameShortenOverride = nil
            scope._msufGFNameTruncationOverride = nil
            if scope.fontOverride == true and not StateHelpers.HasScopedFontOverrideValue(scope, MSUF_DEFAULTS_SPEC) then
                scope.fontOverride = false
            end
        end
    end
end

--- Ordered migration/seed stages of MSUF_EnsureDB_Heavy. Each stage is one
--- contiguous slice of the former single-body pass, called in exactly the
--- original order with the original arguments; `g` is MSUF_DB.general. Stages
--- that read state computed in the prologue receive it explicitly. Keep new
--- one-shot repairs inside the stage that owns the keys they touch.

--- Anchor, UI scale, Flash menu, minimap, integrations, dropdown style,
--- sounds, text colour toggles, navigation icons, menu font, edit mode.
local sharedShellDefaults = MSUF.DefaultsStageFactories.Shell({
    MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION = MSUF_DEFAULTS_NAVIGATION_ICONS_REVISION,
    MSUF_Defaults_GetMenuFontDefault = MSUF_Defaults_GetMenuFontDefault,
    MSUF_Defaults_MigrateUnitDispelOwnership = MSUF_Defaults_MigrateUnitDispelOwnership,
    MSUF_Defaults_NormalizeFontShadowScope = MSUF_Defaults_NormalizeFontShadowScope,
})
local MSUF_Defaults_Stage_SeedShellDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedShellDefaults

--- Dark mode, bar background fill/colour modes, gradients, aggro border,
--- bar mode legacy flags, NPC colour mode, unified bar colour, outline colour.
local function MSUF_Defaults_Stage_SeedBarColorDefaults(profileDB, g)
    if g.darkMode == nil then
        g.darkMode = false
    end
    if g.darkBarTone == nil then
        g.darkBarTone = "black"
    end
    if g.darkBgBrightness == nil then
        g.darkBgBrightness = 0.25      --- 25% Grau als Standard
    end
    --- When true, dark mode uses the bar-background tint color directly (no brightness dimming).
    --- Allows fully custom background colors (including white) in dark mode.
    if g.darkBgCustomColor == nil then
        g.darkBgCustomColor = false
    end
    if g.classBarBgR == nil or g.classBarBgG == nil or g.classBarBgB == nil then
        g.classBarBgR = 0.0   --- default: black background
        g.classBarBgG = 0.0
        g.classBarBgB = 0.0
    end
    --- If enabled, bar background tint color follows the current HP bar color (class/reaction/unified),
    --- instead of using the custom tint swatch.
    if g.barBgMatchHPColor == nil then
        g.barBgMatchHPColor = false
    end
    --- If enabled, the HP background uses the unit's class color while the HP
    --- foreground can stay in Dark/Unified/Gradient mode.
    if g.barBgClassColor == nil then
        g.barBgClassColor = false
    end
    --- Background fill geometry and color source are independent. Migrate the
    --- two legacy booleans into the canonical mode without changing existing
    --- profiles; invalid imported values fail back to the current full/custom
    --- appearance.
    if g.barBgFillMode ~= "full" and g.barBgFillMode ~= "missing" then
        g.barBgFillMode = "full"
    end
    do
        local mode = g.barBgColorMode
        if mode ~= "custom" and mode ~= "match_health" and mode ~= "class" and mode ~= "health_gradient" then
            if g.barBgClassColor == true then
                mode = "class"
            elseif g.barBgMatchHPColor == true then
                mode = "match_health"
            else
                mode = "custom"
            end
        end
        g.barBgColorMode = mode
        g.barBgMatchHPColor = mode == "match_health"
        g.barBgClassColor = mode == "class"
    end
    if g.enableGradient == nil then
        g.enableGradient = false
    end
    if g.enableHealthGradient == nil then
        g.enableHealthGradient = true
    end
    if g.healthGradientLowR == nil or g.healthGradientLowG == nil or g.healthGradientLowB == nil then
        g.healthGradientLowR = 1
        g.healthGradientLowG = 0
        g.healthGradientLowB = 0
    end
    if g.healthGradientMidR == nil or g.healthGradientMidG == nil or g.healthGradientMidB == nil then
        g.healthGradientMidR = 1
        g.healthGradientMidG = 1
        g.healthGradientMidB = 0
    end
    if g.healthGradientHighR == nil or g.healthGradientHighG == nil or g.healthGradientHighB == nil then
        g.healthGradientHighR = 0
        g.healthGradientHighG = 1
        g.healthGradientHighB = 0
    end
    if g.enablePowerGradient == nil then
        g.enablePowerGradient = false
    end
    if g.healthBarGradientColorR == nil or g.healthBarGradientColorG == nil or g.healthBarGradientColorB == nil then
        g.healthBarGradientColorR, g.healthBarGradientColorG, g.healthBarGradientColorB = 0, 0, 0
    end
    if g.powerBarGradientColorR == nil or g.powerBarGradientColorG == nil or g.powerBarGradientColorB == nil then
        g.powerBarGradientColorR, g.powerBarGradientColorG, g.powerBarGradientColorB = 0, 0, 0
    end
    --- Not adopted on Classic: no Classic profile has ever stored these six
    --- keys, and MSUF_UF_Config falls back to exactly these values, so seeding
    --- them there would only change what a saved profile carries.
    if not IS_CLASSIC_FAMILY then
        if g.healthLossColorR == nil then g.healthLossColorR = 1 end
        if g.healthLossColorG == nil then g.healthLossColorG = 0.55 end
        if g.healthLossColorB == nil then g.healthLossColorB = 0.08 end
        if g.powerLossColorR == nil then g.powerLossColorR = 0.70 end
        if g.powerLossColorG == nil then g.powerLossColorG = 0.90 end
        if g.powerLossColorB == nil then g.powerLossColorB = 1 end
    end
    --- Bars: Aggro highlight overlay (Target/Focus/Boss)
    --- Aggro indicator: re-uses the HP outline border as an orange warning when YOU have aggro (target/focus/boss).
    --- Bars offers "Aggro border" with dropdown default 1 (On), the Assistant
    --- manifest declares 1, and group frames default aggroEnabled = true. The
    --- compiled unitframe fallback, however, only consulted the retired
    --- indicator key below - which this very block coerces to "off" for every
    --- profile that never carried it. A profile without an explicit choice
    --- therefore read "On" in the menu while the border stayed dark, and only
    --- an Off/On round trip through the dropdown repaired it. Seed the real key
    --- once, before that coercion, so stored state and menu agree. A profile
    --- that carries the retired key keeps the decision it recorded.
    --- aggroOutlineMode is shared with the group frames, whose own default is
    --- on. Never seed 0 from the coerced "off" below: that would silently kill
    --- a working group aggro border. Only enableAggroHighlight == false is a
    --- real recorded off.
    if g.aggroOutlineMode == nil then
        g.aggroOutlineMode = (g.aggroIndicatorMode == "border"
        or g.enableAggroHighlight ~= false) and 1 or 0
    end
    if g.aggroIndicatorMode == nil then
        if g.enableAggroHighlight == true then
            g.aggroIndicatorMode = "border" --- legacy migrate
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
    if g.powerGradientStrength == nil then
        g.powerGradientStrength = g.gradientStrength
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
        --- Keep legacy key as a reasonable fallback for older builds/tools.
        if type(g.gradientDirection) ~= "string" or g.gradientDirection == "" then
            g.gradientDirection = "RIGHT"
        end
        local hasPowerDirections = (g.powerGradientDirLeft ~= nil) or (g.powerGradientDirRight ~= nil)
            or (g.powerGradientDirUp ~= nil) or (g.powerGradientDirDown ~= nil)
        if not hasPowerDirections then
            g.powerGradientDirLeft = g.gradientDirLeft == true
            g.powerGradientDirRight = g.gradientDirRight == true
            g.powerGradientDirUp = g.gradientDirUp == true
            g.powerGradientDirDown = g.gradientDirDown == true
        end
        if g.powerGradientDirLeft == nil then g.powerGradientDirLeft = false end
        if g.powerGradientDirRight == nil then g.powerGradientDirRight = false end
        if g.powerGradientDirUp == nil then g.powerGradientDirUp = false end
        if g.powerGradientDirDown == nil then g.powerGradientDirDown = false end
        if (not g.powerGradientDirLeft) and (not g.powerGradientDirRight)
            and (not g.powerGradientDirUp) and (not g.powerGradientDirDown)
        then
            g.powerGradientDirRight = true
        end
        if type(g.powerGradientDirection) ~= "string" or g.powerGradientDirection == "" then
            g.powerGradientDirection = g.gradientDirection
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
    --- Normalize Bar mode (supports: dark / class / unified / gradient) and keep legacy flags in sync
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
        --- Gradient mode is HP-derived; neither legacy flag applies.
        g.darkMode = false
        g.useClassColors = false
    else --- unified
        g.darkMode = false
        g.useClassColors = false
    end
    --- NPC Color Mode: "reaction" (classic friendly/neutral/enemy) or "type" (boss/miniboss/caster/melee/regular).
    --- When "type", enemy NPC health bars in barMode "class" show classification-based colors.
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
    if g.npcClassColorBar == nil then
        g.npcClassColorBar = false
    end
    --- Per-unit NPC Type enable (nil/true = on, false = off)
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
    local function NormalizeStaticOutlineColor(tbl)
        if type(tbl) ~= "table" then return end
        if tbl.barOutlineColorMode ~= nil then
            local mode = type(tbl.barOutlineColorMode) == "string" and tbl.barOutlineColorMode:upper() or "BLACK"
            local hasStaticColor = type(tbl.barOutlineColorR) == "number"
                and type(tbl.barOutlineColorG) == "number"
                and type(tbl.barOutlineColorB) == "number"
                and (tbl.barOutlineColorR ~= 0 or tbl.barOutlineColorG ~= 0 or tbl.barOutlineColorB ~= 0)
            if mode == "CLASS" or (mode ~= "CUSTOM" and not hasStaticColor) then
                tbl.barOutlineColorR = 0
                tbl.barOutlineColorG = 0
                tbl.barOutlineColorB = 0
            end
            tbl.barOutlineColorMode = nil
        end
        if tbl.barOutlineColorR ~= nil or tbl.barOutlineColorG ~= nil or tbl.barOutlineColorB ~= nil then
            tbl.barOutlineColorA = 1
        end
    end
    NormalizeStaticOutlineColor(g)
    for _, key in ipairs({ "player", "target", "focus", "boss", "arena", "pet", "targettarget", "focustarget", "gf_party", "gf_raid", "gf_mythicraid" }) do
        NormalizeStaticOutlineColor(profileDB[key])
    end
    if g.barBorderStyle == nil then
        g.barBorderStyle = "THIN"
    end
end

--- Text style flags, name shortening baseline, number abbreviation, custom
--- font colour, slug/monochrome exclusivity, shadow metrics, alpha/baseline.
local MSUF_Defaults_Stage_SeedFontDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedFontDefaults

--- Mouseover highlight, status indicators, boss target highlight, dispel
--- overlay/symbol ownership, obsolete update tuning keys, unit tooltips.
local MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults

--- Castbar colours, per-unit backend + enable flags, cast time formats, boss
--- castbar geometry (physical edge anchor migration), icon/text offsets, sizes.
local sharedBarsDefaults = MSUF.DefaultsStageFactories.Bars({
})
local MSUF_Defaults_Stage_SeedCastbarCoreDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedCastbarCoreDefaults

--- Legacy Auras 1.x key cleanup and the global/per-text font sizes.
local MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes = sharedBarsDefaults.MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes

--- Castbar textures/visuals, width-source normalization, interrupt-ready
--- indicator, per-castbar toggles and detail defaults, focus kick icon.
local MSUF_Defaults_Stage_SeedCastbarDetailDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedCastbarDetailDefaults

--- Bar/background textures, prediction texture validation, HP/power text
--- modes and separators, bar settings scope key.
local MSUF_Defaults_Stage_SeedBarTextureDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedBarTextureDefaults

--- Legacy shared portrait baseline kept as a migration source for the
--- per-unit portrait fields filled in FillUnitDefaults.
local sharedUnitsDefaults = MSUF.DefaultsStageFactories.Units({
    MSUF_DEFAULT_ARENA_OFFSET_X = MSUF_DEFAULT_ARENA_OFFSET_X,
    MSUF_DEFAULT_ARENA_OFFSET_Y = MSUF_DEFAULT_ARENA_OFFSET_Y,
    MSUF_DEFAULT_BOSS_OFFSET_X = MSUF_DEFAULT_BOSS_OFFSET_X,
    MSUF_DEFAULT_BOSS_OFFSET_Y = MSUF_DEFAULT_BOSS_OFFSET_Y,
    MSUF_Defaults_NormalizePortraitClassStyleValue = MSUF_Defaults_NormalizePortraitClassStyleValue,
    MSUF_Defaults_NormalizePortraitRenderValue = MSUF_Defaults_NormalizePortraitRenderValue,
})
local MSUF_Defaults_Stage_SeedPortraitBaselineDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_SeedPortraitBaselineDefaults

--- Power/HP text mode key migration and the one-shot per-unit flattening of
--- inherited HP/Power text settings.
local MSUF_Defaults_Stage_MigrateUnitTextModes = sharedShellDefaults.MSUF_Defaults_Stage_MigrateUnitTextModes

--- Absorb/heal prediction bars, legacy absorb text mode collapse and the v2
--- absorb colour cleanup.
local MSUF_Defaults_Stage_SeedPredictionDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedPredictionDefaults

--- Leader/level/raid group/combat/resting/PvP indicators, the ...Pos ->
--- ...Anchor lift, per-unit raid marker, PvP flag and elite icon defaults.
local function MSUF_Defaults_Stage_SeedStatusIndicatorDefaults(profileDB, g)
    if g.showLeaderIcon == nil then
        g.showLeaderIcon = true
    end
    if g.leaderIconStyle == nil then
        g.leaderIconStyle = "BLIZZARD"
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
    --- Level indicator offset (global)
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
    if g.showRaidGroupInName == nil then
        g.showRaidGroupInName = false
    end
    if g.raidGroupNameAnchor == nil then
        g.raidGroupNameAnchor = 'NAMERIGHT'
    end
    if g.raidGroupNameOffsetX == nil then
        g.raidGroupNameOffsetX = 3
    end
    if g.raidGroupNameOffsetY == nil then
        g.raidGroupNameOffsetY = 0
    end
    if g.raidGroupNameStyle == nil then
        g.raidGroupNameStyle = 'PAREN'
    end
    --- Misc -> Indicators
    ---
    --- Combat/IncomingRes shipped their anchor as `...Pos` while every other
    --- status indicator uses `...Anchor`. The unitframe status compiler only
    --- reads the `...Anchor` schema (MSUF_UF_Config PrefixedStatusDef), so a
    --- profile carrying a moved `...Pos` was silently rendered at the default
    --- while the menu preview still honoured the old key. Lift the legacy value
    --- once, never overwriting an anchor the user has already set.
    --- One-shot: after this runs, the seeded `...Pos` defaults below must not be
    --- lifted again, or every later login would materialize an explicit anchor
    --- where the profile intentionally had none.
    if g._msufStatusPosAnchorMigrated_v1 ~= true then
        g._msufStatusPosAnchorMigrated_v1 = true
        for _, aliasPair in ipairs({
            { "combatStateIndicatorAnchor", "combatStateIndicatorPos" },
            { "incomingResIndicatorAnchor", "incomingResIndicatorPos" },
        }) do
            MSUF_Defaults_CopyIfMissing(g, aliasPair[1], aliasPair[2])
            for _, unitKey in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
                local conf = profileDB[unitKey]
                if type(conf) == "table" then
                    MSUF_Defaults_CopyIfMissing(conf, aliasPair[1], aliasPair[2])
                end
            end
        end
    end
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
    if g.showPvpIndicator == nil then
        g.showPvpIndicator = true
    end
    if g.pvpIndicatorAnchor == nil then
        g.pvpIndicatorAnchor = "TOPRIGHT"
    end
    if g.pvpIndicatorOffsetX == nil then
        g.pvpIndicatorOffsetX = 0
    end
    if g.pvpIndicatorOffsetY == nil then
        g.pvpIndicatorOffsetY = 0
    end
    if g.pvpIndicatorSize == nil then
        g.pvpIndicatorSize = 18
    end
    if g.pvpIndicatorLayer == nil then
        g.pvpIndicatorLayer = 7
    end
    --- Status Icons (Summon / Resting)
    --- These are used by the Unitframe Status element (player/target) and can be overridden per-unit in the Frames menu.
    if g.showRestingIndicator == nil then
        g.showRestingIndicator = true
    end
    --- Rested icon defaults (Blizzard animated Zzz)
    --- Requirement: default size 39 and centered above the attached Player portrait.
    --- Only apply when the profile does not already carry explicit values (no regression for users who moved it).
    if g.restedStateIndicatorSymbol == nil then
        g.restedStateIndicatorSymbol = "rested_blizzard_animated"
    end
    if g.restedStateIndicatorIconStyle == nil then
        g.restedStateIndicatorIconStyle = "BLIZZARD"
    end
    if g.restedStateIndicatorAnchor == nil then
        g.restedStateIndicatorAnchor = "TOPLEFT"
    end
    if g.restedStateIndicatorOffsetX == nil or type(g.restedStateIndicatorOffsetX) ~= "number" then
        g.restedStateIndicatorOffsetX = -40
    end
    if g.restedStateIndicatorOffsetY == nil or type(g.restedStateIndicatorOffsetY) ~= "number" then
        g.restedStateIndicatorOffsetY = 50
    end
    if g.restedStateIndicatorSize == nil or type(g.restedStateIndicatorSize) ~= "number" or g.restedStateIndicatorSize <= 0 then
        g.restedStateIndicatorSize = 39
    end
    if g.restedStateIndicatorLayer == nil then
        g.restedStateIndicatorLayer = 25
    end
    if g.stateIconsTestMode == nil then
        g.stateIconsTestMode = false
    end
    --- Player indicators (Frames -> Player)
    if g.showLevel == nil then
        g.showLevel = false
    end
    if g.showRaidMarker == nil then
        g.showRaidMarker = true
    end
    local legacyShowRaidMarker = g.showRaidMarker
    for _, key in ipairs({"player","target","focus","targettarget","focustarget","pet","boss", "arena"}) do
        profileDB[key] = profileDB[key] or {}
        if profileDB[key].showRaidMarker == nil and legacyShowRaidMarker ~= nil then
            profileDB[key].showRaidMarker = legacyShowRaidMarker
        end
        if profileDB[key].showRaidMarker == nil then
            profileDB[key].showRaidMarker = true
        end
    end
    local legacyRaidMarkerOffsetX = g.raidMarkerOffsetX
    local legacyRaidMarkerOffsetY = g.raidMarkerOffsetY
    local legacyRaidMarkerAnchor  = g.raidMarkerAnchor
        local legacyRaidMarkerSize    = g.raidMarkerSize
    for _, key in ipairs({"player","target","focus","targettarget","focustarget","pet","boss", "arena"}) do
        profileDB[key] = profileDB[key] or {}
        local conf = profileDB[key]
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
--- Hunter Pet Happiness exists again on WoW Forever. Keep the native 24 px
--- visual scale and familiar right-side placement, the same as on Classic Era
--- and TBC, without adding dead fields to Midnight profiles.
if MSUF.Client and MSUF.Client.SupportsPetHappiness == true then
    profileDB.pet = profileDB.pet or {}
    local pet = profileDB.pet
    if pet.showPetHappinessIndicator == nil then pet.showPetHappinessIndicator = true end
    if pet.petHappinessIndicatorSize == nil then pet.petHappinessIndicatorSize = 24 end
    if pet.petHappinessIndicatorAnchor == nil then pet.petHappinessIndicatorAnchor = "RIGHT" end
    if pet.petHappinessIndicatorOffsetX == nil then pet.petHappinessIndicatorOffsetX = -7 end
    if pet.petHappinessIndicatorOffsetY == nil then pet.petHappinessIndicatorOffsetY = -4 end
    if pet.petHappinessIndicatorLayer == nil then pet.petHappinessIndicatorLayer = 7 end
end

--- PvP flag defaults (per-unit). Arena opponents are always PvP-flagged, so
--- the indicator ships disabled there; the control stays available.
for _, key in ipairs({"player","target","focus","targettarget","focustarget","arena"}) do
        profileDB[key] = profileDB[key] or {}
        local conf = profileDB[key]
    if conf.showPvpIndicator == nil then conf.showPvpIndicator = (key ~= "arena") end
        if conf.pvpIndicatorSize == nil then conf.pvpIndicatorSize = 18 end
        if conf.pvpIndicatorAnchor == nil then conf.pvpIndicatorAnchor = "TOPRIGHT" end
        if conf.pvpIndicatorOffsetX == nil then conf.pvpIndicatorOffsetX = 0 end
        if conf.pvpIndicatorOffsetY == nil then conf.pvpIndicatorOffsetY = 0 end
        if conf.pvpIndicatorLayer == nil then conf.pvpIndicatorLayer = 7 end
    end
    --- Elite / Rare icon defaults (per-unit)
    for _, key in ipairs({"target","focus","targettarget","focustarget","boss", "arena"}) do
        profileDB[key] = profileDB[key] or {}
        local u = profileDB[key]
        if u.showEliteIcon    == nil then u.showEliteIcon    = true       end
        if u.eliteIconSize    == nil then u.eliteIconSize    = 18         end
        if u.eliteIconAnchor  == nil then u.eliteIconAnchor  = "TOPRIGHT" end
        --- TOPRIGHT attaches matching corners. +18 places the 18 px icon flush
        --- outside the frame edge, clear of HP/power text and top aura rows.
        if u.eliteIconOffsetX == nil then u.eliteIconOffsetX = 18         end
        if u.eliteIconOffsetY == nil then u.eliteIconOffsetY = 0          end
        if u.eliteIconLayer   == nil then u.eliteIconLayer   = 25         end
        if u.eliteIconStyle   == nil then u.eliteIconStyle   = "BLIZZARD" end
    end
end

--- MSUF_DB.bars: power bar switches, class power shape, detached power bar
--- texture retirement, Player HP bar, rounded frames, outline thickness.
local MSUF_Defaults_Stage_SeedBarsTableDefaults = sharedBarsDefaults.MSUF_Defaults_Stage_SeedBarsTableDefaults

--- MSUF_DB.gameplay: combat timer, combat state text, crosshair, melee
--- range spell storage.
local MSUF_Defaults_Stage_SeedGameplayDefaults = sharedShellDefaults.MSUF_Defaults_Stage_SeedGameplayDefaults

--- Auras3 root, group aura factory seeding, custom display/container tables,
--- Blizzard aura frame split, debuff type border mode, defensive shape, filters.
local function MSUF_Defaults_Stage_SeedAuraDefaults(profileDB)
    --- Auras3 defaults (new installs / reset profile)
    if profileDB.auras3 == nil then
        profileDB.auras3 = MSUF_Defaults_CreateCanonicalUnitAuras()
    end
    --- Group Aura defaults use the same explicit native factory as profile
    --- reset. Only truly Aura-empty scopes are initialized here; an old flat
    --- or nested payload remains unmarked so Profiles.lua can hard-cut it once
    --- while preserving its visible lane size/position.
    local canonicalGroupAuras = MSUF_Defaults_CreateCanonicalGroupAuraState()
    for i = 1, #MSUF_DEFAULTS_GROUP_AURA_SCOPES do
        local scope = MSUF_DEFAULTS_GROUP_AURA_SCOPES[i]
        local conf = type(profileDB[scope]) == "table" and profileDB[scope] or {}
        profileDB[scope] = conf
        local hasAuraPayload = type(conf.auras) == "table"
            or type(conf.privateAuras) == "table" or type(conf.spellIndicators) == "table"
            or conf.aurasEnabled ~= nil or conf.auraMaxIcons ~= nil or conf.auraIconSize ~= nil
            or conf.auraAnchor ~= nil or conf.auraGrowthX ~= nil or conf.auraGrowthY ~= nil
            or conf.auraSpacing ~= nil or conf.auraPerRow ~= nil
            or conf.privateAurasEnabled ~= nil or conf.privateAuraMax ~= nil
            or conf.privateAuraSize ~= nil or conf.privateAuraAnchor ~= nil
            or conf.privateAuraX ~= nil or conf.privateAuraY ~= nil
            or conf.privateAuraCountdown ~= nil or conf._auraMigV2 ~= nil
        local state = canonicalGroupAuras and canonicalGroupAuras[scope]
        if not hasAuraPayload and type(state) == "table" then
            conf.auras = state.auras
            conf.privateAuras = state.privateAuras
            conf.spellIndicators = state.spellIndicators
        end
    end
    --- Auras3: PTR 5 restored the native IMPORTANT filter. Keep the old split
    --- migration marker, but no longer overwrite the per-lane values on load.
    if profileDB and profileDB.auras3 then
        local a3 = profileDB.auras3
        if type(a3.customDisplays) ~= "table" then a3.customDisplays = {} end
        if type(a3.customDisplays.shared) ~= "table" then a3.customDisplays.shared = { items = {} } end
        if type(a3.customDisplays.shared.items) ~= "table" then a3.customDisplays.shared.items = {} end
        if type(a3.customDisplays.perUnit) ~= "table" then a3.customDisplays.perUnit = {} end
        if type(a3.customDisplays.serial) ~= "number" then a3.customDisplays.serial = 0 end
        if type(a3.customContainers) ~= "table" then a3.customContainers = {} end
        if type(a3.customContainers.perUnit) ~= "table" then a3.customContainers.perUnit = {} end
        if type(a3.shared) ~= "table" then a3.shared = {} end
        --- The first local version exposed one combined Blizzard Aura switch.
        --- Split that stored choice once so testers keep the same result while
        --- Buff and Debuff visibility become independently configurable.
        --- Not adopted on Classic: no Classic build ever wrote the combined key,
        --- and the aura menu model performs the same split where it does appear.
        if not IS_CLASSIC_FAMILY and a3.shared.hideBlizzardAuraFrames ~= nil then
            if a3.shared.hideBlizzardBuffFrame == nil then
                a3.shared.hideBlizzardBuffFrame = a3.shared.hideBlizzardAuraFrames == true
            end
            if a3.shared.hideBlizzardDebuffFrame == nil then
                a3.shared.hideBlizzardDebuffFrame = a3.shared.hideBlizzardAuraFrames == true
            end
            a3.shared.hideBlizzardAuraFrames = nil
        end
        local legacyAuraModel = tonumber(a3.profileModelRevision) ~= MSUF_DEFAULTS_AURAS3_PROFILE_MODEL_REVISION
        if legacyAuraModel and a3.shared._msufA3_debuffTypeBorderModeMigrated_v1 ~= true then
            if a3.shared.useDebuffTypeBorders == true then
                a3.shared.debuffTypeBorderMode = "SYMBOL"
            elseif a3.shared.debuffTypeBorderMode == nil then
                a3.shared.debuffTypeBorderMode = "OFF"
            end
            a3.shared._msufA3_debuffTypeBorderModeMigrated_v1 = true
        end
        --- Defaults revision 10: Player Defensives icons follow the frame
        --- portrait. Profiles predating the shared Appearance products fell
        --- back to RECTANGLE inside the portrait replacement, so the shape is
        --- seeded exactly once; a stored choice (including an explicit
        --- Rectangular) stays authoritative afterwards.
        if (tonumber(profileDB._msufDefaultsRevision) or 0) < MSUF_DEFAULTS_PLAYER_DEFENSIVE_SHAPE_REVISION then
            a3.shared._msufA3_factoryDefensiveShape_v1 = nil
            local shapes = type(a3.shared.appearanceIconShapes) == "table" and a3.shared.appearanceIconShapes or {}
            a3.shared.appearanceIconShapes = shapes
            if shapes.playerDefensives == nil then shapes.playerDefensives = "FOLLOW_PORTRAIT" end
        end

        local function EnsureImportantSplit(f)
            if not f then return end
            f.buffs = (type(f.buffs) == "table") and f.buffs or {}
            f.debuffs = (type(f.debuffs) == "table") and f.debuffs or {}
            local b, d = f.buffs, f.debuffs

            --- One-time migration: legacy onlyImportantAuras is retired.
            if f._msufA3_onlyImportantSplitMigrated_v1 ~= true then
                f.onlyImportantAuras = false
                f._msufA3_onlyImportantSplitMigrated_v1 = true
            end

            f.onlyImportantAuras = false
        end

        if legacyAuraModel then
            if a3.shared and a3.shared.filters then
                EnsureImportantSplit(a3.shared.filters)
            end
            if a3.perUnit then
                for _, pu in pairs(a3.perUnit) do
                    if pu and pu.filters then
                        EnsureImportantSplit(pu.filters)
                    end
                end
            end
        end
    end
end

--- Unit-frame geometry/text defaults: the long fill() section, plus the player
--- castbar tick keys and the ToT inline-name keys. The helper only fills nil
--- fields, so saved user choices survive even when new defaults are added for
--- later versions.
local MSUF_Defaults_Stage_FillUnitFrameDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_FillUnitFrameDefaults

--- One-shot boss layout migration plus the range-fade keys for every
--- non-player unit.
local MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade = sharedUnitsDefaults.MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade

--- Per-unit power bar defaults seeded from the legacy shared bars table, plus
--- the one-shot detached power border migration.
local MSUF_Defaults_Stage_SeedUnitPowerBarDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_SeedUnitPowerBarDefaults

--- Per-unit enabled/ownership state, fill animation, unified alpha, OOC fade
--- and the decorative texture layers.
local function MSUF_Defaults_Stage_SeedUnitStateDefaults(profileDB)
    for _, unitKey in ipairs({"player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena"}) do
        profileDB[unitKey] = profileDB[unitKey] or {}
        local u = profileDB[unitKey]
        if u.enabled == nil then
            u.enabled = true
        end
        -- Blizzard ownership is independent from the MSUF enabled state:
        -- both frames may coexist, or MSUF can be disabled while Blizzard stays.
        if u.useBlizzardFrame == nil then
            u.useBlizzardFrame = false
        end
        --- Per-unitframe: smooth health fill animation (matches Group Frames default).
        if u.smoothFill == nil then
            u.smoothFill = false
        end
        --- Not adopted on Classic: its profiles have never stored this key and
        --- the config compile reads a missing one as off.
        if not IS_CLASSIC_FAMILY and u.chunkedFill == nil then
            u.chunkedFill = false
        end
        --- Unified alpha: HP fill opacity + power fill opacity + background texture
        --- opacity + a toggle to keep text/portrait opaque. Legacy combat/layered keys
        --- are wiped once by the _msufAlphaUnified_v1 migration below.
        if u.hpBarAlpha == nil then u.hpBarAlpha = 1 end
        if u.powerBarAlpha == nil then u.powerBarAlpha = 1 end
        if u.hpBgAlpha == nil then u.hpBgAlpha = 0.85 end
        if u.powerBarBgAlpha == nil then u.powerBarBgAlpha = u.hpBgAlpha or 0.85 end
        if u.alphaExcludeTextPortrait == nil then u.alphaExcludeTextPortrait = false end
        if u.alphaExcludePredictionBars == nil then u.alphaExcludePredictionBars = false end
        --- Out-of-combat fade: whole-frame alpha while out of combat (min-composed
        --- with range fade at runtime; strongest fade wins). Off by default.
        if u.oocFadeEnabled == nil then u.oocFadeEnabled = false end
        if u.oocFadeAlpha == nil then u.oocFadeAlpha = 0.5 end
        --- Decorative texture layers (3 slots, Blizzard name-bar style):
        --- SharedMedia texture per slot with own alpha, strata/level, anchor
        --- target, color/gradient modes, blend, mirroring, edge softness,
        --- combat visibility and rounded clipping. Applied purely cold path.
        --- The source, size and link keys below exist only on Classic: the
        --- texture layer runtime resolves a missing one from the older rule,
        --- so Midnight and WoW Forever profiles keep the key set they have.
        if IS_CLASSIC_FAMILY then
            if u.texLayerLinkGeometry == nil then u.texLayerLinkGeometry = false end
            if u.texLayerLinkSize == nil then u.texLayerLinkSize = false end
        end
        for _, texP in ipairs({ "texLayer", "texLayer2", "texLayer3" }) do
            if u[texP .. "Enabled"] == nil then u[texP .. "Enabled"] = false end
            if u[texP .. "Texture"] == nil then u[texP .. "Texture"] = "" end
            if u[texP .. "CustomTexturePath"] == nil then u[texP .. "CustomTexturePath"] = "" end
            if IS_CLASSIC_FAMILY and u[texP .. "SourceMode"] == nil then
                local sourcePath = tostring(u[texP .. "CustomTexturePath"] or "")
                if sourcePath:find("^Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\TextureLayers\\") then
                    u[texP .. "SourceMode"] = "PACK"
                elseif sourcePath ~= "" then
                    u[texP .. "SourceMode"] = "CUSTOM"
                else
                    u[texP .. "SourceMode"] = "SHAREDMEDIA"
                end
            end
            if u[texP .. "Alpha"] == nil then u[texP .. "Alpha"] = 1 end
            if u[texP .. "FollowFrameAlpha"] == nil then u[texP .. "FollowFrameAlpha"] = true end
            if u[texP .. "Strata"] == nil then u[texP .. "Strata"] = "AUTO" end
            if u[texP .. "Level"] == nil then u[texP .. "Level"] = 1 end
            if u[texP .. "AnchorTarget"] == nil then u[texP .. "AnchorTarget"] = "FRAME" end
            if u[texP .. "Anchor"] == nil then u[texP .. "Anchor"] = "TOP" end
            if u[texP .. "OffsetX"] == nil then u[texP .. "OffsetX"] = 0 end
            if u[texP .. "OffsetY"] == nil then u[texP .. "OffsetY"] = 0 end
            if IS_CLASSIC_FAMILY then
                if u[texP .. "ResponsiveSize"] == nil then u[texP .. "ResponsiveSize"] = false end
                if u[texP .. "SizeMode"] == nil then
                    u[texP .. "SizeMode"] = u[texP .. "ResponsiveSize"] == true and "FRAME" or "MANUAL"
                end
                if u[texP .. "EdgeAttach"] == nil then u[texP .. "EdgeAttach"] = "FREE" end
            end
            if u[texP .. "Width"] == nil then u[texP .. "Width"] = 0 end
            if u[texP .. "Height"] == nil then u[texP .. "Height"] = 16 end
            if u[texP .. "ColorMode"] == nil then u[texP .. "ColorMode"] = "CUSTOM" end
            if u[texP .. "ColorTreatment"] == nil then u[texP .. "ColorTreatment"] = "ORIGINAL" end
            if u[texP .. "ColorR"] == nil then u[texP .. "ColorR"] = 1 end
            if u[texP .. "ColorG"] == nil then u[texP .. "ColorG"] = 1 end
            if u[texP .. "ColorB"] == nil then u[texP .. "ColorB"] = 1 end
            if u[texP .. "GradientEnabled"] == nil then u[texP .. "GradientEnabled"] = false end
            if u[texP .. "Gradient2R"] == nil then u[texP .. "Gradient2R"] = 0 end
            if u[texP .. "Gradient2G"] == nil then u[texP .. "Gradient2G"] = 0 end
            if u[texP .. "Gradient2B"] == nil then u[texP .. "Gradient2B"] = 0 end
            --- Bars-style multi-direction gradient: independent per-edge toggles.
            if u[texP .. "GradientDirRight"] == nil then u[texP .. "GradientDirRight"] = true end
            if u[texP .. "GradientDirLeft"] == nil then u[texP .. "GradientDirLeft"] = false end
            if u[texP .. "GradientDirUp"] == nil then u[texP .. "GradientDirUp"] = false end
            if u[texP .. "GradientDirDown"] == nil then u[texP .. "GradientDirDown"] = false end
            if u[texP .. "BlendMode"] == nil then u[texP .. "BlendMode"] = "BLEND" end
            if u[texP .. "MirrorH"] == nil then u[texP .. "MirrorH"] = false end
            if u[texP .. "MirrorV"] == nil then u[texP .. "MirrorV"] = false end
            if u[texP .. "CropMode"] == nil then u[texP .. "CropMode"] = "FULL" end
            if u[texP .. "EdgeSoftness"] == nil then u[texP .. "EdgeSoftness"] = 0 end
            if u[texP .. "Visibility"] == nil then u[texP .. "Visibility"] = "ALWAYS" end
            if u[texP .. "RoundedClip"] == nil then u[texP .. "RoundedClip"] = false end
        end
    end
end

--- Per-unit portrait defaults. Legacy shared/override portrait profiles are
--- flattened once (v4.324 note below), so this runs after the unit tables exist.
local MSUF_Defaults_Stage_SeedUnitPortraitDefaults = sharedUnitsDefaults.MSUF_Defaults_Stage_SeedUnitPortraitDefaults

--- Legacy/unit defaults, split per domain and run in this order. The portrait
--- stage flattens the unit tables the earlier stages created, so keep it last.
local function MSUF_Defaults_Stage_FillUnitDefaults(profileDB, g, legacyPortraitOverrideState)
    MSUF_Defaults_Stage_FillUnitFrameDefaults(profileDB)
    MSUF_Defaults_Stage_MigrateBossLayoutAndRangeFade(profileDB)
    MSUF_Defaults_Stage_SeedUnitPowerBarDefaults(profileDB)
    MSUF_Defaults_Stage_SeedUnitStateDefaults(profileDB)
    MSUF_Defaults_Stage_SeedUnitPortraitDefaults(profileDB, g, legacyPortraitOverrideState)
end

--- One-shot unified alpha migration: wipe the retired combat/layered alpha
--- keys and seed the new fill/background alphas across unit and group confs.
local MSUF_Defaults_Stage_MigrateUnifiedAlpha = sharedUnitsDefaults.MSUF_Defaults_Stage_MigrateUnifiedAlpha

--- Main DB repair pass. This is deliberately broad and cold: it may normalize
--- several systems in one run, but it is protected by MSUF_DB_LastHeavyRun in
--- the public wrapper below so normal callers do not pay for it repeatedly.
local function MSUF_EnsureDB_Heavy(profileDB)
    if type(profileDB) ~= "table" then
        profileDB = {}
    end
    --- Seed brand-new installs / hard-resets from the factory profile payload.
    MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall(profileDB)
    MSUF_Defaults_EnsureRootTables(profileDB)
    local g = profileDB.general
    MSUF_Defaults_RepairFactoryNameShortening(profileDB)
    MSUF_Defaults_RepairModernFactoryPlayerStack(profileDB)
    MSUF_Defaults_RepairModernFactoryNamePresentation(profileDB)
    MSUF_Defaults_MigrateDispelPriorityProfile(profileDB)
    MSUF_Defaults_MigrateGroupTooltipProfile(profileDB)
    MSUF_Defaults_NormalizePortraitRenderDB(profileDB)
    local nativeDispelMigration = tonumber(profileDB._msufNativeDispelTriggerMigration) or 0
    if nativeDispelMigration < 1 then
        if g.dispelBorderTrigger == nil or g.dispelBorderTrigger == "BY_ME" then
            g.dispelBorderTrigger = "DISPEL_TYPE"
        end
    end
    profileDB._msufNativeDispelTriggerMigration = 2
    local legacyPortraitOverrideState = false
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "boss", "arena" }) do
        local u = profileDB[unitKey]
        if type(u) == "table" and u.portraitDecoOverride ~= nil then
            legacyPortraitOverrideState = true
            break
        end
    end
    if type(profileDB.classColors) ~= "table" then profileDB.classColors = {} end
    if type(profileDB.npcColors) ~= "table" then profileDB.npcColors = {} end
    if g.fontKey == nil then
        g.fontKey = MSUF_Defaults_GetGlobalFontDefault()
    end
    MSUF_Defaults_NormalizeFontField(g)
    MSUF_Defaults_Stage_SeedShellDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedBarColorDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedFontDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedHighlightStatusTooltipDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedCastbarCoreDefaults(profileDB, g)
    MSUF_Defaults_Stage_PruneLegacyAuraKeysAndSeedFontSizes(g)
    MSUF_Defaults_Stage_SeedCastbarDetailDefaults(g)
    MSUF_Defaults_Stage_SeedBarTextureDefaults(g)
    MSUF_Defaults_Stage_SeedPortraitBaselineDefaults(profileDB, g)
    MSUF_Defaults_Stage_MigrateUnitTextModes(profileDB, g)
    MSUF_Defaults_Stage_SeedPredictionDefaults(g)
    MSUF_Defaults_Stage_SeedStatusIndicatorDefaults(profileDB, g)
    MSUF_Defaults_Stage_SeedBarsTableDefaults(profileDB)
    MSUF_Defaults_Stage_SeedGameplayDefaults(profileDB)
    --- 5.6 -> 6.0 shape repair for existing DBs and factory defaults.
    MSUF_Defaults_NormalizeProfileTo60Defaults(profileDB)
    --- Root toggle: Shorten unit names (Frames -> General)
    if profileDB.shortenNames == nil then
        profileDB.shortenNames = false
    end
    MSUF_Defaults_Stage_SeedAuraDefaults(profileDB)
    MSUF_Defaults_Stage_FillUnitDefaults(profileDB, g, legacyPortraitOverrideState)
    MSUF_Defaults_Stage_MigrateUnifiedAlpha(profileDB, g)
    for _, key in ipairs({
        "general",
        "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena",
        "gf_party", "gf_raid", "gf_mythicraid",
    }) do
        MSUF_Defaults_NormalizeFontField(profileDB[key])
    end
    MSUF_Defaults_ClearScopedFontKeys(profileDB)
    if g._msufUFLocalFontKeyMigration_v407 ~= true then
        for _, key in ipairs({ "player", "target", "targettarget", "focustarget", "focus", "pet", "boss", "arena" }) do
            local u = profileDB[key]
            if type(u) == "table" then
                u.fontKey = nil
            end
        end
        g._msufUFLocalFontKeyMigration_v407 = true
    end
    profileDB._msufProfileSchema = MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
    profileDB._msufDefaultsRevision = MSUF_DEFAULTS_CURRENT_REVISION
    return profileDB
end

local function MSUF_Defaults_IsCurrentProfileDB(db)
    if type(db) ~= "table"
        or tonumber(db._msufProfileSchema) ~= MSUF_DEFAULTS_CURRENT_PROFILE_SCHEMA
        or tonumber(db._msufDefaultsRevision) ~= MSUF_DEFAULTS_CURRENT_REVISION then
        return false
    end
    --- Keep the fast path safe for truncated/malformed SavedVariables. Nested
    --- value validation belongs to imports (which force EnsureDB), while these
    --- root tables are the minimum runtime contract for a stored profile.
    for i = 1, #MSUF_DEFAULTS_ROOT_TABLE_KEYS do
        if type(db[MSUF_DEFAULTS_ROOT_TABLE_KEYS[i]]) ~= "table" then
            return false
        end
    end
    local g = db.general
    if type(g.fontKey) ~= "string" or g.fontKey == ""
        or db.shortenNames == nil
        or db.bars.barBackgroundAlpha == nil
        or db.gameplay.enableCombatTimer == nil
        or (g.barBgFillMode ~= "full" and g.barBgFillMode ~= "missing")
        or (g.barBgColorMode ~= "custom" and g.barBgColorMode ~= "match_health"
            and g.barBgColorMode ~= "class" and g.barBgColorMode ~= "health_gradient") then
        return false
    end
    return true
end

--- Cheap public guard used by the rest of the addon. Pass force=true only after
--- changing profile tables or importing data, when the full repair/migration
--- pass must be allowed to run again on the active MSUF_DB reference.
--- allowPersistedFastPath is intentionally reserved for profile initialization
--- and private export copies. Normal profile switches retain the old behavior
--- of repairing the newly selected table even when its revision is current.
--- temporaryProfile keeps export materialization from evicting the real active
--- profile from the session-local last-heavy-run cache.
local function MSUF_NormalizeProfileDefaults(profile, force, allowPersistedFastPath)
    assert(type(profile) == "table", "MSUF profile must be a table")
    MSUF_Defaults_PruneRetiredClassPowerTextFields(profile)
    if force ~= true and allowPersistedFastPath == true and MSUF_Defaults_IsCurrentProfileDB(profile) then
        return profile
    end
    return MSUF_EnsureDB_Heavy(profile)
end
ExportPublic("MSUF_NormalizeProfileDefaults", MSUF_NormalizeProfileDefaults)

local function MSUF_EnsureDB(force, allowPersistedFastPath)
    local profile = _G.MSUF_DB
    if type(profile) ~= "table" then
        profile = {}
        ExportPublic("MSUF_DB", profile)
    end
    if force ~= true and MSUF_DB_LastHeavyRun == profile then return profile end
    MSUF_Defaults_MigrateDispelPriorityProfiles()
    MSUF_Defaults_MigrateGroupTooltipProfiles()
    if IS_CLASSIC_FAMILY then
        MSUF_Defaults_RepairSparseFactoryAuraOwnerProfiles()
    end
    MSUF_NormalizeProfileDefaults(profile, force, allowPersistedFastPath)
    MSUF_DB_LastHeavyRun = profile
    return profile
end
ExportPublic("MSUF_EnsureDB", MSUF_EnsureDB)
_G.EnsureDB = MSUF_EnsureDB
--- Optional exports for other modules
MSUF.MSUF_CreateFactoryDefaultProfile = MSUF_Defaults_CreateFactoryProfile
MSUF.MSUF_EnsureDB_Heavy = MSUF_EnsureDB_Heavy
MSUF.MSUF_EnsureDB = MSUF_EnsureDB
MSUF.EnsureDB = MSUF_EnsureDB
ExportPublic("MSUF_CreateFactoryDefaultProfile", MSUF_Defaults_CreateFactoryProfile)
