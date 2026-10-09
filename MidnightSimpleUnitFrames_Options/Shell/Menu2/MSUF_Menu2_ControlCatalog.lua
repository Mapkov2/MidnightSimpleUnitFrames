--- Canonical runtime catalog for Menu2 controls.
---
--- The search registry knows where a visible control lives, while bindings know
--- whether it can read or change state. This module joins both views and
--- exposes exact runtime control identities and destinations to Search.
---
--- controlId contract:
---   * Explicit IDs (meta.controlId, command.controlId, or
---     widget._msuf2ControlId) win and must use portable ID characters.
---   * Existing controls without an explicit ID receive a deterministic ID
---     based on page, kind, raw/source label, and semantic command hints.
---   * A fallback collision never overwrites another control.  Both records are
---     marked unstable and the later record receives a quarantined suffix.
---
--- Label-derived fallbacks are deterministic for the same source metadata, but
--- only explicit IDs and semantic identity keys/control paths are guaranteed to
--- survive a future label rename.

local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Catalog = M.RuntimeControlCatalog or {}
M.RuntimeControlCatalog = Catalog

Catalog.SCHEMA_VERSION = 2

local CLASSIFICATION = {
    setting = true,
    action = true,
    navigation = true,
    ephemeral = true,
    unknown = true,
}

local STATIC_KINDS = {
    faq = true,
    section = true,
    text = true,
    title = true,
    description = true,
    spacer = true,
}

local VALID_ID_SOURCES = {
    explicit = true,
    fallback = true,
    fallback_invalid_explicit = true,
    collision = true,
    explicit_collision = true,
}

local STABLE_IDENTITY_BASIS = {
    identity_key = true,
    control_path = true,
    setting_key = true,
    action_key = true,
    navigation_key = true,
}

local STATE = Catalog._state
if type(STATE) ~= "table" then
    STATE = {
        byId = {},
        byPage = {},
        byWidget = setmetatable({}, { __mode = "k" }),
        components = setmetatable({}, { __mode = "k" }),
        -- Page key -> components marked for it since that page was last
        -- cleared: an upper bound (a collected widget only overcounts), so a
        -- page without an entry has no component to clear.
        componentPages = {},
        revision = 0,
    }
    Catalog._state = STATE
else
    STATE.byId = type(STATE.byId) == "table" and STATE.byId or {}
    STATE.byPage = type(STATE.byPage) == "table" and STATE.byPage or {}
    STATE.byWidget = type(STATE.byWidget) == "table" and STATE.byWidget or setmetatable({}, { __mode = "k" })
    STATE.components = type(STATE.components) == "table" and STATE.components or setmetatable({}, { __mode = "k" })
    STATE.componentPages = {}
    for _, component in pairs(STATE.components) do
        local componentPageKey = component.pageKey
        if componentPageKey ~= nil then
            STATE.componentPages[componentPageKey] = (STATE.componentPages[componentPageKey] or 0) + 1
        end
    end
    STATE.revision = tonumber(STATE.revision) or 0
end

local CLEAN_TEXT_CACHE_LIMIT = 4096
local CLEAN_TEXT_CACHE_MAX_SOURCE_LEN = 256
local cleanTextCache, cleanTextCacheCount = {}, 0
local function CleanText(value)
    if value == nil then return "" end
    -- The cache is keyed by source strings, so a repeated string returns here
    -- before any type or length work; every other value takes the full path.
    local hit = cleanTextCache[value]
    if hit ~= nil then return hit end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" then return "" end
    local text = kind == "string" and value or tostring(value)
    local source = text
    local cacheable = #source <= CLEAN_TEXT_CACHE_MAX_SOURCE_LEN
    if cacheable then
        local cached = cleanTextCache[source]
        if cached ~= nil then return cached end
    end
    if text:find("|", 1, true) then
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    if text:find("^%s") then text = text:gsub("^%s+", "") end
    if text:find("%s$") then text = text:gsub("%s+$", "") end
    if cacheable then
        if cleanTextCacheCount >= CLEAN_TEXT_CACHE_LIMIT then
            cleanTextCache, cleanTextCacheCount = {}, 0
        end
        cleanTextCache[source] = text
        cleanTextCacheCount = cleanTextCacheCount + 1
    end
    return text
end

local function CopyStringList(value)
    if type(value) == "string" then return { value } end
    local out = {}
    for i = 1, #(type(value) == "table" and value or {}) do out[i] = value[i] end
    return out
end

-- Lua 5.1 pattern syntax without calling string.match, which raises on a
-- malformed pattern: escapes, %b, %f, sets and balanced captures. A malformed
-- declared pattern is skipped instead of breaking the page build.
local function PatternSetEnd(text, open)
    local i = open + 1
    if text:sub(i, i) == "^" then i = i + 1 end
    if text:sub(i, i) == "]" then i = i + 1 end
    while i <= #text do
        local c = text:sub(i, i)
        if c == "%" then
            if i == #text then return nil end
            i = i + 2
        elseif c == "]" then
            return i
        else
            i = i + 1
        end
    end
    return nil
