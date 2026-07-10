--- Canonical runtime catalog for Menu2 controls.
---
--- The search registry knows where a visible control lives, while bindings know
--- whether it can read or change state.  This module joins both views without
--- making search or bindings depend on the Assistant implementation.
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
--- survive a future label rename.  GetCoverageReport exposes that distinction
--- and all unknowns.

local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Catalog = M.RuntimeControlCatalog or {}
M.RuntimeControlCatalog = Catalog

Catalog.SCHEMA_VERSION = 1

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
        issueSerial = 0,
        issues = {},
        collisionEvents = 0,
    }
    Catalog._state = STATE
else
    STATE.byId = type(STATE.byId) == "table" and STATE.byId or {}
    STATE.byPage = type(STATE.byPage) == "table" and STATE.byPage or {}
    STATE.byWidget = type(STATE.byWidget) == "table" and STATE.byWidget or setmetatable({}, { __mode = "k" })
    STATE.issues = type(STATE.issues) == "table" and STATE.issues or {}
    STATE.issueSerial = tonumber(STATE.issueSerial) or 0
    STATE.collisionEvents = tonumber(STATE.collisionEvents) or 0
end

local function CleanText(value)
    if value == nil then return "" end
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    local text = tostring(value)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function NormalizeToken(value)
    local text = CleanText(value):lower()
    text = text:gsub("[^%w]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
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

local function IsValidExplicitId(value)
    if type(value) ~= "string" or #value < 3 or #value > 160 then return false end
    if value:find("^%s") or value:find("%s$") then return false end
    return value:match("^[%w_%.:/%-]+$") ~= nil
end

local function IsValidRuntimeId(value)
    if type(value) ~= "string" or #value < 3 or #value > 180 then return false end
    return value:match("^[%w_%.:/%-%~]+$") ~= nil
end

local function SafeCall(method, object, ...)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, object, ...)
    if ok then return value end
    return nil
end

local function WidgetName(widget)
    if not widget then return "" end
    return CleanText(SafeCall(widget.GetName, widget))
end

local function WidgetKind(widget)
    if not widget then return "" end
    return CleanText(widget._msuf2ControlKind or SafeCall(widget.GetObjectType, widget))
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
        current = SafeCall(current.GetParent, current)
    end
    return table.concat(parts, "/")
end

