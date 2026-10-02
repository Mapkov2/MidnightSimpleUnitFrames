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
