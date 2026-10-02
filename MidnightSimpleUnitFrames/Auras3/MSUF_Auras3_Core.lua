--- Auras3/MSUF_Auras3_Core.lua
--- Auras3 namespace and profile DB adapter.
---
--- 6.0 keeps aura configuration, menu, edit-mode handles, previews, and the
--- 12.1 native UnitFrame backend split so secure aura objects stay isolated
--- from menu/edit code.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local ExportPublic = MSUF.ExportPublic

local type = type
local tostring = tostring

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do out[DeepCopy(key, seen)] = DeepCopy(child, seen) end
    return out
end

local FRAME_LIST_RUNTIME_UNITS = { "player", "pet", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
local FRAME_LIST_SCOPES = { "player", "pet", "target", "focus", "boss" }
local PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER = "_msufA3PlayerDefensivesCoreDefault_v1"
local PLAYER_DEFENSIVE_FACTORY_POLICY_MARKER = "_msufFactoryPlayerDefensivesEnabled_v1"

local function FillMissing(dst, defaults)
    if type(dst) ~= "table" or type(defaults) ~= "table" then return dst end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            FillMissing(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
    return dst
end

local NewPlayerDefensiveContainer = assert(MSUF.MSUF_CreateCanonicalPlayerDefensiveAuraContainer,
    "Aura defaults must load before Auras3 core")
local DEFENSIVE_TEMPLATE = NewPlayerDefensiveContainer() -- read-only fill source

local function EnsurePlayerDefensiveCoreDefault(auras, factoryEnabled)
    if type(auras) ~= "table" then return nil end
    local root = type(auras.customContainers) == "table" and auras.customContainers or {}
    auras.customContainers = root
    root.perUnit = type(root.perUnit) == "table" and root.perUnit or {}
    local record = type(root.perUnit.player) == "table" and root.perUnit.player or { items = {} }
    root.perUnit.player = record
    record.items = type(record.items) == "table" and record.items or {}
    local item = record.items[4]
    if type(item) ~= "table" then
        item = NewPlayerDefensiveContainer()
        record.items[4] = item
    end
    local canonicalAuraModel = (tonumber(auras.profileModelRevision) or 0) >= 1
    if canonicalAuraModel then
        if type(factoryEnabled) == "boolean" then item.enabled = factoryEnabled end
        item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] = nil
    elseif type(factoryEnabled) == "boolean" then
        -- Factory resets own this one initial value. The policy marker is
        -- consumed below, so later user toggles remain ordinary saved choices.
        item.enabled = factoryEnabled
        item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] = true
    else
        -- This is intentionally a one-shot opt-out migration. Every profile
        -- that predates the Core feature starts enabled once; after the marker
        -- is stored, a user's explicit menu choice is never overwritten.
        if item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] ~= true then
            item.enabled = true
            item[PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER] = true
        end
    end
    FillMissing(item, DEFENSIVE_TEMPLATE)
    item.name = "Defensive Buffs"
    item.auraType = "BUFF"
    item.sourceUnit = "player"
    item.playerDefensives = true
    item.targetDots = nil
    return item
end

local function EnsurePlayerDefensiveProfileDefault(db, auras)
    local factoryEnabled
    if type(db) == "table" then
        factoryEnabled = db[PLAYER_DEFENSIVE_FACTORY_POLICY_MARKER]
    end
    local item = EnsurePlayerDefensiveCoreDefault(auras, factoryEnabled)
    if item and type(factoryEnabled) == "boolean" then
        db[PLAYER_DEFENSIVE_FACTORY_POLICY_MARKER] = nil
    end
    return item
end

local function MigrateFrameOwnedAuraLists(auras)
    if type(auras) ~= "table" then return end
    local shared = type(auras.shared) == "table" and auras.shared or nil
    local legacyBlacklist = shared and shared.blacklist
    if auras._msufA3FrameOwnedLists_v1 ~= true then
        auras.perUnit = type(auras.perUnit) == "table" and auras.perUnit or {}
        for i = 1, #FRAME_LIST_RUNTIME_UNITS do
            local unit = FRAME_LIST_RUNTIME_UNITS[i]
            local record = type(auras.perUnit[unit]) == "table" and auras.perUnit[unit] or {}
            auras.perUnit[unit] = record
            if record.overrideBlacklist ~= true or type(record.blacklist) ~= "table" then
                record.blacklist = DeepCopy(type(legacyBlacklist) == "table" and legacyBlacklist or { spells = {} })
            end
            record.overrideBlacklist = true -- legacy compatibility; ownership is now always local
        end

        local displays = type(auras.customDisplays) == "table" and auras.customDisplays or {}
        auras.customDisplays = displays
        displays.perUnit = type(displays.perUnit) == "table" and displays.perUnit or {}
        local sharedItems = type(displays.shared) == "table" and displays.shared.items or nil
        for i = 1, #FRAME_LIST_SCOPES do
            local scope = FRAME_LIST_SCOPES[i]
            local record = displays.perUnit[scope]
            if type(record) ~= "table" or record.override ~= true then
                displays.perUnit[scope] = {
                    override = true,
                    items = DeepCopy(type(sharedItems) == "table" and sharedItems or {}),
                }
            end
        end
        auras._msufA3FrameOwnedLists_v1 = true
    end

    -- Shared lists are retired after the one-time fan-out. Keep only the
    -- scope-aware visual/filter defaults in the Shared Aura Style record.
    if shared then shared.blacklist = nil end
    local displays = auras.customDisplays
    if type(displays) == "table" then
        displays.shared = type(displays.shared) == "table" and displays.shared or {}
        displays.shared.items = {}
    end
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end