local function AddIssue(code, message, record, extra)
    STATE.issueSerial = STATE.issueSerial + 1
    local issue = {
        serial = STATE.issueSerial,
        code = tostring(code or "catalog_issue"),
        message = tostring(message or "Runtime control catalog issue"),
        controlId = record and record.controlId or nil,
        pageKey = record and record.pageKey or (extra and extra.pageKey) or nil,
        kind = record and record.kind or (extra and extra.kind) or nil,
        label = record and record.label or (extra and extra.label) or nil,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            if issue[key] == nil and type(value) ~= "function" and type(value) ~= "table" then issue[key] = value end
        end
    end
    STATE.issues[#STATE.issues + 1] = issue
    -- Current issues are diagnostic state, not an unbounded event log.  Page
    -- cleanup removes its own issues; this cap protects never-cleared globals.
    if #STATE.issues > 512 then table.remove(STATE.issues, 1) end
    return issue
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
    if type(command.sourceFn) == "function" then
        local ok, value = pcall(command.sourceFn, label)
        if ok then return CleanText(value) end
    end
    return ""
end

local function SemanticIdentity(meta, command, widget, label)
    meta = type(meta) == "table" and meta or {}
    command = type(command) == "table" and command or {}

    local candidates = {
        { meta.identityKey, "identity_key" },
        { meta.controlPath, "control_path" },
        { meta.settingKey or command.settingKey, "setting_key" },
        { meta.actionKey or command.actionKey, "action_key" },
        { meta.navigationKey or command.navigationKey, "navigation_key" },
        { meta.identityLabel, "source_label" },
        { widget and widget._msuf2SearchText, "source_label" },
        { CommandSource(command, label), "command_source" },
        { label, "display_label" },
    }
    for i = 1, #candidates do
        local value = CleanText(candidates[i][1])
        if value ~= "" then return value, candidates[i][2] end
    end
    return "unidentified", "missing"
end

local function FallbackId(pageKey, kind, identity, command)
    local commandKind = type(command) == "table" and CleanText(command.kind) or ""
    local seed = table.concat({ pageKey, kind, identity, commandKind }, "\031")
    return table.concat({
        "menu2",
        Slug(pageKey, "unknown", 36),
        Slug(kind, "control", 24),
        Slug(identity, "unidentified", 42),
        StableHash(seed),
    }, "."), seed
end

local function CommandMetadata(command, label)
    if type(command) ~= "table" then return nil end
    local values = command.values
    if type(values) ~= "table" and type(command.getValues) == "function" then
        local ok, resolved = pcall(command.getValues)
        if ok and type(resolved) == "table" then values = resolved end
    end
    local count = 0
    if type(values) == "table" then
        for _ in pairs(values) do count = count + 1 end
    end
    return {
        kind = CleanText(command.kind),
        ctxKey = CleanText(command.ctxKey),
        source = CommandSource(command, label),
        settingKey = CleanText(command.settingKey),
        actionKey = CleanText(command.actionKey),
        navigationKey = CleanText(command.navigationKey),
        hasGet = type(command.get) == "function",
        hasSet = type(command.set) == "function",
        hasRefresh = type(command.refresh) == "function",
        hasCombatGuard = type(command.blockCombat) == "function",
        hasDynamicValues = type(command.getValues) == "function",
        valueCount = count,
        min = tonumber(command.min),
        max = tonumber(command.max),
        step = tonumber(command.step),
    }
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
        STATE.collisionEvents = STATE.collisionEvents + 1
        AddIssue("explicit_id_collision", "Two runtime controls declared the same explicit controlId.", record, {
            requestedId = explicitId,
            existingId = occupied.controlId,
        })
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
    return record.controlId
end

function Catalog.Register(widget, meta, registrationSource)
    if not widget or type(meta) ~= "table" then return nil, "widget and metadata are required" end

    local command = type(meta.command) == "table" and meta.command or nil
    local pageKey = CleanText(meta.pageKey or (command and command.ctxKey) or M._msuf2SearchBuildKey or M.activeKey)
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

    if not record then
        local fallbackId, seed = FallbackId(pageKey, kind, identity, command)
        local requestedId = explicitId or fallbackId
        local idSource = explicitId and "explicit" or (invalidExplicitId and "fallback_invalid_explicit" or "fallback")
        local occupied = STATE.byId[requestedId]
        local collision = occupied and occupied.widget ~= widget
        local controlId = requestedId
        if collision then
            occupied.collision = true
            occupied.identityStable = false
            controlId = AllocateCollisionId(requestedId, seed, widget)
            idSource = explicitId and "explicit_collision" or "collision"
            STATE.collisionEvents = STATE.collisionEvents + 1
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
            widget = widget,
            sources = {},
        }
        if collision then
            occupied.collisionGroup = requestedId
            record.collisionGroup = requestedId
            record.identityStable = false
            AddIssue(explicitId and "explicit_id_collision" or "fallback_id_collision",
                explicitId and "Two runtime controls declared the same explicit controlId." or "Two runtime controls produced the same deterministic fallback controlId.",
                record,
                { requestedId = requestedId, existingId = occupied.controlId })
        end
        if invalidExplicitId then
            record.invalidExplicitId = invalidExplicitId
            AddIssue("invalid_explicit_id", "The declared controlId was invalid; a deterministic fallback was used.", record, {
                requestedId = invalidExplicitId,
            })
        end
        IndexRecord(record)
    end

    if invalidExplicitId and record.invalidExplicitId ~= invalidExplicitId then
        record.invalidExplicitId = invalidExplicitId
        AddIssue("invalid_explicit_id", "The declared controlId was invalid; a deterministic fallback was used.", record, {
            requestedId = invalidExplicitId,
        })
    end

    record.pageKey = pageKey
    record.kind = kind
    if label ~= "" then record.label = label end
    if identity ~= "" and (record.identityBasis == "missing" or identityBasis ~= "display_label") then
        record.identityLabel = identity
        record.identityBasis = identityBasis
    end
    if command then record.command = command end
    record.commandMeta = CommandMetadata(record.command, record.label)
    record.identityKey = CleanText(meta.identityKey or record.identityKey)
    record.controlPath = CleanText(meta.controlPath or record.controlPath)
    record.settingKey = CleanText(meta.settingKey or (record.command and record.command.settingKey) or record.settingKey)
    record.actionKey = CleanText(meta.actionKey or (record.command and record.command.actionKey) or record.actionKey)
    record.navigationKey = CleanText(meta.navigationKey or (record.command and record.command.navigationKey) or record.navigationKey)
    record.help = CleanText(meta.help or meta.description or record.help)
    record.registrationCount = (tonumber(record.registrationCount) or 0) + 1
    registrationSource = Slug(registrationSource, "runtime", 36)
    record.sources[registrationSource] = true

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
    return record.controlId, record
end

function Catalog.Get(controlId)
    return STATE.byId[controlId]
end

function Catalog.GetForWidget(widget)
    return widget and STATE.byWidget[widget] or nil
end

function Catalog.ClearPage(pageKey)
    pageKey = CleanText(pageKey)
    if pageKey == "" then return 0 end
    local page = STATE.byPage[pageKey]
    if not page then return 0 end
    local records = {}
    for controlId in pairs(page) do
        local record = STATE.byId[controlId]
        if record then records[#records + 1] = record end
    end
    for i = 1, #records do RemoveRecord(records[i]) end
    local kept = {}
    for i = 1, #STATE.issues do
        if STATE.issues[i].pageKey ~= pageKey then kept[#kept + 1] = STATE.issues[i] end
    end
    STATE.issues = kept
    return #records
end

local function SortedRecords()
    local out = {}
    for _, record in pairs(STATE.byId) do out[#out + 1] = record end
    table.sort(out, function(a, b) return tostring(a.controlId) < tostring(b.controlId) end)
    return out
end

local function PublicRecord(record)
    local sources = {}
    for source in pairs(record.sources or {}) do sources[#sources + 1] = source end
    table.sort(sources)
    local command
    if type(record.commandMeta) == "table" then
        command = {}
        for key, value in pairs(record.commandMeta) do command[key] = value end
    end
    return {
        schemaVersion = record.schemaVersion,
        controlId = record.controlId,
        pageKey = record.pageKey,
        kind = record.kind,
        label = record.label,
        classification = record.classification,
        classificationSource = record.classificationSource,
        idSource = record.idSource,
        identityBasis = record.identityBasis,
        idIdentityBasis = record.idIdentityBasis,
        identityScope = record.identityScope,
        identityStable = record.identityStable and true or false,
        collision = record.collision and true or false,
        collisionGroup = record.collisionGroup,
        invalidExplicitId = record.invalidExplicitId,
        settingKey = record.settingKey ~= "" and record.settingKey or nil,
        actionKey = record.actionKey ~= "" and record.actionKey or nil,
        navigationKey = record.navigationKey ~= "" and record.navigationKey or nil,
        command = command,
        sources = sources,
    }
end

function Catalog.GetRecords()
    local records = SortedRecords()
    local out = {}
    for i = 1, #records do out[i] = PublicRecord(records[i]) end
    return out
end

function Catalog.ValidateRecord(record)
    local errors, warnings = {}, {}
    if type(record) ~= "table" then return false, { "record must be a table" }, warnings end
    if tonumber(record.schemaVersion) ~= Catalog.SCHEMA_VERSION then errors[#errors + 1] = "schemaVersion is missing or unsupported" end
    if not IsValidRuntimeId(record.controlId) then errors[#errors + 1] = "controlId is missing or invalid" end
    if CleanText(record.pageKey) == "" then errors[#errors + 1] = "pageKey is missing" end
    if CleanText(record.kind) == "" then errors[#errors + 1] = "kind is missing" end
    if not CLASSIFICATION[record.classification] then errors[#errors + 1] = "classification is invalid" end
    if not VALID_ID_SOURCES[record.idSource] then errors[#errors + 1] = "idSource is invalid" end
    if record.classification == "setting" then
        if not (record.commandMeta and record.commandMeta.hasGet and record.commandMeta.hasSet) and record.settingKey == "" then
            warnings[#warnings + 1] = "setting has no complete read/write command metadata"
        end
    elseif record.classification == "action" and not (record.commandMeta and record.commandMeta.hasSet) and record.actionKey == "" then
        warnings[#warnings + 1] = "action has no write command metadata"
    elseif record.classification == "navigation" and record.navigationKey == "" then
        warnings[#warnings + 1] = "navigation control has no navigationKey"
    elseif record.classification == "unknown" then
        warnings[#warnings + 1] = "control semantics are unknown"
    end
    if record.collision then warnings[#warnings + 1] = "controlId collision requires an explicit ID" end
    if not record.identityStable then warnings[#warnings + 1] = "identity is not stable across source changes" end
    return #errors == 0, errors, warnings
end

function Catalog.ValidateAll()
    local records = SortedRecords()
    local report = { valid = true, records = #records, errors = {}, warnings = {} }
    for i = 1, #records do
        local record = records[i]
        local valid, errors, warnings = Catalog.ValidateRecord(record)
        if not valid then report.valid = false end
        for j = 1, #errors do
            report.errors[#report.errors + 1] = { controlId = record.controlId, message = errors[j] }
        end
        for j = 1, #warnings do
            report.warnings[#report.warnings + 1] = { controlId = record.controlId, message = warnings[j] }
        end
    end
    return report
end

function Catalog.GetCoverageReport()
    local records = SortedRecords()
    local report = {
        schemaVersion = Catalog.SCHEMA_VERSION,
        total = #records,
        byClassification = { setting = 0, action = 0, navigation = 0, ephemeral = 0, unknown = 0 },
        byIdSource = {},
        byPage = {},
        deterministicIds = 0,
        explicitIds = 0,
        unstableIds = 0,
        collisions = 0,
        interactive = 0,
        knownInteractive = 0,
        interactiveCoveragePercent = 100,
        unknown = {},
        currentIssues = {},
        collisionEventsLifetime = STATE.collisionEvents,
    }

    for i = 1, #records do
        local record = records[i]
        local classification = CLASSIFICATION[record.classification] and record.classification or "unknown"
        report.byClassification[classification] = report.byClassification[classification] + 1
        report.byIdSource[record.idSource] = (report.byIdSource[record.idSource] or 0) + 1
        local page = report.byPage[record.pageKey]
        if not page then
            page = { total = 0, setting = 0, action = 0, navigation = 0, ephemeral = 0, unknown = 0 }
            report.byPage[record.pageKey] = page
        end
        page.total = page.total + 1
        page[classification] = page[classification] + 1
        if record.idSource == "explicit" then report.explicitIds = report.explicitIds + 1 end
        if record.idSource == "fallback" or record.idSource == "fallback_invalid_explicit" then
            report.deterministicIds = report.deterministicIds + 1
        end
        if not record.identityStable then report.unstableIds = report.unstableIds + 1 end
        if record.collision then report.collisions = report.collisions + 1 end
        if classification ~= "ephemeral" then
            report.interactive = report.interactive + 1
            if classification ~= "unknown" then report.knownInteractive = report.knownInteractive + 1 end
        end
        if classification == "unknown" then
            local item = PublicRecord(record)
            item.reason = record.classificationSource
            report.unknown[#report.unknown + 1] = item
        end
    end

    if report.interactive > 0 then
        report.interactiveCoveragePercent = math.floor((report.knownInteractive * 10000 / report.interactive) + 0.5) / 100
    end
    report.catalogComplete = report.byClassification.unknown == 0 and report.collisions == 0 and report.unstableIds == 0

    for i = 1, #STATE.issues do
        local issue = STATE.issues[i]
        if (not issue.controlId) or STATE.byId[issue.controlId] then
            local copy = {}
            for key, value in pairs(issue) do copy[key] = value end
            report.currentIssues[#report.currentIssues + 1] = copy
        end
    end
    return report
end

-- Menu2-level API: callers do not need to know the catalog object name.
function M.RegisterRuntimeControl(widget, meta, registrationSource)
    return Catalog.Register(widget, meta, registrationSource)
end

function M.ClearRuntimeControlsForPage(pageKey)
    return Catalog.ClearPage(pageKey)
end

function M.GetRuntimeControlCoverageReport()
    return Catalog.GetCoverageReport()
end
