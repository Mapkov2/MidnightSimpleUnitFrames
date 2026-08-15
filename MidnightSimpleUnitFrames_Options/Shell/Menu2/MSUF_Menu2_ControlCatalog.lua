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
---
--- Assistant target contract:
---   * Persisted settings/actions require an explicit settingKey/actionKey.
---   * A deliberately non-scalar control may instead declare a reviewed
---     assistantDisposition (compound, dynamic, or duplicate) plus its reason.
---   * Runtime get/set closures prove capability only and never satisfy this
---     semantic completeness contract by themselves.

local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

local Catalog = M.RuntimeControlCatalog or {}
M.RuntimeControlCatalog = Catalog

Catalog.SCHEMA_VERSION = 2

-- Page-provided commands and metadata providers are plugin-style boundaries:
-- they must report authoring bugs without taking down the complete catalog or
-- leaving an Assistant transaction half-finished.
local function InvokeBoundary(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, r1, r2, r3, r4 = pcall(fn, ...)
    if not ok then
        local handler = _G.geterrorhandler and _G.geterrorhandler()
        if type(handler) == "function" and pcall(handler, r1) then return false, r1 end
        if type(print) == "function" then
            print("|cffffd700MSUF callback:|r", tostring(r1))
        end
        return false, r1
    end
    return true, r1, r2, r3, r4
end
M.InvokeBoundary = InvokeBoundary

-- Shell controls are not built by the page/widget factories, so an omitted raw
-- Button would otherwise be invisible to a percentage calculated only from
-- already-registered records.  Keep the executable shell surface and the
-- deliberately non-command UI mechanics in one small fail-closed contract.
-- Assistant V2 validates this table during coverage and runtime acceptance.
M.REQUIRED_SHELL_CONTRACT = {
    schemaVersion = 1,
    minimumControls = 8,
    minimumDispositions = 14,
    controls = {
        ["menu2.menu-chrome.window-close"] = { classification = "action", kind = "button", actionKey = "menu_window_close" },
        ["menu2.menu-chrome.window-minimize"] = { classification = "action", kind = "button", actionKey = "menu_window_minimize" },
        ["menu2.menu-chrome.window-maximize"] = { classification = "action", kind = "button", actionKey = "menu_window_maximize" },
        ["menu2.menu-chrome.window-restore"] = { classification = "action", kind = "button", actionKey = "menu_window_restore" },
        ["menu2.menu-chrome.search-clear"] = { classification = "action", kind = "button", actionKey = "menu_search_clear" },
        ["menu2.menu-chrome.search-intro-dismiss"] = { classification = "action", kind = "button", actionKey = "set_nav_search_intro" },
        ["menu2.menu-chrome.toolbar-page-back"] = { classification = "action", kind = "button", actionKey = "dashboard_page_back" },
        ["menu2.menu-chrome.toolbar-page-forward"] = { classification = "action", kind = "button", actionKey = "dashboard_page_forward" },
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

-- Persisted controls need a reviewable Assistant identity.  Executable get/set
-- closures only prove that the menu can operate a widget; they do not prove
-- which natural-language setting or action the Assistant is allowed to target.
-- A control that intentionally has no one-to-one target may opt out with one
-- of these narrow, source-declared dispositions and a human review reason.
local ASSISTANT_REVIEW_DISPOSITIONS = {
    compound = true,
    dynamic = true,
    duplicate = true,
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

local CLEAN_TEXT_CACHE_LIMIT = 4096
local CLEAN_TEXT_CACHE_MAX_SOURCE_LEN = 256
local cleanTextCache, cleanTextCacheCount = {}, 0
local function CleanText(value)
    if value == nil then return "" end
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

local function CopySerializableActionValue(value, seen, depth)
    local kind = type(value)
    if value == nil or kind == "boolean" or kind == "string" then return value end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil, "non-finite number" end
        return value
    end
    if kind ~= "table" then return nil, "unsupported " .. kind end
    depth = (depth or 0) + 1
    if depth > 5 then return nil, "table nesting exceeds five levels" end
    seen = seen or {}
    if seen[value] then return nil, "cyclic table" end
    seen[value] = true
    local out = {}
    for key, item in pairs(value) do
        local keyKind = type(key)
        if keyKind ~= "string" and keyKind ~= "number" then
            seen[value] = nil
            return nil, "unsupported table key " .. keyKind
        end
        local copy, err = CopySerializableActionValue(item, seen, depth)
        if err then
            seen[value] = nil
            return nil, err
        end
        out[key] = copy
    end
    seen[value] = nil
    return out
end

local function ActionValueFingerprint(value)
    local kind = type(value)
    if value == nil then return "z:" end
    if kind == "boolean" then return value and "b:1" or "b:0" end
    if kind == "number" then return "n:" .. string.format("%.17g", value) end
    if kind == "string" then return "s:" .. value end
    if kind ~= "table" then return "x:" .. kind end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        local lt, rt = type(left), type(right)
        if lt ~= rt then return lt < rt end
        return tostring(left) < tostring(right)
    end)
    local parts = { "t:" }
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = ActionValueFingerprint(key) .. "=" .. ActionValueFingerprint(value[key])
    end
    return table.concat(parts, "\030")
end

local function IsValidLuaPattern(text)
    return pcall(string.match, "", text)
end

local function NormalizeAssistantRouteList(value, fieldName, requireAnchors)
    local out, errors, seen = {}, {}, {}
    if value == nil then return out, errors end
    if type(value) == "string" then value = { value } end
    if type(value) ~= "table" then
        errors[#errors + 1] = fieldName .. " must be a string list"
        return out, errors
    end
    local numericKeys = {}
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            errors[#errors + 1] = fieldName .. " must be a dense numeric string list"
        else
            numericKeys[#numericKeys + 1] = key
        end
    end
    table.sort(numericKeys)
    for index = 1, #numericKeys do
        local key = numericKeys[index]
        if key ~= index then errors[#errors + 1] = fieldName .. " must not contain gaps" end
        local raw = value[key]
        local text = type(raw) == "string" and CleanText(raw) or ""
        if text == "" then
            errors[#errors + 1] = fieldName .. " entries must be non-empty strings"
        elseif requireAnchors and (text:sub(1, 1) ~= "^" or text:sub(-1) ~= "$") then
            errors[#errors + 1] = fieldName .. " entries must be fully anchored with ^ and $"
        else
            local valid = true
            if requireAnchors then valid = IsValidLuaPattern(text) end
            if not valid then
                errors[#errors + 1] = fieldName .. " contains an invalid Lua pattern: " .. text
            elseif not seen[text] then
                seen[text] = true
                out[#out + 1] = text
            end
        end
    end
    return out, errors
end

local function AssistantRouteFingerprint(record)
    return table.concat(record and record.assistantSettingKeys or {}, "\030")
        .. "\029" .. table.concat(record and record.assistantSettingKeyPatterns or {}, "\030")
        .. "\029" .. table.concat(record and record.assistantSettingRouteErrors or {}, "\030")
end

local NORMALIZED_TOKEN_CACHE_LIMIT = 4096
local NORMALIZED_TOKEN_CACHE_MAX_SOURCE_LEN = 256
local normalizedTokenCache, normalizedTokenCacheCount = {}, 0
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

local function IsValidExplicitId(value)
    if type(value) ~= "string" or #value < 3 or #value > 160 then return false end
    if value:find("^%s") or value:find("%s$") then return false end
    return value:match("^[%w_%.:/%-]+$") ~= nil
end

local function IsValidRuntimeId(value)
    if type(value) ~= "string" or #value < 3 or #value > 180 then return false end
    return value:match("^[%w_%.:/%-%~]+$") ~= nil
end

--- Optional widget accessor: templates vary in which of GetName/GetObjectType/
--- GetParent they expose, so the nil-guard is the useful part. Formerly named
--- SafeCall and wrapped in pcall, which hid a protected call from a `grep pcall`
--- audit and swallowed real widget bugs. None of these accessors throw.
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
        local ok, value = InvokeBoundary(command.sourceFn, label)
        if ok then return CleanText(value) end
    end
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

local function CommandMetadata(command, label)
    if type(command) ~= "table" then return nil end
    local values = command.values
    if type(values) ~= "table" and type(command.getValues) == "function" then
        local ok, resolved = InvokeBoundary(command.getValues)
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
        assistantDisposition = CleanText(command.assistantDisposition):lower(),
        assistantDispositionReason = CleanText(command.assistantDispositionReason),
        assistantSettingKeyCount = #(type(command.assistantSettingKeys) == "table" and command.assistantSettingKeys or {}),
        assistantSettingKeyPatternCount = #(type(command.assistantSettingKeyPatterns) == "table" and command.assistantSettingKeyPatterns or {}),
        hasGet = type(command.get) == "function",
        hasSet = type(command.set) == "function",
        hasRefresh = type(command.refresh) == "function",
        hasCombatGuard = type(command.blockCombat) == "function",
        hasDynamicValues = type(command.getValues) == "function",
        hasValues = type(command.values) == "table" or type(command.getValues) == "function",
        hasRuntimeValidator = type(command.canExecute) == "function",
        valueCount = count,
        valueKind = CleanText(command.valueKind),
        historyMode = CleanText(command.historyMode),
        percentIsValue = command.percentIsValue == true,
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

-- Command metadata is consumed only by cold read paths (capability checks,
-- audit reports, Assistant descriptors). Building the ~30-field table with its
-- CleanText fan-out during Catalog.Register made every page build pay for it
-- per control, so registration only marks it dirty and readers materialize it
-- here on first access.
local function EnsureCommandMeta(record)
    if type(record) ~= "table" then return nil end
    if record._commandMetaDirty then
        record._commandMetaDirty = nil
        record.commandMeta = CommandMetadata(record.command, record.label)
    end
    return record.commandMeta
end

local SETTING_COMMAND_KINDS = {
    toggle = true, slider = true, dropdown = true, segment = true,
    textinput = true, color = true, dragrow = true,
}
local function CapabilityIssue(record)
    if type(record) ~= "table" then return nil end
    local meta = EnsureCommandMeta(record)
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
    elseif kind == "dropdown" or kind == "segment" or kind == "dragrow" then
        if meta.hasValues ~= true then return kind .. " is missing a values provider" end
        if kind == "dragrow" then
            if meta.valueKind ~= "enum" then return "dragrow requires valueKind=enum" end
            local disposition = CleanText(record.assistantDisposition):lower()
            local routeCount = #(record.assistantSettingKeys or {}) + #(record.assistantSettingKeyPatterns or {})
            if disposition ~= "dynamic" or routeCount == 0 then
                return "dragrow requires a reviewed dynamic Registry order route"
            end
        end
    end
    return nil
end
local function RuntimeCapabilityIssue(record)
    local issue = CapabilityIssue(record)
    if issue then return issue end
    local command, meta = record and record.command, EnsureCommandMeta(record)
    if type(command) ~= "table" or type(meta) ~= "table" then return nil end
    if meta.hasGet then
        local ok = InvokeBoundary(command.get)
        if not ok then return "read command raised an error" end
    end
    local kind = CleanText(meta.kind ~= "" and meta.kind or record.kind):lower()
    if kind == "dropdown" or kind == "segment" or kind == "dragrow" then
        local values = command.values
        if type(values) ~= "table" and type(command.getValues) == "function" then
            local ok, resolved = InvokeBoundary(command.getValues)
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
        local ok, resolved = InvokeBoundary(values)
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
        actionFixedArgs = CopySerializableActionValue(meta.actionFixedArgs),
        actionInputArg = meta.actionInputArg,
        assistantDisposition = meta.assistantDisposition,
        assistantDispositionReason = meta.assistantDispositionReason,
        assistantSettingKeys = CopyStringList(meta.assistantSettingKeys),
        assistantSettingKeyPatterns = CopyStringList(meta.assistantSettingKeyPatterns),
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

local REVISION_KEY_PARTS = {}
local function RevisionKey(record)
    if type(record) ~= "table" then return nil end
    local parts = REVISION_KEY_PARTS
    parts[1] = tostring(record.controlId or "")
    parts[2] = tostring(record.pageKey or "")
    parts[3] = tostring(record.kind or "")
    parts[4] = tostring(record.label or "")
    parts[5] = tostring(record.identityLabel or "")
    parts[6] = tostring(record.controlPath or "")
    parts[7] = tostring(record.settingKey or "")
    parts[8] = tostring(record.actionKey or "")
    parts[9] = tostring(record.navigationKey or "")
    parts[10] = ActionValueFingerprint(record.actionFixedArgs)
    parts[11] = tostring(record.actionInputArg or "")
    parts[12] = tostring(record.assistantDisposition or "")
    parts[13] = tostring(record.assistantDispositionReason or "")
    parts[14] = AssistantRouteFingerprint(record)
    parts[15] = tostring(record.help or "")
    parts[16] = tostring(record.classification or "")
    parts[17] = record.confirmRequired and "1" or "0"
    parts[18] = tostring(record.command or "")
    return table.concat(parts, "\031", 1, 18)
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
    record.commandMeta = nil
    record._commandMetaDirty = true
    -- Record fields always hold CleanText output from an earlier pass, so an
    -- unchanged field skips the re-clean; only newly declared sources pay it.
    local declaredValue = meta.identityKey
    record.identityKey = declaredValue and CleanText(declaredValue) or record.identityKey or ""
    declaredValue = meta.controlPath
    record.controlPath = declaredValue and CleanText(declaredValue) or record.controlPath or ""
    declaredValue = meta.settingKey or (record.command and record.command.settingKey)
    record.settingKey = declaredValue and CleanText(declaredValue) or record.settingKey or ""
    declaredValue = meta.actionKey or (record.command and record.command.actionKey)
    record.actionKey = declaredValue and CleanText(declaredValue) or record.actionKey or ""
    declaredValue = meta.navigationKey or (record.command and record.command.navigationKey)
    record.navigationKey = declaredValue and CleanText(declaredValue) or record.navigationKey or ""
    local declaredActionFixedArgs = meta.actionFixedArgs
    if declaredActionFixedArgs == nil and command then declaredActionFixedArgs = command.actionFixedArgs end
    if declaredActionFixedArgs ~= nil then
        local fixedArgs, fixedArgsError = CopySerializableActionValue(declaredActionFixedArgs)
        record.actionFixedArgs = fixedArgs
        record.actionContractError = fixedArgsError
    elseif meta.actionKey ~= nil or command and command.actionKey ~= nil then
        record.actionFixedArgs = nil
        record.actionContractError = nil
    end
    local declaredActionInputArg = meta.actionInputArg
    if declaredActionInputArg == nil and command then declaredActionInputArg = command.actionInputArg end
    if declaredActionInputArg ~= nil then
        record.actionInputArg = CleanText(declaredActionInputArg)
    elseif meta.actionKey ~= nil or command and command.actionKey ~= nil then
        record.actionInputArg = ""
    else
        record.actionInputArg = record.actionInputArg or ""
    end
    local declaredDisposition = meta.assistantDisposition
    if declaredDisposition == nil and command then declaredDisposition = command.assistantDisposition end
    local declaredDispositionReason = meta.assistantDispositionReason
    if declaredDispositionReason == nil and command then
        declaredDispositionReason = command.assistantDispositionReason
    end
    local declaredTargetKey = meta.settingKey ~= nil or meta.actionKey ~= nil
        or command and (command.settingKey ~= nil or command.actionKey ~= nil)
    local declaredSettingKeys = meta.assistantSettingKeys
    if declaredSettingKeys == nil and command then declaredSettingKeys = command.assistantSettingKeys end
    local declaredSettingKeyPatterns = meta.assistantSettingKeyPatterns
    if declaredSettingKeyPatterns == nil and command then
        declaredSettingKeyPatterns = command.assistantSettingKeyPatterns
    end
    local declaredAssistantRoutes = declaredSettingKeys ~= nil or declaredSettingKeyPatterns ~= nil
    if declaredDisposition ~= nil or declaredDispositionReason ~= nil then
        record.assistantDisposition = CleanText(declaredDisposition):lower()
        record.assistantDispositionReason = CleanText(declaredDispositionReason)
    elseif declaredTargetKey then
        -- Promotion from a reviewed role to a canonical key must not retain a
        -- stale opt-out disposition from an earlier virtual/search record.
        record.assistantDisposition = ""
        record.assistantDispositionReason = ""
    else
        record.assistantDisposition = record.assistantDisposition or ""
        record.assistantDispositionReason = record.assistantDispositionReason or ""
    end
    if declaredAssistantRoutes then
        local keys, keyErrors = NormalizeAssistantRouteList(
            declaredSettingKeys, "assistantSettingKeys", false)
        local patterns, patternErrors = NormalizeAssistantRouteList(
            declaredSettingKeyPatterns, "assistantSettingKeyPatterns", true)
        record.assistantSettingKeys = keys
        record.assistantSettingKeyPatterns = patterns
        record.assistantSettingRouteErrors = {}
        for i = 1, #keyErrors do record.assistantSettingRouteErrors[#record.assistantSettingRouteErrors + 1] = keyErrors[i] end
        for i = 1, #patternErrors do record.assistantSettingRouteErrors[#record.assistantSettingRouteErrors + 1] = patternErrors[i] end
    elseif declaredTargetKey then
        record.assistantSettingKeys = {}
        record.assistantSettingKeyPatterns = {}
        record.assistantSettingRouteErrors = {}
    else
        record.assistantSettingKeys = type(record.assistantSettingKeys) == "table" and record.assistantSettingKeys or {}
        record.assistantSettingKeyPatterns = type(record.assistantSettingKeyPatterns) == "table"
            and record.assistantSettingKeyPatterns or {}
        record.assistantSettingRouteErrors = type(record.assistantSettingRouteErrors) == "table"
            and record.assistantSettingRouteErrors or {}
    end
    declaredValue = meta.help or meta.description
    record.help = declaredValue and CleanText(declaredValue) or record.help or ""
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

-- Legacy positive PercentSymbol settings intentionally focus the modern
-- inverse HidePercentSymbol toggle.  The Registry owns the value inversion;
-- this catalog evidence is navigation-only and must remain explicit so a
-- generic semantic match can never silently become an accepted alias.
local REVIEWED_DUPLICATE_CONTROL_PATH_SETTING_COMPACTS = {
    ["classpower/advanced/player/hp/text/player/hpbar/text/right/hide/percent/symbol"] = "playerhpbartextrightpercentsymbol",
    ["classpower/advanced/player/hp/text/player/hpbar/text/left/hide/percent/symbol"] = "playerhpbartextleftpercentsymbol",
    ["classpower/advanced/player/hp/text/player/hpbar/text/center/hide/percent/symbol"] = "playerhpbartextcenterpercentsymbol",
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

local function DescriptorReviewedAliasSource(compacts, controlPath)
    local path = CleanText(controlPath):lower()
    local reviewed = REVIEWED_CONTROL_PATH_SETTING_COMPACTS[path]
    if reviewed == nil then return nil end
    if not DescriptorMatchesReviewedSetting(compacts, path) then return false end
    local duplicate = REVIEWED_DUPLICATE_CONTROL_PATH_SETTING_COMPACTS[path]
    if duplicate then
        for i = 1, #(compacts or {}) do
            if compacts[i].value == duplicate then return "reviewed_duplicate_alias" end
        end
    end
    return "reviewed_descriptor_alias"
end

local function ReviewedAssistantDisposition(record)
    local disposition = CleanText(record and record.assistantDisposition):lower()
    local reason = CleanText(record and record.assistantDispositionReason)
    if disposition == "" then
        if reason ~= "" then return nil, "assistantDispositionReason requires assistantDisposition" end
        return nil
    end
    if not ASSISTANT_REVIEW_DISPOSITIONS[disposition] then
        return nil, "unsupported assistantDisposition: " .. disposition
    end
    if reason == "" then
        return nil, "assistantDisposition requires a non-empty review reason"
    end
    return disposition, nil, reason
end

-- Legacy path shapes are useful migration hints, never proof.  Keep them in
-- reports so reviewers can make bounded source edits without letting a broad
-- substring rule silently bless a persisted control.
local function SuggestedAssistantDisposition(record)
    local path = CleanText(record and record.controlPath):lower()
    if path:find("/status/selected/", 1, true)
        or path:find("/status/placement/", 1, true)
        or path:find("/position/slot", 1, true)
        or path:find("/slot/offset/", 1, true)
        or path:find("/editor/", 1, true)
        or path:find("/resource/slots/", 1, true)
        or record and record.pageKey == "opt_colors" and path:find("/class/power/", 1, true)
    then
        return "dynamic", "the control path looks selected-scope dependent"
    end
    if record and record.pageKey == "classpower"
        and path:find("/detached/power/", 1, true)
        and not ReviewedSettingAliases(path)
    then
        return "duplicate", "the control path looks like a second surface for a Player setting"
    end
    if path:find("/portrait/enabled", 1, true)
        or path:find("/move/together", 1, true)
        or path:find("/move_together", 1, true)
        or path:find("/text/preset", 1, true)
    then
        return "compound", "the control path looks like a multi-value projection"
    end
    return nil
end

-- Explain whether a persisted record has an auditable Assistant contract.
-- Runtime closures remain capability evidence only; they never establish the
-- semantic target by themselves.
local function AssistantLinkDisposition(record)
    local classification = tostring(record and record.classification or "unknown")
    local path = CleanText(record and record.controlPath):lower()
    local targetKey = classification == "setting" and CleanText(record and record.settingKey)
        or classification == "action" and CleanText(record and record.actionKey) or ""
    if classification == "setting" or classification == "action" then
        if targetKey ~= "" then
            return classification .. ".explicit", "The control declares its canonical Assistant "
                .. (classification == "setting" and "settingKey." or "actionKey."), classification == "setting", true
        end
        local disposition, dispositionError, reviewReason = ReviewedAssistantDisposition(record)
        if disposition then
            return classification .. ".reviewed-" .. disposition, reviewReason, false, true
        end
        local suggested, suggestionReason = SuggestedAssistantDisposition(record)
        local reason = dispositionError or ("Persisted " .. classification
            .. " has no explicit target key or reviewed Assistant disposition.")
        return classification .. ".unresolved", reason, false, false, suggested, suggestionReason
    end
    if classification == "navigation" then
        return "navigation.route", "This control only opens another surface and has no backing setting.", false, true
    end
    if classification == "ephemeral" then
        if path:find("preview", 1, true) then
            return "ephemeral.preview", "This state exists only to drive the menu preview and is intentionally not persisted as a setting.", false, true
        end
        return "ephemeral.ui-state", "This is transient menu workspace or selector state and is intentionally excluded from setting linkage.", false, true
    end
    return "unknown.unclassified", "The control has no safe runtime classification, so the Assistant must not guess a setting link.", false, false
end

local function PublicRecord(record)
    local sources = {}
    for source in pairs(record.sources or {}) do sources[#sources + 1] = source end
    table.sort(sources)
    local command
    local commandMeta = EnsureCommandMeta(record)
    if type(commandMeta) == "table" then
        command = {}
        for key, value in pairs(commandMeta) do command[key] = value end
    end
    local linkDisposition, linkReason, linkEligible, contractAccounted, suggestedDisposition, suggestionReason = AssistantLinkDisposition(record)
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
        actionFixedArgs = CopySerializableActionValue(record.actionFixedArgs),
        actionInputArg = record.actionInputArg ~= "" and record.actionInputArg or nil,
        actionContractError = record.actionContractError,
        navigationKey = record.navigationKey ~= "" and record.navigationKey or nil,
        assistantDisposition = record.assistantDisposition ~= "" and record.assistantDisposition or nil,
        assistantDispositionReason = record.assistantDispositionReason ~= "" and record.assistantDispositionReason or nil,
        assistantSettingKeys = CopyStringList(record.assistantSettingKeys),
        assistantSettingKeyPatterns = CopyStringList(record.assistantSettingKeyPatterns),
        assistantSettingRouteErrors = CopyStringList(record.assistantSettingRouteErrors),
        confirmRequired = record.confirmRequired and true or false,
        virtual = record.virtual and true or false,
        assistantLinkDisposition = linkDisposition,
        assistantLinkReason = linkReason,
        assistantStaticSettingLinkEligible = linkEligible and true or false,
        assistantContractAccounted = contractAccounted and true or false,
        suggestedAssistantDisposition = suggestedDisposition,
        suggestedAssistantDispositionReason = suggestionReason,
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

local function SemanticPath(record)
    local path = CleanText(record and record.controlPath)
    if path == "" then path = CleanText(record and record.identityKey) end
    if path == "" then path = CleanText(record and record.controlId) end
    return path
end

local function FamilyIdentity(path)
    local parts, family, members = {}, {}, {}
    for part in tostring(path or ""):gmatch("[^/]+") do parts[#parts + 1] = part end
    for i = 1, #parts do
        local part = parts[i]
        if part:match("^%d+$") then
            family[#family + 1] = "{member}"
            members[#members + 1] = part
        else
            family[#family + 1] = part
        end
    end
    if #members == 0 then return nil, nil end
    return table.concat(family, "/"), table.concat(members, ".")
end

local function AssistantSafety(record)
    if type(record) ~= "table" then return "readOnly" end
    if record.classification == "navigation" then return "nonStateful" end
    local command = record.command
    local readable = type(command) == "table" and type(command.get) == "function"
    local writable = type(command) == "table" and type(command.set) == "function"
    if record.classification == "unknown" or not writable then return "readOnly" end
    -- Persisted Menu2 callbacks are capability evidence, not an Assistant
    -- transaction boundary. Only a canonical Registry target can provide
    -- validation, confirmation, snapshot, undo/redo, and atomic rollback.
    -- Reviewed dynamic/compound/duplicate controls remain discoverable and
    -- navigable, but fail closed until a concrete target is selected.
    if record.classification == "setting" and CleanText(record.settingKey) == "" then return "guided" end
    if record.classification == "action" and CleanText(record.actionKey) == "" then return "guided" end
    if record.classification == "action" and record.actionContractError then return "guided" end
    if record.confirmRequired == true then return "confirm" end
    if record.classification == "ephemeral" then return "nonStateful" end
    if record.classification == "setting" and not readable then return "readOnly" end
    return "direct"
end

local function AssistantSemanticId(record)
    local path = SemanticPath(record)
    local familyId, memberKey = FamilyIdentity(path)
    local pagePath = CleanText(record.pageKey)
    if pagePath ~= "" and path ~= "" then pagePath = pagePath .. "/" .. path
    elseif pagePath == "" then pagePath = path end
    if record.classification == "ephemeral" and familyId then
        familyId = CleanText(record.pageKey) .. "/" .. familyId
        return "instance:" .. familyId .. ":" .. memberKey, familyId, memberKey
    end
    local target = record.classification == "setting" and CleanText(record.settingKey)
        or record.classification == "action" and CleanText(record.actionKey)
        or record.classification == "navigation" and CleanText(record.navigationKey) or ""
    local prefix = record.classification == "setting" and "setting"
        or record.classification == "action" and "action"
        or record.classification == "navigation" and "navigation" or "control"
    if target == "" then target = pagePath end
    if pagePath ~= "" and path ~= target then target = target .. "@" .. pagePath end
    return prefix .. ":" .. target, familyId, memberKey
end

local function SelectableValues(record)
    local command = record and record.command
    if type(command) ~= "table" then return nil end
    local values = command.values
    if type(values) ~= "table" and type(command.getValues) == "function" then
        local ok, resolved = InvokeBoundary(command.getValues)
        if ok and type(resolved) == "table" then values = resolved end
    end
    if type(values) ~= "table" then return nil end
    local out = {}
    for _, row in pairs(values) do
        if type(row) == "table" and row.value ~= nil and row.disabled ~= true and row.header ~= true then
            out[#out + 1] = { value = row.value, text = CleanText(row.text or row.label or row.value) }
        elseif type(row) == "string" or type(row) == "number" then
            out[#out + 1] = { value = row, text = tostring(row) }
        end
    end
    table.sort(out, function(left, right)
        local leftText, rightText = tostring(left.text), tostring(right.text)
        if leftText ~= rightText then return leftText < rightText end
        return tostring(left.value) < tostring(right.value)
    end)
    return out
end

local function AssistantDescriptor(record)
    local semanticId, familyId, memberKey = AssistantSemanticId(record)
    local command = EnsureCommandMeta(record) or {}
    return {
        schemaVersion = Catalog.SCHEMA_VERSION,
        semanticId = semanticId,
        familyId = familyId,
        memberKey = memberKey,
        contextBound = familyId ~= nil,
        controlId = record.controlId,
        pageKey = record.pageKey,
        controlPath = SemanticPath(record),
        classification = record.classification,
        kind = record.kind,
        label = record.label,
        help = record.help,
        settingKey = record.settingKey ~= "" and record.settingKey or nil,
        actionKey = record.actionKey ~= "" and record.actionKey or nil,
        actionFixedArgs = CopySerializableActionValue(record.actionFixedArgs),
        actionInputArg = record.actionInputArg ~= "" and record.actionInputArg or nil,
        actionContractError = record.actionContractError,
        navigationKey = record.navigationKey ~= "" and record.navigationKey or nil,
        assistantDisposition = record.assistantDisposition ~= "" and record.assistantDisposition or nil,
        safety = AssistantSafety(record),
        valueKind = command.valueKind ~= "" and command.valueKind or nil,
        percentIsValue = command.percentIsValue == true,
        min = command.min,
        max = command.max,
        step = command.step,
        values = SelectableValues(record),
        confirmRequired = record.confirmRequired == true,
        identityStable = record.identityStable == true,
    }
end

function Catalog.GetAssistantDescriptors()
    local records, out = SortedRecords(), {}
    for i = 1, #records do out[i] = AssistantDescriptor(records[i]) end
    return out
end

local function EnsureSemanticIndex()
    local cached = Catalog._assistantSemanticIndex
    if type(cached) == "table" and cached.revision == STATE.revision then return cached end
    cached = { revision = STATE.revision, bySemanticId = {}, ambiguous = {} }
    local records = SortedRecords()
    for i = 1, #records do
        local record = records[i]
        local semanticId = AssistantSemanticId(record)
        local previous = cached.bySemanticId[semanticId]
        if previous and previous ~= record then
            cached.bySemanticId[semanticId] = nil
            cached.ambiguous[semanticId] = true
        elseif not cached.ambiguous[semanticId] then
            cached.bySemanticId[semanticId] = record
        end
    end
    Catalog._assistantSemanticIndex = cached
    return cached
end

function Catalog.Resolve(semanticId, context)
    semanticId = CleanText(semanticId)
    if semanticId == "" then return nil, "missing_semantic_id" end
    local index = EnsureSemanticIndex()
    if index.ambiguous[semanticId] then return nil, "ambiguous_semantic_id" end
    local record = index.bySemanticId[semanticId]
    if not record then return nil, "not_built" end
    if type(context) == "table" and context.pageKey and CleanText(context.pageKey) ~= record.pageKey then
        return nil, "wrong_page_context"
    end
    -- Keep the live widget available to exact-control navigation.  The
    -- generated Assistant schema is function-free, so it resolves a stable
    -- semantic ID only after the owning page has been built; returning the
    -- widget here lets the caller focus the exact transient/test control too.
    return record, record.widget, AssistantDescriptor(record)
end

function Catalog.Read(controlId)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil, "combat" end
    local record = STATE.byId[CleanText(controlId)]
    local command = record and record.command
    if not (command and type(command.get) == "function") then return nil, "read_unavailable" end
    local ok, r1, r2, r3, r4 = InvokeBoundary(command.get)
    if not ok then return nil, "read_failed", r1 end
    return true, r1, r2, r3, r4
end

local function ValueAllowed(record, value)
    local kind = CleanText(record and record.kind):lower()
    local command = record and record.command or {}
    if kind == "toggle" then return type(value) == "boolean", value end
    if kind == "slider" then
        value = tonumber(value)
        if value == nil then return false end
        local minimum, maximum = tonumber(command.min), tonumber(command.max)
        if minimum and value < minimum or maximum and value > maximum then return false end
        return true, value
    end
    if kind == "dropdown" or kind == "segment" then
        local values = SelectableValues(record) or {}
        for i = 1, #values do
            if value == values[i].value or tostring(value):lower() == tostring(values[i].text):lower() then
                return true, values[i].value
            end
        end
        return false
    end
    if kind == "textinput" then return type(value) == "string", value end
    if kind == "color" then
        if type(value) ~= "table" then return false end
        local r, g, b = tonumber(value[1] or value.r), tonumber(value[2] or value.g), tonumber(value[3] or value.b)
        local a = tonumber(value[4] or value.a or 1)
        if not r or not g or not b or not a or r < 0 or r > 1 or g < 0 or g > 1
            or b < 0 or b > 1 or a < 0 or a > 1 then return false end
        return true, { r, g, b, a }
    end
    if kind == "button" then return true, value end
    -- Drag and drag-row controls represent ordered state, not a scalar click.
    -- They require a reviewed Registry order owner; never pass an arbitrary
    -- value through to a widget callback.
    return false
end

function Catalog.Execute(controlId, value, options)
    options = type(options) == "table" and options or {}
    if _G.InCombatLockdown and _G.InCombatLockdown() then return false, "combat" end
    local record = STATE.byId[CleanText(controlId)]
    if not record then return false, "stale_control" end
    local safety = AssistantSafety(record)
    if safety == "readOnly" then return false, "read_only" end
    if safety == "guided" then return false, "guided" end
    if safety == "confirm" and options.confirmed ~= true then
        return false, "confirmation_required", AssistantSemanticId(record)
    end
    local command = record.command
    if not (command and type(command.set) == "function") then return false, "write_unavailable" end
    if type(command.blockCombat) == "function" then
        local ok, blocked = InvokeBoundary(command.blockCombat)
        if not ok or blocked == true then return false, "blocked" end
    end
    if type(command.canExecute) == "function" then
        local ok, executable = InvokeBoundary(command.canExecute)
        if not ok or executable ~= true then return false, "stale_control" end
    end
    local valid, normalized = ValueAllowed(record, value)
    if not valid then return false, "invalid_value" end
    local ok, result
    if record.kind == "color" then
        ok, result = InvokeBoundary(command.set, normalized[1], normalized[2], normalized[3], normalized[4])
    else
        ok, result = InvokeBoundary(command.set, normalized)
    end
    if not ok then return false, "write_failed", result end
    if result == false then return false, "write_rejected" end
    if type(command.refresh) == "function" then
        local refreshed, refreshError = InvokeBoundary(command.refresh)
        if not refreshed then return false, "refresh_failed", refreshError end
    end
    return true, result
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
    local best, bestScore, bestSource, tied
    local function ConsiderRecord(record)
        local considerMeta = EnsureCommandMeta(record)
        if record and record.classification == "setting"
            and (not expectedKinds or expectedKinds[record.kind])
            and considerMeta and considerMeta.hasGet and considerMeta.hasSet
        then
            local recordTokens, recordSet, rawPath = RecordSettingTokens(record)
            local reviewedAliasSource = DescriptorReviewedAliasSource(compacts, rawPath)
            local reviewedMatch = reviewedAliasSource ~= false
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
                    best, bestScore, bestSource, tied = record, score,
                        reviewedAliasSource or "semantic_descriptor", false
                elseif score == bestScore and record ~= best then
                    tied = true
                end
            end
        end
    end
    local pageRecords = pageKey ~= "" and STATE.byPage[pageKey] or nil
    if pageKey ~= "" and not pageRecords then
        return nil, "page_not_built"
    elseif pageRecords then
        for controlId in pairs(pageRecords) do ConsiderRecord(STATE.byId[controlId]) end
    else
        for _, record in pairs(STATE.byId) do ConsiderRecord(record) end
    end
    if not best then return nil, "no_semantic_match" end
    if tied then return nil, "ambiguous_semantic_match" end
    return best, bestSource or "semantic_descriptor"
end

local function SettingDescriptorFingerprint(descriptor)
    if type(descriptor) ~= "table" then return "" end
    local fields = { "attribute", "dbPath", "type", "label", "category", "unit", "frameType",
        "menuControlDisposition", "menuControlDispositionReason", "menuControlDispositionEvidence" }
    local parts = {}
    for i = 1, #fields do
        local key = fields[i]
        local value = descriptor[key]
        if type(value) == "table" then
            local nested = {}
            for j = 1, #value do nested[#nested + 1] = CleanText(value[j]) end
            value = table.concat(nested, ".")
        end
        parts[#parts + 1] = key .. "=" .. CleanText(value)
    end
    return table.concat(parts, "|")
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
        local ok, prepared = pcall(prepare, widget, descriptor)
        if not ok or prepared ~= true then return nil, nil, "prepare_failed" end
    end

    return PublicRecord(record), widget, "control_id"
end

-- Late-bound exact-control lookup for Search and the load-on-demand Assistant.
-- This deliberately scans the existing catalog instead of maintaining a second
-- setting index: exact navigation is a cold user action and should not add idle
-- memory for thousands of controls.
function Catalog.FindBySettingKey(settingKey, pageKey, descriptor)
    settingKey = CleanText(settingKey)
    pageKey = CleanText(pageKey)
    if settingKey == "" then return nil end
    local descriptorFingerprint = SettingDescriptorFingerprint(descriptor)

    -- Exact search focusing calls this resolver again during the immediate,
    -- zero-delay, and 0.05-second layout passes. Serve that one repeated key
    -- before scanning; the catalog revision invalidates the scalar cache.
    local cached = STATE.lastSettingDescriptorLookup
    if cached and cached.revision == STATE.revision and cached.settingKey == settingKey
        and cached.pageKey == pageKey and cached.descriptorFingerprint == descriptorFingerprint
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
            descriptorFingerprint = descriptorFingerprint,
            controlId = best.controlId,
            source = "explicit",
        }
        return PublicRecord(best), best.widget, "explicit"
    end

    -- A reviewed dynamic control may represent a finite set or a narrow key
    -- family selected by its current scope/resource/lane.  Source files must
    -- declare that family explicitly.  Never infer it from labels or broad
    -- page prefixes, and reject overlap between two controls as ambiguous.
    local dynamicBest, dynamicSource, dynamicAmbiguous
    local function ConsiderDynamicRecord(record)
        if not record or record.classification ~= "setting"
            or CleanText(record.assistantDisposition):lower() ~= "dynamic"
            or #(record.assistantSettingRouteErrors or {}) > 0
        then
            return
        end
        local matchedSource
        for i = 1, #(record.assistantSettingKeys or {}) do
            if record.assistantSettingKeys[i] == settingKey then
                matchedSource = "reviewed_dynamic_key"
                break
            end
        end
        if not matchedSource then
            -- Patterns were validated by IsValidLuaPattern at registration.
            for i = 1, #(record.assistantSettingKeyPatterns or {}) do
                if string.match(settingKey, record.assistantSettingKeyPatterns[i]) ~= nil then
                    matchedSource = "reviewed_dynamic_pattern"
                    break
                end
            end
        end
        if matchedSource then
            if not dynamicBest then
                dynamicBest, dynamicSource = record, matchedSource
            elseif dynamicBest ~= record then
                dynamicAmbiguous = true
            elseif dynamicSource ~= "reviewed_dynamic_key" then
                dynamicSource = matchedSource
            end
        end
    end
    if pageRecords then
        for controlId in pairs(pageRecords) do ConsiderDynamicRecord(STATE.byId[controlId]) end
    elseif pageKey == "" then
        for _, record in pairs(STATE.byId) do ConsiderDynamicRecord(record) end
    end
    if dynamicAmbiguous then
        STATE.lastSettingDescriptorLookup = {
            revision = STATE.revision,
            settingKey = settingKey,
            pageKey = pageKey,
            descriptorFingerprint = descriptorFingerprint,
            source = "ambiguous_reviewed_dynamic",
        }
        return nil, nil, "ambiguous_reviewed_dynamic"
    elseif dynamicBest then
        STATE.lastSettingDescriptorLookup = {
            revision = STATE.revision,
            settingKey = settingKey,
            pageKey = pageKey,
            descriptorFingerprint = descriptorFingerprint,
            controlId = dynamicBest.controlId,
            source = dynamicSource,
        }
        local public = PublicRecord(dynamicBest)
        public.resolvedSettingKey = settingKey
        public.settingKeySource = dynamicSource
        return public, dynamicBest.widget, dynamicSource
    elseif pageKey ~= "" and not pageRecords then
        STATE.lastSettingDescriptorLookup = {
            revision = STATE.revision,
            settingKey = settingKey,
            pageKey = pageKey,
            descriptorFingerprint = descriptorFingerprint,
            source = "page_not_built",
        }
        return nil, nil, "page_not_built"
    end

    descriptor = type(descriptor) == "table" and descriptor or nil
    if not descriptor then return nil end

    if CleanText(descriptor.menuControlDisposition):lower() == "standalone"
        and CleanText(descriptor.menuControlDispositionReason) ~= ""
        and CleanText(descriptor.menuControlDispositionEvidence) ~= ""
    then
        STATE.lastSettingDescriptorLookup = {
            revision = STATE.revision,
            settingKey = settingKey,
            pageKey = pageKey,
            descriptorFingerprint = descriptorFingerprint,
            source = "reviewed_standalone",
        }
        return nil, nil, "reviewed_standalone"
    end

    local resolved, source = ResolveSettingDescriptorRecord(settingKey, pageKey, descriptor)
    STATE.lastSettingDescriptorLookup = {
        revision = STATE.revision,
        settingKey = settingKey,
        pageKey = pageKey,
        descriptorFingerprint = descriptorFingerprint,
        controlId = resolved and resolved.controlId or nil,
        source = source,
    }
    if not resolved then return nil, nil, source end
    local public = PublicRecord(resolved)
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
    local reviewedDisposition, dispositionError = ReviewedAssistantDisposition(record)
    local declaredDisposition = CleanText(record.assistantDisposition) ~= ""
        or CleanText(record.assistantDispositionReason) ~= ""
    local routeKeyCount = #(record.assistantSettingKeys or {})
    local routePatternCount = #(record.assistantSettingKeyPatterns or {})
    local routeCount = routeKeyCount + routePatternCount
    for i = 1, #(record.assistantSettingRouteErrors or {}) do
        errors[#errors + 1] = record.assistantSettingRouteErrors[i]
    end
    if routeCount > 0 then
        if record.classification ~= "setting" then
            errors[#errors + 1] = "Assistant setting routes are only valid for setting controls"
        end
        if CleanText(record.assistantDisposition):lower() ~= "dynamic" then
            errors[#errors + 1] = "Assistant setting routes require assistantDisposition=dynamic"
        end
        if CleanText(record.settingKey) ~= "" then
            errors[#errors + 1] = "settingKey and Assistant dynamic routes are mutually exclusive"
        end
    end
    if declaredDisposition and dispositionError then errors[#errors + 1] = dispositionError end
    if declaredDisposition and record.classification ~= "setting" and record.classification ~= "action" then
        errors[#errors + 1] = "assistantDisposition is only valid for persisted setting/action controls"
    end
    local validateMeta = EnsureCommandMeta(record)
    if record.classification == "setting" then
        if not (validateMeta and validateMeta.hasGet and validateMeta.hasSet) and record.settingKey == "" then
            warnings[#warnings + 1] = "setting has no complete read/write command metadata"
        end
        if record.settingKey ~= "" and reviewedDisposition then
            errors[#errors + 1] = "settingKey and assistantDisposition are mutually exclusive"
        elseif record.settingKey == "" and not reviewedDisposition then
            warnings[#warnings + 1] = "persisted setting lacks an explicit Assistant target or reviewed disposition"
        end
    elseif record.classification == "action" then
        if not (validateMeta and validateMeta.hasSet) and record.actionKey == "" then
            warnings[#warnings + 1] = "action has no write command metadata"
        end
        if record.actionKey ~= "" and reviewedDisposition then
            errors[#errors + 1] = "actionKey and assistantDisposition are mutually exclusive"
        elseif record.actionKey == "" and not reviewedDisposition then
            warnings[#warnings + 1] = "persisted action lacks an explicit Assistant target or reviewed disposition"
        end
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
        persistedControls = 0,
        resolvedTargets = 0,
        explicitTargetCount = 0,
        registryValidatedTargetCount = 0,
        registryMissingTargetCount = 0,
        registryMissingTargets = {},
        reviewedDispositionCount = 0,
        reviewedDispositionCounts = {},
        reviewedDynamicRouteControlCount = 0,
        reviewedDynamicRouteKeyCount = 0,
        reviewedDynamicRoutePatternCount = 0,
        invalidAssistantRouteCount = 0,
        invalidAssistantRoutes = {},
        invalidAssistantDispositionCount = 0,
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
        requiredShellControlCount = 0,
        requiredShellDispositionCount = 0,
        missingShellControls = {},
        invalidShellControls = {},
        shellContractComplete = false,
    }

    for _ in pairs(STATE.components) do report.componentParts = report.componentParts + 1 end

    for i = 1, #records do
        local record = records[i]
        local classification = CLASSIFICATION[record.classification] and record.classification or "unknown"
        local routeKeyCount = #(record.assistantSettingKeys or {})
        local routePatternCount = #(record.assistantSettingKeyPatterns or {})
        local routeCount = routeKeyCount + routePatternCount
        local routeErrors = record.assistantSettingRouteErrors or {}
        local routeAssociationError
        if routeCount > 0 and classification ~= "setting" then
            routeAssociationError = "Assistant setting routes are only valid for setting controls"
        elseif routeCount > 0 and CleanText(record.assistantDisposition):lower() ~= "dynamic" then
            routeAssociationError = "Assistant setting routes require assistantDisposition=dynamic"
        elseif routeCount > 0 and CleanText(record.settingKey) ~= "" then
            routeAssociationError = "settingKey and Assistant dynamic routes are mutually exclusive"
        end
        if routeCount > 0 then
            report.reviewedDynamicRouteControlCount = report.reviewedDynamicRouteControlCount + 1
            report.reviewedDynamicRouteKeyCount = report.reviewedDynamicRouteKeyCount + routeKeyCount
            report.reviewedDynamicRoutePatternCount = report.reviewedDynamicRoutePatternCount + routePatternCount
        end
        if #routeErrors > 0 or routeAssociationError then
            report.invalidAssistantRouteCount = report.invalidAssistantRouteCount + 1
            report.invalidAssistantRoutes[#report.invalidAssistantRoutes + 1] = {
                controlId = record.controlId,
                pageKey = record.pageKey,
                reason = routeAssociationError or table.concat(routeErrors, "; "),
            }
        end
        local linkDisposition, _, linkEligible = AssistantLinkDisposition(record)
        report.assistantLinkDispositionCounts[linkDisposition] =
            (report.assistantLinkDispositionCounts[linkDisposition] or 0) + 1
        if linkEligible then report.assistantStaticSettingLinkEligible = report.assistantStaticSettingLinkEligible + 1
        else report.assistantStaticSettingLinkExcluded = report.assistantStaticSettingLinkExcluded + 1 end
        report.byClassification[classification] = report.byClassification[classification] + 1
        report.byIdSource[record.idSource] = (report.byIdSource[record.idSource] or 0) + 1
        local page = report.byPage[record.pageKey]
        if not page then
            page = {
                total = 0, setting = 0, action = 0, navigation = 0, ephemeral = 0, unknown = 0,
                assistantContractGaps = 0,
            }
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
        local reportMeta = EnsureCommandMeta(record)
        if classification == "ephemeral" then
            if reportMeta and reportMeta.hasSet then report.interactiveEphemeral = report.interactiveEphemeral + 1
            else report.passiveEphemeral = report.passiveEphemeral + 1 end
        end
        if classification == "unknown" then
            local item = PublicRecord(record)
            item.reason = record.classificationSource
            report.unknown[#report.unknown + 1] = item
        end
        if classification == "setting" or classification == "action"
            or classification == "ephemeral" and reportMeta and reportMeta.hasSet then
            local capabilityIssue = RuntimeCapabilityIssue(record)
            if capabilityIssue then
                report.invalidCapabilityCount = report.invalidCapabilityCount + 1
                report.invalidCapabilities[#report.invalidCapabilities + 1] = {
                    controlId = record.controlId, pageKey = record.pageKey,
                    classification = classification, kind = reportMeta and reportMeta.kind or record.kind,
                    reason = capabilityIssue,
                }
            end
            -- Ephemeral commands are runtime capability, not persisted
            -- Assistant targets.  Only settings/actions participate below.
            if classification == "setting" or classification == "action" then
                report.persistedControls = report.persistedControls + 1
                local key = classification == "setting" and CleanText(record.settingKey)
                    or CleanText(record.actionKey)
                local disposition, dispositionError = ReviewedAssistantDisposition(record)
                local declaredDisposition = CleanText(record.assistantDisposition) ~= ""
                    or CleanText(record.assistantDispositionReason) ~= ""
                local conflict = key ~= "" and declaredDisposition
                local gapReason
                if conflict then
                    report.invalidAssistantDispositionCount = report.invalidAssistantDispositionCount + 1
                    gapReason = "explicit target key and assistantDisposition are mutually exclusive"
                elseif key ~= "" then
                    report.resolvedTargets = report.resolvedTargets + 1
                    report.explicitTargetCount = report.explicitTargetCount + 1
                    if targetValidationAvailable then
                        local target
                        if classification == "setting" then target = registry:GetSetting(key)
                        else target = registry:GetAction(key) end
                        if target ~= nil then
                            report.registryValidatedTargetCount = report.registryValidatedTargetCount + 1
                        else
                            report.registryMissingTargetCount = report.registryMissingTargetCount + 1
                            report.registryMissingTargets[#report.registryMissingTargets + 1] = {
                                controlId = record.controlId,
                                pageKey = record.pageKey,
                                classification = classification,
                                targetKey = key,
                            }
                        end
                    end
                elseif disposition then
                    report.reviewedDispositionCount = report.reviewedDispositionCount + 1
                    report.reviewedDispositionCounts[disposition] =
                        (report.reviewedDispositionCounts[disposition] or 0) + 1
                else
                    if declaredDisposition and dispositionError then
                        report.invalidAssistantDispositionCount = report.invalidAssistantDispositionCount + 1
                    end
                    gapReason = dispositionError or "missing explicit settingKey/actionKey or reviewed Assistant disposition"
                end
                if gapReason then
                    local _, _, _, _, suggestedDisposition, suggestionReason = AssistantLinkDisposition(record)
                    report.unresolvedTargetCount = report.unresolvedTargetCount + 1
                    page.assistantContractGaps = page.assistantContractGaps + 1
                    report.unresolvedTargets[#report.unresolvedTargets + 1] = {
                        controlId = record.controlId,
                        pageKey = record.pageKey,
                        classification = classification,
                        targetKey = key ~= "" and key or nil,
                        reason = gapReason,
                        suggestedDisposition = suggestedDisposition,
                        suggestionReason = suggestionReason,
                    }
                end
            end
        end
    end

    if report.interactive > 0 then
        report.interactiveCoveragePercent = math.floor((report.knownInteractive * 10000 / report.interactive) + 0.5) / 100
    end
    local shell = M.REQUIRED_SHELL_CONTRACT
    if type(shell) == "table" then
        for controlId, expected in pairs(shell.controls or {}) do
            report.requiredShellControlCount = report.requiredShellControlCount + 1
            local record = STATE.byId[controlId]
            if not record then
                report.missingShellControls[#report.missingShellControls + 1] = controlId
            else
                local mismatches = {}
                for _, field in ipairs({ "classification", "kind", "actionKey" }) do
                    local wanted = CleanText(expected and expected[field])
                    if wanted ~= "" and CleanText(record[field]) ~= wanted then
                        mismatches[#mismatches + 1] = field .. "=" .. CleanText(record[field]) .. " expected=" .. wanted
                    end
                end
                if #mismatches > 0 then
                    report.invalidShellControls[#report.invalidShellControls + 1] = {
                        controlId = controlId,
                        reason = table.concat(mismatches, "; "),
                    }
                end
            end
        end
        for _ in pairs(shell.dispositions or {}) do
            report.requiredShellDispositionCount = report.requiredShellDispositionCount + 1
        end
        table.sort(report.missingShellControls)
        table.sort(report.invalidShellControls, function(left, right)
            return tostring(left and left.controlId or "") < tostring(right and right.controlId or "")
        end)
        report.shellContractComplete = tonumber(shell.schemaVersion) == 1
            and report.requiredShellControlCount >= (tonumber(shell.minimumControls) or 0)
            and report.requiredShellDispositionCount >= (tonumber(shell.minimumDispositions) or 0)
            and #report.missingShellControls == 0
            and #report.invalidShellControls == 0
    end
    report.assistantContractComplete = report.unresolvedTargetCount == 0
        and report.invalidAssistantDispositionCount == 0
        and report.invalidAssistantRouteCount == 0
    report.assistantRegistryCrosswalkComplete = not targetValidationAvailable
        or report.registryMissingTargetCount == 0
    report.catalogComplete = report.byClassification.unknown == 0 and report.collisions == 0
        and report.unstableIds == 0
        and report.assistantContractComplete
        and report.assistantRegistryCrosswalkComplete
        and report.invalidCapabilityCount == 0
        and report.shellContractComplete

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
-- Direct alias instead of a wrapper: this sits on the per-control
-- registration path of every page build.
M.RegisterRuntimeControl = Catalog.Register
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
        settingKey = opts.settingKey,
        actionKey = opts.actionKey,
        actionFixedArgs = opts.actionFixedArgs,
        actionInputArg = opts.actionInputArg,
        navigationKey = opts.navigationKey,
        assistantDisposition = opts.assistantDisposition,
        assistantDispositionReason = opts.assistantDispositionReason,
        assistantSettingKeys = opts.assistantSettingKeys,
        assistantSettingKeyPatterns = opts.assistantSettingKeyPatterns,
        confirmRequired = opts.confirmRequired == true,
        historyMode = opts.historyMode,
        help = opts.help,
        command = opts.command,
    }
    if not meta.command and meta.classification == "action" then
        meta.command = M.BuildRuntimeWidgetCommand(widget, meta, meta.kind)
    end
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

function M.GetRuntimeControlCoverageReport()
    return Catalog.GetCoverageReport()
end