ExportPublic("MSUF_Auras3", A3)

-- Native aura runtime failures are recorded on A3.nativeAuraRuntimeError so
-- diagnostics and smokes can read them, but nothing ever showed them: a
-- Blizzard_AuraContainer that refuses to load, a missing container template,
-- a container short of its method contract or a filter string Blizzard
-- rejects leaves the affected lanes dark with no message. Each distinct
-- failure is handed to the shared error boundary once per session. Clients
-- expected to lack the 12.1 aura runtime stay silent: a pre-12.1 build is
-- already told by the client version warning, and a non-Mainline project
-- never had it.
local reportedNativeAuraRuntimeErrors = {}
local function NativeAuraRuntimeExpected()
    local warning = MSUF.ClientVersionWarning
    if type(warning) == "table" and type(warning.IsLegacyClient) == "function"
        and warning.IsLegacyClient() == true then
        return false
    end
    -- The Mainline family owns the 12.1 aura runtime, and WoW Forever runs the
    -- Mainline build whatever project ID it reports, so the code family is the
    -- honest question. A harness that loads this file without the client model
    -- keeps the Mainline answer, the build this file belongs to.
    local client = MSUF.Client
    if type(client) ~= "table" then return true end
    return client.Family == "Mainline"
end
function A3._RecordNativeAuraRuntimeError(message)
    A3.nativeAuraRuntimeError = message
    if reportedNativeAuraRuntimeErrors[message] then return message end
    reportedNativeAuraRuntimeErrors[message] = true
    local report = MSUF.ReportError or _G.MSUF_ReportError
    if type(report) == "function" and NativeAuraRuntimeExpected() then
        report("Auras3", message)
    end
    return message
end

A3.addonName = addonName
A3.embedTarget = (type(MSUF.UFCore) == "table" and MSUF.UFCore.embedTarget) or addonName
A3.embedded = true
if type(MSUF.UFCore) == "table" then
    MSUF.UFCore.Auras3 = A3
end

A3.version = 3
A3._runtimeConfigGen = A3._runtimeConfigGen or 1
A3._unitFrameOwners = A3._unitFrameOwners or {}
A3.PlayerDefensiveCoreDefaultMarker = PLAYER_DEFENSIVE_CORE_DEFAULT_MARKER
A3.PlayerDefensiveFactoryPolicyMarker = PLAYER_DEFENSIVE_FACTORY_POLICY_MARKER
A3.NewPlayerDefensiveContainer = NewPlayerDefensiveContainer
A3.EnsurePlayerDefensiveCoreDefault = EnsurePlayerDefensiveCoreDefault

MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
ExportPublic("MSUF_AuraCore", MSUF.AuraCore)
MSUF.AuraCore.Auras3 = A3

