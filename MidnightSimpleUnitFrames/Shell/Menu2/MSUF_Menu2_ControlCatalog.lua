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

-- Shell controls are not built by the page/widget factories, so an omitted raw
-- Button would otherwise be invisible to a percentage calculated only from
-- already-registered records.  Keep the executable shell surface and the
-- deliberately non-command UI mechanics in one small fail-closed contract.
-- Assistant V2 validates this table during coverage and runtime acceptance.
M.REQUIRED_SHELL_CONTRACT = {
    schemaVersion = 1,
    minimumControls = 6,
    minimumDispositions = 14,
    controls = {
        ["menu2.menu-chrome.window-close"] = { classification = "action", kind = "button" },
        ["menu2.menu-chrome.window-minimize"] = { classification = "action", kind = "button" },
        ["menu2.menu-chrome.window-maximize"] = { classification = "action", kind = "button" },
        ["menu2.menu-chrome.window-restore"] = { classification = "action", kind = "button" },
        ["menu2.menu-chrome.search-clear"] = { classification = "action", kind = "button" },
        ["menu2.menu-chrome.search-intro-dismiss"] = { classification = "action", kind = "button" },
    },
    dispositions = {
        ["window.drag"] = "direct-manipulation",
        ["window.resize"] = "direct-manipulation",
        ["minimized-window.drag"] = "direct-manipulation",
        ["scroll.mechanics"] = "navigation-mechanic",
        ["search.input"] = "self-referential-input",
        ["assistant.input"] = "self-referential-input",
        ["assistant.run"] = "self-referential-submit",
        ["dropdown.choice-rows"] = "logical-dropdown-values",
        ["dropdown.scrollbar"] = "navigation-mechanic",
        ["toggle.label-proxy"] = "logical-toggle-component",
        ["slider.value-input"] = "logical-slider-component",
        ["slider.step-buttons"] = "logical-slider-component",
        ["segment.buttons"] = "logical-segment-component",
        ["scope-selector.buttons"] = "logical-selector-component",
    },
}

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
        issueSerial = 0,
        issues = {},
        collisionEvents = 0,
        revision = 0,
    }
    Catalog._state = STATE
else
    STATE.byId = type(STATE.byId) == "table" and STATE.byId or {}
    STATE.byPage = type(STATE.byPage) == "table" and STATE.byPage or {}
    STATE.byWidget = type(STATE.byWidget) == "table" and STATE.byWidget or setmetatable({}, { __mode = "k" })
    STATE.components = type(STATE.components) == "table" and STATE.components or setmetatable({}, { __mode = "k" })
    STATE.issues = type(STATE.issues) == "table" and STATE.issues or {}
    STATE.issueSerial = tonumber(STATE.issueSerial) or 0
    STATE.collisionEvents = tonumber(STATE.collisionEvents) or 0
    STATE.revision = tonumber(STATE.revision) or 0
end

local function CleanText(value)
    if value == nil then return "" end
    if type(value) ~= "string" and type(value) ~= "number" then return "" end
    local text = tostring(value)
    if text:find("|", 1, true) then
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    if text:find("^%s") then text = text:gsub("^%s+", "") end
    if text:find("%s$") then text = text:gsub("%s+$", "") end
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
    local metadata = {
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
        hasValues = type(command.values) == "table" or type(command.getValues) == "function",
        hasRuntimeValidator = type(command.canExecute) == "function",
        valueCount = count,
        min = tonumber(command.min),
        max = tonumber(command.max),
        step = tonumber(command.step),
    }
    local interaction = CleanText(command.interaction)
    local previewSurface = CleanText(command.previewSurface)
    local previewHandleKey = CleanText(command.previewHandleKey)
    local previewUnitKey = CleanText(command.previewUnitKey)
    local previewScope = CleanText(command.previewScope)
    if interaction ~= "" then metadata.interaction = interaction end
    if previewSurface ~= "" then metadata.previewSurface = previewSurface end
    if previewHandleKey ~= "" then metadata.previewHandleKey = previewHandleKey end
    if previewUnitKey ~= "" then metadata.previewUnitKey = previewUnitKey end
    if previewScope ~= "" then metadata.previewScope = previewScope end
    return metadata
end

local SETTING_COMMAND_KINDS = {
    toggle = true, slider = true, dropdown = true, segment = true,
    textinput = true, color = true,
}
local function CapabilityIssue(record)
    if type(record) ~= "table" then return nil end
    local meta = record.commandMeta
    local transient = record.classification == "ephemeral" and type(meta) == "table" and meta.hasSet == true
    if record.classification ~= "setting" and record.classification ~= "action" and not transient then return nil end
    if type(meta) ~= "table" or meta.hasSet ~= true then return "missing executable write command" end
    local settingLike = record.classification == "setting" or transient and meta.hasGet == true
    if settingLike and meta.hasGet ~= true then return "missing readable setting command" end
    local kind = CleanText(meta.kind ~= "" and meta.kind or record.kind):lower()
    if settingLike and not SETTING_COMMAND_KINDS[kind] then
        return "unsupported setting command kind: " .. (kind ~= "" and kind or "<missing>")
    end
    if kind == "slider" then
        if meta.min == nil or meta.max == nil or meta.step == nil then return "slider is missing min/max/step" end
        if meta.min > meta.max then return "slider min exceeds max" end
        if meta.step <= 0 then return "slider step must be positive" end
    elseif kind == "dropdown" or kind == "segment" then
        if meta.hasValues ~= true then return kind .. " is missing a values provider" end
    end
    return nil
end
local function RuntimeCapabilityIssue(record)
    local issue = CapabilityIssue(record)
    if issue then return issue end
    local command, meta = record and record.command, record and record.commandMeta
    if type(command) ~= "table" or type(meta) ~= "table" then return nil end
    if meta.hasGet then
        local ok = pcall(command.get)
        if not ok then return "read command raised an error" end
    end
    local kind = CleanText(meta.kind ~= "" and meta.kind or record.kind):lower()
    if kind == "dropdown" or kind == "segment" then
        local values = command.values
        if type(values) ~= "table" and type(command.getValues) == "function" then
            local ok, resolved = pcall(command.getValues)
            if not ok then return "values provider raised an error" end
            values = resolved
        end
        if type(values) ~= "table" then return kind .. " values provider did not return a table" end
    end
    return nil