end
local function IsValidLuaPattern(text)
    local i, n, depth = 1, #text, 0
    while i <= n do
        local c = text:sub(i, i)
        if c == "%" then
            local class = text:sub(i + 1, i + 1)
            if class == "" then return false end
            if class == "b" then
                if i + 3 > n then return false end
                i = i + 4
            elseif class == "f" then
                local close = text:sub(i + 2, i + 2) == "[" and PatternSetEnd(text, i + 2)
                if not close then return false end
                i = close + 1
            else
                i = i + 2
            end
        elseif c == "[" then
            local close = PatternSetEnd(text, i)
            if not close then return false end
            i = close + 1
        elseif c == "(" then
            depth = depth + 1
            i = i + 1
        elseif c == ")" then
            depth = depth - 1
            if depth < 0 then return false end
            i = i + 1
        else
            i = i + 1
        end
    end
    return depth == 0
end

local NORMALIZED_TOKEN_CACHE_LIMIT = 4096
local NORMALIZED_TOKEN_CACHE_MAX_SOURCE_LEN = 256
local normalizedTokenCache, normalizedTokenCacheCount = {}, 0
local function NormalizeSearchSettingAliases(value, isPattern)
    local out, seen = {}, {}
    if type(value) ~= "table" then return out end
    for i = 1, #value do
        local item = CleanText(value[i])
        local valid = item ~= "" and #item <= 192 and not seen[item]
        if valid and isPattern then
            valid = IsValidLuaPattern(item)
        end
        if valid then
            seen[item] = true
            out[#out + 1] = item
        end
    end
    return out
end

local function NormalizeToken(value)
    local source = CleanText(value)
    local cacheable = #source <= NORMALIZED_TOKEN_CACHE_MAX_SOURCE_LEN
    if cacheable then
        local cached = normalizedTokenCache[source]
        if cached ~= nil then return cached end
    end
    local text = source:lower()
    text = text:gsub("[^%w]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if cacheable then
        if normalizedTokenCacheCount >= NORMALIZED_TOKEN_CACHE_LIMIT then
            normalizedTokenCache, normalizedTokenCacheCount = {}, 0
        end
        normalizedTokenCache[source] = text
        normalizedTokenCacheCount = normalizedTokenCacheCount + 1
    end
    return text
end

local function Slug(value, fallback, limit)
    local text = NormalizeToken(value):gsub(" ", "-")
    if text == "" then text = fallback or "unknown" end
    limit = tonumber(limit) or 40
    if #text > limit then text = text:sub(1, limit):gsub("%-+$", "") end
    return text ~= "" and text or (fallback or "unknown")
end

-- A small deterministic hash that stays inside Lua's exact integer range even
-- on the Lua 5.1 number model used by WoW.
local function StableHash(text)
    text = tostring(text or "")
    local hash = 104729
    for i = 1, #text do
        hash = (hash * 131 + text:byte(i)) % 2147483647
    end
    return string.format("%08x", hash)
end

-- Both registrations of a control (binding and search) check the same ID, and
-- the shared unit/group pages repeat theirs, so answers are memoized.
local EXPLICIT_ID_CACHE_LIMIT = 4096
local explicitIdCache, explicitIdCacheCount = {}, 0
local function IsValidExplicitId(value)
    if type(value) ~= "string" or #value < 3 or #value > 160 then return false end
    local known = explicitIdCache[value]
    if known ~= nil then return known end
    local valid = not (value:find("^%s") or value:find("%s$")) and value:match("^[%w_%.:/%-]+$") ~= nil
    if explicitIdCacheCount >= EXPLICIT_ID_CACHE_LIMIT then
        explicitIdCache, explicitIdCacheCount = {}, 0
    end
    explicitIdCache[value] = valid
    explicitIdCacheCount = explicitIdCacheCount + 1
    return valid
end

local function IsValidRuntimeId(value)
    if type(value) ~= "string" or #value < 3 or #value > 180 then return false end
    return value:match("^[%w_%.:/%-%~]+$") ~= nil
end

--- Optional widget accessor: templates vary in which of GetName/GetObjectType/
--- GetParent they expose. Available accessors run directly; exceptions propagate.
local function ReadWidget(method, object, ...)
    if type(method) ~= "function" then return nil end
    return method(object, ...)
end

local function WidgetName(widget)
    if not widget then return "" end
    return CleanText(ReadWidget(widget.GetName, widget))
end

local function WidgetKind(widget)
    if not widget then return "" end
    return CleanText(widget._msuf2ControlKind or ReadWidget(widget.GetObjectType, widget))
end

local function WidgetStructureHint(widget)
    if not widget then return "no-widget" end
    local parts = {}
    local current = widget
    for _ = 1, 4 do
        if not current then break end
        local name = WidgetName(current)
        local kind = WidgetKind(current)
        parts[#parts + 1] = (name ~= "" and name or "anonymous") .. ":" .. (kind ~= "" and kind or "object")
        current = ReadWidget(current.GetParent, current)
    end
    return table.concat(parts, "/")
end

local function ExplicitId(meta, command, widget)
    local value = meta and meta.controlId
    if value == nil and type(command) == "table" then value = command.controlId end
    if value == nil and widget then value = widget._msuf2ControlId end
    if value == nil then return nil, nil end
    if IsValidExplicitId(value) then return value, nil end
    return nil, tostring(value)
end

local function CommandSource(command, label)
    if type(command) ~= "table" then return "" end
    local direct = CleanText(command.source or command.sourceKey or command.settingKey or command.actionKey or command.navigationKey)
    if direct ~= "" then return direct end
    if type(command.sourceFn) == "function" then return CleanText(command.sourceFn(label)) end
    return ""
end

local function SemanticIdentity(meta, command, widget, label)
    meta = type(meta) == "table" and meta or {}
    command = type(command) == "table" and command or {}

    local value = CleanText(meta.identityKey)
    if value ~= "" then return value, "identity_key" end
    value = CleanText(meta.controlPath)
    if value ~= "" then return value, "control_path" end
    value = CleanText(meta.settingKey or command.settingKey)
    if value ~= "" then return value, "setting_key" end
    value = CleanText(meta.actionKey or command.actionKey)
    if value ~= "" then return value, "action_key" end
    value = CleanText(meta.navigationKey or command.navigationKey)
    if value ~= "" then return value, "navigation_key" end
    value = CleanText(meta.identityLabel)
    if value ~= "" then return value, "source_label" end
    value = CleanText(widget and widget._msuf2SearchText)
    if value ~= "" then return value, "source_label" end
    -- CommandSource may call a page-provided sourceFn; it only runs for
    -- controls that lack every stronger identity key above, which keeps the
    -- identity result identical while sparing its CleanText fan-out on the
    -- overwhelmingly common keyed paths.
    value = CleanText(CommandSource(command, label))
    if value ~= "" then return value, "command_source" end
    value = CleanText(label)
    if value ~= "" then return value, "display_label" end
    return "unidentified", "missing"
end

local function FallbackId(pageKey, kind, identity, command)
    local commandKind = type(command) == "table" and CleanText(command.kind) or ""
    local seed = pageKey .. "\031" .. kind .. "\031" .. identity .. "\031" .. commandKind
    return "menu2." .. Slug(pageKey, "unknown", 36)
        .. "." .. Slug(kind, "control", 24)
        .. "." .. Slug(identity, "unidentified", 42)
        .. "." .. StableHash(seed), seed
end

local function InferClassification(meta, command, kind)
    meta = type(meta) == "table" and meta or {}
    command = type(command) == "table" and command or nil
    local explicit = meta.classification or meta.controlType or (command and command.classification)
    if CLASSIFICATION[explicit] then return explicit, "explicit" end

    local navigationKey = meta.navigationKey or (command and command.navigationKey)
    if navigationKey or meta.navigation == true or (command and command.navigation == true) then
        return "navigation", "navigation_metadata"
    end
    local hasGet = command and type(command.get) == "function"
    local hasSet = command and type(command.set) == "function"
    if meta.settingKey or (command and command.settingKey) or (hasGet and hasSet) then
        return "setting", "read_write_command"
    end
    if meta.actionKey or (command and command.actionKey) or hasSet then
        return "action", "write_command"
    end
    if meta.ephemeral == true or STATIC_KINDS[kind] then
        return "ephemeral", meta.ephemeral == true and "explicit_ephemeral" or "static_search_object"
    end
    if command then return "unknown", "unclassified_command_shape" end
    return "unknown", "missing_command_metadata"
end

local REVISION_KEY_PARTS = {}
local REVISION_NO_KEYS = {}
local function RevisionKey(record)
    if type(record) ~= "table" then return nil end
    local parts = REVISION_KEY_PARTS
    local settingKeys = record.searchSettingKeys or REVISION_NO_KEYS
    local settingKeyPatterns = record.searchSettingKeyPatterns or REVISION_NO_KEYS
    parts[1] = tostring(record.controlId or "")
    parts[2] = tostring(record.pageKey or "")
    parts[3] = tostring(record.kind or "")
    parts[4] = tostring(record.label or "")
    parts[5] = tostring(record.identityLabel or "")
    parts[6] = tostring(record.controlPath or "")
    parts[7] = tostring(record.settingKey or "")
    parts[8] = tostring(record.actionKey or "")
    parts[9] = tostring(record.navigationKey or "")
    parts[10] = tostring(record.help or "")
    parts[11] = tostring(record.classification or "")
    parts[12] = tostring(record.command or "")
    -- Two empty lists join to the bare separator; skip both concats for them.
    if #settingKeys == 0 and #settingKeyPatterns == 0 then
        parts[13] = "\029"
    else
        parts[13] = table.concat(settingKeys, "\030") .. "\029" .. table.concat(settingKeyPatterns, "\030")
    end
    parts[14] = record.searchIndexed and "1" or "0"
    return table.concat(parts, "\031", 1, 14)
end

local function RemoveRecord(record)
    if type(record) ~= "table" then return end
    if STATE.byId[record.controlId] == record then STATE.byId[record.controlId] = nil end
    local page = STATE.byPage[record.pageKey]
    if page then
        page[record.controlId] = nil
        if next(page) == nil then STATE.byPage[record.pageKey] = nil end
    end
    if record.widget and STATE.byWidget[record.widget] == record then STATE.byWidget[record.widget] = nil end
end

local function IndexRecord(record)
    STATE.byId[record.controlId] = record
    STATE.byPage[record.pageKey] = STATE.byPage[record.pageKey] or {}
    STATE.byPage[record.pageKey][record.controlId] = true
    if record.widget then STATE.byWidget[record.widget] = record end
end

local function AllocateCollisionId(baseId, seed, widget)
    local suffixSeed = table.concat({ seed or baseId, WidgetStructureHint(widget) }, "\031")
    local candidate = baseId .. "~" .. StableHash(suffixSeed)
    local serial = 1
    while STATE.byId[candidate] and STATE.byId[candidate].widget ~= widget do
        serial = serial + 1
        candidate = baseId .. "~" .. StableHash(suffixSeed .. "\031" .. tostring(serial))
    end
    return candidate
end

local function PromoteExplicitId(record, explicitId)
    if not record or not explicitId or record.controlId == explicitId then return record and record.controlId end
    local oldId = record.controlId
    local occupied = STATE.byId[explicitId]
    RemoveRecord(record)
    if occupied and occupied.virtual == true and record.virtual ~= true then
        RemoveRecord(occupied)
        occupied = nil
        STATE.revision = STATE.revision + 1
    end
    if occupied and occupied.widget ~= record.widget then
        occupied.collision = true
        occupied.identityStable = false
        occupied.collisionGroup = explicitId
        record.controlId = AllocateCollisionId(explicitId, explicitId, record.widget)
        record.idSource = "explicit_collision"
        record.idIdentityBasis = "explicit_collision"
        record.collision = true
        record.collisionGroup = explicitId
        record.identityStable = false
    else
        record.controlId = explicitId
        record.idSource = "explicit"
        record.identityStable = true
        record.idIdentityBasis = "explicit"
        record.identityScope = "explicit"
    end
    record.previousControlId = oldId
    IndexRecord(record)
    if record.widget then record.widget._msuf2RuntimeControlId = record.controlId end
    STATE.revision = STATE.revision + 1
    return record.controlId
end

function M.DeclareExactSearchPreparation(widget, meta)
    if not meta.prepareExactSearchTarget then return end
    widget._msuf2ExactTargetKinds = { [meta.searchPrepareKind] = true }
    -- searchPrepareSettingKey names the one setting the prepared view edits;
    -- without it the contract covers any setting of the control (true).
    widget._msuf2ExactTargetContracts = { [meta.searchPrepareKind] = {
        [meta.searchPrepareValue] = meta.searchPrepareSettingKey or true } }
    widget._msuf2PrepareExactSearchTarget = meta.prepareExactSearchTarget
end

--- Exact links into a control that edits one setting per selectable view (a
--- slot, an indicator, a scope): values maps each prepareValue to the setting
--- that view edits, and select(value) shows that view in place and answers
--- whether it is shown. Another kind's hook on the same control is kept.
function M.DeclareExactViewContract(widget, kind, values, select)
    if not (widget and kind and select and type(values) == "table" and next(values) ~= nil) then return widget end
    local previous = widget._msuf2PrepareExactSearchTarget
    widget._msuf2ExactTargetKinds = widget._msuf2ExactTargetKinds or {}
    widget._msuf2ExactTargetKinds[kind] = true
    widget._msuf2ExactTargetContracts = widget._msuf2ExactTargetContracts or {}
    widget._msuf2ExactTargetContracts[kind] = values
    widget._msuf2PrepareExactSearchTarget = function(self, target)
        if type(target) ~= "table" or target.prepareKind ~= kind then
            return previous ~= nil and previous(self, target) or false
        end
        local value = tostring(target.prepareValue or "")
        local settingKey = values[value]
        if not settingKey or tostring(target.settingKey or "") ~= settingKey then return false end
        return select(value) == true
    end
    return widget
end

function Catalog.Register(widget, meta, registrationSource)
    if not widget or type(meta) ~= "table" then return nil, "widget and metadata are required" end
    if widget._msuf2ControlPartOf ~= nil then return nil, "component controls are owned by their logical parent" end

    local command = type(meta.command) == "table" and meta.command or nil
    local pageKey = CleanText(meta.pageKey or (command and command.ctxKey) or M.PageKeyForWidget(widget) or M.activeKey)
    if pageKey == "" then pageKey = "unknown" end
    local kind = NormalizeToken(meta.kind or WidgetKind(widget))
    if kind == "" then kind = "control" end
    local label = CleanText(meta.label or meta.title or meta.text or widget._msuf2SearchText or widget._msuf2SearchTitle)
    local identity, identityBasis = SemanticIdentity(meta, command, widget, label)
    local explicitId, invalidExplicitId = ExplicitId(meta, command, widget)

    local record = STATE.byWidget[widget]
    if record and record.pageKey ~= pageKey then
        RemoveRecord(record)
        record = nil
    end

    if record and explicitId and record.controlId ~= explicitId then PromoteExplicitId(record, explicitId) end
    local revisionBefore = record and (record._revisionKey or RevisionKey(record)) or nil

    if not record then
        -- Valid explicit IDs never use the fallback ID, so skip its three Slug
        -- passes and the StableHash for the common declared-controlId case.
        -- AllocateCollisionId falls back to baseId when seed is nil.
        local fallbackId, seed
        if not explicitId then fallbackId, seed = FallbackId(pageKey, kind, identity, command) end
        local requestedId = explicitId or fallbackId
        local idSource = explicitId and "explicit" or (invalidExplicitId and "fallback_invalid_explicit" or "fallback")
        local occupied = STATE.byId[requestedId]
        -- A virtual record is a compact command contract for a real control
        -- whose frame is built only after opening a disclosure/page.  Once the
        -- real widget exists it owns the same semantic ID; replace the token
        -- instead of reporting a false collision or retaining both records.
        if occupied and occupied.virtual == true and meta.virtual ~= true then
            RemoveRecord(occupied)
            occupied = nil
            STATE.revision = STATE.revision + 1
        end
        local collision = occupied and occupied.widget ~= widget
        local controlId = requestedId
        if collision then
            occupied.collision = true
            occupied.identityStable = false
            controlId = AllocateCollisionId(requestedId, seed, widget)
            idSource = explicitId and "explicit_collision" or "collision"
        end

        record = {
            schemaVersion = Catalog.SCHEMA_VERSION,
            controlId = controlId,
            pageKey = pageKey,
            kind = kind,
            label = label,
            identityLabel = identity,
            identityBasis = identityBasis,
            idIdentityBasis = explicitId and "explicit" or identityBasis,
            identityScope = explicitId and "explicit"
                or (STABLE_IDENTITY_BASIS[identityBasis] and "semantic")
                or (identityBasis == "display_label" and "locale_runtime" or "source_runtime"),
            identityStable = explicitId ~= nil or STABLE_IDENTITY_BASIS[identityBasis] == true,
            idSource = idSource,
            collision = collision and true or false,
            virtual = meta.virtual == true,
            widget = widget,
            -- Size the record for the fields every registration assigns below,
            -- so it is allocated once instead of growing through a rehash. Each
            -- false is overwritten before anything reads it (the code below
            -- treats false like the nil it replaces).
            searchIndexed = false, identityKey = false, controlPath = false, settingKey = false,
            searchSettingKeys = false, searchSettingKeyPatterns = false, actionKey = false,
            navigationKey = false, help = false, classification = false, classificationSource = false,
            _revisionKey = false,
        }
        if collision then
            occupied.collisionGroup = requestedId
            record.collisionGroup = requestedId
            record.identityStable = false
        end
        IndexRecord(record)
    end

    record.pageKey = pageKey
    record.searchIndexed = meta.searchIndexed == true
    record.kind = kind
    if label ~= "" then record.label = label end
    if identity ~= "" and (record.identityBasis == "missing" or identityBasis ~= "display_label") then
        record.identityLabel = identity
        record.identityBasis = identityBasis
    end
    if command then record.command = command end
    -- Record fields always hold CleanText output from an earlier pass, so an
    -- unchanged field skips the re-clean; only newly declared sources pay it.
    local declaredValue = meta.identityKey
    record.identityKey = declaredValue and CleanText(declaredValue) or record.identityKey or ""
    declaredValue = meta.controlPath
    record.controlPath = declaredValue and CleanText(declaredValue) or record.controlPath or ""
    declaredValue = meta.settingKey or (record.command and record.command.settingKey)
    record.settingKey = declaredValue and CleanText(declaredValue) or record.settingKey or ""
    local declaredSearchSettingKeys = meta.searchSettingKeys or (command and command.searchSettingKeys)
    local declaredSearchSettingKeyPatterns = meta.searchSettingKeyPatterns or (command and command.searchSettingKeyPatterns)
    if declaredSearchSettingKeys ~= nil then
        record.searchSettingKeys = NormalizeSearchSettingAliases(declaredSearchSettingKeys, false)
    else
        record.searchSettingKeys = record.searchSettingKeys or {}
    end
    if declaredSearchSettingKeyPatterns ~= nil then
        record.searchSettingKeyPatterns = NormalizeSearchSettingAliases(declaredSearchSettingKeyPatterns, true)
    else
        record.searchSettingKeyPatterns = record.searchSettingKeyPatterns or {}
    end
    declaredValue = meta.actionKey or (record.command and record.command.actionKey)
    record.actionKey = declaredValue and CleanText(declaredValue) or record.actionKey or ""
    declaredValue = meta.navigationKey or (record.command and record.command.navigationKey)
    record.navigationKey = declaredValue and CleanText(declaredValue) or record.navigationKey or ""
    declaredValue = meta.help or meta.description
    record.help = declaredValue and CleanText(declaredValue) or record.help or ""
    record.virtual = meta.virtual == true

    local declaredClassification = meta.classification or meta.controlType
    if CLASSIFICATION[declaredClassification] then
        record.declaredClassification = declaredClassification
    elseif meta.ephemeral == true then
        record.declaredClassification = "ephemeral"
    end
    local classification, reason = InferClassification(meta, record.command, kind)
    if record.declaredClassification and reason ~= "explicit" and reason ~= "explicit_ephemeral" then
        classification = record.declaredClassification
        reason = "explicit"
    end
    record.classification = classification
    record.classificationSource = reason

    widget._msuf2RuntimeControlId = record.controlId
    widget._msuf2RuntimeControlRecord = record
    local revisionAfter = RevisionKey(record)
    record._revisionKey = revisionAfter
    if revisionBefore ~= revisionAfter then
        STATE.revision = STATE.revision + 1
        if M.RefreshSearchControlIdentity then M.RefreshSearchControlIdentity(widget, record) end
    end
    return record.controlId, record
end

-- Search and the menu bindings register the actual controls in this catalog.
-- Bindings and Search share this registration entry point.
M.RegisterRuntimeControl = Catalog.Register

function Catalog.Get(controlId)
    return STATE.byId[controlId]
end

function Catalog.RestoreWidget(widget)
    local record = widget and widget._msuf2RuntimeControlRecord
    if record and not STATE.byWidget[widget] then return Catalog.Register(widget, record, "page-restore") end
end

function Catalog.GetForWidget(widget)
    return widget and STATE.byWidget[widget] or nil
end

function Catalog.ClearPage(pageKey)
    pageKey = CleanText(pageKey)
    if pageKey == "" then return 0 end
    -- Every page build clears first; only a page that marked components pays
    -- the walk over the components of all pages.
    if STATE.componentPages[pageKey] then
        for widget, component in pairs(STATE.components) do
            if component.pageKey == pageKey then
                STATE.components[widget] = nil
                widget._msuf2RuntimeControlComponent = nil
            end
        end
        STATE.componentPages[pageKey] = nil
    end
    local page = STATE.byPage[pageKey]
    if not page then return 0 end
    local records = {}
    for controlId in pairs(page) do
        local record = STATE.byId[controlId]
        if record then records[#records + 1] = record end
    end
    for i = 1, #records do RemoveRecord(records[i]) end
    if #records > 0 then STATE.revision = STATE.revision + 1 end
    return #records
end

local function SortedRecords()
    local out = {}
    for _, record in pairs(STATE.byId) do out[#out + 1] = record end
    table.sort(out, function(a, b) return tostring(a.controlId) < tostring(b.controlId) end)
    return out
end

local function PublicRecord(record)
    return {
        schemaVersion = record.schemaVersion, controlId = record.controlId, pageKey = record.pageKey,
        kind = record.kind, label = record.label, help = record.help, identityLabel = record.identityLabel,
        identityKey = record.identityKey, controlPath = record.controlPath ~= "" and record.controlPath or nil,
        classification = record.classification, searchIndexed = record.searchIndexed == true,
        idSource = record.idSource, identityBasis = record.identityBasis, identityScope = record.identityScope,
        identityStable = record.identityStable == true, collision = record.collision == true,
        settingKey = record.settingKey ~= "" and record.settingKey or nil,
        actionKey = record.actionKey ~= "" and record.actionKey or nil,
        navigationKey = record.navigationKey ~= "" and record.navigationKey or nil,
    }
end

function Catalog.GetRecords()
    local records = SortedRecords()
    local out = {}
    for i = 1, #records do out[i] = PublicRecord(records[i]) end
    return out
end

--- Resolves an explicit runtime control identity without label, text, geometry,
--- or setting-key inference. Changelog links use this path so a renamed label or
--- a second similarly named control can never redirect the click elsewhere.
function Catalog.ResolveExactTarget(pageKey, descriptor)
    pageKey = CleanText(pageKey)
    descriptor = type(descriptor) == "table" and descriptor or nil
    local controlId = descriptor and CleanText(descriptor.controlId) or ""
    if pageKey == "" or controlId == "" then return nil, nil, "missing_exact_identity" end

    local record = STATE.byId[controlId]
    if not record then return nil, nil, "control_not_built" end
    if CleanText(record.pageKey) ~= pageKey then return nil, nil, "page_mismatch" end
    local widget = record.widget
    if not widget then return nil, nil, "widget_missing" end

    local settingKey = CleanText(descriptor.settingKey)
    local recordSettingKey = CleanText(record.settingKey)
    if settingKey ~= "" and recordSettingKey ~= "" and recordSettingKey ~= settingKey then
        return nil, nil, "setting_mismatch"
    end

    local prepareKind = CleanText(descriptor.prepareKind)
    if prepareKind ~= "" then
        local supported = widget._msuf2ExactTargetKinds
        local contracts = widget._msuf2ExactTargetContracts
        local prepare = widget._msuf2PrepareExactSearchTarget
        if type(supported) ~= "table" or supported[prepareKind] ~= true or type(prepare) ~= "function" then
            return nil, nil, "unsupported_prepare_kind"
        end
        local prepareValue = CleanText(descriptor.prepareValue)
        local contract = type(contracts) == "table" and contracts[prepareKind] or nil
        local contractSettingKey = type(contract) == "table" and contract[prepareValue] or nil
        if prepareValue == "" or contractSettingKey == nil then return nil, nil, "unsupported_prepare_value" end
        if contractSettingKey ~= true and CleanText(contractSettingKey) ~= settingKey then
            return nil, nil, "prepare_setting_mismatch"
        end
        local prepared = prepare(widget, descriptor)
        if prepared ~= true then return nil, nil, "prepare_failed" end
    end

    return PublicRecord(record), widget, "control_id"
end

-- Late-bound exact-control lookup for Search.
-- This deliberately scans the existing catalog instead of maintaining a second
-- setting index: exact navigation is a cold user action and should not add idle
-- memory for thousands of controls.
function Catalog.FindBySettingKey(settingKey, pageKey)
    settingKey = CleanText(settingKey)
    pageKey = CleanText(pageKey)
    if settingKey == "" then return nil end

    -- Exact search focusing calls this resolver again during the immediate,
    -- zero-delay, and 0.05-second layout passes. Serve that one repeated key
    -- before scanning; the catalog revision invalidates the scalar cache.
    local cached = STATE.lastSettingDescriptorLookup
    if cached and cached.revision == STATE.revision and cached.settingKey == settingKey
        and cached.pageKey == pageKey
    then
        local record = cached.controlId and STATE.byId[cached.controlId] or nil
        if record then
            local public = PublicRecord(record)
            public.resolvedSettingKey = settingKey
            public.settingKeySource = cached.source
            return public, record.widget, cached.source
        end
        return nil, nil, cached.source
    end

    local best
    local pageRecords = pageKey ~= "" and STATE.byPage[pageKey] or nil
    for controlId in pairs(pageRecords or {}) do
        local record = STATE.byId[controlId]
        if record and record.settingKey == settingKey then
            best = record
            break
        end
    end
    -- With an explicit page hint, fail closed instead of focusing a visually
    -- similar widget on another page. Page-less callers may still search all.
    if not best and pageKey == "" then
        for _, record in pairs(STATE.byId) do
            if record.settingKey == settingKey then
                if not best
                    or (record.identityStable and not best.identityStable)
                    or (not record.collision and best.collision)
                then
                    best = record
                end
            end
        end
    end
    if best then
        STATE.lastSettingDescriptorLookup = {
            revision = STATE.revision,
            settingKey = settingKey,
            pageKey = pageKey,
            controlId = best.controlId,
            source = "explicit",
        }
        return PublicRecord(best), best.widget, "explicit"
    end

    local aliasBest, aliasAmbiguous
    local function ConsiderSearchAlias(record)
        if not record or record.classification ~= "setting" then return end
        local matched = false
        for i = 1, #(record.searchSettingKeys or {}) do
            if record.searchSettingKeys[i] == settingKey then
                matched = true
                break
            end
        end
        if not matched then
            for i = 1, #(record.searchSettingKeyPatterns or {}) do
                if string.match(settingKey, record.searchSettingKeyPatterns[i]) ~= nil then
                    matched = true
                    break
                end
            end
        end
        if matched then
            if not aliasBest then aliasBest = record elseif aliasBest ~= record then aliasAmbiguous = true end
        end
    end
    if pageRecords then
        for controlId in pairs(pageRecords) do ConsiderSearchAlias(STATE.byId[controlId]) end
    elseif pageKey == "" then
        for _, record in pairs(STATE.byId) do ConsiderSearchAlias(record) end
    end
    if aliasAmbiguous then return nil, nil, "ambiguous_search_setting" end
    if aliasBest then
        local public = PublicRecord(aliasBest)
        public.resolvedSettingKey = settingKey
        public.settingKeySource = "search_alias"
        return public, aliasBest.widget, "search_alias"
    end

    return nil, nil, "setting_not_registered"
end

function M.IsRuntimeControlRegisteredForWidget(widget, pageKey)
    local record = Catalog.GetForWidget(widget)
    if not record then return false end
    if pageKey == nil then return true end
    return record.pageKey == CleanText(pageKey)
end

-- Composite widgets (segments, scope selectors, slider +/- buttons) expose one
-- logical command on the parent. Their child buttons remain visible UI parts,
-- but are removed from the semantic catalog so they cannot become duplicate
-- unknown controls. Runtime reports retain an explicit component count.
function M.MarkRuntimeControlComponent(widget, owner)
    if not widget or not owner then return false end
    widget._msuf2ControlPartOf = owner
    local record = STATE.byWidget[widget]
    if record then
        RemoveRecord(record)
        STATE.revision = STATE.revision + 1
    end
    local componentPageKey = CleanText(M.PageKeyForWidget(widget) or M.activeKey or "unknown")
    STATE.components[widget] = {
        owner = owner,
        pageKey = componentPageKey,
    }
    STATE.componentPages[componentPageKey] = (STATE.componentPages[componentPageKey] or 0) + 1
    widget._msuf2RuntimeControlComponent = true
    if type(M.UnregisterSearchWidget) == "function" then M.UnregisterSearchWidget(widget) end
    return true
end

-- Registers a command-backed option without allocating a WoW frame. This is
-- intended for controls hidden behind conditional dashboard disclosures. The
-- token is stable and tiny; Catalog.Register transparently promotes the same
-- explicit ID to the real widget when that widget is eventually constructed.
function M.RegisterVirtualRuntimeControl(meta, registrationSource)
    if type(meta) ~= "table" then return nil, "metadata is required" end
    if not IsValidExplicitId(meta.controlId) then return nil, "virtual controls require a valid explicit controlId" end
    local controlId = meta.controlId
    local existing = STATE.byId[controlId]
    if existing and existing.virtual ~= true then return existing.controlId, existing end
    M._virtualRuntimeControlTokens = M._virtualRuntimeControlTokens or {}
    local token = M._virtualRuntimeControlTokens[controlId]
    if not token then
        token = { _msuf2VirtualRuntimeControl = true }
        M._virtualRuntimeControlTokens[controlId] = token
    end
    meta.virtual = true
    return Catalog.Register(token, meta, registrationSource or "virtual")
end

function M.RegisterMenuChromeControl(widget, path, label, classification, opts)
    if not widget then return nil end
    opts = type(opts) == "table" and opts or {}
    local token = Slug(path, "control", 72)
    local meta = {
        controlId = "menu2.menu-chrome." .. token,
        identityKey = "menu-chrome." .. token,
        controlPath = "menu-chrome/" .. token,
        pageKey = "menu_chrome",
        kind = opts.kind or (classification == "navigation" and "button" or "button"),
        label = label or path,
        classification = classification or "action",
        settingKey = opts.settingKey,
        actionKey = opts.actionKey,
        navigationKey = opts.navigationKey,
        historyMode = opts.historyMode,
        help = opts.help,
        command = opts.command,
    }
    -- Theme buttons refresh their visible label through RegisterSearchWidget.
    -- Preserve the semantic chrome metadata on the widget so that a later
    -- SetText cannot demote a stable navigation/action back to a raw button.
    local searchMeta = {}
    for key, value in pairs(type(widget._msuf2SearchMeta) == "table" and widget._msuf2SearchMeta or {}) do
        searchMeta[key] = value
    end
    for key, value in pairs(meta) do searchMeta[key] = value end
    searchMeta.label = label or path
    searchMeta.kind = meta.kind
    widget._msuf2SearchMeta = searchMeta
    local existing = STATE.byId[meta.controlId]
    if existing and existing.widget ~= widget then RemoveRecord(existing) end
    return Catalog.Register(widget, meta, "menu-chrome")
end

function M.ClearRuntimeControlsForPage(pageKey)
    return Catalog.ClearPage(pageKey)
end


-- Stable identity and registration contract shared by all page families.
-- Every control of a page normalizes the same page key and domain again (and
-- the unit pages share their paths), so string results are memoized.
local CONTROL_PATH_CACHE_LIMIT = 4096
local CONTROL_PATH_CACHE_MAX_SOURCE_LEN = 256
local controlPathCache, controlPathCacheCount = {}, 0
local function NormalizeControlPath(value)
    local cached = controlPathCache[value]
    if cached ~= nil then return cached end
    local source = tostring(value or "")
    local path = source:gsub("([%l%d])([%u])", "%1_%2"):lower()
    path = path:gsub("[^%w]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    if source == value and #source <= CONTROL_PATH_CACHE_MAX_SOURCE_LEN then
        if controlPathCacheCount >= CONTROL_PATH_CACHE_LIMIT then
            controlPathCache, controlPathCacheCount = {}, 0
        end
        controlPathCache[source] = path
        controlPathCacheCount = controlPathCacheCount + 1
    end
    return path
end
local function ControlMeta(pageKey, domain, semanticPath, classification, exact)
    local identity = NormalizeControlPath(pageKey) .. "." .. NormalizeControlPath(domain)
        .. "." .. NormalizeControlPath(semanticPath)
    local meta = {
        controlId = "menu2." .. identity,
        identityKey = identity,
        controlPath = identity:gsub("%.", "/"),
        classification = classification or "setting",
    }
    if type(exact) == "table" then
        for key, value in pairs(exact) do meta[key] = value end
    end
    return meta
end
local function RegisterControl(widget, meta, label, kind, values)
    if not (widget and type(meta) == "table" and type(M.RegisterSearchWidget) == "function") then return widget end
    local payload = {}
    for key, value in pairs(meta) do payload[key] = value end
    payload.label = label or payload.label
    payload.kind = kind or payload.kind
    payload.values = values or payload.values
    M.RegisterSearchWidget(widget, payload)
    return widget
end
M.ControlMeta = ControlMeta
M.RegisterControlMetadata = RegisterControl

M.NormalizeControlPath = NormalizeControlPath

local function PortableControlToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w_]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
    return token ~= "" and token or (fallback or "control")
end
M.PortableControlToken = PortableControlToken

local function AuraCatalogToken(value, fallback)
    local token = tostring(value or ""):lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    return token ~= "" and token or (fallback or "control")
end
M.AuraCatalogToken = AuraCatalogToken

local function GroupAuraSettingKeys(scope, suffix)
    suffix = tostring(suffix or "")
    if scope == "party" then return { "gf_party" .. suffix } end
    -- Raid and Mythic Raid share this Menu2 Aura editor and each write fans out
    -- to both backing scopes.  Retain both finite identities so exact guidance
    -- reaches the same reviewed dynamic control from either Registry setting.
    return { "gf_raid" .. suffix, "gf_mythicraid" .. suffix }
end
M.GroupAuraSettingKeys = GroupAuraSettingKeys