--- Unit aura lane-key schema: the one source for the Buff and Debuff lane keys
--- of the player, pet, target, focus, boss and arena frames. Every saved key is
--- listed once with the profile table that owns it and its Shared default. The
--- menu schema (MenuModel/MSUF_Auras3_Menu_Schema.lua) and the runtime schema
--- (Runtime/MSUF_Auras3_Runtime_Schema.lua) take their key sets, lane specs and
--- default tables from A3.LaneKeySchema. Every client loads this file before
--- both; the Classic flavors load only the menu schema.
---
--- Owner: where Menu2 writes a unit-scope value.
---   layout             perUnit.layout (frame-local placement)
---   layoutShared       perUnit.layoutShared (counts and growth)
---   styleLayout        perUnit.layout, inherited from Shared Style until the
---                      unit overrides its style
---   styleLayoutShared  perUnit.layoutShared, inherited the same way
---   false              Shared only, never routed to a unit
--- Defaults: the Shared default tables a key's value belongs to.
---   S  the legacy defaults the menu seeds once into a pre-canonical Shared
---      table (Menu_Storage, Model.EnsureDB)
---   F  the fallbacks the runtime compiler reads when a key is absent
--- Both sets are saved-profile contracts: change one only with a migration.
---
--- The rows of the lane-key schema: data only, read once by BuildLaneKeySchema.
local function LaneKeySchemaRows()
    local SF, S, F = "SF", "S", "F"

    -- Shared keys without a lane prefix: key, owner, default, defaults.
    local SHARED_KEYS = {
        { "iconSize", "layout", 26, SF },
        { "spacing", "layout", 2, SF },
        { "offsetX", "layout", 0, S },
        { "offsetY", "layout", 6, S },
        { "perRow", "layoutShared", 12, SF },
        { "growth", "layoutShared", "RIGHT", SF },
        { "rowWrap", "layoutShared", "DOWN", SF },
        { "iconZoom", "styleLayout", 100, SF },
        { "stylePadding", "styleLayout", 0, F },
        { "durationBarHeight", "styleLayout", 2, SF },
        { "stackTextSize", "styleLayout", 14, SF },
        { "stackTextOffsetX", "styleLayout", -1, SF },
        { "stackTextOffsetY", "styleLayout", 1, SF },
        { "cooldownTextSize", "styleLayout", 14, SF },
        { "cooldownTextOffsetX", "styleLayout", 0, SF },
        { "cooldownTextOffsetY", "styleLayout", 0, SF },
        { "showTooltip", "styleLayoutShared", true, SF },
        { "showCooldownSwipe", "styleLayoutShared", true, SF },
        { "cooldownSwipeReverse", "styleLayoutShared", false, SF },
        { "sortMethod", "styleLayoutShared", "DEFAULT", F },
        { "sortReverse", "styleLayoutShared", false, F },
        { "showDurationBar", "styleLayoutShared", false, SF },
        { "durationBarDisplay", "styleLayoutShared", "BAR_ONLY", SF },
        { "durationBarPosition", "styleLayoutShared", "BOTTOM", SF },
        { "durationBarDirection", "styleLayoutShared", "REMAINING", SF },
        { "showCooldownText", "styleLayoutShared", true, SF },
        { "showStackCount", "styleLayoutShared", true, SF },
        { "debuffTypeBorderMode", "styleLayoutShared", "OFF", SF },
        { "dispelBorderMode", "styleLayoutShared" },
        { "useDebuffTypeBorders", "styleLayoutShared", false, SF },
        { "stackCountAnchor", "styleLayoutShared", "TOPRIGHT", SF },
        { "cooldownTextAnchor", "styleLayoutShared", "CENTER", SF },
        { "cooldownDecimalSeconds", "styleLayoutShared", 3, SF },
        { "iconShape", false, "RECTANGLE", S },
        { "showWeaponEnchants", false, false, F },
        { "styleBorderEnabled", false, false, F },
        { "styleBorderStyle", false, "SOLID", F },
        { "styleBorderThickness", false, 1, F },
        { "styleBorderColor", false, { 0, 0, 0, 1 }, F },
        { "styleShadowEnabled", false, false, F },
        { "styleShadowSize", false, 4, F },
        { "styleShadowColor", false, { 0, 0, 0, 0.8 }, F },
    }

    -- The two lanes. Lane defaults cover the fields whose default differs per lane.
    local LANES = {
        buff = { prefix = "buff", rootKey = "Buffs", filter = "HELPFUL",
            defaults = { yKey = 36, anchorKey = "BOTTOMRIGHT", layerKey = 5 } },
        debuff = { prefix = "debuff", rootKey = "Debuffs", filter = "HARMFUL",
            defaults = { yKey = 6, anchorKey = "TOPLEFT", layerKey = 6 } },
    }

    -- Lane spec fields: field, key (prefix .. suffix; "%s" takes the lane's
    -- rootKey instead), owner, the Shared key the lane field overrides, default,
    -- defaults. A field with a Shared key and no default takes the Shared key's.
    local LANE_FIELDS = {
        { "xKey", "GroupOffsetX", "layout", nil, 0, SF },
        { "yKey", "GroupOffsetY", "layout", nil, nil, SF },
        { "sizeKey", "GroupIconSize", "layout", nil, 26, SF },
        { "anchorKey", "Anchor", "layout", nil, nil, SF },
        { "layerKey", "Layer", "layout", nil, nil, SF },
        { "strataKey", "Strata", "layout" },
        { "spacingKey", "Spacing", "layout" },
        { "showKey", "show%s", "layoutShared", nil, true, SF },
        { "maxKey", "max%s", "layoutShared", nil, 12, SF },
        { "perRowKey", "PerRow", "layoutShared" },
        { "growthKey", "GrowthX", "layoutShared" },
        { "wrapKey", "GrowthY", "layoutShared" },
        { "iconZoomKey", "IconZoom", "styleLayout", "iconZoom", nil, S },
        { "paddingKey", "StylePadding", "styleLayout", "stylePadding" },
        { "durationBarHeightKey", "DurationBarHeight", "styleLayout", "durationBarHeight", nil, S },
        { "stackSizeKey", "StackTextSize", "styleLayout", "stackTextSize", nil, S },
        { "stackXKey", "StackTextOffsetX", "styleLayout", "stackTextOffsetX", nil, S },
        { "stackYKey", "StackTextOffsetY", "styleLayout", "stackTextOffsetY", nil, S },
        { "cooldownSizeKey", "CooldownTextSize", "styleLayout", "cooldownTextSize", nil, S },
        { "cooldownXKey", "CooldownTextOffsetX", "styleLayout", "cooldownTextOffsetX", nil, S },
        { "cooldownYKey", "CooldownTextOffsetY", "styleLayout", "cooldownTextOffsetY", nil, S },
        { "showTextKey", "ShowCooldownText", "styleLayoutShared", "showCooldownText", nil, S },
        { "swipeKey", "ShowCooldownSwipe", "styleLayoutShared", "showCooldownSwipe", nil, S },
        { "swipeReverseKey", "CooldownSwipeReverse", "styleLayoutShared", "cooldownSwipeReverse", nil, S },
        { "sortMethodKey", "SortMethod", "styleLayoutShared", "sortMethod", nil, S },
        { "sortReverseKey", "SortReverse", "styleLayoutShared", "sortReverse", nil, S },
        { "showDurationBarKey", "ShowDurationBar", "styleLayoutShared", "showDurationBar", nil, S },
        { "durationBarDisplayKey", "DurationBarDisplay", "styleLayoutShared", "durationBarDisplay", nil, S },
        { "durationBarPositionKey", "DurationBarPosition", "styleLayoutShared", "durationBarPosition", nil, S },
        { "durationBarDirectionKey", "DurationBarDirection", "styleLayoutShared", "durationBarDirection", nil, S },
        { "tooltipKey", "ShowTooltip", "styleLayoutShared", "showTooltip", nil, SF },
        { "showStackKey", "ShowStackCount", "styleLayoutShared", "showStackCount", nil, S },
        { "stackAnchorKey", "StackCountAnchor", "styleLayoutShared", "stackCountAnchor", nil, S },
        { "cooldownAnchorKey", "CooldownTextAnchor", "styleLayoutShared", "cooldownTextAnchor", nil, S },
        { "cooldownDecimalKey", "CooldownDecimalSeconds", "styleLayoutShared", "cooldownDecimalSeconds", nil, S },
        { "iconShapeKey", "IconShape", false, "iconShape", nil, S },
        { "filterKey", "s", false },
    }

    -- Lane keys outside the spec: lanes, key suffix, owner, the menu's style
    -- name for it, default, defaults.
    local LANE_EXTRA_KEYS = {
        { "buff debuff", "FrameEffectType", "styleLayoutShared", nil, "none", SF },
        { "buff debuff", "FrameEffectColor", "styleLayoutShared", nil, { 0.69, 0.50, 0.88, 0.80 }, SF },
        { "buff debuff", "FrameEffectPriority", "styleLayoutShared", nil, 5, SF },
        { "buff debuff", "FrameEffectThickness", "styleLayoutShared", nil, 2, SF },
        { "buff debuff", "FrameEffectLayer", "styleLayoutShared", nil, 0, SF },
        { "buff debuff", "FrameEffectStrata", "styleLayoutShared", nil, "AUTO", SF },
        { "buff", "ShowStealable", "styleLayoutShared", "showStealable", false, S },
        { "buff", "StealableStyle", "styleLayoutShared", "stealableStyle", "BORDER_ICON", S },
        -- Pre-6.0 Buffs lane offsets: seeded into old profiles, read by nothing new.
        { "buff", "OffsetX", false, nil, 0, S },
        { "buff", "OffsetY", false, nil, 30, S },
    }

    -- The Debuffs lane has no prefixed copy of these; its style key is the
    -- Shared key itself.
    local LANE_STYLE_ALIASES = { debuff = { "debuffTypeBorderMode", "useDebuffTypeBorders" } }
    return SHARED_KEYS, LANES, LANE_FIELDS, LANE_EXTRA_KEYS, LANE_STYLE_ALIASES