end

-- Some menu controls are actions rather than DB bindings (profile lifecycle,
-- import/export, preview tools, and dashboard buttons).  They still need an
-- executable catalog command, but duplicating those actions in the Assistant
-- would create a second registry and keep page-specific state alive.  Build a
-- tiny late-bound adapter only for such controls.  The closures deliberately
-- resolve the widget's current callbacks at execution time because several
-- pages register search metadata before installing their OnClick/on-change
-- handlers.
local function RuntimeWidgetValues(widget)
    local values = widget and widget.values
    if type(values) == "function" then
        local ok, resolved = pcall(values)
        values = ok and resolved or nil
    end
    return type(values) == "table" and values or nil
end

local function RuntimeWidgetGet(widget, kind)
    if not widget then return nil end
    if kind == "toggle" and type(widget.GetChecked) == "function" then return widget:GetChecked() and true or false end
    if (kind == "dropdown" or kind == "slider" or kind == "segment") and type(widget.GetValue) == "function" then
        return widget:GetValue()
    end
    if kind == "textinput" and type(widget.GetText) == "function" then return widget:GetText() end
    return nil
end

local function RuntimeWidgetClick(widget)
    local handler = widget and type(widget.GetScript) == "function" and widget:GetScript("OnClick") or nil
    if type(handler) == "function" then return handler(widget, "LeftButton", false) end
    -- Some clickable option tiles are Frames rather than Buttons and expose
    -- their semantic left-click through OnMouseUp.
    handler = widget and type(widget.GetScript) == "function" and widget:GetScript("OnMouseUp") or nil
    if type(handler) == "function" then return handler(widget, "LeftButton") end
    error("runtime control has no click handler", 2)
end

local function RuntimeWidgetCanExecute(widget, kind)
    if not widget then return false end
    if kind == "dropdown" then return type(widget._msuf2OnValueChanged) == "function" end
    if kind == "textinput" then return type(widget._msuf2OnCommit) == "function" end
    if kind == "slider" or kind == "segment" then return type(widget.SetValue) == "function" end
    if kind == "toggle" then
        if type(widget.SetChecked) ~= "function" or type(widget.GetScript) ~= "function" then return false end
        return type(widget:GetScript("OnClick")) == "function"
    end
    if type(widget.GetScript) ~= "function" then return false end
    return type(widget:GetScript("OnClick")) == "function" or type(widget:GetScript("OnMouseUp")) == "function"
end

local function RuntimeWidgetSet(widget, kind, value)
    if not widget then error("runtime control widget is unavailable", 2) end
    if kind == "button" then return RuntimeWidgetClick(widget) end
    if kind == "toggle" then
        local current = type(widget.GetChecked) == "function" and (widget:GetChecked() and true or false) or nil
        local desired = value
        if desired == nil then desired = current == nil and true or not current else desired = desired and true or false end
        if current ~= nil and current == desired then return false end
        local handler = type(widget.GetScript) == "function" and widget:GetScript("OnClick") or nil
        if type(handler) == "function" and type(widget.SetChecked) == "function" then
            -- WoW changes a CheckButton's checked state before OnClick. Direct
            -- Assistant invocation must emulate that ordering for raw toggles.
            widget:SetChecked(desired)
            local result = handler(widget, "LeftButton", false)
            local actual = type(widget.GetChecked) == "function" and (widget:GetChecked() and true or false) or desired
            return actual == desired and (result == nil and true or result) or false
        end
        error("runtime toggle has no setter", 2)
    end
    if kind == "dropdown" then
        if type(widget._msuf2OnValueChanged) ~= "function" then error("runtime dropdown has no value handler", 2) end
        widget:SetValue(value)
        return widget._msuf2OnValueChanged(value)
    end
    if kind == "textinput" then
        if type(widget.SetText) == "function" then widget:SetText(tostring(value or "")) end
        if type(widget._msuf2OnCommit) ~= "function" then error("runtime text input has no commit handler", 2) end
        return widget._msuf2OnCommit(tostring(value or ""))
    end
    if kind == "slider" or kind == "segment" then
        if type(widget.SetValue) ~= "function" then error("runtime value control has no setter", 2) end
        return widget:SetValue(value)
    end
    return RuntimeWidgetClick(widget)
end

function M.BuildRuntimeWidgetCommand(widget, meta, kind)
    meta = type(meta) == "table" and meta or {}
    kind = CleanText(kind or meta.kind or (widget and widget._msuf2ControlKind)):lower()
    local classification = meta.classification or meta.controlType
    -- Automatic widget construction also feeds search, but has no semantic
    -- classification yet.  Wait for the explicit page registration so bound
    -- controls never allocate throwaway adapter closures.
    local readable = kind == "toggle" or kind == "dropdown" or kind == "slider" or kind == "segment" or kind == "textinput"
    local transientControl = classification == "ephemeral" and (readable or kind == "button")
    if classification ~= "setting" and classification ~= "action" and not transientControl then return nil end
    local writable = readable or kind == "button" or classification == "action"
    if not writable then return nil end
    local command = {
        kind = kind ~= "" and kind or (classification == "action" and "button" or "control"),
        source = meta.controlPath or meta.identityKey,
        settingKey = meta.settingKey,
        actionKey = meta.actionKey,
        confirmRequired = meta.confirmRequired == true,
        historyMode = meta.historyMode or (classification == "ephemeral" and "none" or nil),
        blockCombat = type(meta.blockCombat) == "function" and meta.blockCombat or nil,
    }
    if readable then command.get = function() return RuntimeWidgetGet(widget, kind) end end
    command.set = function(value) return RuntimeWidgetSet(widget, kind, value) end
    command.canExecute = function() return RuntimeWidgetCanExecute(widget, kind) end
    if kind == "dropdown" or kind == "segment" then command.getValues = function() return RuntimeWidgetValues(widget) end end
    if kind == "slider" and widget then
        if type(widget.GetMinMaxValues) == "function" then command.min, command.max = widget:GetMinMaxValues() end
        command.step = tonumber(widget._msuf2Step)
    end
    return command
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

