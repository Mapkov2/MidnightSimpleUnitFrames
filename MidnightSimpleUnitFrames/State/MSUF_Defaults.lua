-- Defaults bootstrap, field normalization and shared client policy.
local MSUF_Defaults_NormalizeAuras3Profile
local addonName, addonNS = ...
local MSUF = (_G.MSUF_NS) or addonNS or {}
local Parts = {}
MSUF.DefaultsParts = Parts
local ExportPublic = MSUF.ExportPublic

--- Client facts, read once when this file loads. Every client loads this file;
--- the Classic flavors (Vanilla, TBC, Mists) differ from Mainline (Midnight and
--- WoW Forever) only in the small hunks gated on these two locals. Nothing here
--- reads WOW_PROJECT_ID: Game/Shared/Initialize.lua owns that.
local IS_CLASSIC_FAMILY = MSUF.Client.Family == "Classic"
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

--- MSUF default class-resource colors, kept in MSUF's own table: Blizzard's
--- PowerBarColor stays exactly as shipped (writing into it recoloured
--- Blizzard's own bars and tainted entries Blizzard code reads). The power
--- color resolver reads MSUF._PBCSnap before Blizzard's table, and
--- MSUF_GetDefaultPowerColor gives the menu and the class power fallback the
--- same default.
do
    local defaults = {
        RUNES = { r = 128/255, g = 0, b = 17/255 },                --- #800011
        SOUL_SHARDS = { r = 135/255, g = 136/255, b = 238/255 },   --- #8788EE
    }
    MSUF._PBCSnap = defaults
    ExportPublic("MSUF_GetDefaultPowerColor", function(token)
        local c = defaults[token]
        if c == nil then
            local pbc = _G.PowerBarColor
            c = type(pbc) == "table" and token ~= nil and pbc[token] or nil
        end
        if type(c) ~= "table" then return nil end
        return c.r or c[1], c.g or c[2], c.b or c[3]
    end)
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
--- Forever has its own authored factory export. Other clients retain the
--- shared baseline from State/Defaults/MSUF_Defaults_Shell.lua.
local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF.Client.IsForever
    and MSUF.MSUF_FOREVER_FACTORY_DEFAULT_PROFILE_COMPACT
    or MSUF.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT

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
    return MSUF.TryDecodeFactoryPayload(E, cleaned)
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
    -- The retired 3D model mode, like any unknown value, loads as 2D.
    if v == "CLASS" then return v end
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
    for _, unitKey in ipairs({ "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }) do
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
local MSUF_DEFAULTS_TEXT_SCOPE_KEYS = StateHelpers.AliasMigrations.Contexts.defaults.scopes
local MSUF_DEFAULTS_GROUP_SCOPE_KEYS = StateHelpers.AliasMigrations.Contexts.defaults.groups
--- Hunter Pet Happiness exists on Classic Era, TBC and WoW Forever. Its status
--- keys are normalized like every other status prefix there; Midnight keeps the
--- shared spec untouched. Mists carries the prefix as well, as the Classic
--- Defaults always did: the normalizers ignore a key that is not there, so it is
--- inert on a client whose seeding below never writes one.
if MSUF.Client.SupportsPetHappiness == true or IS_CLASSIC_FAMILY then
    local petHappinessSpec = {}
    for key, value in pairs(StateHelpers.DefaultsSpec) do petHappinessSpec[key] = value end
    petHappinessSpec.statusPrefixes = {}
    for i, prefix in ipairs(StateHelpers.DefaultsSpec.statusPrefixes) do
        petHappinessSpec.statusPrefixes[i] = prefix
    end
    petHappinessSpec.statusPrefixes[#petHappinessSpec.statusPrefixes + 1] = "petHappinessIndicator"
    if IS_CLASSIC_FAMILY then
        petHappinessSpec.statusPrefixes[#petHappinessSpec.statusPrefixes + 1] = "petXPBar"
    end
    MSUF_DEFAULTS_SPEC = petHappinessSpec
end
local MSUF_Defaults_ToNumber = StateHelpers.ToNumber
local MSUF_Defaults_CopyIfMissing = StateHelpers.CopyIfMissing
local MSUF_Defaults_NormalizeNumberField = StateHelpers.NormalizeNumberField
--- Called with two arguments only: the nilEmpty flag stays off, so an empty
--- string is kept exactly as this file always did.
local MSUF_Defaults_UpperStringField = StateHelpers.UpperStringField
local MSUF_Defaults_TableHasAnyValue = StateHelpers.TableHasAnyValue

local function MSUF_Defaults_NormalizeUnitPositionAliases(db)
    if type(db) ~= "table" then return false end
    local changed = false
    for _, key in ipairs(MSUF_DEFAULTS_TEXT_SCOPE_KEYS) do
        local u = db[key]
        changed = StateHelpers.NormalizePositionAliases(u, "defaults") or changed
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

--- Defaults selects the shared ledger's narrow boot context until the complete
--- translator loads. Stored/factory translation then uses its trusted context.
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
    local sharedTranslator = MSUF.PublicGlobals.MSUF_ProfileIO_TranslateProfileToCurrent
    if type(sharedTranslator) ~= "function" and type(MSUF) == "table" then
        sharedTranslator = MSUF.MSUF_ProfileIO_TranslateProfileToCurrent
    end
    if type(sharedTranslator) == "function" then
        --- This pass only sees stored and factory profiles; imports run the
        --- untrusted pass on their payload first. Without the trust flag it wiped
        --- the dispel migration stamp and forced showNavigationIcons back on.
        local _, translated = sharedTranslator(db, {
            source = "defaults", markProfile = true, trustProfileMetadata = true,
        })
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
    changed = StateHelpers.NormalizeProfileTextAliases(db, "defaults") or changed
    changed = MSUF_Defaults_NormalizeNumericLayers(db) or changed
    return changed
end
ExportPublic("MSUF_NormalizeProfileTo60Defaults", MSUF_Defaults_NormalizeProfileTo60Defaults)

local MSUF_DEFAULT_BOSS_OFFSET_X = MSUF.DefaultsSchema.Values.UnitFrames.boss.offsetX
local MSUF_DEFAULT_BOSS_OFFSET_Y = MSUF.DefaultsSchema.Values.UnitFrames.boss.offsetY
local MSUF_DEFAULT_ARENA_OFFSET_X = MSUF.DefaultsSchema.Values.UnitFrames.arena.offsetX
local MSUF_DEFAULT_ARENA_OFFSET_Y = MSUF.DefaultsSchema.Values.UnitFrames.arena.offsetY

local function MSUF_GetDefaultUnitOffsets(unit)
    local defaults = unit and MSUF.DefaultsSchema.Values.UnitFrames[unit]
    if defaults then return defaults.offsetX, defaults.offsetY end
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

local MSUF_DEFAULT_PREDICTION_BAR_VALUES = MSUF.DefaultsSchema.Values.PredictionBars

local function MSUF_Defaults_ApplyPredictionBarBaseline(db)
    if type(db) ~= "table" then return end
    db.general = db.general or {}

    local function Apply(conf)
        if type(conf) ~= "table" then return end
        MSUF.DefaultsSchema.Fill(conf, MSUF_DEFAULT_PREDICTION_BAR_VALUES, true)
    end

    Apply(db.general)
    db.general.showSelfHealPrediction = true

    for _, key in ipairs({
        "player", "target", "targettarget", "tot", "focustarget", "focus", "pet", "pettarget", "boss", "arena",
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
local fresh = {}

Parts.ARENA_AURA_SLOTS = ARENA_AURA_SLOTS
Parts.ExportPublic = ExportPublic
Parts.IS_CLASSIC_FAMILY = IS_CLASSIC_FAMILY
Parts.MSUF_DEFAULTS_GROUP_SCOPE_KEYS = MSUF_DEFAULTS_GROUP_SCOPE_KEYS
Parts.MSUF_DEFAULTS_SPEC = MSUF_DEFAULTS_SPEC
Parts.MSUF_DEFAULTS_TEXT_SCOPE_KEYS = MSUF_DEFAULTS_TEXT_SCOPE_KEYS
Parts.MSUF_DEFAULT_ARENA_OFFSET_X = MSUF_DEFAULT_ARENA_OFFSET_X
Parts.MSUF_DEFAULT_ARENA_OFFSET_Y = MSUF_DEFAULT_ARENA_OFFSET_Y
Parts.MSUF_DEFAULT_BOSS_OFFSET_X = MSUF_DEFAULT_BOSS_OFFSET_X
Parts.MSUF_DEFAULT_BOSS_OFFSET_Y = MSUF_DEFAULT_BOSS_OFFSET_Y
Parts.MSUF_Defaults_ApplyPredictionBarBaseline = MSUF_Defaults_ApplyPredictionBarBaseline
Parts.MSUF_Defaults_CopyIfMissing = MSUF_Defaults_CopyIfMissing
Parts.MSUF_Defaults_DeepCopy = MSUF_Defaults_DeepCopy
Parts.MSUF_Defaults_GetEffectiveLocale = MSUF_Defaults_GetEffectiveLocale
Parts.MSUF_Defaults_GetGlobalFontDefault = MSUF_Defaults_GetGlobalFontDefault
Parts.MSUF_Defaults_GetMenuFontDefault = MSUF_Defaults_GetMenuFontDefault
Parts.MSUF_Defaults_GetProfilePayload = MSUF_Defaults_GetProfilePayload
Parts.MSUF_Defaults_NormalizePortraitClassStyleValue = MSUF_Defaults_NormalizePortraitClassStyleValue
Parts.MSUF_Defaults_NormalizePortraitRenderDB = MSUF_Defaults_NormalizePortraitRenderDB
Parts.MSUF_Defaults_NormalizePortraitRenderValue = MSUF_Defaults_NormalizePortraitRenderValue
Parts.MSUF_Defaults_NormalizeProfileTo60Defaults = MSUF_Defaults_NormalizeProfileTo60Defaults
Parts.MSUF_Defaults_PruneRetiredClassPowerTextFields = MSUF_Defaults_PruneRetiredClassPowerTextFields
Parts.MSUF_Defaults_TableHasAnyValue = MSUF_Defaults_TableHasAnyValue
Parts.MSUF_Defaults_ToNumber = MSUF_Defaults_ToNumber
Parts.MSUF_Defaults_TryDecodeCompactString = MSUF_Defaults_TryDecodeCompactString
Parts.MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED = MSUF_FACTORY_DEFAULT_PLAYER_DEFENSIVES_ENABLED
Parts.MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = MSUF_FACTORY_DEFAULT_PROFILE_COMPACT
Parts.StateHelpers = StateHelpers
Parts.fresh = fresh
function Parts.Bind0()
    MSUF_Defaults_NormalizeAuras3Profile = Parts.MSUF_Defaults_NormalizeAuras3Profile
end