end

local function BuildLaneKeySchema()
    local SHARED_KEYS, LANES, LANE_FIELDS, LANE_EXTRA_KEYS, LANE_STYLE_ALIASES = LaneKeySchemaRows()
    local SF, S, F = "SF", "S", "F"
    local schema = {
        LANE_SPECS = {},
        LANE_LAYOUT_FIELDS = {},
        LANE_SHARED_LAYOUT_FIELDS = {},
        LAYOUT_KEYS = {},
        SHARED_LAYOUT_KEYS = {},
        STYLE_LAYOUT_KEYS = {},
        STYLE_SHARED_LAYOUT_KEYS = {},
        SCOPE_MATERIALIZED_LAYOUT_KEYS = {},
        LANE_STYLE_KEYS = {},
    }
    local OWNER_SETS = {
        layout = { schema.LAYOUT_KEYS },
        layoutShared = { schema.SHARED_LAYOUT_KEYS },
        styleLayout = { schema.LAYOUT_KEYS, schema.STYLE_LAYOUT_KEYS },
        styleLayoutShared = { schema.SHARED_LAYOUT_KEYS, schema.STYLE_SHARED_LAYOUT_KEYS },
    }
    local seedDefaults, fallbackDefaults, ownerOf = {}, {}, {}
    local function AddKey(key, owner, default, defaults)
        assert(ownerOf[key] == nil, "MSUF Auras3 lane key listed twice: " .. tostring(key))
        ownerOf[key] = owner
        assert(owner == false or OWNER_SETS[owner], "MSUF Auras3 lane key has an unknown owner: " .. tostring(key))
        for _, set in ipairs(owner and OWNER_SETS[owner] or {}) do set[key] = true end
        if defaults == SF or defaults == S then seedDefaults[key] = default end
        if defaults == SF or defaults == F then fallbackDefaults[key] = default end
    end

    local sharedDefault = {}
    for _, row in ipairs(SHARED_KEYS) do
        AddKey(row[1], row[2], row[3], row[4])
        sharedDefault[row[1]] = row[3]
    end
    for _, field in ipairs(LANE_FIELDS) do
        if field[3] == "layout" then
            schema.LANE_LAYOUT_FIELDS[#schema.LANE_LAYOUT_FIELDS + 1] = field[1]
        elseif field[3] == "layoutShared" then
            schema.LANE_SHARED_LAYOUT_FIELDS[#schema.LANE_SHARED_LAYOUT_FIELDS + 1] = field[1]
        end
    end
    for kind, lane in pairs(LANES) do
        local spec = { rootKey = lane.rootKey, filter = lane.filter,
            defaultAnchor = lane.defaults.anchorKey, defaultLayer = lane.defaults.layerKey }
        local styleKeys = {}
        for _, field in ipairs(LANE_FIELDS) do
            local name, suffix, owner, sharedKey = field[1], field[2], field[3], field[4]
            local key = suffix:find("%s", 1, true) and suffix:format(lane.rootKey) or lane.prefix .. suffix
            local default = lane.defaults[name]
            if default == nil then default = field[5] end
            if default == nil and sharedKey then default = sharedDefault[sharedKey] end
            spec[name] = key
            AddKey(key, owner, default, field[6])
            if sharedKey then styleKeys[sharedKey] = key end
        end
        for _, extra in ipairs(LANE_EXTRA_KEYS) do
            if (" " .. extra[1] .. " "):find(" " .. kind .. " ", 1, true) then
                local key = lane.prefix .. extra[2]
                AddKey(key, extra[3], extra[5], extra[6])
                if extra[4] then styleKeys[extra[4]] = key end
            end
        end
        for _, key in ipairs(LANE_STYLE_ALIASES[kind] or {}) do styleKeys[key] = key end
        -- Per-lane spacing is materialized into every scope rather than inherited.
        schema.SCOPE_MATERIALIZED_LAYOUT_KEYS[spec.spacingKey] = true
        schema.LANE_SPECS[kind] = spec
        schema.LANE_STYLE_KEYS[kind] = styleKeys
    end

    -- Each default-table build hands out fresh value tables, so no reader can
    -- change another's defaults through a shared color table.
    local function Copy(values)
        local out = {}
        for key, value in pairs(values) do out[key] = DeepCopy(value) end
        return out
    end
    function schema.SeedDefaults() return Copy(seedDefaults) end
    function schema.FallbackDefaults() return Copy(fallbackDefaults) end
    return schema
end
A3.LaneKeySchema = BuildLaneKeySchema()

local function EnsureRootDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        db = {}
        ExportPublic("MSUF_DB", db)
    end
    return db
end

function A3.NormalizeProfileDB(db)
    if type(db.auras2) == "table" then
        --- Every caller passes a stored profile: the live MSUF_DB, a profile being
        --- exported, or an import candidate whose payload already ran the untrusted
        --- import pass. Without the trust flag the translator wiped the defaults and
        --- dispel migration stamps and forced showNavigationIcons back on.
        _G.MSUF_ProfileIO_TranslateProfileToCurrent(db, {
            source = "auras3_core", markProfile = true, trustProfileMetadata = true,
        })
    end
    local current = db.auras3
    if type(current) ~= "table" then
        current = MSUF.MSUF_CreateCanonicalUnitAuras()
        db.auras3 = current
    end
    db.auras2 = nil
    current._msufAurasRuntime = nil
    MSUF.MSUF_MaterializeUnitAuraLaneOwners(current)
    if tonumber(current.profileModelRevision) and tonumber(current.profileModelRevision) >= 1 then
        current._msufA3FrameOwnedLists_v1 = nil
    else
        MigrateFrameOwnedAuraLists(current)
    end
    EnsurePlayerDefensiveProfileDefault(db, current)
    return current, current.shared
end

-- Normalizing is idempotent: skip it while the stamped profile is unchanged.
local sDB, sAuras, sItem, sGen
local function DefensiveItem(a)
    a = a.customContainers; a = type(a) == "table" and a.perUnit
    a = type(a) == "table" and a.player; a = type(a) == "table" and a.items
    return type(a) == "table" and a[4] or nil
end
function A3.EnsureDB()
    local db = EnsureRootDB()
    local cur, it = db.auras3, sItem
    if cur and cur == sAuras and db == sDB and sGen == A3._runtimeConfigGen and it
        and DefensiveItem(cur) == it and it.name == "Defensive Buffs" and type(it.placed) == "table" then
        return cur, cur.shared
    end
    local current, shared = A3.NormalizeProfileDB(db)
    sDB, sAuras, sItem, sGen = db, current, DefensiveItem(current), A3._runtimeConfigGen
    return current, shared
end

function A3.BumpRuntimeConfig()
    A3._runtimeConfigGen = (A3._runtimeConfigGen or 0) + 1
    return A3._runtimeConfigGen
end

function A3.UnitFrameAuraEnabled()
    return false
end

function A3.SetUnitFrameOwner(unit, frame, owns)
    if not unit then return end
    local owners = A3._unitFrameOwners
    if owns and frame then
        owners[unit] = frame
    elseif owners[unit] == frame or not frame then
        owners[unit] = nil
    end
end

function A3.RuntimeOwnsUnit()
    return false
end

function A3.EnableFrame(frame)
    if frame then frame._msufA3UnitAuraOwner = nil end
    return false
end

function A3.DisableFrame(frame)
    if frame then frame._msufA3UnitAuraOwner = nil end
    return true
end

function A3.RenderFrame()
    return false
end

function A3.ForceUpdateFrame()
    return false
end

function A3.RequestUnit()
    return false
end

function A3.RequestScope()
    A3.BumpRuntimeConfig()
    return true
end

--- Request helpers both client backends share: Retail's
--- Auras3/Runtime/MSUF_Auras3_Runtime_Facade.lua and Classic's
--- Game/Classic/Auras/MSUF_Auras3_Requests.lua each kept a copy, and this
--- core's own scope list had drifted from them (no arena).
A3._requestApplyScopeKeys = A3._requestApplyScopeKeys or {
    player = true, pet = true, target = true, focus = true, boss = true, arena = true,
    party = true, raid = true, mythicraid = true,
    gf_party = true, gf_raid = true, gf_mythicraid = true,
    group = true, groups = true,
    shared = true, global = true, all = true, ["*"] = true,
}

A3._LooksLikeApplyScope = function(value)
    value = tostring(value or ""):lower()
    if value == "" then return false end
    if A3._requestApplyScopeKeys[value] then return true end
    return value:match("^boss%d+$") ~= nil
        or value:match("^arena%d+$") ~= nil
        or value:match("^party%d+$") ~= nil
        or value:match("^raid%d+$") ~= nil
end

--- The group frame kind a preview refresh for `scope` touches, and whether it
--- touches the group previews at all.
function A3._AuraPreviewGroupKind(scope)
    local key = tostring(scope or ""):lower()
    if key == "party" or key == "gf_party" or key:match("^party%d+$") then return "party", true end
    if key == "raid" or key == "gf_raid" or key:match("^raid%d+$") then return "raid", true end
    if key == "mythicraid" or key == "gf_mythicraid" then return "mythicraid", true end
    if key == "" or key == "shared" or key == "global" or key == "all" or key == "*"
        or key == "group" or key == "groups" then
        return nil, true
    end
    return nil, false
end

--- Queues aura runtime work that combat blocked. The backend owns the driver
--- (A3._EnsureDeferredAuraRuntimeDriver) and the flush, and names the reason a
--- request without one carries (A3._deferredAuraDefaultReason).
function A3._QueueDeferredAuraRuntime(scope, reason, visuals)
    scope = tostring(scope or "shared"):lower()
    A3._deferredAuraRuntime = true
    A3._deferredAuraRuntimeReason = reason or A3._deferredAuraRuntimeReason
        or A3._deferredAuraDefaultReason or "AURAS3_DEFERRED"
    if visuals == true then A3._deferredAuraRuntimeVisuals = true end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
    elseif A3._deferredAuraRuntimeAll ~= true then
        A3._deferredAuraRuntimeScopes = A3._deferredAuraRuntimeScopes or {}
        A3._deferredAuraRuntimeScopes[scope] = true
    end
    local frame = A3._EnsureDeferredAuraRuntimeDriver()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return false
end

function A3.RefreshAll()
    A3.BumpRuntimeConfig()
    return true
end

function A3.RequestApply(scopeOrReason, reason)
    if A3._LooksLikeApplyScope(scopeOrReason) and type(A3.RequestScope) == "function" then
        return A3.RequestScope(scopeOrReason, reason or "AURAS3_REQUEST_APPLY")
    end
    return A3.RefreshAll()
end

function A3.RefreshUnit()
    A3.BumpRuntimeConfig()
    return true
end

function A3.ApplyFontsFromGlobal()
    A3.BumpRuntimeConfig()
    return true
end

function A3.UpdateUnitAnchor()
    return true
end

function A3.RefreshEditPreview()
    return true
end

function A3.ResolveUnitFrameConfig()
    return nil
end

function A3.BuildAuraLaneMetrics()
    return nil
end

-- Shared configuration rule. Runtime and both menu layers bind this once.
local function NormalizeDebuffTypeBorderMode(value, fallback)
    if value == true then return "SYMBOL" end
    if value == false then return "OFF" end
    value = tostring(value or ""):upper()
    if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
    if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
        or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
        return "SYMBOL"
    end
    if value == "OFF" or value == "NONE" or value == "DISABLED" then return "OFF" end
    return fallback or "OFF"
end
A3.NormalizeDebuffTypeBorderMode = NormalizeDebuffTypeBorderMode
ExportPublic("MSUF_NormalizeAuraDebuffTypeBorderMode", NormalizeDebuffTypeBorderMode)

-- Legacy group flags intentionally retain their own fallback semantics.
local function NormalizeDispelBorderMode(value, legacyEnabled)
  if value == true then return "SYMBOL" end
  if value == false then return "OFF" end
  value = tostring(value or ""):upper()
  if value == "BORDER" or value == "COLOR" or value == "ON" then return "BORDER" end
  if value == "SYMBOL" or value == "BORDER_SYMBOL" or value == "BORDER_SYMBOLS"
    or value == "BORDER+SYMBOL" or value == "ICON" or value == "WITH_SYMBOL" then
    return "SYMBOL"
  end
  if value == "OFF" or value == "NONE" or value == "DISABLED" then return legacyEnabled == true and "SYMBOL" or "OFF" end
  return legacyEnabled == true and "SYMBOL" or "OFF"
end
ExportPublic("MSUF_NormalizeLegacyDispelBorderMode", NormalizeDispelBorderMode)

local AuraStrataIsSecret = _G.issecretvalue
local function SyncFrameStrata(frame, strata)
    if not (frame and frame.SetFrameStrata) then return false end
    if AuraStrataIsSecret(strata) == true then return false end
    if strata == nil or strata == "" then return false end
    local cachedStrata = frame._msufA3FrameStrata
    if AuraStrataIsSecret(cachedStrata) ~= true and cachedStrata == strata then return false end
    frame._msufA3FrameStrata = strata
    local currentStrata
    if frame.GetFrameStrata then currentStrata = frame:GetFrameStrata() end
    if AuraStrataIsSecret(currentStrata) == true or currentStrata ~= strata then
        frame:SetFrameStrata(strata)
        return true
    end
    return false
end
A3.SyncFrameStrata = SyncFrameStrata
ExportPublic("MSUF_AuraSyncFrameStrata", SyncFrameStrata)

local function AnchorOffset(anchor, w, h)
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    anchor = tostring(anchor or "TOPLEFT")
    if anchor == "TOPLEFT" then return 0, h end
    if anchor == "TOP" then return w * 0.5, h end
    if anchor == "TOPRIGHT" then return w, h end
    if anchor == "LEFT" then return 0, h * 0.5 end
    if anchor == "CENTER" then return w * 0.5, h * 0.5 end
    if anchor == "RIGHT" then return w, h * 0.5 end
    if anchor == "BOTTOMLEFT" then return 0, 0 end
    if anchor == "BOTTOM" then return w * 0.5, 0 end
    if anchor == "BOTTOMRIGHT" then return w, 0 end
    return 0, h
end
A3.AnchorOffset = AnchorOffset
ExportPublic("MSUF_AuraAnchorOffset", AnchorOffset)

--- The offset pair that reproduces `host`'s on-screen rect from `anchor` on
--- `parent`, unrounded, or nil while either rect is unresolved. The dispel
--- symbol previews of both backends turn a drag into saved offsets with it;
--- the host is parented to the frame, so the raw edges share one scale.
function A3.HostAnchorOffset(host, parent, anchor)
    local hl, hr, ht, hb = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
    local pl, pr, pt, pb = parent:GetLeft(), parent:GetRight(), parent:GetTop(), parent:GetBottom()
    if not (hl and hr and ht and hb and pl and pr and pt and pb) then return nil, nil end
    anchor = tostring(anchor or "TOPRIGHT")
    local x
    if anchor:find("LEFT", 1, true) then
        x = hl - pl
    elseif anchor:find("RIGHT", 1, true) then
        x = hr - pr
    else
        x = ((hl + hr) * 0.5) - ((pl + pr) * 0.5)
    end
    local y
    if anchor:find("TOP", 1, true) then
        y = ht - pt
    elseif anchor:find("BOTTOM", 1, true) then
        y = hb - pb
    else
        y = ((ht + hb) * 0.5) - ((pt + pb) * 0.5)
    end
    return x, y
end

local function PaddingInset(anchor, pad)
    pad = tonumber(pad) or 0
    if pad == 0 then return 0, 0 end
    anchor = tostring(anchor or "TOPLEFT")
    local dx = anchor:find("LEFT", 1, true) and pad or (anchor:find("RIGHT", 1, true) and -pad or 0)
    local dy = anchor:find("BOTTOM", 1, true) and pad or (anchor:find("TOP", 1, true) and -pad or 0)
    return dx, dy
end
A3.PaddingInset = PaddingInset
ExportPublic("MSUF_AuraPaddingInset", PaddingInset)

local function NormalizeDispelTrigger(value)
    if value == "BY_RAID" or value == "RAID" or value == "GROUP" or value == "BY_GROUP" then return "BY_RAID" end
    if value == "DISPEL_TYPE" or value == "TYPE" or value == "ANY_DISPEL_TYPE" then return "DISPEL_TYPE" end
    if value == "ANY_DEBUFF" or value == "ANY" or value == "ALL_DEBUFFS" then return "DISPEL_TYPE" end
    return "BY_ME"
end
A3.NormalizeDispelTrigger = NormalizeDispelTrigger
ExportPublic("MSUF_NormalizeDispelBorderTrigger", NormalizeDispelTrigger)

local function SpellIDFromKey(value)
    value = tostring(value or "")
    local id = tonumber(value:match("spell:(%d+)") or value:match("#(%d+)") or value:match("^(%d+)$"))
    return id and math.floor(id + 0.5) or nil
end
A3.SpellIDFromKey = SpellIDFromKey
ExportPublic("MSUF_AuraSpellIDFromKey", SpellIDFromKey)

local function ButtonAnchor(xSign, ySign)
    if ySign > 0 then
        return xSign < 0 and "BOTTOMRIGHT" or "BOTTOMLEFT"
    end
    return xSign < 0 and "TOPRIGHT" or "TOPLEFT"
end
A3.ButtonAnchor = ButtonAnchor
ExportPublic("MSUF_AuraButtonAnchor", ButtonAnchor)

local function ReadParentFrameStrata(parentFrame)
    local strata
    if parentFrame and parentFrame.GetFrameStrata then strata = parentFrame:GetFrameStrata() end
    if AuraStrataIsSecret(strata) == true then return nil end
    return strata
end
A3.ReadParentFrameStrata = ReadParentFrameStrata
ExportPublic("MSUF_AuraReadParentFrameStrata", ReadParentFrameStrata)

local function TableHasAnyKey(tbl, keys)
    if type(tbl) ~= "table" or type(keys) ~= "table" then return false end
    for key in pairs(keys) do
        if tbl[key] ~= nil then return true end
    end
    return false
end
A3.TableHasAnyKey = TableHasAnyKey
ExportPublic("MSUF_AuraTableHasAnyKey", TableHasAnyKey)