local function RevisionKey(record)
    if type(record) ~= "table" then return nil end
    return table.concat({
        tostring(record.controlId or ""), tostring(record.pageKey or ""), tostring(record.kind or ""),
        tostring(record.label or ""), tostring(record.identityLabel or ""), tostring(record.controlPath or ""),
        tostring(record.settingKey or ""), tostring(record.actionKey or ""), tostring(record.navigationKey or ""),
        tostring(record.help or ""), tostring(record.classification or ""),
        record.confirmRequired and "1" or "0", tostring(record.command or ""),
    }, "\031")
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
    STATE.revision = STATE.revision + 1
    return record.controlId
end

function Catalog.Register(widget, meta, registrationSource)
    if not widget or type(meta) ~= "table" then return nil, "widget and metadata are required" end
    if widget._msuf2ControlPartOf ~= nil then return nil, "component controls are owned by their logical parent" end

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
    local revisionBefore = record and (record._revisionKey or RevisionKey(record)) or nil

    if not record then
        local fallbackId, seed = FallbackId(pageKey, kind, identity, command)
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
            virtual = meta.virtual == true,
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
    record.virtual = meta.virtual == true
    record.confirmRequired = meta.confirmRequired == true or (record.command and record.command.confirmRequired == true) or record.confirmRequired == true
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
    local revisionAfter = RevisionKey(record)
    record._revisionKey = revisionAfter
    if revisionBefore ~= revisionAfter then STATE.revision = STATE.revision + 1 end
    return record.controlId, record
end

function Catalog.Get(controlId)
    return STATE.byId[controlId]
end

function Catalog.GetForWidget(widget)
    return widget and STATE.byWidget[widget] or nil
end

function Catalog.GetRevision()
    return STATE.revision
end

function Catalog.ClearPage(pageKey)
    pageKey = CleanText(pageKey)
    if pageKey == "" then return 0 end
    for widget, component in pairs(STATE.components) do
        if component.pageKey == pageKey then
            STATE.components[widget] = nil
            widget._msuf2RuntimeControlComponent = nil
        end
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

-- A small reviewed bridge for controls whose stable UI path and SavedVariables
-- key use intentionally different vocabulary.  Values are compact canonical
-- setting-key suffixes (the scope before the first dot is omitted).  This is
-- not a fuzzy alias list: each entry names one concrete runtime control path,
-- and the descriptor resolver still requires page and widget-kind agreement.
--
-- Class Resources is the densest example because its table-driven page keeps
-- terse layout paths ("layout/x", "style/text/font") while the public setting
-- contract uses long names ("classPowerOffsetX", "classPowerFontSize").
local REVIEWED_CONTROL_PATH_SETTING_COMPACTS = {
    ["classpower/advanced/layout/enabled"] = "showclasspower",
    ["classpower/advanced/layout/shape"] = "classpowershape",
    ["classpower/advanced/layout/height"] = "classpowerheight",
    ["classpower/advanced/layout/width/mode"] = "classpowerwidthmode",
    ["classpower/advanced/layout/width"] = "classpowerwidth",
    ["classpower/advanced/layout/x"] = "classpoweroffsetx",
    ["classpower/advanced/layout/y"] = "classpoweroffsety",
    ["classpower/advanced/layout/level"] = "classpowerframeleveloffset",
    ["classpower/advanced/layout/shape/alignment"] = "classpowershapealign",
    ["classpower/advanced/behavior/anchor"] = "classpoweranchortocooldown",
    ["classpower/advanced/behavior/charged"] = "showchargedcombopoints",
    ["classpower/advanced/behavior/text"] = "classpowershowtext",
    ["classpower/advanced/behavior/rune"] = "runeshowtime",
    ["classpower/advanced/behavior/reverse"] = "classpowerfillreverse",
    ["classpower/advanced/behavior/ele"] = "showelemaelstrom",
    ["classpower/advanced/behavior/ebon"] = "showebonmight",
    ["classpower/advanced/behavior/shadow"] = "showshadowmana",
    ["classpower/advanced/behavior/prediction"] = "classpowershowprediction",
    ["classpower/advanced/behavior/smooth"] = "classpowersmoothfill",
    ["classpower/advanced/style/resources/color"] = "classpowercolorbytype",
    ["classpower/advanced/style/resources/combo/color"] = "classpowercombopointcolormode",
    ["classpower/advanced/style/resources/fg/tex"] = "classpowertexture",
    ["classpower/advanced/style/resources/bg/tex"] = "classpowerbgtexture",
    ["classpower/advanced/style/text/font"] = "classpowerfontsize",
    ["classpower/advanced/style/text/text/x"] = "classpowertextoffsetx",
    ["classpower/advanced/style/text/text/y"] = "classpowertextoffsety",
    ["classpower/advanced/style/opacity/bg"] = "classpowerbgalpha",
    ["classpower/advanced/style/opacity/filled"] = "classpowerfilledalpha",
    ["classpower/advanced/style/opacity/empty"] = "classpoweremptyalpha",
    ["classpower/advanced/style/pips/separator"] = "classpowertickwidth",
    ["classpower/advanced/style/pips/outline"] = "classpoweroutline",
    ["classpower/advanced/style/pips/gap"] = "classpowergap",
    ["classpower/advanced/visibility/out/of/combat"] = "classpowerhideooc",
    ["classpower/advanced/visibility/when/full"] = "classpowerhidewhenfull",
    ["classpower/advanced/visibility/when/empty"] = "classpowerhidewhenempty",

    ["classpower/advanced/player/hp/enabled"] = "playerhpbarenabled",
    ["classpower/advanced/player/hp/layout/anchor"] = "playerhpbaranchor",
    ["classpower/advanced/player/hp/layout/width/mode"] = "playerhpbarwidthmode",
    ["classpower/advanced/player/hp/layout/manual/width"] = "playerhpbarwidth",
    ["classpower/advanced/player/hp/layout/shape"] = "playerhpbarshape",
    ["classpower/advanced/player/hp/layout/orb/size"] = "playerhpbarorbsize",
    ["classpower/advanced/player/hp/layout/height"] = "playerhpbarheight",
    ["classpower/advanced/player/hp/layout/smooth"] = "playerhpbarsmoothfill",
    ["classpower/advanced/player/hp/layout/gap"] = "playerhpbargap",
    ["classpower/advanced/player/hp/layout/x"] = "playerhpbaroffsetx",
    ["classpower/advanced/player/hp/layout/y"] = "playerhpbaroffsety",
    ["classpower/advanced/player/hp/layout/layer"] = "playerhpbarframeleveloffset",
    ["classpower/advanced/player/hp/textures/color"] = "playerhpbarcolormode",
    ["classpower/advanced/player/hp/textures/fg"] = "playerhpbartexture",
    ["classpower/advanced/player/hp/textures/bg"] = "playerhpbarbgtexture",
    ["classpower/advanced/player/hp/textures/bg/alpha"] = "playerhpbarbgalpha",
    ["classpower/advanced/player/hp/textures/outline"] = "playerhpbaroutline",
    ["classpower/advanced/player/hp/text/enabled"] = "playerhpbartextenabled",
    ["classpower/advanced/player/hp/text/use/player/text"] = "playerhpbaruseplayertext",
    ["classpower/advanced/player/hp/text/right"] = "playerhpbartextright",
    ["classpower/advanced/player/hp/text/left"] = "playerhpbartextleft",
    ["classpower/advanced/player/hp/text/center"] = "playerhpbartextcenter",
    ["classpower/advanced/player/hp/text/sep"] = "playerhpbartextseparator",
    ["classpower/advanced/player/hp/text/reverse"] = "playerhpbartextreverse",
    ["classpower/advanced/player/hp/text/size"] = "playerhpbartextsize",
    ["classpower/advanced/player/hp/text/x"] = "playerhpbartextoffsetx",
    ["classpower/advanced/player/hp/text/y"] = "playerhpbartextoffsety",
    ["classpower/advanced/player/hp/text/player/hpbar/text/right/hide/percent/symbol"] = {
        "playerhpbartextrighthidepercentsymbol", "playerhpbartextrightpercentsymbol",
    },
    ["classpower/advanced/player/hp/text/player/hpbar/text/left/hide/percent/symbol"] = {
        "playerhpbartextlefthidepercentsymbol", "playerhpbartextleftpercentsymbol",
    },
    ["classpower/advanced/player/hp/text/player/hpbar/text/center/hide/percent/symbol"] = {
        "playerhpbartextcenterhidepercentsymbol", "playerhpbartextcenterpercentsymbol",
    },

    ["classpower/advanced/detached/power/layout/mode"] = "detachedpowerbarwidthmode",
    ["classpower/advanced/detached/power/textures/fg"] = "detachedpowerbartexture",
    ["classpower/advanced/detached/power/textures/bg"] = "detachedpowerbarbgtexture",
    ["classpower/advanced/detached/power/textures/outline"] = "detachedpowerbaroutline",

    ["opt/castbar/global/focus/kick/enable/focus/kick/icon"] = "enablefocuskickicon",
    ["opt/castbar/global/focus/kick/focus/kick/icon/width"] = "focuskickiconwidth",
    ["opt/castbar/global/focus/kick/focus/kick/icon/height"] = "focuskickiconheight",
    ["opt/castbar/global/focus/kick/focus/kick/icon/offset/x"] = "focuskickiconoffsetx",
    ["opt/castbar/global/focus/kick/focus/kick/icon/offset/y"] = "focuskickiconoffsety",
    ["opt/castbar/global/focus/kick/text"] = "focuskicktextsize",
    ["opt/colors/advanced/npc/type/enabled"] = "npccolormode",
    ["opt/colors/advanced/npc/type/option/npc/type/color/bar"] = "npctypecolorbar",
    ["opt/bars/global/highlight/aggro/roles"] = "aggromode",
    ["opt/bars/global/highlight/border/mode/aggro/outline/mode"] = { "aggrooutlinemode", "aggroborder" },
}

local function ReviewedSettingAliases(controlPath)
    return REVIEWED_CONTROL_PATH_SETTING_COMPACTS[CleanText(controlPath):lower()]
end

local function DescriptorMatchesReviewedSetting(compacts, controlPath)
    local reviewed = ReviewedSettingAliases(controlPath)
    if reviewed == nil then return true end
    local accepted = type(reviewed) == "table" and reviewed or { reviewed }
    for i = 1, #(compacts or {}) do
        local value = compacts[i].value
        for j = 1, #accepted do if value == accepted[j] then return true end end
    end
    return false
end

-- Explain why a catalog record does or does not own a static one-setting
-- Assistant link.  This is intentionally structural and cold-path only.  It
-- prevents audits from treating preview state, selected-slot editors, compound
-- projections, and duplicate surfaces as unexplained coverage holes.
local function AssistantLinkDisposition(record)
    local classification = tostring(record and record.classification or "unknown")
    local path = CleanText(record and record.controlPath):lower()
    local kind = tostring(record and record.kind or "")
    if classification == "setting" then
        if CleanText(record and record.settingKey) ~= "" then
            return "setting.explicit", "The control declares its canonical Assistant settingKey.", true
        end
        if record and record.confirmRequired then
            return "setting.confirmation-required", "This mutation requires confirmation and is not a direct setting shortcut.", false
        end
        if kind == "button" then
            return "setting.compound-control", "This button applies a compound or positional choice rather than one scalar setting.", false
        end
        if path:find("/preview/", 1, true) then
            return "setting.preview-state", "This control changes preview-only state, not a persisted one-to-one setting.", false
        end
        if path:find("/status/selected/", 1, true)
            or path:find("/status/placement/", 1, true)
            or path:find("/position/slot", 1, true)
            or path:find("/slot/offset/", 1, true)
            or path:find("/editor/", 1, true)
            or path:find("/resource/slots/", 1, true)
            or record and record.pageKey == "opt_colors" and path:find("/class/power/", 1, true)
        then
            return "setting.dynamic-selector", "The visible widget edits whichever adjacent selector or preview handle is active, so it has no single static settingKey.", false
        end
        if record and record.pageKey == "classpower"
            and path:find("/detached/power/", 1, true)
            and not ReviewedSettingAliases(path)
        then
            return "setting.duplicate-surface", "This is a Class Resources view of a Player setting whose canonical Assistant surface is the Player page.", false
        end
        if path:find("/portrait/enabled", 1, true)
            or path:find("/move/together", 1, true)
            or path:find("/move_together", 1, true)
            or path:find("/text/preset", 1, true)
        then
            return "setting.compound-projection", "This convenience control projects or updates multiple backing values and is not one scalar setting.", false
        end
        return "setting.descriptor", "A canonical Assistant descriptor may resolve this stable control path at request time.", true
    end
    if classification == "action" then
        if record and record.confirmRequired then
            return "action.confirmation-required", "This is a confirmation-gated action, not a setting; it must use the Assistant action contract.", false
        end
        return "action.command", "This is an executable action, not a setting; it must use actionKey or its bound command.", false
    end
    if classification == "navigation" then
        return "navigation.route", "This control only opens another surface and has no backing setting.", false
    end
    if classification == "ephemeral" then
        if path:find("preview", 1, true) then
            return "ephemeral.preview", "This state exists only to drive the menu preview and is intentionally not persisted as a setting.", false
        end
        return "ephemeral.ui-state", "This is transient menu workspace or selector state and is intentionally excluded from setting linkage.", false
    end
    return "unknown.unclassified", "The control has no safe runtime classification, so the Assistant must not guess a setting link.", false
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
    local linkDisposition, linkReason, linkEligible = AssistantLinkDisposition(record)
    return {
        schemaVersion = record.schemaVersion,
        controlId = record.controlId,
        pageKey = record.pageKey,
        kind = record.kind,
        label = record.label,
        help = record.help,
        identityLabel = record.identityLabel,
        controlPath = record.controlPath ~= "" and record.controlPath or nil,
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
        confirmRequired = record.confirmRequired and true or false,
        virtual = record.virtual and true or false,
        assistantLinkDisposition = linkDisposition,
        assistantLinkReason = linkReason,
        assistantStaticSettingLinkEligible = linkEligible and true or false,
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

-- Exact Assistant navigation normally arrives with a canonical setting key and
-- a compact, read-only descriptor (attribute/dbPath/type/label).  Most Menu2
-- controls predate settingKey metadata, but they already expose stable semantic
-- control paths.  Resolve those two independent identities here, on demand,
-- instead of retaining a second thousands-entry index in the always-loaded
-- addon.  The matcher is deliberately fail-closed: every meaningful token in
-- one descriptor identity must be present, the widget kind must agree when the
-- descriptor declares a type, and a tied result is rejected.
local SETTING_TOKEN_ALIASES = {
    alpha = "alpha", opacity = "alpha",
    background = "background", bg = "background",
    color = "color", colour = "color",
    delimiter = "separator", separator = "separator",
    enable = "enabled", enabled = "enabled", show = "enabled", shown = "enabled",
    visible = "enabled", visibility = "enabled", use = "enabled",
    hp = "health", health = "health",
    position = "offset", pos = "offset", offset = "offset",
    sign = "symbol", symbol = "symbol",
    strata = "layer", layer = "layer",
}

local SETTING_DESCRIPTOR_STOP_TOKENS = {
    a = true, an = true, ["and"] = true, ["for"] = true, ["in"] = true, of = true,
    on = true, option = true, setting = true, the = true, to = true,
}

local function AddSettingToken(tokens, seen, token)
    token = CleanText(token):lower()
    token = SETTING_TOKEN_ALIASES[token] or token
    if token == "" or SETTING_DESCRIPTOR_STOP_TOKENS[token] or seen[token] then return end
    seen[token] = true
    tokens[#tokens + 1] = token
end

local function SettingIdentityTokens(value, ignored)
    local text = CleanText(value)
    if text == "" then return {} end
    text = text:gsub("%%", " percent ")
    text = text:gsub("(%l)(%u)", "%1 %2")
    text = text:gsub("(%u)(%u%l)", "%1 %2")
    text = text:gsub("[^%w]+", " ")
    local tokens, seen = {}, {}
    for token in text:gmatch("%S+") do
        local normalized = SETTING_TOKEN_ALIASES[token:lower()] or token:lower()
        if not (ignored and ignored[normalized]) then AddSettingToken(tokens, seen, normalized) end
    end
    return tokens
end

local function TokenSet(tokens)
    local out = {}
    for i = 1, #(tokens or {}) do out[tokens[i]] = true end
    return out
end

local function AddDescriptorSignature(out, seen, value, source, ignored)
    local tokens = SettingIdentityTokens(value, ignored)
    if #tokens == 0 then return end
    local key = table.concat(tokens, "\031")
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = { tokens = tokens, source = source }
end

local function CompactSettingIdentity(value)
    return CleanText(value):lower():gsub("[^%w]+", "")
end

local function AddDescriptorCompact(out, seen, value, source)
    local compact = CompactSettingIdentity(value)
    if #compact < 5 or seen[compact] then return end
    seen[compact] = true
    out[#out + 1] = { value = compact, source = source }
end

local function SettingDescriptorSignatures(settingKey, pageKey, descriptor)
    descriptor = type(descriptor) == "table" and descriptor or {}
    local ignored = TokenSet(SettingIdentityTokens(pageKey))
    -- The page key carries scope words (uf_target, gf_party, and so on).  They
    -- locate the page but are not part of the control's local identity.
    ignored.uf, ignored.gf, ignored.unit = true, true, true
    local scope = tostring(settingKey or ""):match("^([^%.]+)")
    local nonSemanticScope = {
        player = true, target = true, focus = true, pet = true, boss = true,
        targettarget = true, focustarget = true, general = true, bars = true,
        menu = true, auras3 = true, barScope = true, fontScope = true,
        gf_party = true, gf_raid = true, gf_mythicraid = true,
    }
    if nonSemanticScope[scope] then
        local scopeTokens = SettingIdentityTokens(scope)
        for i = 1, #scopeTokens do ignored[scopeTokens[i]] = true end
    end

    local signatures, seen = {}, {}
    AddDescriptorSignature(signatures, seen, descriptor.attribute, "attribute", ignored)
    AddDescriptorSignature(signatures, seen, descriptor.dbPath, "db_path", ignored)
    AddDescriptorSignature(signatures, seen, tostring(settingKey or ""):gsub("^[^%.]+%.", ""), "setting_key", ignored)
    AddDescriptorSignature(signatures, seen, descriptor.label, "label", ignored)
    local compacts, compactSeen = {}, {}
    AddDescriptorCompact(compacts, compactSeen, descriptor.attribute, "attribute")
    AddDescriptorCompact(compacts, compactSeen, descriptor.dbPath, "db_path")
    AddDescriptorCompact(compacts, compactSeen, tostring(settingKey or ""):gsub("^[^%.]+%.", ""), "setting_key")
    return signatures, compacts
end

local EXPECTED_SETTING_KINDS = {
    boolean = { toggle = true },
    bool = { toggle = true },
    number = { slider = true },
    color = { color = true },
    enum = { dropdown = true, segment = true },
    string = { dropdown = true, textinput = true },
}

local GENERIC_SETTING_IDENTITY_TOKENS = {
    alpha = true, anchor = true, background = true, color = true, enabled = true,
    height = true, layer = true, mode = true, offset = true, opacity = true,
    size = true, style = true, text = true, width = true, x = true, y = true,
}

local function RecordSettingTokens(record)
    local rawPath = CleanText(record and record.controlPath):lower()
    -- Some semantic paths intentionally describe UI concepts rather than DB
    -- spelling.  Expand only lossless UI synonyms used by shared builders.
    rawPath = rawPath:gsub("slotx", "slot x"):gsub("sloty", "slot y")
    local tokens, seen = {}, {}
    local function Add(value)
        local list = SettingIdentityTokens(value)
        for i = 1, #list do AddSettingToken(tokens, seen, list[i]) end
    end
    Add(rawPath)
    Add(record and record.label)
    Add(record and record.identityLabel)
    Add(record and record.kind)
    if rawPath:find("/position/", 1, true) then AddSettingToken(tokens, seen, "offset") end
    if rawPath:find("/anchor_to", 1, true) then
        AddSettingToken(tokens, seen, "anchor")
        AddSettingToken(tokens, seen, "frame")
        AddSettingToken(tokens, seen, "name")
    end
    if rawPath:find("/move_together", 1, true) then
        AddSettingToken(tokens, seen, "direct")
        AddSettingToken(tokens, seen, "layout")
    end
    if rawPath:find("/basics/enabled", 1, true) then AddSettingToken(tokens, seen, "frame") end
    if rawPath:find("/basics/smooth_fill", 1, true) then
        AddSettingToken(tokens, seen, "frame")
        AddSettingToken(tokens, seen, "health")
    end
    if rawPath:find("/basics/reverse_fill", 1, true) then AddSettingToken(tokens, seen, "health") end
    if rawPath:find("/power/detached", 1, true) then AddSettingToken(tokens, seen, "bar") end
    if rawPath:find("/castbar/manual_width", 1, true) then AddSettingToken(tokens, seen, "bar") end
    if rawPath:find("/castbar/detail/msuf2_castbar_spell_", 1, true)
        or rawPath:find("/castbar/spell_text_", 1, true)
    then
        AddSettingToken(tokens, seen, "text")
        AddSettingToken(tokens, seen, "name")
    end
    if rawPath:find("/castbar/feature/msuf2_castbar_text", 1, true) then AddSettingToken(tokens, seen, "spell") end
    if seen.text and seen.size then AddSettingToken(tokens, seen, "font") end
    return tokens, seen, rawPath
end

local function CompactPathMatchScore(compacts, rawPath)
    local segments, reviewedSegments = {}, {}
    for segment in tostring(rawPath or ""):gmatch("[^/]+") do
        segments[CompactSettingIdentity(segment)] = true
    end
    local reviewed = ReviewedSettingAliases(rawPath)
    if type(reviewed) == "string" then
        segments[reviewed] = true
        reviewedSegments[reviewed] = true
    elseif type(reviewed) == "table" then
        for i = 1, #reviewed do
            segments[reviewed[i]] = true
            reviewedSegments[reviewed[i]] = true
        end
    end
    -- Exact equivalences shared by every unit page. The semantic control path
    -- names the visible UI concept while the Assistant key names its backing
    -- SavedVariables field.
    if rawPath:find("/text/name/show", 1, true) then segments.showname = true end
    if rawPath:find("/text/hp/show", 1, true) then segments.showhp, segments.hptext = true, true end
    if rawPath:find("/power/detached", 1, true) and not rawPath:find("detachedpowerbar", 1, true) then
        segments.powerbardetached = true
    end
    if rawPath:find("/castbar/detail/msuf2_castbar_spell_align", 1, true) then segments.spellnamealign = true end
    if rawPath:find("/castbar/detail/msuf2_castbar_spell_position", 1, true) then segments.spellnameposition = true end
    if rawPath:find("/castbar/detail/msuf2_castbar_spell_size", 1, true) then segments.spellnamefontsize = true end
    if rawPath:find("/castbar/detail/msuf2_castbar_spell_x", 1, true) then segments.textoffsetx = true end
    if rawPath:find("/castbar/detail/msuf2_castbar_spell_y", 1, true) then segments.textoffsety = true end
    if rawPath:find("/castbar/detail/msuf2_castbar_time_size", 1, true) then segments.timefontsize = true end
    if rawPath:find("/castbar/spell_text_manual_width", 1, true) then segments.spellnamemaxwidth = true end
    if rawPath:find("/castbar/spell_text_width_mode", 1, true) then segments.spellnametruncate = true end
    if rawPath:find("/api/set/absorb/overlay/color", 1, true) then segments.absorbbarcolor = true end
    if rawPath:find("/api/set/heal/absorb/overlay/color", 1, true) then segments.healabsorbbarcolor = true end
    local best
    for i = 1, #(compacts or {}) do
        local compact = compacts[i]
        -- A lone compact such as "height", "enabled", or "color" is not an
        -- identity.  Accept it only when a reviewed exact path alias supplied
        -- that compact; otherwise the richer token signatures must prove the
        -- subsection.  This prevents a unit-frame height request from landing
        -- on the only visible Cast Bar Height slider, for example.
        if segments[compact.value]
            and (reviewedSegments[compact.value] or not GENERIC_SETTING_IDENTITY_TOKENS[compact.value])
        then
            local weight = compact.source == "attribute" and 36
                or compact.source == "db_path" and 32
                or 28
            local score = 1000 + #compact.value + weight
            if not best or score > best then best = score end
        end
    end
    return best
end

local function SignatureMatch(signature, recordTokens, recordSet, rawPath, descriptor)
    local effective, matched = 0, 0
    local dynamicSlot = rawPath:find("/position/slot", 1, true) ~= nil
    local signatureSet = TokenSet(signature.tokens)
    if dynamicSlot and not (signatureSet.slot or signatureSet.left or signatureSet.center or signatureSet.right) then return nil end
    local dynamicStatus = rawPath:find("/status/selected/", 1, true) ~= nil
    local descriptorAttribute = CleanText(descriptor and descriptor.attribute):lower()
    local descriptorFrameType = CleanText(descriptor and descriptor.frameType):lower()
    local descriptorCategory = CleanText(descriptor and descriptor.category):lower()
    local statusDescriptor = (descriptorFrameType == "group" and descriptorAttribute:find("statusicon", 1, true) ~= nil)
        or (descriptorFrameType == "unitframe" and descriptorCategory:find("status icons", 1, true) ~= nil)
    local dynamicStatusFields = {
        x = true, y = true, size = true, anchor = true, layer = true,
        enabled = true, style = true, custom = true, color = true, symbol = true,
    }
    for i = 1, #signature.tokens do
        local token = signature.tokens[i]
        -- One selected Slot X/Y control edits left, center, or right according
        -- to the adjacent selector.  Direction is therefore state, not widget
        -- identity, and all three canonical slot keys resolve to that control.
        local dynamicSide = dynamicSlot and (token == "left" or token == "center" or token == "right")
        local dynamicStatusIdentity = dynamicStatus and statusDescriptor and not dynamicStatusFields[token]
        if not dynamicSide and not dynamicStatusIdentity then
            effective = effective + 1
            if recordSet[token] then matched = matched + 1 end
        end
    end
    if effective == 0 or matched ~= effective then return nil end
    if effective == 1 and GENERIC_SETTING_IDENTITY_TOKENS[signature.tokens[1]]
        and not (dynamicSlot or dynamicStatus and statusDescriptor)
    then
        return nil
    end
    local sourceWeight = signature.source == "attribute" and 24
        or signature.source == "db_path" and 22
        or signature.source == "setting_key" and 18
        or 8
    return effective * 100 + sourceWeight
end

local function ResolveSettingDescriptorRecord(settingKey, pageKey, descriptor)
    local signatures, compacts = SettingDescriptorSignatures(settingKey, pageKey, descriptor)
    if #signatures == 0 then return nil, "missing_descriptor" end
    local expectedKinds = EXPECTED_SETTING_KINDS[CleanText(descriptor and descriptor.type):lower()]
    local best, bestScore, tied
    local function ConsiderRecord(record)
        if record and record.classification == "setting"
            and (not expectedKinds or expectedKinds[record.kind])
            and record.commandMeta and record.commandMeta.hasGet and record.commandMeta.hasSet
        then
            local recordTokens, recordSet, rawPath = RecordSettingTokens(record)
            local reviewedMatch = DescriptorMatchesReviewedSetting(compacts, rawPath)
            local score
            if reviewedMatch then
                score = CompactPathMatchScore(compacts, rawPath)
            end
            local semanticScore
            if reviewedMatch then
                for i = 1, #signatures do
                    local candidate = SignatureMatch(signatures[i], recordTokens, recordSet, rawPath, descriptor)
                    if candidate then semanticScore = (semanticScore or 0) + candidate end
                end
            end
            if semanticScore then score = (score or 0) + semanticScore end
            if score then
                -- Prefer a stable semantic identity if two controls expose the
                -- same vocabulary; never let that preference break a true tie
                -- between equally stable controls.
                if record.identityStable then score = score + 2 end
                if record.idSource == "explicit" then score = score + 1 end
                if not bestScore or score > bestScore then
                    best, bestScore, tied = record, score, false
                elseif score == bestScore and record ~= best then
                    tied = true
                end
            end
        end
    end
    local pageRecords = pageKey ~= "" and STATE.byPage[pageKey] or nil
    if pageRecords then
        for controlId in pairs(pageRecords) do ConsiderRecord(STATE.byId[controlId]) end
    else
        for _, record in pairs(STATE.byId) do ConsiderRecord(record) end
    end
    if not best then return nil, "no_semantic_match" end
    if tied then return nil, "ambiguous_semantic_match" end
    return best, "semantic_descriptor"
end

-- Late-bound exact-control lookup for Search and the load-on-demand Assistant.
-- This deliberately scans the existing catalog instead of maintaining a second
-- setting index: exact navigation is a cold user action and should not add idle
-- memory for thousands of controls.
function Catalog.FindBySettingKey(settingKey, pageKey, descriptor)
    settingKey = CleanText(settingKey)
    pageKey = CleanText(pageKey)
    if settingKey == "" then return nil end

    -- Exact search focusing calls this resolver again during the immediate,
    -- zero-delay, and 0.05-second layout passes. Serve that one repeated key
    -- before scanning; the catalog revision invalidates the scalar cache.
    local cached = STATE.lastSettingDescriptorLookup
    if cached and cached.revision == STATE.revision and cached.settingKey == settingKey and cached.pageKey == pageKey then
        local record = cached.controlId and STATE.byId[cached.controlId] or nil
        if record then
            local public = PublicRecord(record)
            public.settingKey = settingKey
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
    -- Preserve the previous cross-page fallback for callers with an outdated
    -- page hint, but avoid it for the normal exact-page hit.
    if not best then
        for _, record in pairs(STATE.byId) do
            if record.settingKey == settingKey then
                if pageKey ~= "" and record.pageKey == pageKey then
                    best = record
                    break
                end
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

    descriptor = type(descriptor) == "table" and descriptor or nil
    if not descriptor then return nil end

    local resolved, source = ResolveSettingDescriptorRecord(settingKey, pageKey, descriptor)
    STATE.lastSettingDescriptorLookup = {
        revision = STATE.revision,
        settingKey = settingKey,
        pageKey = pageKey,
        controlId = resolved and resolved.controlId or nil,
        source = source,
    }
    if not resolved then return nil, nil, source end
    local public = PublicRecord(resolved)
    public.settingKey = settingKey
    public.resolvedSettingKey = settingKey
    public.settingKeySource = source
    return public, resolved.widget, source
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
    local capabilityIssue = CapabilityIssue(record)
    if capabilityIssue then warnings[#warnings + 1] = capabilityIssue end
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
    local assistant = _G.MSUF_NS and _G.MSUF_NS.Assistant
    local registry = assistant and assistant.Registry
    local targetValidationAvailable = type(registry) == "table"
        and type(registry.GetSetting) == "function" and type(registry.GetAction) == "function"
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
        targetValidationAvailable = targetValidationAvailable,
        resolvedTargets = 0,
        unresolvedTargetCount = 0,
        unresolvedTargets = {},
        invalidCapabilityCount = 0,
        invalidCapabilities = {},
        interactiveEphemeral = 0,
        passiveEphemeral = 0,
        assistantLinkDispositionCounts = {},
        assistantStaticSettingLinkEligible = 0,
        assistantStaticSettingLinkExcluded = 0,
        collisionEventsLifetime = STATE.collisionEvents,
        componentParts = 0,
    }

    for _ in pairs(STATE.components) do report.componentParts = report.componentParts + 1 end

    for i = 1, #records do
        local record = records[i]
        local classification = CLASSIFICATION[record.classification] and record.classification or "unknown"
        local linkDisposition, _, linkEligible = AssistantLinkDisposition(record)
        report.assistantLinkDispositionCounts[linkDisposition] =
            (report.assistantLinkDispositionCounts[linkDisposition] or 0) + 1
        if linkEligible then report.assistantStaticSettingLinkEligible = report.assistantStaticSettingLinkEligible + 1
        else report.assistantStaticSettingLinkExcluded = report.assistantStaticSettingLinkExcluded + 1 end
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
        if classification == "ephemeral" then
            if record.commandMeta and record.commandMeta.hasSet then report.interactiveEphemeral = report.interactiveEphemeral + 1
            else report.passiveEphemeral = report.passiveEphemeral + 1 end
        end
        if classification == "unknown" then
            local item = PublicRecord(record)
            item.reason = record.classificationSource
            report.unknown[#report.unknown + 1] = item
        end
        if classification == "setting" or classification == "action"
            or classification == "ephemeral" and record.commandMeta and record.commandMeta.hasSet then
            local capabilityIssue = RuntimeCapabilityIssue(record)
            if capabilityIssue then
                report.invalidCapabilityCount = report.invalidCapabilityCount + 1
                report.invalidCapabilities[#report.invalidCapabilities + 1] = {
                    controlId = record.controlId, pageKey = record.pageKey,
                    classification = classification, kind = record.commandMeta and record.commandMeta.kind or record.kind,
                    reason = capabilityIssue,
                }
            end
            local key = classification == "setting" and record.settingKey or record.actionKey
            local hasDirectClosure = classification == "setting"
                and record.commandMeta and record.commandMeta.hasGet and record.commandMeta.hasSet
                or classification == "action" and record.commandMeta and record.commandMeta.hasSet
                or classification == "ephemeral" and record.commandMeta and record.commandMeta.hasSet
            local resolved = hasDirectClosure == true
            if resolved and record.commandMeta and record.commandMeta.hasRuntimeValidator then
                local ok, executable = pcall(record.command.canExecute)
                resolved = ok and executable == true
            end
            if not resolved and key and key ~= "" and targetValidationAvailable then
                resolved = classification == "setting" and registry:GetSetting(key) ~= nil
                    or classification == "action" and registry:GetAction(key) ~= nil
            end
            if resolved then
                report.resolvedTargets = report.resolvedTargets + 1
            else
                report.unresolvedTargetCount = report.unresolvedTargetCount + 1
                report.unresolvedTargets[#report.unresolvedTargets + 1] = {
                    controlId = record.controlId,
                    pageKey = record.pageKey,
                    classification = classification,
                    targetKey = key ~= "" and key or nil,
                }
            end
        end
    end

    if report.interactive > 0 then
        report.interactiveCoveragePercent = math.floor((report.knownInteractive * 10000 / report.interactive) + 0.5) / 100
    end
    report.catalogComplete = report.byClassification.unknown == 0 and report.collisions == 0
        and report.unstableIds == 0
        and report.unresolvedTargetCount == 0
        and report.invalidCapabilityCount == 0

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

-- Composite widgets (segments, scope selectors, slider +/- buttons) expose one
-- logical command on the parent. Their child buttons remain visible UI parts,
-- but are removed from the semantic catalog so they cannot become duplicate
-- unknown controls. Runtime reports retain an explicit component count.
function M.MarkRuntimeControlComponent(widget, owner)
    if not widget or not owner then return false end
    widget._msuf2ControlPartOf = owner
    local record = STATE.byWidget[widget]
    if record then RemoveRecord(record); STATE.revision = STATE.revision + 1 end
    STATE.components[widget] = {
        owner = owner,
        pageKey = CleanText(M._msuf2SearchBuildKey or M.activeKey or "unknown"),
    }
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
        navigationKey = opts.navigationKey,
        confirmRequired = opts.confirmRequired == true,
        historyMode = opts.historyMode,
        help = opts.help,
        command = opts.command,
    }
    if not meta.command and meta.classification == "action" then
        meta.command = M.BuildRuntimeWidgetCommand(widget, meta, meta.kind)
    end
    local existing = STATE.byId[meta.controlId]
    if existing and existing.widget ~= widget then RemoveRecord(existing) end
    return Catalog.Register(widget, meta, "menu-chrome")
end

function M.ClearRuntimeControlsForPage(pageKey)
    return Catalog.ClearPage(pageKey)
end

function M.GetRuntimeControlCoverageReport()
    return Catalog.GetCoverageReport()
end
